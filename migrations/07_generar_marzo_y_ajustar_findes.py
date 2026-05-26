"""
═══════════════════════════════════════════════════════════════════════
 07_generar_marzo_y_ajustar_findes.py
 Dos fixes en uno:

  1) GENERAR TURNOS DE MARZO 2026 (igual lógica que abril/mayo):
     - Lee rrhh_turnos_default por (empleado, día_semana)
     - Para findes sin default, infiere desde fichadas reales
     - Crea filas en rrhh_turnos

  2) AJUSTAR FINDES DE UNICENTER MAL INFERIDOS:
     - Detecta sáb/dom con turno hora_inicio=09:45-16:00 en Unicenter
       (templace "mañana" inferido por error desde una fichada temprana)
     - Los reemplaza por template "finde_completo" (13:45-22:00)
     - Solo afecta a empleados de Unicenter

  USO:
    python 07_generar_marzo_y_ajustar_findes.py              # DRY-RUN
    python 07_generar_marzo_y_ajustar_findes.py --aplicar    # Escribir
    python 07_generar_marzo_y_ajustar_findes.py --solo-marzo
    python 07_generar_marzo_y_ajustar_findes.py --solo-findes
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
from datetime import date, datetime, timedelta
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
    with urlrequest.urlopen(req, timeout=30) as r: return json.loads(r.read())

def fetch_patch(path, body):
    data = json.dumps(body, ensure_ascii=False).encode('utf-8')
    req = urlrequest.Request(f"{SUPA_URL}/rest/v1/{_encode_url(path)}",
                             data=data, headers={**H, "Prefer": "return=representation"},
                             method='PATCH')
    with urlrequest.urlopen(req, timeout=30) as r: return json.loads(r.read())


def inferir_template_desde_hora(local, hora_entrada_min):
    rangos = {
        'unicenter': [
            ('manana',         585, 960),
            ('tarde',          945, 1320),
            ('intermedio',     765, 1140),
            ('finde_completo', 825, 1320),
        ],
        'alcorta': [
            ('manana',     585, 960),
            ('tarde',      945, 1260),
            ('intermedio', 765, 1140),
            ('completo',   585, 1260),
        ],
        'oficina': [('completo', 465, 1050)],
    }
    if local not in rangos: return None
    candidatos = rangos[local]
    best = None
    for cod, hi, hf in candidatos:
        d = abs(hora_entrada_min - hi)
        if best is None or d < best[1]:
            best = (cod, d, hi, hf)
    return best


def generar_marzo(aplicar):
    print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print("1) GENERAR TURNOS DE MARZO 2026")
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

    # Empleados activos que fichan
    empleados = fetch_get("rrhh_empleados?select=id,nombre_completo,local&estado=eq.activo&ficha=eq.true")
    print(f"   {len(empleados)} empleados activos que fichan")

    # Templates
    tpls = fetch_get("rrhh_templates_turno?activo=eq.true&select=id,local,codigo,hora_inicio,hora_fin")
    tpl_by = {(t['local'], t['codigo']): t for t in tpls}

    # Defaults por (empleado_id, dia_semana)
    defaults = fetch_get("rrhh_turnos_default?select=empleado_id,dia_semana,template_id,hora_inicio,hora_fin,es_franco")
    def_map = {(d['empleado_id'], d['dia_semana']): d for d in defaults}

    # Rango marzo 2026
    dia_ini = date(2026, 3, 1)
    dia_fin = date(2026, 3, 31)

    # Borrar turnos previos de marzo (si los hay)
    if aplicar:
        # No borrar si solo dry-run; en aplicar borrar para regenerar limpio
        existentes = fetch_get(f"rrhh_turnos?fecha=gte.{dia_ini.isoformat()}&fecha=lte.{dia_fin.isoformat()}&select=id&limit=2000")
        print(f"   Turnos existentes en marzo: {len(existentes)}")

    # Fichadas para inferencia
    fichadas = fetch_get(f"rrhh_fichadas_raw?fecha=gte.{dia_ini.isoformat()}&fecha=lte.{dia_fin.isoformat()}&select=empleado_id,fecha,hora&limit=5000")
    fich_por_dia = defaultdict(list)
    for f in fichadas:
        if f['empleado_id'] is None: continue
        fich_por_dia[(f['empleado_id'], f['fecha'])].append(f['hora'])

    inserts = []
    stats = defaultdict(int)

    for emp in empleados:
        local = emp['local']
        cursor = dia_ini
        while cursor <= dia_fin:
            dow_py = cursor.weekday()
            dow_db = 0 if dow_py == 6 else dow_py + 1
            key_def = (emp['id'], dow_db)
            fecha_str = cursor.isoformat()
            fich = sorted(fich_por_dia.get((emp['id'], fecha_str), []))

            row = None
            if key_def in def_map:
                d = def_map[key_def]
                row = {
                    'empleado_id': emp['id'],
                    'fecha':       fecha_str,
                    'template_id': d.get('template_id'),
                    'hora_inicio': d.get('hora_inicio'),
                    'hora_fin':    d.get('hora_fin'),
                    'es_franco':   d.get('es_franco', False),
                    'tipo':        'franco' if d.get('es_franco') else 'planificado',
                    'planificado_por': 'sistema-genera',
                }
                stats['desde_default'] += 1
            elif fich:
                primera = fich[0]
                h, mn = map(int, primera.split(':')[:2])
                em = h*60 + mn
                inf = inferir_template_desde_hora(local, em)
                if inf:
                    cod, dist, hi, hf = inf
                    tpl = tpl_by.get((local, cod))
                    row = {
                        'empleado_id': emp['id'],
                        'fecha':       fecha_str,
                        'template_id': tpl['id'] if tpl else None,
                        'hora_inicio': tpl['hora_inicio'] if tpl else None,
                        'hora_fin':    tpl['hora_fin'] if tpl else None,
                        'es_franco':   False,
                        'tipo':        'planificado',
                        'planificado_por': 'sistema-genera-inferido',
                    }
                    stats['inferido'] += 1

            if row: inserts.append(row)
            cursor += timedelta(days=1)

    print(f"\n   Total turnos a generar: {len(inserts)}")
    print(f"     - Desde default: {stats['desde_default']}")
    print(f"     - Inferidos:     {stats['inferido']}")

    if not aplicar:
        print("\n   🔵 DRY-RUN — no se escribe")
        return

    # Borrar previos
    # PostgREST: usar delete con filtro
    req = urlrequest.Request(
        f"{SUPA_URL}/rest/v1/rrhh_turnos?fecha=gte.{dia_ini.isoformat()}&fecha=lte.{dia_fin.isoformat()}",
        headers=H, method='DELETE'
    )
    try:
        with urlrequest.urlopen(req, timeout=30) as r: pass
        print(f"   ✓ Turnos previos de marzo borrados")
    except Exception as e:
        print(f"   ⚠ Error borrando previos: {e}")

    BATCH = 200
    subidos = 0
    for i in range(0, len(inserts), BATCH):
        batch = inserts[i:i+BATCH]
        fetch_post("rrhh_turnos", batch)
        subidos += len(batch)
        print(f"     ✓ {subidos}/{len(inserts)}")
    print(f"   ✅ {subidos} turnos de marzo generados")


def ajustar_findes_unicenter(aplicar):
    print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print("2) AJUSTAR FINDES UNICENTER MAL INFERIDOS")
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

    # Template finde_completo de unicenter
    tpls = fetch_get("rrhh_templates_turno?local=eq.unicenter&codigo=eq.finde_completo&select=*")
    if not tpls:
        print("   ❌ No se encontró template unicenter/finde_completo")
        return
    tpl_finde = tpls[0]
    print(f"   Template destino: id={tpl_finde['id']}, {tpl_finde['hora_inicio']} → {tpl_finde['hora_fin']}")

    # Empleados de Unicenter
    emps_uni = fetch_get("rrhh_empleados?local=eq.unicenter&estado=eq.activo&ficha=eq.true&select=id,nombre_completo")
    emp_ids = [e['id'] for e in emps_uni]
    emp_nombre = {e['id']: e['nombre_completo'] for e in emps_uni}
    print(f"   {len(emps_uni)} empleados Unicenter activos")

    # Buscar turnos sáb/dom con hora_inicio=09:45 y hora_fin=16:00
    # PostgREST: usar in.(...) para empleado_id
    emp_in = ','.join(map(str, emp_ids))
    turnos_sospechosos = fetch_get(
        f"rrhh_turnos?empleado_id=in.({emp_in})&hora_inicio=eq.09:45:00&hora_fin=eq.16:00:00&es_franco=eq.false&select=id,empleado_id,fecha,hora_inicio,hora_fin,planificado_por&limit=2000"
    )

    # Filtrar solo los que son sáb (6) o dom (0) por weekday
    a_corregir = []
    for t in turnos_sospechosos:
        d = datetime.strptime(t['fecha'], '%Y-%m-%d').date()
        dow = d.weekday()  # 0=lun .. 5=sáb .. 6=dom
        if dow == 5 or dow == 6:
            a_corregir.append(t)

    print(f"\n   Turnos a corregir (sáb/dom con turno 'mañana'): {len(a_corregir)}")
    for t in a_corregir[:15]:
        print(f"     · {emp_nombre.get(t['empleado_id'],'?')[:30]:30} {t['fecha']} {t['hora_inicio']}→{t['hora_fin']}")
    if len(a_corregir) > 15:
        print(f"     ... y {len(a_corregir)-15} más")

    if not aplicar:
        print("\n   🔵 DRY-RUN — no se escribe")
        return

    if not a_corregir:
        print("\n   Nada para corregir.")
        return

    actualizados = 0
    for t in a_corregir:
        fetch_patch(f"rrhh_turnos?id=eq.{t['id']}", {
            'template_id': tpl_finde['id'],
            'hora_inicio': tpl_finde['hora_inicio'],
            'hora_fin':    tpl_finde['hora_fin'],
            'planificado_por': 'fix-findes-unicenter',
        })
        actualizados += 1
        if actualizados % 20 == 0:
            print(f"     ✓ {actualizados}/{len(a_corregir)}")
    print(f"   ✅ {actualizados} turnos ajustados a finde_completo")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--aplicar', action='store_true')
    ap.add_argument('--solo-marzo', action='store_true')
    ap.add_argument('--solo-findes', action='store_true')
    args = ap.parse_args()

    if not SUPA_KEY:
        sys.exit("❌ Falta SUPABASE_SERVICE_KEY en sync_anviz/.env")

    do_marzo = not args.solo_findes
    do_findes = not args.solo_marzo

    if do_marzo: generar_marzo(args.aplicar)
    if do_findes: ajustar_findes_unicenter(args.aplicar)

    if not args.aplicar:
        print("\n\n🔵 Esto fue DRY-RUN. Para aplicar:")
        print(f"   python {Path(__file__).name} --aplicar")


if __name__ == '__main__':
    main()
