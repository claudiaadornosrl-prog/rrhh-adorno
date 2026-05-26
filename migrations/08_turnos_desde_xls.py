"""
═══════════════════════════════════════════════════════════════════════
 08_turnos_desde_xls.py
 Carga turnos planificados leyendo la columna F (Jornada) de los Excel
 del CrossChex Cloud — NO infiere, usa los horarios que ya cargaron las
 encargadas en CrossChex.

 Estructura de los .xls:
   A: Nombre        | B: Núm. emp | C: Cargo | D: Departamento | E: Fecha
   F: Jornada (ej. "09:45 - 22:00")   ← CLAVE
   G: Entrada | H: Salida | ...

 Comportamiento:
   - Si la fila tiene Jornada cargada → usa ese horario
   - Si NO la tiene (típico aparato 2 de Alcorta) → la salta
   - Borra turnos previos del mes/local procesado antes de insertar
   - Idempotente: podés re-correr

 USO:
   python 08_turnos_desde_xls.py inbox/archivo.xls
   python 08_turnos_desde_xls.py inbox/archivo.xls --aplicar
   python 08_turnos_desde_xls.py inbox/   (procesa todos los .xls de la carpeta)
═══════════════════════════════════════════════════════════════════════
"""
import sys
if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    except Exception:
        pass

import os, json, re, argparse
from pathlib import Path
from urllib import request as urlrequest
from urllib.parse import quote
from datetime import datetime, date
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


def _encode_url(p): return quote(p, safe="/?=&.,:%-_*+")

def fetch_get(path):
    req = urlrequest.Request(f"{SUPA_URL}/rest/v1/{_encode_url(path)}", headers=H)
    with urlrequest.urlopen(req, timeout=30) as r: return json.loads(r.read())

def fetch_post(path, body):
    data = json.dumps(body, ensure_ascii=False).encode('utf-8')
    req = urlrequest.Request(f"{SUPA_URL}/rest/v1/{_encode_url(path)}",
                             data=data, headers={**H, "Prefer": "return=representation"},
                             method='POST')
    try:
        with urlrequest.urlopen(req, timeout=30) as r: return json.loads(r.read())
    except Exception as e:
        if hasattr(e, 'read'):
            print(f"   ❌ POST error: {e.read().decode('utf-8','replace')[:300]}")
        raise

def fetch_delete(path):
    req = urlrequest.Request(f"{SUPA_URL}/rest/v1/{_encode_url(path)}", headers=H, method='DELETE')
    with urlrequest.urlopen(req, timeout=30) as r: return r.read()


# ─── Detectar formato de fecha (AR vs US) ───
def parse_fecha(s, formato_pista=None):
    """Devuelve YYYY-MM-DD. Detecta si es DD/MM/YYYY (AR) o MM/DD/YYYY (US)."""
    s = (s or '').strip()
    if not s: return None
    # Intentar AR primero
    fmts_a_probar = ['%d/%m/%Y', '%m/%d/%Y', '%Y-%m-%d', '%d-%m-%Y']
    if formato_pista == 'US':
        fmts_a_probar = ['%m/%d/%Y', '%d/%m/%Y', '%Y-%m-%d']
    elif formato_pista == 'AR':
        fmts_a_probar = ['%d/%m/%Y', '%m/%d/%Y', '%Y-%m-%d']
    for f in fmts_a_probar:
        try:
            return datetime.strptime(s, f).strftime('%Y-%m-%d')
        except ValueError:
            continue
    return None


def detectar_formato_fecha(fechas_sample):
    """Mira las primeras fechas y decide si es US o AR."""
    us_score = 0
    ar_score = 0
    for s in fechas_sample[:30]:
        parts = s.split('/')
        if len(parts) != 3: continue
        try:
            d, m = int(parts[0]), int(parts[1])
        except: continue
        if d > 12: ar_score += 1   # primer número > 12 → es día → AR
        elif m > 12: us_score += 1 # segundo número > 12 → es día → US
    return 'AR' if ar_score >= us_score else 'US'


# ─── Mapeo de departamentos a "local" en la DB ───
DEPT_A_LOCAL = {
    'oficina': 'oficina',
    'unicenter': 'unicenter',
    'claudia adorno - unicenter': 'unicenter',
    'alcorta': 'alcorta',
    'adornix': 'alcorta',  # los aparatos viejos de Alcorta están como Adornix
}


def normalizar(s):
    return (s or '').strip().lower()


def parse_jornada(j):
    """'09:45 - 22:00' → ('09:45', '22:00')"""
    if not j: return (None, None)
    m = re.match(r'^\s*(\d{1,2}:\d{2})\s*-\s*(\d{1,2}:\d{2})\s*$', j)
    if not m: return (None, None)
    return m.group(1) + ':00', m.group(2) + ':00'


def cargar_excel(path):
    """Lee un .xls del CrossChex y devuelve lista de filas dict."""
    with open(path, 'r', encoding='utf-8') as f:
        html = f.read()
    trs = re.findall(r'<tr[^>]*>(.*?)</tr>', html, re.DOTALL)
    rows = []
    fechas_sample = []
    for tr in trs[2:]:
        cells = re.findall(r'<t[dh][^>]*>(.*?)</t[dh]>', tr, re.DOTALL)
        cells = [re.sub(r'<[^>]+>', '', c).strip() for c in cells]
        if len(cells) < 8: continue
        if not cells[0]: continue
        rows.append({
            'nombre': cells[0], 'num_emp': cells[1], 'cargo': cells[2],
            'depto': cells[3], 'fecha_raw': cells[4],
            'jornada': cells[5], 'entrada': cells[6], 'salida': cells[7],
        })
        if cells[4]: fechas_sample.append(cells[4])

    fmt = detectar_formato_fecha(fechas_sample)
    for r in rows:
        r['fecha'] = parse_fecha(r['fecha_raw'], fmt)
    return rows, fmt


def buscar_empleado(rows_xls, empleados_db):
    """Mapea cada nombre del Excel a un empleado_id de la DB."""
    by_apellido = defaultdict(list)
    by_dni = {}
    for e in empleados_db:
        n = normalizar(e.get('nombre_completo'))
        partes = n.replace(',', '').split()
        if partes: by_apellido[partes[0]].append(e)
        if e.get('dni'): by_dni[e['dni']] = e

    # Anviz workno → empleado (si ya está vinculado)
    workno_to_emp = {}
    # No tenemos esta info directa; nos basamos en nombre

    cache = {}
    no_encontrados = set()
    for r in rows_xls:
        nombre = r['nombre']
        if nombre in cache:
            r['empleado_id'] = cache[nombre]
            continue
        n = normalizar(nombre)
        # Probar match por nombre completo invertido (Excel: "Nombre Apellido", DB: "APELLIDO, NOMBRE")
        partes = n.split()
        emp = None
        # Buscar cuyo apellido aparezca en cualquier parte
        for parte in partes:
            if parte in by_apellido and len(by_apellido[parte]) == 1:
                emp = by_apellido[parte][0]; break
        if not emp:
            # Match por inclusión parcial
            for e in empleados_db:
                nb = normalizar(e.get('nombre_completo'))
                if all(t in nb for t in partes if len(t) > 2):
                    emp = e; break
        if emp:
            cache[nombre] = emp['id']
            r['empleado_id'] = emp['id']
        else:
            cache[nombre] = None
            r['empleado_id'] = None
            no_encontrados.add(nombre)
    return no_encontrados


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('path', help='Archivo .xls o carpeta con .xls')
    ap.add_argument('--aplicar', action='store_true')
    args = ap.parse_args()

    if not SUPA_KEY: sys.exit("❌ Falta SUPABASE_SERVICE_KEY")

    p = Path(args.path)
    if p.is_dir():
        archivos = sorted(p.glob('*.xls'))
    else:
        archivos = [p]
    if not archivos:
        sys.exit("❌ Sin archivos .xls a procesar")

    # Cargar empleados activos
    empleados_db = fetch_get("rrhh_empleados?select=id,nombre_completo,dni,local,estado&estado=eq.activo&ficha=eq.true")
    print(f"📥 {len(empleados_db)} empleados activos\n")

    # Templates por local (para asignar template_id si match)
    tpls = fetch_get("rrhh_templates_turno?select=id,local,codigo,hora_inicio,hora_fin")
    tpl_by_horario = {}  # (local, hi, hf) → template
    for t in tpls:
        if t.get('hora_inicio') and t.get('hora_fin'):
            key = (t['local'], t['hora_inicio'][:5], t['hora_fin'][:5])
            tpl_by_horario[key] = t

    # Acumular turnos por (empleado_id, fecha). Si hay duplicados de aparatos
    # distintos, prioriza el que tenga jornada cargada.
    turnos_a_insertar = {}   # (emp_id, fecha) → dict
    locales_meses = set()    # (local, año-mes) → para borrar previo antes de insertar
    stats = defaultdict(int)
    sin_jornada = defaultdict(int)  # local → count

    for archivo in archivos:
        print(f"📄 {archivo.name}")
        rows, fmt = cargar_excel(str(archivo))
        print(f"   Filas: {len(rows)} | Formato fecha: {fmt}")
        if not rows: continue
        deptos = set(r['depto'] for r in rows if r['depto'])
        print(f"   Departamentos: {deptos}")

        no_enc = buscar_empleado(rows, empleados_db)
        if no_enc:
            print(f"   ⚠ {len(no_enc)} nombres no encontrados: {list(no_enc)[:5]}")

        # Detectar local de este archivo
        local_arch = None
        for d in deptos:
            dl = DEPT_A_LOCAL.get(normalizar(d))
            if dl: local_arch = dl; break

        for r in rows:
            if not r['empleado_id'] or not r['fecha']: continue
            local_emp = next((e['local'] for e in empleados_db if e['id'] == r['empleado_id']), None)
            local = local_emp or local_arch
            if not local: continue

            hi, hf = parse_jornada(r['jornada'])
            if not hi:
                # Sin jornada cargada — no insertar (la fila puede tener fichada igual pero no horario asignado)
                sin_jornada[local] += 1
                continue

            tpl = tpl_by_horario.get((local, hi[:5], hf[:5]))
            key = (r['empleado_id'], r['fecha'])
            row = {
                'empleado_id': r['empleado_id'],
                'fecha':       r['fecha'],
                'template_id': tpl['id'] if tpl else None,
                'hora_inicio': hi,
                'hora_fin':    hf,
                'es_franco':   False,
                'tipo':        'planificado',
                'planificado_por': 'xls-jornada',
            }
            # Si ya existe pero el anterior no tenía jornada o este es más completo, sobrescribir
            if key not in turnos_a_insertar:
                turnos_a_insertar[key] = row
                stats['nuevos'] += 1

            # Track local/mes para borrar previos
            ano_mes = r['fecha'][:7]
            locales_meses.add((local, ano_mes))

    print(f"\n━━━ Resumen ━━━")
    print(f"   Turnos a insertar (únicos): {len(turnos_a_insertar)}")
    for (loc, ym) in sorted(locales_meses):
        cnt = sum(1 for k, v in turnos_a_insertar.items() if v['fecha'].startswith(ym) and any(e['id']==k[0] and e['local']==loc for e in empleados_db))
        print(f"     · {loc} {ym}: {cnt} turnos")
    print(f"\n   Filas sin jornada (saltadas): {dict(sin_jornada)}")

    if not args.aplicar:
        print("\n🔵 DRY-RUN — no se escribe. Para aplicar:")
        print(f"   python {Path(__file__).name} {args.path} --aplicar")
        return

    # Borrar turnos previos para los (local, mes) procesados
    # Necesitamos borrar solo los empleados del local correspondiente
    for (loc, ym) in sorted(locales_meses):
        emp_ids_local = [e['id'] for e in empleados_db if e['local'] == loc]
        if not emp_ids_local: continue
        y, m = ym.split('-')
        dia_ini = f"{ym}-01"
        # último día del mes
        if m == '12':
            dia_fin = f"{int(y)+1}-01-01"
        else:
            dia_fin = f"{y}-{int(m)+1:02d}-01"
        emp_in = ','.join(map(str, emp_ids_local))
        print(f"   🗑 Borrando turnos previos {loc} {ym}...")
        fetch_delete(f"rrhh_turnos?empleado_id=in.({emp_in})&fecha=gte.{dia_ini}&fecha=lt.{dia_fin}")

    # Insertar
    inserts = list(turnos_a_insertar.values())
    BATCH = 200
    subidos = 0
    for i in range(0, len(inserts), BATCH):
        chunk = inserts[i:i+BATCH]
        fetch_post("rrhh_turnos", chunk)
        subidos += len(chunk)
        print(f"   ✓ {subidos}/{len(inserts)}")

    print(f"\n✅ {subidos} turnos planificados cargados desde XLS")


if __name__ == '__main__':
    main()
