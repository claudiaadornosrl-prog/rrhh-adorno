"""
═══════════════════════════════════════════════════════════════════════
 MIGRACIÓN — Recibos de sueldo desde OneDrive
 Sube los PDFs de RECIBOS DE SUELDO/{LOCAL}/{AÑO}/Liqui {Apellido}/*.pdf
 a Supabase Storage bucket 'rrhh-recibos' y crea registros en rrhh_sueldos.
═══════════════════════════════════════════════════════════════════════

USO:
    python 01_migrar_recibos.py --dry-run               # Solo lista, no sube
    python 01_migrar_recibos.py --año 2026              # Solo año específico
    python 01_migrar_recibos.py --empleado "BIANCHI"    # Solo un empleado
    python 01_migrar_recibos.py                         # Sube todo (cuidado, son ~3300 PDFs)

REQUIERE:
    pip install supabase python-dotenv

CONFIGURACIÓN:
    Setear SUPABASE_SERVICE_KEY en .env (NO la anon key — necesita service role para skipear RLS)
"""
import os
import re
import sys
import argparse
import unicodedata
from pathlib import Path
from datetime import datetime

# ── CONFIG ────────────────────────────────────────────────────────
ONEDRIVE_ROOT = Path(r"C:\Users\Usuario\OneDrive - Claudia Adorno SRL\DOCUMENTOS\EMPLEADOS\RECIBOS DE SUELDO")
SUPA_URL = "https://kwwiykssrpabncpqtmwi.supabase.co"
SUPA_KEY = os.environ.get("SUPABASE_SERVICE_KEY", "")  # ⚠️ service role key, NO la anon

# Mapeo carpeta OneDrive → local en RRHH
LOCAL_MAP = {
    "UNICENTER":     "unicenter",
    "ALCORTA":       "alcorta",
    "ADMINISTRACION":"oficina",
    # Locales históricos (los empleados están dados de baja, los recibos también):
    "BARUGEL":       None,  # skipear
    "EL SOLAR":      None,
    "DESIGN":        None,
}

# Map apellido → empleado_id (lo cargamos al iniciar consultando Supabase)
APELLIDO_TO_ID = {}

# ── HELPERS ────────────────────────────────────────────────────────
def slug(s: str) -> str:
    """Quita tildes, lower, sin caracteres raros — para matching de apellidos."""
    s = unicodedata.normalize('NFD', s)
    s = ''.join(c for c in s if unicodedata.category(c) != 'Mn')
    return re.sub(r'[^a-z]', '', s.lower())

def extraer_apellido_y_periodo(filename: str, año: int):
    """
    Intenta extraer (apellido, periodo) de nombres como:
      'ALMADA 10-2015 SIN FIRMAR.pdf'
      'BIANCHI Liq 03-2024.pdf'
      'BIANCHI Aguinaldo 2024.pdf'
      'ADORNO 04-2026.pdf'
    """
    name = Path(filename).stem.upper()
    # Buscar patrón MM-YYYY o M-YYYY
    m = re.search(r'(\d{1,2})[-/_](\d{4})', name)
    if m:
        mes, año_pdf = int(m.group(1)), int(m.group(2))
        if 1 <= mes <= 12 and 2010 <= año_pdf <= 2030:
            periodo = f"{año_pdf}-{mes:02d}"
        else:
            periodo = None
    else:
        periodo = None
    # Apellido = primera palabra antes del primer número/concepto
    palabras = re.findall(r'[A-ZÁÉÍÓÚÑ]+', name)
    apellido = palabras[0] if palabras else None
    return apellido, periodo

# ── MAIN ────────────────────────────────────────────────────────
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--dry-run', action='store_true', help='Solo listar, no subir')
    ap.add_argument('--año', type=int, help='Procesar solo un año')
    ap.add_argument('--empleado', type=str, help='Procesar solo apellido (case insensitive)')
    ap.add_argument('--local', type=str, choices=['unicenter','alcorta','oficina'], help='Procesar solo un local')
    args = ap.parse_args()

    if not args.dry_run and not SUPA_KEY:
        print("❌ Setear variable de entorno SUPABASE_SERVICE_KEY")
        print("   (NO uses la anon key — necesita service_role para escribir en cualquier carpeta de Storage)")
        sys.exit(1)

    if not ONEDRIVE_ROOT.exists():
        print(f"❌ No existe la carpeta: {ONEDRIVE_ROOT}")
        sys.exit(1)

    # Cargar mapeo apellido→empleado_id desde Supabase
    if not args.dry_run:
        from supabase import create_client
        sb = create_client(SUPA_URL, SUPA_KEY)
        empleados = sb.table('rrhh_empleados').select('id, apellido').execute().data
        for e in empleados:
            APELLIDO_TO_ID[slug(e['apellido'])] = e['id']
        print(f"📋 Cargados {len(APELLIDO_TO_ID)} empleados de Supabase")

    # Iterar
    stats = {'archivos': 0, 'subidos': 0, 'sin_match': 0, 'sin_periodo': 0, 'errores': 0, 'skip_local': 0}
    sin_match_apellidos = set()

    for local_dir in ONEDRIVE_ROOT.iterdir():
        if not local_dir.is_dir(): continue
        local = LOCAL_MAP.get(local_dir.name)
        if local is None:
            stats['skip_local'] += sum(1 for _ in local_dir.rglob('*.pdf'))
            continue
        if args.local and local != args.local:
            continue

        for año_dir in local_dir.iterdir():
            if not año_dir.is_dir(): continue
            try:
                año_int = int(año_dir.name)
            except ValueError:
                continue
            if args.año and año_int != args.año:
                continue

            for liqui_dir in año_dir.iterdir():
                if not liqui_dir.is_dir(): continue
                # carpeta "Liqui Bianchi Soledad" → apellido = Bianchi
                m = re.search(r'(?:liqui|liq|sueldos?)\s+([a-záéíóúñ]+)', liqui_dir.name, re.IGNORECASE)
                apellido_dir = m.group(1) if m else None

                for pdf in liqui_dir.glob('*.pdf'):
                    stats['archivos'] += 1
                    apellido, periodo = extraer_apellido_y_periodo(pdf.name, año_int)
                    apellido = apellido or apellido_dir
                    if args.empleado and (not apellido or args.empleado.upper() not in apellido.upper()):
                        continue

                    if not apellido:
                        stats['sin_match'] += 1
                        continue
                    if not periodo:
                        stats['sin_periodo'] += 1
                        continue

                    apellido_slug = slug(apellido)
                    emp_id = APELLIDO_TO_ID.get(apellido_slug)
                    if not args.dry_run and not emp_id:
                        sin_match_apellidos.add(apellido)
                        stats['sin_match'] += 1
                        continue

                    print(f"  {local:9s} {periodo} {apellido:18s} → {pdf.name}")

                    if args.dry_run:
                        stats['subidos'] += 1
                        continue

                    # Subir a Storage
                    try:
                        ext = pdf.suffix.lower()
                        storage_path = f"{emp_id}/recibo/{periodo}.pdf"
                        with open(pdf, 'rb') as f:
                            data = f.read()
                        sb.storage.from_('rrhh-recibos').upload(
                            storage_path, data,
                            {'content-type': 'application/pdf', 'upsert': 'true'}
                        )
                        # Insertar / upsert en rrhh_sueldos
                        sb.table('rrhh_sueldos').upsert({
                            'empleado_id': emp_id,
                            'periodo': periodo,
                            'recibo_url': storage_path,
                        }, on_conflict='empleado_id,periodo').execute()
                        stats['subidos'] += 1
                    except Exception as e:
                        stats['errores'] += 1
                        print(f"     ❌ {e}")

    # Resumen
    print("\n" + "═"*60)
    print(f"📊 RESUMEN")
    print(f"  Total archivos visitados:  {stats['archivos']}")
    print(f"  Subidos {'(simulado)' if args.dry_run else 'OK'}: {stats['subidos']}")
    print(f"  Sin match empleado:        {stats['sin_match']}")
    print(f"  Sin período detectable:    {stats['sin_periodo']}")
    print(f"  Skip por local histórico:  {stats['skip_local']}")
    print(f"  Errores:                   {stats['errores']}")
    if sin_match_apellidos:
        print(f"\n⚠️ Apellidos sin coincidencia ({len(sin_match_apellidos)}):")
        for a in sorted(sin_match_apellidos): print(f"     {a}")

if __name__ == '__main__':
    main()
