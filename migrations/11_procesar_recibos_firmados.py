r"""
═══════════════════════════════════════════════════════════════════════
 11_procesar_recibos_firmados.py
 Procesa los mails que llegan a claudiaadornosrl@gmail.com con
 "RECIBO YYYY-MM <APELLIDO>" o "REC-NNNNN" en el subject + PDF adjunto
 firmado, los guarda en
   OneDrive\EMPLEADOS\RECIBOS\<APELLIDO NOMBRE>\
 y marca el recibo como firmado en rrhh_liquidacion
 (pdf_firmado_at + pdf_url_firmado).

 SETUP INICIAL (una sola vez):
   1. Activar 2FA en la cuenta de Google (claudiaadornosrl@gmail.com)
   2. Generar un "App password" en https://myaccount.google.com/apppasswords
   3. Agregar en sync_anviz/.env:
        GMAIL_USER=claudiaadornosrl@gmail.com
        GMAIL_APP_PASSWORD=xxxxxxxxxxxxxxxx
      (Probablemente ya están si tenés corriendo el 10_procesar_vacaciones)

 USO:
   python 11_procesar_recibos_firmados.py            # DRY-RUN (no escribe)
   python 11_procesar_recibos_firmados.py --aplicar  # Procesa y guarda
   python 11_procesar_recibos_firmados.py --aplicar --marcar-leido
═══════════════════════════════════════════════════════════════════════
"""
import sys
if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    except Exception:
        pass

import os, json, re, argparse, imaplib, email
from email.header import decode_header
from pathlib import Path
from urllib import request as urlrequest
from urllib.parse import quote
from datetime import datetime

try:
    from dotenv import load_dotenv
    load_dotenv(Path(__file__).parent.parent / 'sync_anviz' / '.env')
except ImportError:
    pass

SUPA_URL = os.environ.get('SUPABASE_URL', 'https://kwwiykssrpabncpqtmwi.supabase.co')
SUPA_KEY = os.environ.get('SUPABASE_SERVICE_KEY')
GMAIL_USER = os.environ.get('GMAIL_USER', 'claudiaadornosrl@gmail.com')
GMAIL_PASS = os.environ.get('GMAIL_APP_PASSWORD')

# Carpeta donde se guardan los recibos firmados (por empleada)
ONEDRIVE_RECIBOS = Path(r'C:\Users\Usuario\OneDrive - Claudia Adorno SRL\DOCUMENTOS\EMPLEADOS\RECIBOS')

H = {
    "apikey": SUPA_KEY or '',
    "Authorization": f"Bearer {SUPA_KEY or ''}",
    "Content-Type": "application/json; charset=utf-8",
}


def _encode_url(p): return quote(p, safe="/?=&.,:%-_*+")

def fetch_get(path):
    req = urlrequest.Request(f"{SUPA_URL}/rest/v1/{_encode_url(path)}", headers=H)
    with urlrequest.urlopen(req, timeout=30) as r: return json.loads(r.read())

def fetch_patch(path, body):
    data = json.dumps(body, ensure_ascii=False).encode('utf-8')
    req = urlrequest.Request(f"{SUPA_URL}/rest/v1/{_encode_url(path)}",
                             data=data, headers={**H, "Prefer": "return=representation"},
                             method='PATCH')
    with urlrequest.urlopen(req, timeout=30) as r: return json.loads(r.read())


def _decode_header(h):
    if not h: return ''
    parts = decode_header(h)
    out = []
    for txt, enc in parts:
        if isinstance(txt, bytes):
            try: out.append(txt.decode(enc or 'utf-8', errors='replace'))
            except: out.append(txt.decode('utf-8', errors='replace'))
        else:
            out.append(txt)
    return ''.join(out)


def normalizar(s):
    return (s or '').strip().lower()


def buscar_empleado(subject_text, empleados):
    """Busca empleado por nombre/apellido en el subject."""
    txt = normalizar(subject_text)
    for w in ['recibo', 'haberes', 'sueldo', 'firmado', 'firmada', 're:', 'fwd:', 'rec-']:
        txt = txt.replace(w, ' ')
    tokens = [t for t in re.split(r'[^a-zñáéíóú0-9]+', txt) if len(t) >= 3]
    # Quitar tokens que parezcan año-mes (YYYY-MM o YYYY o MM)
    tokens = [t for t in tokens if not re.match(r'^\d{4}(-\d{1,2})?$', t) and not re.match(r'^\d{1,2}$', t)]
    if not tokens: return None

    candidatos = []
    for e in empleados:
        nombre_norm = normalizar(e['nombre_completo']).replace(',', '')
        partes_emp = set(re.split(r'\s+', nombre_norm))
        coincidencias = sum(1 for t in tokens if t in partes_emp)
        if coincidencias > 0:
            candidatos.append((coincidencias, e))
    if not candidatos: return None
    candidatos.sort(key=lambda x: -x[0])
    if len(candidatos) == 1 or candidatos[0][0] > candidatos[1][0]:
        return candidatos[0][1]
    return [c[1] for c in candidatos if c[0] == candidatos[0][0]]


def buscar_carpeta_empleado(empleado_nombre, crear_si_no_existe=True):
    """Encuentra la carpeta del empleado en OneDrive\\EMPLEADOS\\RECIBOS\\<APELLIDO NOMBRE>\\.
       Si no existe, la crea."""
    if not ONEDRIVE_RECIBOS.exists():
        if crear_si_no_existe:
            ONEDRIVE_RECIBOS.mkdir(parents=True, exist_ok=True)
        else:
            return None
    nombre_norm = normalizar(empleado_nombre).replace(',', '')
    partes = nombre_norm.split()
    if not partes: return None
    apellido = partes[0]

    # Match exacto del apellido en una carpeta existente
    for d in ONEDRIVE_RECIBOS.iterdir():
        if not d.is_dir(): continue
        d_norm = normalizar(d.name)
        if apellido in d_norm.split():
            return d
    # Fallback: parcial
    for d in ONEDRIVE_RECIBOS.iterdir():
        if not d.is_dir(): continue
        if apellido in normalizar(d.name):
            return d
    # No existe → la creamos con el nombre completo en mayúsculas
    if crear_si_no_existe:
        nuevo = ONEDRIVE_RECIBOS / empleado_nombre.replace(',', '').upper()
        nuevo.mkdir(parents=True, exist_ok=True)
        return nuevo
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--aplicar', action='store_true')
    ap.add_argument('--marcar-leido', action='store_true', help='Marca el mail como leído al procesarlo')
    args = ap.parse_args()

    if not SUPA_KEY: sys.exit("[ERROR] Falta SUPABASE_SERVICE_KEY en .env")
    if not GMAIL_PASS: sys.exit("[ERROR] Falta GMAIL_APP_PASSWORD en .env\n   Generalo en https://myaccount.google.com/apppasswords")

    print(f"Carpeta OneDrive: {ONEDRIVE_RECIBOS}")
    if not ONEDRIVE_RECIBOS.exists():
        print(f"   La carpeta no existe — se va a crear cuando llegue el primer recibo.")

    # Empleados activos
    print(f"Cargando empleados...")
    empleados = fetch_get("rrhh_empleados?select=id,nombre_completo,local,estado&estado=eq.activo")
    print(f"   {len(empleados)} empleados activos")

    # Conectar a Gmail vía IMAP
    print(f"\nConectando a Gmail ({GMAIL_USER})...")
    M = imaplib.IMAP4_SSL('imap.gmail.com')
    M.login(GMAIL_USER, GMAIL_PASS)
    M.select('INBOX')

    # Buscar mails sin leer con "RECIBO" o "REC-" en subject
    typ, data = M.search(None, '(OR (SUBJECT "RECIBO") (SUBJECT "REC-") UNSEEN)')
    if typ != 'OK':
        print(f"   ERROR en search")
        return
    nums = data[0].split()
    print(f"   {len(nums)} mails sin leer relacionados con recibos")

    if not nums:
        print(f"\nOK Sin mails nuevos para procesar.")
        M.logout()
        return

    procesados, ambiguos, sin_pdf, sin_match, ya_firmados = 0, 0, 0, 0, 0

    for num in nums:
        typ, data = M.fetch(num, '(RFC822)')
        if typ != 'OK': continue
        msg = email.message_from_bytes(data[0][1])
        subject = _decode_header(msg.get('Subject', ''))
        from_addr = _decode_header(msg.get('From', ''))

        print(f"\n--- Mail #{num.decode()} ---")
        print(f"   Subject: {subject}")
        print(f"   From:    {from_addr}")

        # Buscar adjunto PDF
        pdf_bytes = None
        pdf_filename = None
        for part in msg.walk():
            filename = part.get_filename()
            if filename and filename.lower().endswith('.pdf'):
                pdf_bytes = part.get_payload(decode=True)
                pdf_filename = _decode_header(filename)
                break

        if not pdf_bytes:
            print(f"   AVISO Sin PDF adjunto")
            sin_pdf += 1
            continue

        # Identificar por CÓDIGO REC-NNNNN primero (más robusto)
        haystack = (subject + ' ' + (pdf_filename or ''))
        codigo_match = re.search(r'REC-(\d{1,8})', haystack, re.IGNORECASE)
        liq = None
        emp = None
        if codigo_match:
            liq_id = int(codigo_match.group(1))
            liqs = fetch_get(
                f"rrhh_liquidacion?id=eq.{liq_id}"
                f"&select=id,periodo,empleado_id,pdf_firmado_at,pdf_enviado_at,recibo_neto,local,"
                f"empleado:rrhh_empleados(id,nombre_completo,local)"
            )
            if liqs:
                liq = liqs[0]
                if liq.get('pdf_firmado_at'):
                    print(f"   AVISO La liquidacion REC-{liq_id:05d} ya tiene PDF firmado guardado")
                    ya_firmados += 1
                    continue
                emp = liq.get('empleado') or next((e for e in empleados if e['id'] == liq['empleado_id']), None)
                print(f"   OK Match por codigo REC-{liq_id:05d} -> {emp['nombre_completo'] if emp else '?'}")

        # Fallback: identificar por nombre + período YYYY-MM en subject
        if not liq:
            emp_match = buscar_empleado(subject, empleados)
            if isinstance(emp_match, list):
                print(f"   AVISO Ambiguo, varios candidatos: {[e['nombre_completo'] for e in emp_match]}")
                ambiguos += 1
                continue
            if not emp_match:
                print(f"   AVISO Sin match (ni por codigo ni por nombre)")
                sin_match += 1
                continue
            emp = emp_match
            print(f"   OK Empleado (por nombre): {emp['nombre_completo']}")

            # Buscar la liquidación más reciente sin firmar de ese empleado
            # Si hay un YYYY-MM en el subject, lo usamos como filtro
            periodo_match = re.search(r'\b(20\d{2})[-/](\d{1,2})\b', subject)
            extra = ''
            if periodo_match:
                year = periodo_match.group(1)
                month = periodo_match.group(2).zfill(2)
                extra = f"&periodo=eq.{year}-{month}-01"
            liqs = fetch_get(
                f"rrhh_liquidacion?empleado_id=eq.{emp['id']}&pdf_firmado_at=is.null"
                f"{extra}&select=id,periodo,recibo_neto,local&order=periodo.desc&limit=5"
            )
            if not liqs:
                print(f"   AVISO Sin liquidaciones pendientes de firma para este empleado")
                continue
            liq = liqs[0]

        if not emp or not liq:
            print(f"   AVISO Inconsistencia, salto")
            continue

        print(f"   OK Liquidacion: id={liq['id']} periodo={liq['periodo']} neto={liq.get('recibo_neto')}")

        # Localizar/crear carpeta del empleado
        carpeta = buscar_carpeta_empleado(emp['nombre_completo'])
        if not carpeta:
            print(f"   AVISO No se pudo obtener carpeta en OneDrive para {emp['nombre_completo']}")
            continue
        print(f"   OK Carpeta destino: {carpeta}")

        # Armar nombre del archivo
        periodo = (liq['periodo'] or '')[:7]  # YYYY-MM
        nombre_clean = emp['nombre_completo'].replace(',', '').strip()
        fname = f"RECIBO {periodo} {nombre_clean}.pdf"
        fpath = carpeta / fname
        print(f"   ARCHIVO: {fname}")

        if not args.aplicar:
            print(f"   DRY-RUN -- no se guarda")
            procesados += 1
            continue

        # Guardar PDF
        with open(fpath, 'wb') as f:
            f.write(pdf_bytes)
        print(f"   OK Guardado en disco")

        # Marcar liquidación en DB
        patch = {
            'pdf_firmado_at': datetime.utcnow().isoformat() + 'Z',
            'pdf_url_firmado': str(fpath),
        }
        try:
            fetch_patch(f"rrhh_liquidacion?id=eq.{liq['id']}", patch)
            print(f"   OK Liquidacion #{liq['id']} marcada como firmada")
            procesados += 1
        except Exception as e:
            print(f"   ERROR al patchear liquidacion: {e}")
            continue

        if args.marcar_leido:
            M.store(num, '+FLAGS', '\\Seen')

    M.logout()
    print(f"\n========== RESUMEN ==========")
    print(f"  Procesados:           {procesados}")
    print(f"  Ya firmados (skip):   {ya_firmados}")
    print(f"  Sin PDF:              {sin_pdf}")
    print(f"  Ambiguos:             {ambiguos}")
    print(f"  Sin match empleado:   {sin_match}")
    print(f"  Total mails leidos:   {len(nums)}")


if __name__ == '__main__':
    main()
