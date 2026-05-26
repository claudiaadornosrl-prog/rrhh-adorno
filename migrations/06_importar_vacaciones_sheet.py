"""
═══════════════════════════════════════════════════════════════════════
 06_importar_vacaciones_sheet.py
 Importa las vacaciones desde el Google Sheet "Vacaciones 2025"
 (ID: 18t5HD6ksXXYG-sfe4XXX-FsMMVznpKzGQnSd8CI0LRE)

 ═══ NOTAS IMPORTANTES (confirmadas con JP) ═══
   - OFICINA: vacaciones por días HÁBILES (lun-vie)
   - LOCALES (Unicenter / Alcorta): días CORRIDOS
   - Sanchez y Veron: se fueron y volvieron → antigüedad real se debe
     verificar contra recibos de sueldo. ESTOS SALDOS SON PROVISORIOS.
   - Días sin goce: NO se contemplan acá (se manejan aparte como licencia)
   - Período viejo de 2023 (Rivera): NO se importa
   - Datos del sheet son del 2026 (a pesar del nombre "Vacaciones 2025")

 USO:
   python 06_importar_vacaciones_sheet.py            # DRY-RUN (no escribe)
   python 06_importar_vacaciones_sheet.py --aplicar  # Escribe en Supabase
═══════════════════════════════════════════════════════════════════════
"""
import sys
if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    except Exception:
        pass

import os, json, argparse
from pathlib import Path
from urllib import request as urlrequest
from urllib.parse import quote
from datetime import datetime, timedelta
from collections import defaultdict

try:
    from dotenv import load_dotenv
    load_dotenv(Path(__file__).parent.parent / 'sync_anviz' / '.env')
except ImportError:
    pass

SUPA_URL = os.environ.get('SUPABASE_URL', 'https://kwwiykssrpabncpqtmwi.supabase.co')
SUPA_KEY = os.environ.get('SUPABASE_SERVICE_KEY')

H = {
    "apikey": SUPA_KEY or '',
    "Authorization": f"Bearer {SUPA_KEY or ''}",
    "Content-Type": "application/json; charset=utf-8",
}

AÑO = 2026

# ═══════════════════════════════════════════════════════════════════════
# DATOS DEL SHEET — REVISADOS CON JP A PARTIR DE LAS 2 CAPTURAS
# Estructura: apellido → dict
#   saldo, tomados, periodos: lista de (desde, hasta) en DD/MM/YYYY
#   local_hint: 'oficina' usa días hábiles; otros usan corridos
# ═══════════════════════════════════════════════════════════════════════
DATOS = {
    # ─── ALCORTA (días corridos) ───
    'Benitez':   {'saldo':28, 'tomados':14, 'periodos':[('19/01/2026','01/02/2026')], 'local':'alcorta', 'nota':''},
    'Quiroga':   {'saldo':21, 'tomados':14, 'periodos':[('05/01/2026','18/01/2026')], 'local':'alcorta', 'nota':''},
    'Veron':     {'saldo':14, 'tomados':14, 'periodos':[('19/01/2026','01/02/2026')], 'local':'alcorta', 'nota':'⚠ se fue y volvió → verificar antigüedad real'},
    'Copa':      {'saldo':28, 'tomados':14, 'periodos':[('16/02/2026','01/03/2026')], 'local':'alcorta', 'nota':'Liliana'},
    'Bianchi':   {'saldo':21, 'tomados':14, 'periodos':[('16/02/2026','01/03/2026')], 'local':'alcorta', 'nota':''},
    'Nicola':    {'saldo':14, 'tomados':14, 'periodos':[('02/02/2026','15/02/2026')], 'local':'alcorta', 'nota':''},
    'Noguera':   {'saldo':14, 'tomados':14, 'periodos':[('02/02/2026','15/02/2026')], 'local':'alcorta', 'nota':'Adrian'},
    'Adorno':    {'saldo':28, 'tomados':0,  'periodos':[], 'local':'alcorta', 'nota':'No ficha — saldo de referencia, no toma vacaciones por sistema'},

    # ─── UNICENTER (días corridos) ───
    'Donzelli':  {'saldo':28, 'tomados':14, 'periodos':[('16/02/2026','01/03/2026')], 'local':'unicenter', 'nota':''},
    'Freccero':  {'saldo':14, 'tomados':14, 'periodos':[('19/01/2026','01/02/2026')], 'local':'unicenter', 'nota':'Estefania'},
    'Damela':    {'saldo':28, 'tomados':14, 'periodos':[('05/01/2026','18/01/2026')], 'local':'unicenter', 'nota':'Silvina'},
    'Godoy':     {'saldo':28, 'tomados':14, 'periodos':[('19/01/2026','01/02/2026')], 'local':'unicenter', 'nota':'Cintia'},
    'Escasany':  {'saldo':21, 'tomados':0,  'periodos':[], 'local':'unicenter', 'nota':'Sin período cargado en el sheet'},
    'Moreira':   {'saldo':14, 'tomados':12, 'periodos':[('04/02/2026','15/02/2026')], 'local':'unicenter', 'nota':'12 días corridos'},
    'Sanchez':   {'saldo':28, 'tomados':14, 'periodos':[('02/02/2026','15/02/2026')], 'local':'unicenter', 'nota':'⚠ se fue y volvió → verificar antigüedad real'},

    # ─── OFICINA (días hábiles) ───
    'Rivera':    {'saldo':15, 'tomados':4, 'periodos':[('08/01/2026','09/01/2026'),
                                                       ('08/04/2026','08/04/2026'),
                                                       ('24/04/2026','24/04/2026')], 'local':'oficina', 'nota':'4 hábiles (no se importa el período de 2023)'},
    'Contreras': {'saldo':20, 'tomados':0, 'periodos':[], 'local':'oficina', 'nota':'Marisa — sin período cargado en el sheet'},
    'Monzon':    {'saldo':15, 'tomados':4, 'periodos':[('15/01/2026','16/01/2026'),
                                                       ('13/02/2026','13/02/2026'),
                                                       ('17/04/2026','17/04/2026')], 'local':'oficina', 'nota':'4 hábiles'},

    # ─── Suarez (Gabriela) ───
    # JP confirmó que ya no trabaja en la empresa — NO se importa.
}


def _encode_url(path):
    # Codificar caracteres no-ASCII (como 'ñ' en 'año') en la query string.
    # urllib.parse.quote NO codifica caracteres ASCII como '=' '&' '?' por default,
    # pero sí caracteres como 'ñ'.
    return quote(path, safe="/?=&.,:%-_*+")


def fetch_get(path):
    url = f"{SUPA_URL}/rest/v1/{_encode_url(path)}"
    req = urlrequest.Request(url, headers=H)
    with urlrequest.urlopen(req, timeout=30) as r:
        return json.loads(r.read())


def fetch_post(path, body):
    data = json.dumps(body, ensure_ascii=False).encode('utf-8')
    url = f"{SUPA_URL}/rest/v1/{_encode_url(path)}"
    req = urlrequest.Request(url, data=data,
                             headers={**H, "Prefer": "return=representation"},
                             method='POST')
    try:
        with urlrequest.urlopen(req, timeout=30) as r:
            return json.loads(r.read())
    except Exception as e:
        if hasattr(e, 'read'):
            print(f"❌ POST {path} → HTTP {e.code}")
            print(f"   Body: {e.read().decode('utf-8', 'replace')[:600]}")
            print(f"   First record being sent: {json.dumps(body[0] if isinstance(body, list) and body else body, ensure_ascii=False, indent=2)[:400]}")
        raise


def fetch_patch(path, body):
    data = json.dumps(body, ensure_ascii=False).encode('utf-8')
    url = f"{SUPA_URL}/rest/v1/{_encode_url(path)}"
    req = urlrequest.Request(url, data=data,
                             headers={**H, "Prefer": "return=representation"},
                             method='PATCH')
    with urlrequest.urlopen(req, timeout=30) as r:
        return json.loads(r.read())


def parse_fecha(s):
    d, m, y = s.split('/')
    return f"{y}-{int(m):02d}-{int(d):02d}"


def dias_corridos(desde, hasta):
    d1 = datetime.strptime(desde, '%Y-%m-%d')
    d2 = datetime.strptime(hasta, '%Y-%m-%d')
    return (d2 - d1).days + 1


def dias_habiles(desde, hasta):
    d1 = datetime.strptime(desde, '%Y-%m-%d')
    d2 = datetime.strptime(hasta, '%Y-%m-%d')
    n = 0
    d = d1
    while d <= d2:
        if d.weekday() < 5: n += 1   # 0..4 = lun-vie
        d += timedelta(days=1)
    return n


def normalizar(s):
    return (s or '').strip().lower()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--aplicar', action='store_true', help='Sin esta flag, solo simula (dry-run)')
    args = ap.parse_args()

    if not SUPA_KEY:
        sys.exit("❌ Falta SUPABASE_SERVICE_KEY en sync_anviz/.env")

    print(f"📥 Cargando empleados activos de la DB...")
    empleados = fetch_get("rrhh_empleados?select=id,nombre_completo,dni,local,estado&estado=eq.activo")
    print(f"   {len(empleados)} empleados activos")

    # Índice por primer apellido del nombre_completo
    by_apellido = defaultdict(list)
    for e in empleados:
        n = normalizar(e.get('nombre_completo'))
        partes = n.replace(',', '').split()
        if partes:
            by_apellido[partes[0]].append(e)

    def buscar(apellido):
        key = normalizar(apellido)
        matches = by_apellido.get(key, [])
        if len(matches) == 1: return matches[0]
        if len(matches) > 1:
            print(f"   ⚠ Múltiples matches para {apellido!r}: {[m['nombre_completo'] for m in matches]}")
            return matches[0]
        for e in empleados:
            if key in normalizar(e['nombre_completo']):
                return e
        return None

    # Movimientos existentes
    existentes = fetch_get("rrhh_vacaciones_movimientos?select=empleado_id,fecha_desde,fecha_hasta")
    set_existentes = {(m['empleado_id'], m['fecha_desde'], m['fecha_hasta']) for m in existentes}

    # Cache de vacaciones_id por (empleado_id, año) — para FK obligatoria
    vac_id_cache = {}

    print(f"\n━━━ Plan a aplicar ━━━")

    inserts_movs = []
    upserts_saldos = []
    no_encontrados = []
    skip = []

    for apellido, info in DATOS.items():
        emp = buscar(apellido)
        if not emp:
            no_encontrados.append(apellido)
            print(f"   ❌ {apellido}: no se encontró en la DB")
            continue

        nombre_db = emp['nombre_completo']
        local_db = emp['local']
        local_hint = info['local']
        warn_local = ' ⚠ local distinto al hint' if (local_hint != '?' and local_db != local_hint) else ''

        usa_habiles = (local_db == 'oficina')
        suma_dias = 0
        periodos_str = []
        for desde_s, hasta_s in info['periodos']:
            desde = parse_fecha(desde_s)
            hasta = parse_fecha(hasta_s)
            d = dias_habiles(desde, hasta) if usa_habiles else dias_corridos(desde, hasta)
            suma_dias += d
            periodos_str.append(f"{desde_s}→{hasta_s} ({d}{'h' if usa_habiles else 'c'})")

        check_ok = ' ✓' if suma_dias == info['tomados'] or not info['periodos'] else f' ⚠ tomados={info["tomados"]} ≠ sum_periodos={suma_dias}'

        print(f"\n   {apellido:12} → {nombre_db[:32]:32}  local={local_db}{warn_local}")
        print(f"       saldo: corresp={info['saldo']:3} tomados={info['tomados']:3}{check_ok}")
        if periodos_str:
            print(f"       periodos: {', '.join(periodos_str)}")
        if info['nota']:
            print(f"       📝 {info['nota']}")

        # Saldo
        upserts_saldos.append({
            'empleado_id': emp['id'],
            'año': AÑO,
            'dias_correspondientes': info['saldo'],
            'dias_tomados': info['tomados'],
            'nombre_log': nombre_db,
        })

        # Movimientos
        for desde_s, hasta_s in info['periodos']:
            desde = parse_fecha(desde_s)
            hasta = parse_fecha(hasta_s)
            d = dias_habiles(desde, hasta) if usa_habiles else dias_corridos(desde, hasta)
            d1 = datetime.strptime(desde, '%Y-%m-%d')
            if (emp['id'], desde, hasta) in set_existentes:
                skip.append(f"{apellido} {desde}→{hasta}")
                continue
            obs = f'Importado del Sheet Vacaciones 2025'
            if usa_habiles: obs += ' (días hábiles)'
            if info['nota']: obs += f' — {info["nota"]}'
            # vacaciones_id se resuelve más adelante (después de upsert saldos)
            inserts_movs.append({
                '_empleado_id_lookup': emp['id'],
                '_año_lookup': d1.year,
                'empleado_id': emp['id'],
                'fecha_desde': desde,
                'fecha_hasta': hasta,
                'dias': d,
                'estado': 'tomada',
                'observaciones': obs,
                'solicitado_por': 'import-sheet',
                'aprobado_por':   'import-sheet',
                'fecha_aprobacion': datetime.utcnow().isoformat() + 'Z',
            })

    print(f"\n━━━ Resumen ━━━")
    print(f"   Empleados a procesar:     {len(upserts_saldos)}")
    print(f"   Períodos nuevos a cargar: {len(inserts_movs)}")
    print(f"   Períodos ya existentes:   {len(skip)}")
    print(f"   No encontrados en DB:     {len(no_encontrados)}")
    if no_encontrados:
        print(f"      {no_encontrados}")

    if not args.aplicar:
        print(f"\n🔵 DRY-RUN — nada se escribió. Para aplicar:")
        print(f"   python {Path(__file__).name} --aplicar")
        return

    print(f"\n📤 Aplicando...")

    # Saldos
    for s in upserts_saldos:
        nombre_log = s.pop('nombre_log')
        existing = fetch_get(f"rrhh_vacaciones?empleado_id=eq.{s['empleado_id']}&año=eq.{s['año']}&select=id")
        if existing:
            fetch_patch(f"rrhh_vacaciones?id=eq.{existing[0]['id']}", {
                'dias_correspondientes': s['dias_correspondientes'],
                'dias_tomados': s['dias_tomados'],
            })
            print(f"   ✓ Saldo actualizado: {nombre_log[:35]:35} corresp={s['dias_correspondientes']} tomados={s['dias_tomados']}")
        else:
            fetch_post("rrhh_vacaciones", [s])
            print(f"   + Saldo creado:      {nombre_log[:35]:35} corresp={s['dias_correspondientes']} tomados={s['dias_tomados']}")

    # Movimientos — resolver vacaciones_id antes de insertar (FK obligatoria)
    if inserts_movs:
        # Cachear los vacaciones.id por (empleado_id, año)
        print(f"\n   Resolviendo vacaciones_id (FK)...")
        for m in inserts_movs:
            key = (m['_empleado_id_lookup'], m['_año_lookup'])
            if key not in vac_id_cache:
                rows = fetch_get(f"rrhh_vacaciones?empleado_id=eq.{key[0]}&año=eq.{key[1]}&select=id")
                if not rows:
                    print(f"   ❌ No se encontró rrhh_vacaciones para empleado={key[0]} año={key[1]}")
                    continue
                vac_id_cache[key] = rows[0]['id']
            m['vacaciones_id'] = vac_id_cache[key]
            # Quitar los campos lookup antes de POST
            del m['_empleado_id_lookup']
            del m['_año_lookup']

        BATCH = 50
        for i in range(0, len(inserts_movs), BATCH):
            chunk = inserts_movs[i:i+BATCH]
            fetch_post("rrhh_vacaciones_movimientos", chunk)
            print(f"   ✓ Movimientos: {i+len(chunk)}/{len(inserts_movs)}")

    print(f"\n✅ Listo. Re-procesá los meses afectados (enero–mayo) desde Asistencias → Resumen mensual → Procesar mes.")


if __name__ == '__main__':
    main()
