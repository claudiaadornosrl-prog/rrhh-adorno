"""
═══════════════════════════════════════════════════════════════════════
 03_import_crosschex_excel.py — Importa reportes .xls de CrossChex Cloud
                                  a rrhh_fichadas_raw en Supabase.

 Mientras esperamos la activación de Developer Mode en Anviz, esto sirve
 para cargar fichadas históricas / del mes anterior manualmente.

 Los .xls de CrossChex son HTML disfrazado. El parser:
   1. Lee el HTML como tabla con pandas
   2. Detecta el local desde la columna "Departamento":
        "Oficina"                     -> oficina
        "Claudia Adorno - Unicenter"  -> unicenter
        "Adornix"                     -> alcorta
   3. Detecta formato de fecha (Oficina = MM/DD/YYYY, locales = DD/MM/YYYY)
   4. Cada fila trae 1 entrada + 1 salida → genera 2 registros en rrhh_fichadas_raw
   5. Upsert idempotente (no duplica al re-correr)

 USO:
    python 03_import_crosschex_excel.py archivo1.xls archivo2.xls ...
    python 03_import_crosschex_excel.py *.xls --dry-run     # No escribe en Supabase
═══════════════════════════════════════════════════════════════════════
"""
import sys
if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    except Exception:
        pass

import os
import re
import json
import argparse
import unicodedata
from pathlib import Path
from datetime import datetime, timezone, timedelta
from collections import defaultdict

import warnings
warnings.filterwarnings('ignore')

try:
    from dotenv import load_dotenv
    load_dotenv(Path(__file__).parent.parent / 'sync_anviz' / '.env')
except ImportError:
    print("WARN: python-dotenv no instalado, intentando con variables de entorno directas")

import pandas as pd

# ───────────────────────────────────────────────────────────────
# CONFIG
# ───────────────────────────────────────────────────────────────
SUPA_URL = os.environ.get('SUPABASE_URL', 'https://kwwiykssrpabncpqtmwi.supabase.co')
SUPA_KEY = os.environ.get('SUPABASE_SERVICE_KEY')

# Mapeo Departamento (CrossChex) → local (RRHH)
DEPTO_LOCAL = {
    'oficina':                    'oficina',
    'claudia adorno - unicenter': 'unicenter',
    'adornix':                    'alcorta',
}

# Cuál cuenta Anviz corresponde a cada local (para identificar origen)
LOCAL_CUENTA = {
    'oficina':   'oficina',
    'unicenter': 'unicenter',
    'alcorta':   'alcorta',
}

# Locales con formato US (MM/DD/YYYY); el resto usa DD/MM/YYYY
LOCALES_FECHA_US = {'oficina'}


# ───────────────────────────────────────────────────────────────
# Helpers
# ───────────────────────────────────────────────────────────────
def slug(s: str) -> str:
    if not s: return ''
    s = unicodedata.normalize('NFD', str(s))
    s = ''.join(c for c in s if unicodedata.category(c) != 'Mn')
    return re.sub(r'[^a-z0-9]', '', s.lower())


def detectar_dispositivo(filename: str) -> str:
    """Extrae el serial del dispositivo del nombre: CurrentData_AllDepts_260301_to_260526_21833.xls → 21833"""
    m = re.search(r'_(\d+)\.xls$', filename, re.IGNORECASE)
    return m.group(1) if m else 'unknown'


def parsear_fecha(s: str, formato_us: bool):
    """Parsea fecha según formato del local. Devuelve date o None."""
    if not s or s == 'nan': return None
    s = str(s).strip()
    fmts = ['%m/%d/%Y', '%m/%d/%y'] if formato_us else ['%d/%m/%Y', '%d/%m/%y']
    for fmt in fmts:
        try:
            return datetime.strptime(s, fmt).date()
        except ValueError:
            continue
    return None


def parsear_hora(s: str):
    """'07:45' → time(7,45)"""
    if not s or s in ('nan', '00:00'): return None
    s = str(s).strip()
    try:
        return datetime.strptime(s, '%H:%M').time()
    except ValueError:
        try:
            return datetime.strptime(s, '%H:%M:%S').time()
        except ValueError:
            return None


# ───────────────────────────────────────────────────────────────
# Parser principal
# ───────────────────────────────────────────────────────────────
def parsear_xls(path: Path):
    """Devuelve una lista de dicts listos para rrhh_fichadas_raw."""
    tables = pd.read_html(path, encoding='utf-8')
    if not tables:
        raise ValueError(f"No hay tablas en {path.name}")
    df = tables[0]
    # Headers en fila índice 1
    headers = df.iloc[1].fillna('').astype(str).tolist()
    df.columns = headers
    df = df.iloc[2:].reset_index(drop=True)
    # Las columnas "Jornada" aparecen 2x — la 2da es nuestra "horas planificadas"
    # Buscar col índice de Entrada/Salida/Nombre por nombre
    df = df[df['Nombre'].notna() & (df['Nombre'].astype(str).str.strip() != '')]
    if df.empty: return []

    # Detectar local desde Departamento
    deptos = df['Departamento'].dropna().str.strip().unique()
    if len(deptos) == 0:
        raise ValueError(f"{path.name}: sin departamento detectable")
    depto = deptos[0]   # asumimos 1 archivo = 1 local
    local = DEPTO_LOCAL.get(depto.lower())
    if not local:
        raise ValueError(f"{path.name}: departamento desconocido '{depto}'")

    cuenta_anviz = LOCAL_CUENTA[local]
    formato_us = local in LOCALES_FECHA_US
    dispositivo = detectar_dispositivo(path.name)

    print(f"  → Local: {local} · Dispositivo: {dispositivo} · Formato fecha: {'MM/DD/YYYY' if formato_us else 'DD/MM/YYYY'}")

    # Procesar filas
    registros = []
    sin_fecha = 0
    sin_fichada = 0
    AR_TZ = timezone(timedelta(hours=-3))

    for _, row in df.iterrows():
        nombre = str(row.get('Nombre','')).strip()
        if not nombre: continue
        # Partir en first/last name (heurística: último token es apellido salvo casos especiales)
        # Anviz suele tener "Nombre Apellido" o "Nombre Nombre Apellido" — heurística simple
        partes = nombre.split()
        if len(partes) == 1:
            first, last = '', partes[0]
        elif len(partes) == 2:
            first, last = partes[0], partes[1]
        else:
            # 3+ palabras: primer token = nombre, resto = apellidos compuestos
            first, last = partes[0], ' '.join(partes[1:])

        workno = str(row.get('Número de empleado','')).strip() or None

        fecha_str = str(row.get('Fecha','')).strip()
        fecha = parsear_fecha(fecha_str, formato_us)
        if not fecha:
            sin_fecha += 1
            continue

        entrada = parsear_hora(str(row.get('Entrada','')))
        salida  = parsear_hora(str(row.get('Salida','')))

        if not entrada and not salida:
            sin_fichada += 1
            continue

        # Generar un registro por cada fichada presente
        for h, checktype in [(entrada, 0), (salida, 1)]:
            if not h: continue
            dt_local = datetime.combine(fecha, h, tzinfo=AR_TZ)
            dt_utc   = dt_local.astimezone(timezone.utc)
            registros.append({
                'empleado_id':        None,   # se completa después con el match
                'anviz_workno':       workno,
                'anviz_first_name':   first,
                'anviz_last_name':    last,
                'fecha':              fecha.isoformat(),
                'hora':               h.strftime('%H:%M:%S'),
                'fecha_hora':         dt_utc.isoformat(),
                'local':              local,
                'dispositivo_serial': dispositivo,
                'dispositivo_nombre': depto,
                'checktype':          checktype,
                'cuenta_anviz':       cuenta_anviz,
                'raw_data':           json.dumps({k: str(v) for k,v in row.items()}, ensure_ascii=False),
            })

    print(f"  ✓ {len(registros)} fichadas extraídas ({sin_fecha} sin fecha, {sin_fichada} sin fichada)")
    return registros


# ───────────────────────────────────────────────────────────────
# Match con empleados de Supabase
# ───────────────────────────────────────────────────────────────
def cargar_empleados(supabase):
    data = supabase.table('rrhh_empleados').select('id, dni, apellido, nombre, local').execute().data
    match = {}
    for e in data:
        apellido = e['apellido'] or ''
        nombre   = e['nombre'] or ''
        # Tokens del apellido — ej. "NOGUERA PARRA" → ["NOGUERA", "PARRA"]
        apellido_tokens = apellido.split()
        primer_apellido = apellido_tokens[0] if apellido_tokens else ''
        primer_nombre   = nombre.split()[0] if nombre else ''
        for k in [
            slug(apellido + nombre),
            slug(nombre + apellido),
            slug(apellido),
            slug(e.get('dni','') or ''),
            slug(apellido + primer_nombre),
            # Variantes con primer apellido solo (para apellidos compuestos en RRHH vs simples en Anviz)
            slug(primer_apellido + primer_nombre),
            slug(primer_nombre + primer_apellido),
            slug(primer_apellido),
        ]:
            if k and k not in match:
                match[k] = e['id']
    print(f"  → {len(data)} empleados cargados → {len(match)} variantes de match")
    return match


def matchear_registros(registros, empleado_match):
    sin_match = defaultdict(int)
    for r in registros:
        for k in [
            slug(r['anviz_last_name'] + r['anviz_first_name']),
            slug(r['anviz_first_name'] + r['anviz_last_name']),
            slug(r['anviz_last_name']),
            slug(r['anviz_workno'] or ''),
        ]:
            if k and k in empleado_match:
                r['empleado_id'] = empleado_match[k]
                break
        if not r['empleado_id']:
            sin_match[f"{r['anviz_last_name']} {r['anviz_first_name']}"] += 1
    if sin_match:
        print(f"  ⚠ Empleados sin match en RRHH:")
        for n, c in sin_match.items():
            print(f"      «{n}»: {c} fichadas")
    return sum(1 for r in registros if r['empleado_id'])


# ───────────────────────────────────────────────────────────────
# Main
# ───────────────────────────────────────────────────────────────
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('archivos', nargs='+', help='Archivos .xls de CrossChex')
    ap.add_argument('--dry-run', action='store_true', help='No escribe en Supabase')
    args = ap.parse_args()

    print("═══════════════════════════════════════════════════════════════")
    print(" Importador CrossChex Excel → rrhh_fichadas_raw")
    print("═══════════════════════════════════════════════════════════════\n")

    # Conectar Supabase (si no es dry-run)
    supabase = None
    empleado_match = {}
    if not args.dry_run:
        if not SUPA_KEY:
            sys.exit("❌ Falta SUPABASE_SERVICE_KEY en .env de sync_anviz/")
        from supabase import create_client
        supabase = create_client(SUPA_URL, SUPA_KEY)
        print("✓ Conectado a Supabase")
        empleado_match = cargar_empleados(supabase)
    else:
        print("🔵 DRY-RUN — no se escribirá en Supabase")

    # Expandir wildcards y directorios — útil cuando PowerShell no expande *.xls
    import glob as _glob
    archivos_resueltos = []
    for arg in args.archivos:
        p = Path(arg)
        if p.is_dir():
            archivos_resueltos.extend(sorted(p.glob('*.xls')))
        elif any(c in arg for c in '*?['):
            archivos_resueltos.extend([Path(x) for x in sorted(_glob.glob(arg))])
        elif p.exists():
            archivos_resueltos.append(p)
        else:
            # Probar glob por si tiene wildcards no escapados
            expanded = sorted(_glob.glob(arg))
            if expanded:
                archivos_resueltos.extend([Path(x) for x in expanded])
            else:
                print(f"\n❌ No existe: {arg}")

    if not archivos_resueltos:
        print("\n⚠️  No se encontraron archivos. Verificá la ruta.")
        return

    print(f"\n📂 Procesando {len(archivos_resueltos)} archivo(s):")
    for f in archivos_resueltos:
        print(f"   · {f.name}")

    todos_los_registros = []
    for path in archivos_resueltos:
        print(f"\n📄 {path.name}")
        try:
            regs = parsear_xls(path)
            todos_los_registros.extend(regs)
        except Exception as e:
            print(f"  ❌ Error: {e}")
            import traceback; traceback.print_exc()

    print(f"\n═══════════════════════════════════════════════════════════════")
    print(f" Total fichadas extraídas: {len(todos_los_registros)}")
    print(f"═══════════════════════════════════════════════════════════════")

    if not todos_los_registros:
        print("Nada para subir.")
        return

    # Matchear
    if not args.dry_run:
        matched = matchear_registros(todos_los_registros, empleado_match)
        print(f"\n✓ {matched}/{len(todos_los_registros)} fichadas matcheadas con empleado")

    if args.dry_run:
        print("\nMuestra de los primeros 3 registros:")
        for r in todos_los_registros[:3]:
            print(f"  {r['fecha']} {r['hora']} | {r['anviz_last_name']} {r['anviz_first_name']} | {r['local']} | dev={r['dispositivo_serial']} | type={r['checktype']}")
        return

    # Dedup por (fecha_hora, dispositivo_serial, anviz_workno) — clave del unique constraint
    print(f"\n🔍 Deduplicando por (fecha_hora, dispositivo, workno)...")
    vistos = {}
    for r in todos_los_registros:
        key = (r['fecha_hora'], r['dispositivo_serial'], r['anviz_workno'])
        # Quedarse con el más reciente (mismo registro = lo último gana)
        vistos[key] = r
    registros_dedup = list(vistos.values())
    print(f"   ✓ {len(todos_los_registros)} → {len(registros_dedup)} (eliminados {len(todos_los_registros) - len(registros_dedup)} duplicados)")

    # Upsert en batches
    print(f"\n📤 Subiendo {len(registros_dedup)} a rrhh_fichadas_raw…")
    BATCH = 200
    subidos = 0
    for i in range(0, len(registros_dedup), BATCH):
        batch = registros_dedup[i:i+BATCH]
        try:
            supabase.table('rrhh_fichadas_raw').upsert(
                batch,
                on_conflict='fecha_hora,dispositivo_serial,anviz_workno'
            ).execute()
            subidos += len(batch)
            print(f"  ✓ {subidos}/{len(registros_dedup)}")
        except Exception as e:
            print(f"  ❌ Error en batch {i}: {e}")
            raise
    print(f"\n✅ Subidos {subidos} registros a Supabase")


if __name__ == '__main__':
    main()
