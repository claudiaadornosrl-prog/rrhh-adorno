r"""
═══════════════════════════════════════════════════════════════════════
 sync_ipc_indec.py
 Sincroniza la tabla rrhh_ipc_argentina con datos oficiales del INDEC.

 Fuente: API pública de datos.gob.ar
   Serie: 148.3_INIVELNAL_DICI_M_26
   (IPC Nivel General Nacional, variación mensual)

 Comportamiento:
   • Consulta los últimos ~24 meses de la API INDEC.
   • Para cada mes retornado, hace UPSERT en rrhh_ipc_argentina:
       - Si NO existía el registro → INSERT con fuente='INDEC'.
       - Si existía con fuente distinta a 'INDEC' (p.ej. 'Proyección') → UPDATE.
       - Si ya existía con fuente='INDEC' y el mismo valor → no toca.
       - Si ya existía con fuente='INDEC' pero valor distinto (revisión INDEC) → UPDATE.
   • Meses futuros con fuente='Proyección consultoras' que aún no publicó
     INDEC se dejan intactos.
   • Loggea todos los cambios.

 Uso:
   python sync_ipc_indec.py            # DRY-RUN (no escribe)
   python sync_ipc_indec.py --aplicar  # Sincroniza en DB

═══════════════════════════════════════════════════════════════════════
"""
import os, sys, json, argparse
from pathlib import Path
from urllib import request as urlrequest
from urllib.error import URLError, HTTPError
from datetime import datetime, timezone

try:
    from dotenv import load_dotenv
    _here = Path(__file__).parent
    _envpaths = [
        _here / '.env',
        _here.parent / 'sync_anviz' / '.env',
        Path('/opt/adorno/procesador/.env'),  # VPS ubicación estándar
        Path.cwd() / '.env',
    ]
    _seen = set()
    for _envpath in _envpaths:
        try:
            _resolved = _envpath.resolve()
        except Exception:
            continue
        if _resolved in _seen: continue
        _seen.add(_resolved)
        if _envpath.is_file():
            load_dotenv(_envpath, override=False)
except ImportError:
    pass

SUPA_URL = os.environ.get('SUPABASE_URL', 'https://kwwiykssrpabncpqtmwi.supabase.co')
SUPA_KEY = os.environ.get('SUPABASE_SERVICE_KEY')

# API INDEC
IPC_SERIE_ID  = '148.3_INIVELNAL_DICI_M_26'
IPC_API_URL   = ('https://apis.datos.gob.ar/series/api/series/'
                 f'?ids={IPC_SERIE_ID}&representation_mode=percent_change'
                 '&format=json&limit=24&sort=desc')

# ─── Helpers Supabase ─────────────────────────────────────────────────
def supa_get(path):
    """GET a Supabase REST API."""
    if not SUPA_KEY:
        raise RuntimeError('Falta SUPABASE_SERVICE_KEY en .env')
    url = f"{SUPA_URL}/rest/v1/{path}"
    req = urlrequest.Request(url, headers={
        'apikey': SUPA_KEY,
        'Authorization': f'Bearer {SUPA_KEY}',
        'Accept': 'application/json',
    })
    with urlrequest.urlopen(req, timeout=20) as resp:
        return json.loads(resp.read().decode('utf-8'))

def supa_upsert(tabla, filas, on_conflict='mes'):
    """UPSERT via POST con header Prefer: resolution=merge-duplicates."""
    if not SUPA_KEY:
        raise RuntimeError('Falta SUPABASE_SERVICE_KEY en .env')
    if not filas:
        return []
    url = f"{SUPA_URL}/rest/v1/{tabla}?on_conflict={on_conflict}"
    body = json.dumps(filas).encode('utf-8')
    req = urlrequest.Request(url, data=body, method='POST', headers={
        'apikey': SUPA_KEY,
        'Authorization': f'Bearer {SUPA_KEY}',
        'Content-Type': 'application/json',
        'Prefer': 'resolution=merge-duplicates,return=representation',
    })
    with urlrequest.urlopen(req, timeout=20) as resp:
        return json.loads(resp.read().decode('utf-8'))

# ─── Fetch API INDEC ──────────────────────────────────────────────────
def fetch_ipc_indec():
    """Retorna lista de (mes_str_yyyy_mm_01, variacion_pct_float)."""
    req = urlrequest.Request(IPC_API_URL, headers={
        'Accept': 'application/json',
        'User-Agent': 'Claudia-Adorno-RRHH-sync/1.0',
    })
    with urlrequest.urlopen(req, timeout=30) as resp:
        data = json.loads(resp.read().decode('utf-8'))
    resultados = []
    for row in data.get('data', []):
        mes = row[0]                        # "2026-05-01"
        val_frac = row[1]                   # 0.021499... (fracción)
        if mes is None or val_frac is None:
            continue
        pct = round(float(val_frac) * 100, 3)
        resultados.append((mes, pct))
    return resultados

# ─── Sincronización ───────────────────────────────────────────────────
def sincronizar(dry_run=True, verbose=True):
    if verbose:
        print(f"═══════════════════════════════════════════════════════════════")
        print(f"  SYNC IPC INDEC · {datetime.now(timezone.utc).isoformat()}")
        print(f"  Modo: {'DRY-RUN (no aplica)' if dry_run else 'APLICAR'}")
        print(f"═══════════════════════════════════════════════════════════════")

    # 1) Fetch API INDEC
    try:
        indec = fetch_ipc_indec()
    except (URLError, HTTPError) as e:
        print(f"❌ Error fetch API INDEC: {e}")
        return {'ok': False, 'error': str(e)}
    if verbose:
        print(f"📡 API INDEC devolvió {len(indec)} meses")
        for mes, pct in indec[:6]:
            print(f"    {mes}  {pct:5.2f}%")
        if len(indec) > 6:
            print(f"    ... y {len(indec) - 6} más")

    # 2) Fetch estado actual de la DB
    meses_desde = min(m for m, _ in indec)
    existentes = supa_get(
        f"rrhh_ipc_argentina?select=mes,variacion_pct,fuente&mes=gte.{meses_desde}"
    )
    db_map = {r['mes']: r for r in existentes}
    if verbose:
        print(f"\n💾 DB tiene {len(existentes)} registros desde {meses_desde}")

    # 3) Comparar y armar payload
    cambios = []
    for mes, pct_api in indec:
        actual = db_map.get(mes)
        if not actual:
            cambios.append({
                'accion': 'INSERT',
                'mes': mes, 'pct_nuevo': pct_api, 'pct_viejo': None,
                'fuente_vieja': None,
            })
            continue
        pct_db = float(actual['variacion_pct'])
        fuente_db = actual['fuente']
        # Diferencia > 0.005 (medio decimal) o fuente ≠ INDEC → actualizar
        cambio_pct = abs(pct_db - pct_api) > 0.005
        cambio_fuente = fuente_db != 'INDEC'
        if cambio_pct or cambio_fuente:
            cambios.append({
                'accion': 'UPDATE',
                'mes': mes, 'pct_nuevo': pct_api, 'pct_viejo': pct_db,
                'fuente_vieja': fuente_db,
            })

    # 4) Log y aplicar
    if not cambios:
        if verbose: print("\n✅ Nada que actualizar — todo al día.")
        return {'ok': True, 'cambios': 0}

    if verbose:
        print(f"\n🔄 {len(cambios)} cambio(s) detectado(s):")
        for c in cambios:
            if c['accion'] == 'INSERT':
                print(f"  + INSERT  {c['mes']}  {c['pct_nuevo']:5.2f}%  (mes nuevo)")
            else:
                delta = c['pct_nuevo'] - c['pct_viejo']
                print(f"  ~ UPDATE  {c['mes']}  {c['pct_viejo']:5.2f}% → {c['pct_nuevo']:5.2f}%  (Δ {delta:+.2f}, ex-{c['fuente_vieja']})")

    if dry_run:
        if verbose: print(f"\n[DRY-RUN] no se aplicaron. Correr con --aplicar para efectivizar.")
        return {'ok': True, 'cambios': len(cambios), 'dry_run': True}

    # UPSERT
    payload = [{
        'mes': c['mes'],
        'variacion_pct': c['pct_nuevo'],
        'fuente': 'INDEC',
        'notas': 'Sincronizado automáticamente desde apis.datos.gob.ar',
        'cargado_at': datetime.now(timezone.utc).isoformat(),
    } for c in cambios]
    supa_upsert('rrhh_ipc_argentina', payload, on_conflict='mes')
    if verbose:
        print(f"\n✅ {len(cambios)} registro(s) sincronizado(s) en Supabase.")
    return {'ok': True, 'cambios': len(cambios)}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Sync IPC INDEC → rrhh_ipc_argentina')
    parser.add_argument('--aplicar', action='store_true',
                        help='Aplicar cambios (por defecto es DRY-RUN)')
    parser.add_argument('--silencioso', action='store_true',
                        help='Solo mostrar resumen final')
    args = parser.parse_args()

    result = sincronizar(dry_run=not args.aplicar, verbose=not args.silencioso)
    if not result.get('ok'):
        sys.exit(1)
