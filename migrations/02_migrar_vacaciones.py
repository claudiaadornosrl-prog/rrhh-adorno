"""
═══════════════════════════════════════════════════════════════════════
 MIGRACIÓN — Vacaciones históricas desde OneDrive
 Lee VACACIONES/{NOMBRE EMPLEADO}/VACACIONES YYYY [NOMBRE] DD-MM-YYYY AL DD-MM-YYYY.pdf
 y crea movimientos en rrhh_vacaciones_movimientos (estado='tomada').
═══════════════════════════════════════════════════════════════════════

USO:
    python 02_migrar_vacaciones.py --dry-run
    python 02_migrar_vacaciones.py
"""
import os, re, sys, argparse, unicodedata
from pathlib import Path
from datetime import datetime

ONEDRIVE_ROOT = Path(r"C:\Users\Usuario\OneDrive - Claudia Adorno SRL\DOCUMENTOS\EMPLEADOS\VACACIONES")
SUPA_URL = "https://kwwiykssrpabncpqtmwi.supabase.co"
SUPA_KEY = os.environ.get("SUPABASE_SERVICE_KEY", "")

def slug(s: str) -> str:
    s = unicodedata.normalize('NFD', s)
    s = ''.join(c for c in s if unicodedata.category(c) != 'Mn')
    return re.sub(r'[^a-z]', '', s.lower())

# Regex para extraer rango de fechas del nombre
# Variantes: "01-12-2024 AL 14-12-2024" o "01-12-2024 A 14-12-2024" o "01/12/2024 al 14/12/2024"
RE_FECHAS = re.compile(r'(\d{1,2})[-/](\d{1,2})[-/](\d{2,4})\s*(?:AL?|A)\s*(\d{1,2})[-/](\d{1,2})[-/](\d{2,4})', re.IGNORECASE)

def parse_fecha_dmy(d, m, y):
    d, m, y = int(d), int(m), int(y)
    if y < 100: y += 2000
    try:
        return datetime(y, m, d).date()
    except ValueError:
        return None

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--dry-run', action='store_true')
    args = ap.parse_args()

    if not args.dry_run and not SUPA_KEY:
        print("❌ Setear SUPABASE_SERVICE_KEY"); sys.exit(1)
    if not ONEDRIVE_ROOT.exists():
        print(f"❌ No existe: {ONEDRIVE_ROOT}"); sys.exit(1)

    APELLIDO_TO_ID = {}
    if not args.dry_run:
        from supabase import create_client
        sb = create_client(SUPA_URL, SUPA_KEY)
        empleados = sb.table('rrhh_empleados').select('id, apellido').execute().data
        for e in empleados:
            APELLIDO_TO_ID[slug(e['apellido'])] = e['id']

    stats = {'visitados': 0, 'parseados': 0, 'insertados': 0, 'sin_match': 0, 'sin_fechas': 0}
    sin_match = set()

    for emp_dir in ONEDRIVE_ROOT.iterdir():
        if not emp_dir.is_dir(): continue
        if emp_dir.name.startswith('EX'): continue
        # Apellido en nombre de carpeta: "BIANCHI MARIA SOLEDAD" → apellido = primera palabra
        palabras = emp_dir.name.split()
        if not palabras: continue
        apellido = palabras[0]
        emp_id = APELLIDO_TO_ID.get(slug(apellido)) if not args.dry_run else 'DRY'

        for pdf in emp_dir.glob('*.pdf'):
            stats['visitados'] += 1
            m = RE_FECHAS.search(pdf.name)
            if not m:
                stats['sin_fechas'] += 1
                continue
            desde = parse_fecha_dmy(m.group(1), m.group(2), m.group(3))
            hasta = parse_fecha_dmy(m.group(4), m.group(5), m.group(6))
            if not desde or not hasta or hasta < desde:
                stats['sin_fechas'] += 1
                continue
            stats['parseados'] += 1
            dias = (hasta - desde).days + 1

            if not emp_id or emp_id == 'DRY' and not args.dry_run:
                stats['sin_match'] += 1
                sin_match.add(apellido)
                continue

            print(f"  {apellido:25s} {desde} → {hasta} ({dias}d)")

            if args.dry_run: continue

            # Buscar vacaciones_id del año
            año = desde.year
            try:
                vac = sb.table('rrhh_vacaciones').select('id').eq('empleado_id', emp_id).eq('año', año).maybe_single().execute().data
                if not vac:
                    # Crear con 14 días (default — se recalcula después)
                    vac = sb.table('rrhh_vacaciones').insert({
                        'empleado_id': emp_id, 'año': año, 'dias_correspondientes': 14, 'dias_tomados': 0,
                    }).execute().data[0]
                sb.table('rrhh_vacaciones_movimientos').insert({
                    'vacaciones_id': vac['id'],
                    'empleado_id': emp_id,
                    'fecha_desde': desde.isoformat(),
                    'fecha_hasta': hasta.isoformat(),
                    'dias': dias,
                    'estado': 'tomada',
                    'solicitado_por': 'migracion-historica',
                    'aprobado_por': 'migracion-historica',
                    'fecha_aprobacion': datetime.now().isoformat(),
                    'observaciones': f'Migrado desde OneDrive: {pdf.name}',
                }).execute()
                stats['insertados'] += 1
            except Exception as e:
                print(f"     ❌ {e}")

    print("\n" + "═"*60)
    print(f"📊 RESUMEN VACACIONES")
    print(f"  Archivos visitados:        {stats['visitados']}")
    print(f"  Con fechas parseables:     {stats['parseados']}")
    print(f"  Insertados {'(dry)' if args.dry_run else 'OK'}: {stats['insertados']}")
    print(f"  Sin match empleado:        {stats['sin_match']}")
    print(f"  Sin fechas en nombre:      {stats['sin_fechas']}")
    if sin_match:
        print(f"\n⚠️ Apellidos sin coincidencia:")
        for a in sorted(sin_match): print(f"     {a}")

if __name__ == '__main__':
    main()
