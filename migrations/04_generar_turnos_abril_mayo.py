"""
═══════════════════════════════════════════════════════════════════════
 04_generar_turnos_abril_mayo.py
 Genera los turnos planificados (rrhh_turnos) para abril y mayo 2026
 a partir de los defaults + inferencia desde fichadas reales.

 Lógica:
   1. Para cada empleado activo, para cada día del rango:
      a. Si hay default para ese día_semana → insertar turno desde default
      b. Si NO hay default pero el empleado fichó ese día → inferir turno
         según la hora de entrada (mañana/tarde/intermedio/etc).
      c. Si no fichó y no hay default → no genera turno.

 Esto cubre:
   - L-V Unicenter (default existe)
   - L-D Alcorta (excepto Liliana findes)
   - L-V Oficina, findes franco
   - Findes Unicenter (sin default → inferido desde fichada)
   - Findes Liliana Copa (sin default → inferido desde fichada)

 USO:
    python 04_generar_turnos_abril_mayo.py            # 2026-04 y 2026-05
    python 04_generar_turnos_abril_mayo.py --dry-run  # solo simulación
    python 04_generar_turnos_abril_mayo.py --mes 2026-04
═══════════════════════════════════════════════════════════════════════
"""
import sys
if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    except Exception:
        pass

import os, argparse
from pathlib import Path
from datetime import date, timedelta, datetime, time as dtime
from collections import defaultdict

try:
    from dotenv import load_dotenv
    load_dotenv(Path(__file__).parent.parent / 'sync_anviz' / '.env')
except ImportError:
    pass

SUPA_URL = os.environ.get('SUPABASE_URL', 'https://kwwiykssrpabncpqtmwi.supabase.co')
SUPA_KEY = os.environ.get('SUPABASE_SERVICE_KEY')


def inferir_template_desde_hora(local, hora_entrada_min):
    """Dada una hora de entrada en minutos (ej. 14:50 = 890), devuelve qué template aplica."""
    # local → lista de (codigo, hi_min, hf_min)
    rangos = {
        'unicenter': [
            ('manana',         585, 960),   # 9:45-16
            ('tarde',          945, 1320),  # 15:45-22
            ('intermedio',     765, 1140),  # 12:45-19
            ('finde_completo', 825, 1320),  # 13:45-22
        ],
        'alcorta': [
            ('manana',     585, 960),
            ('tarde',      945, 1260),
            ('intermedio', 765, 1140),
            ('completo',   585, 1260),
        ],
        'oficina': [
            ('completo', 465, 1050),
        ],
    }
    if local not in rangos: return None
    # El template más cercano a la hora de entrada
    candidatos = rangos[local]
    best = None
    for cod, hi, hf in candidatos:
        d = abs(hora_entrada_min - hi)
        if best is None or d < best[1]:
            best = (cod, d, hi, hf)
    return best  # (codigo, distancia, hi_min, hf_min)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--mes', help='YYYY-MM. Si no se pasa, procesa abril+mayo 2026')
    ap.add_argument('--dry-run', action='store_true')
    args = ap.parse_args()

    if not SUPA_KEY: sys.exit("❌ Falta SUPABASE_SERVICE_KEY")
    from supabase import create_client
    sb = create_client(SUPA_URL, SUPA_KEY)
    print("✓ Conectado a Supabase")

    meses = [args.mes] if args.mes else ['2026-04', '2026-05']

    # 1) Cargar empleados activos
    empleados = sb.table('rrhh_empleados').select('id, nombre_completo, local').eq('estado', 'activo').eq('ficha', True).execute().data
    emp_local = {e['id']: e['local'] for e in empleados}
    print(f"✓ {len(empleados)} empleados activos")

    # 2) Cargar templates
    tpls = sb.table('rrhh_templates_turno').select('*').eq('activo', True).execute().data
    tpl_by = {(t['local'], t['codigo']): t for t in tpls}
    print(f"✓ {len(tpls)} templates")

    # 3) Cargar turnos_default (por empleado_id × dia_semana)
    defaults = sb.table('rrhh_turnos_default').select('*').execute().data
    def_map = {}
    for d in defaults:
        def_map[(d['empleado_id'], d['dia_semana'])] = d
    print(f"✓ {len(defaults)} defaults")

    inserts = []
    stats = defaultdict(int)

    for mes in meses:
        y, m = map(int, mes.split('-'))
        dia_ini = date(y, m, 1)
        dia_fin = date(y, m+1 if m<12 else 1, 1) - timedelta(days=1) if m<12 else date(y+1,1,1)-timedelta(days=1)
        print(f"\n📅 Procesando {mes}: {dia_ini} → {dia_fin}")

        # 4) Cargar fichadas del mes (para inferir findes sin default)
        fichadas = sb.table('rrhh_fichadas_raw').select(
            'empleado_id, fecha, hora'
        ).gte('fecha', dia_ini.isoformat()).lte('fecha', dia_fin.isoformat()).execute().data
        # Agrupar primera entrada del día
        fich_por_dia = defaultdict(list)
        for f in fichadas:
            if f['empleado_id'] is None: continue
            fich_por_dia[(f['empleado_id'], f['fecha'])].append(f['hora'])

        for emp in empleados:
            local = emp['local']
            cursor = dia_ini
            while cursor <= dia_fin:
                # Python weekday: 0=Lun ... 6=Dom. Nuestra convención: 0=Dom, 1=Lun, ..., 6=Sáb
                dow_py = cursor.weekday()
                dow_db = 0 if dow_py == 6 else dow_py + 1
                key_def = (emp['id'], dow_db)
                fecha_str = cursor.isoformat()
                fich = sorted(fich_por_dia.get((emp['id'], fecha_str), []))

                row = None
                if key_def in def_map:
                    # Usar default
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
                    # No hay default pero fichó → inferir desde primera entrada
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

    print(f"\n📊 Total turnos a generar: {len(inserts)}")
    print(f"  - Desde default: {stats['desde_default']}")
    print(f"  - Inferidos:     {stats['inferido']}")

    if args.dry_run:
        print("\n🔵 DRY-RUN — no se escribe")
        # Mostrar primeros 5 inferidos como ejemplo
        inferidos = [i for i in inserts if 'inferido' in (i.get('planificado_por') or '')]
        print(f"\nEjemplos de inferidos (primeros 5):")
        for i in inferidos[:5]:
            print(f"  emp={i['empleado_id']} {i['fecha']} {i['hora_inicio']}-{i['hora_fin']}")
        return

    # Upsert (borra y reinserta para los meses procesados)
    for mes in meses:
        y, m = map(int, mes.split('-'))
        dia_ini = date(y, m, 1).isoformat()
        dia_fin = (date(y, m+1 if m<12 else 1, 1) - timedelta(days=1) if m<12 else date(y+1,1,1)-timedelta(days=1)).isoformat()
        sb.table('rrhh_turnos').delete().gte('fecha', dia_ini).lte('fecha', dia_fin).execute()
    print(f"✓ Turnos previos borrados para los meses")

    BATCH = 200
    subidos = 0
    for i in range(0, len(inserts), BATCH):
        batch = inserts[i:i+BATCH]
        sb.table('rrhh_turnos').insert(batch).execute()
        subidos += len(batch)
        print(f"  ✓ {subidos}/{len(inserts)}")
    print(f"\n✅ {subidos} turnos generados")


if __name__ == '__main__':
    main()
