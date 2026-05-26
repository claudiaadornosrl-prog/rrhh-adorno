r"""
═══════════════════════════════════════════════════════════════════════
 10_procesar_vacaciones_firmadas.py
 Procesa los mails que llegan a claudiaadornosrl@gmail.com con
 "VACACIONES <nombre>" en el subject + PDF adjunto firmado, los
 guarda en OneDrive\EMPLEADOS\VACACIONES\<APELLIDO NOMBRE>\ y marca
 el movimiento como documento firmado recibido en la DB.

 SETUP INICIAL (una sola vez):
   1. Activar 2FA en la cuenta de Google
   2. Generar un "App password" en https://myaccount.google.com/apppasswords
   3. Agregar en sync_anviz/.env:
        GMAIL_USER=claudiaadornosrl@gmail.com
        GMAIL_APP_PASSWORD=xxxxxxxxxxxxxxxx

 USO:
   python 10_procesar_vacaciones_firmadas.py            # DRY-RUN (no escribe)
   python 10_procesar_vacaciones_firmadas.py --aplicar  # Procesa y guarda
   python 10_procesar_vacaciones_firmadas.py --aplicar --marcar-leido  # Además marca el mail como leído
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
from datetime import datetime, date
from collections import defaultdict

try:
    from dotenv import load_dotenv
    load_dotenv(Path(__file__).parent.parent / 'sync_anviz' / '.env')
except ImportError:
    pass

SUPA_URL = os.environ.get('SUPABASE_URL', 'https://kwwiykssrpabncpqtmwi.supabase.co')
SUPA_KEY = os.environ.get('SUPABASE_SERVICE_KEY')
GMAIL_USER = os.environ.get('GMAIL_USER', 'claudiaadornosrl@gmail.com')
GMAIL_PASS = os.environ.get('GMAIL_APP_PASSWORD')

# Ruta a la carpeta de vacaciones en OneDrive
ONEDRIVE_VACACIONES = Path(r'C:\Users\Usuario\OneDrive - Claudia Adorno SRL\DOCUMENTOS\EMPLEADOS\VACACIONES')

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
    # Quitar la palabra "vacaciones" y otras comunes
    for w in ['vacaciones', 'vacacion', 'notificacion', 'notificación', 'firma', 'firmada', 'firmado', 're:', 'fwd:']:
        txt = txt.replace(w, ' ')
    tokens = [t for t in re.split(r'[^a-zñáéíóú]+', txt) if len(t) >= 3]
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
    # Si el mejor tiene más coincidencias que el segundo, es claro
    if len(candidatos) == 1 or candidatos[0][0] > candidatos[1][0]:
        return candidatos[0][1]
    # Empate — devolver lista para que el usuario decida
    return [c[1] for c in candidatos if c[0] == candidatos[0][0]]


def buscar_carpeta_empleado(empleado_nombre):
    """Encuentra la carpeta en OneDrive matcheando por apellido."""
    if not ONEDRIVE_VACACIONES.exists():
        return None
    nombre_norm = normalizar(empleado_nombre).replace(',', '')
    partes = nombre_norm.split()
    if not partes: return None
    apellido = partes[0]   # En la DB el primer token suele ser el apellido

    # Match exacto del nombre
    for d in ONEDRIVE_VACACIONES.iterdir():
        if not d.is_dir(): continue
        d_norm = normalizar(d.name)
        if apellido in d_norm.split():
            return d
    # Fallback: parcial
    for d in ONEDRIVE_VACACIONES.iterdir():
        if not d.is_dir(): continue
        if apellido in normalizar(d.name):
            return d
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--aplicar', action='store_true')
    ap.add_argument('--marcar-leido', action='store_true', help='Marca el mail como leído al procesarlo')
    args = ap.parse_args()

    if not SUPA_KEY: sys.exit("❌ Falta SUPABASE_SERVICE_KEY en .env")
    if not GMAIL_PASS: sys.exit("❌ Falta GMAIL_APP_PASSWORD en .env\n   Generalo en https://myaccount.google.com/apppasswords")

    print(f"📂 Carpeta OneDrive: {ONEDRIVE_VACACIONES}")
    if not ONEDRIVE_VACACIONES.exists():
        sys.exit(f"❌ No existe la carpeta. Verificá la ruta.")

    # Empleados activos
    print(f"📥 Cargando empleados...")
    empleados = fetch_get("rrhh_empleados?select=id,nombre_completo,local,estado&estado=eq.activo")
    print(f"   {len(empleados)} empleados activos")

    # Conectar a Gmail vía IMAP
    print(f"\n📬 Conectando a Gmail ({GMAIL_USER})...")
    M = imaplib.IMAP4_SSL('imap.gmail.com')
    M.login(GMAIL_USER, GMAIL_PASS)
    M.select('INBOX')

    # Buscar mails sin leer con "VACACIONES" O "VAC-" en subject
    typ, data = M.search(None, '(OR (SUBJECT "VACACIONES") (SUBJECT "VAC-") UNSEEN)')
    if typ != 'OK':
        print(f"   ❌ Error en search")
        return
    nums = data[0].split()
    print(f"   {len(nums)} mails sin leer relacionados con vacaciones")

    if not nums:
        print(f"\n✅ Sin mails nuevos para procesar.")
        M.logout()
        return

    procesados, ambiguos, sin_pdf, sin_match = 0, 0, 0, 0

    for num in nums:
        typ, data = M.fetch(num, '(RFC822)')
        if typ != 'OK': continue
        msg = email.message_from_bytes(data[0][1])
        subject = _decode_header(msg.get('Subject', ''))
        from_addr = _decode_header(msg.get('From', ''))
        fecha_mail = msg.get('Date', '')

        print(f"\n━ Mail #{num.decode()} ━")
        print(f"   Subject: {subject}")
        print(f"   From:    {from_addr}")

        # Buscar adjunto PDF
        pdf_bytes = None
        pdf_filename = None
        for part in msg.walk():
            ctype = part.get_content_type()
            filename = part.get_filename()
            if filename and filename.lower().endswith('.pdf'):
                pdf_bytes = part.get_payload(decode=True)
                pdf_filename = _decode_header(filename)
                break

        if not pdf_bytes:
            print(f"   ⚠ Sin PDF adjunto")
            sin_pdf += 1
            continue

        # Identificar por CÓDIGO VAC-NNNNN primero (más robusto)
        # Buscar en subject Y filename
        haystack = (subject + ' ' + (pdf_filename or ''))
        codigo_match = re.search(r'VAC-(\d{1,8})', haystack, re.IGNORECASE)
        mov = None
        emp = None
        if codigo_match:
            mov_id = int(codigo_match.group(1))
            movs = fetch_get(f"rrhh_vacaciones_movimientos?id=eq.{mov_id}&select=id,fecha_desde,fecha_hasta,dias,empleado_id,estado,documento_firmado_at")
            if movs:
                mov = movs[0]
                if mov.get('documento_firmado_at'):
                    print(f"   ⚠ El movimiento VAC-{mov_id:05d} ya tiene documento firmado")
                    continue
                emp = next((e for e in empleados if e['id'] == mov['empleado_id']), None)
                print(f"   ✓ Match por código VAC-{mov_id:05d} → {emp['nombre_completo'] if emp else '?'}")

        # Fallback: identificar por nombre en subject
        if not mov:
            emp_match = buscar_empleado(subject, empleados)
            if isinstance(emp_match, list):
                print(f"   ⚠ Ambiguo — varios candidatos: {[e['nombre_completo'] for e in emp_match]}")
                ambiguos += 1
                continue
            if not emp_match:
                print(f"   ⚠ Sin match — no se identificó empleado (ni por código ni por nombre)")
                sin_match += 1
                continue
            emp = emp_match
            print(f"   ✓ Empleado (por nombre): {emp['nombre_completo']}")

            # Buscar el movimiento más reciente aprobado/tomado sin documento firmado
            movs = fetch_get(f"rrhh_vacaciones_movimientos?empleado_id=eq.{emp['id']}&estado=in.(aprobada,tomada)&documento_firmado_at=is.null&select=id,fecha_desde,fecha_hasta,dias&order=fecha_desde.desc&limit=5")
            if not movs:
                print(f"   ⚠ Sin movimientos pendientes de documento para este empleado")
                continue
            mov = movs[0]

        if not emp or not mov:
            print(f"   ⚠ Inconsistencia, salto")
            continue

        print(f"   ✓ Movimiento: id={mov['id']} {mov['fecha_desde']} → {mov['fecha_hasta']} ({mov['dias']}d)")

        # Localizar carpeta del empleado
        carpeta = buscar_carpeta_empleado(emp['nombre_completo'])
        if not carpeta:
            print(f"   ⚠ No se encontró carpeta en OneDrive para {emp['nombre_completo']}")
            continue
        print(f"   ✓ Carpeta destino: {carpeta}")

        # Armar nombre del archivo
        # Buscar año del saldo desde la tabla rrhh_vacaciones
        vac_id = mov.get('vacaciones_id')
        año_saldo = mov['fecha_desde'][:4]
        if vac_id:
            saldos = fetch_get(f"rrhh_vacaciones?id=eq.{vac_id}&select=año")
            if saldos: año_saldo = saldos[0]['año']
        nombre_corto = emp['nombre_completo']
        nombre_clean = nombre_corto.replace(',', '').strip()
        d1 = mov['fecha_desde'].split('-'); d1str = f"{d1[2]}-{d1[1]}-{d1[0]}"
        d2 = mov['fecha_hasta'].split('-'); d2str = f"{d2[2]}-{d2[1]}-{d2[0]}"
        fname = f"VACACIONES {año_saldo} {nombre_clean} {d1str} AL {d2str}.pdf"
        fpath = carpeta / fname
        print(f"   📄 Archivo: {fname}")

        if not args.aplicar:
            print(f"   🔵 DRY-RUN — no se guarda")
            procesados += 1
            continue

        # Guardar PDF
        with open(fpath, 'wb') as f:
            f.write(pdf_bytes)
        print(f"   ✓ Guardado")

        # Marcar movimiento en DB:
        #   - documento_firmado_at: ahora
        #   - documento_firmado_path: ruta OneDrive
        #   - calendar_sync_pending=true: para que después se cree el evento en Calendar
        #   - Si estaba 'aprobada' → pasar a 'tomada' (el documento firmado confirma que se va a tomar)
        patch = {
            'documento_firmado_path': str(fpath),
            'documento_firmado_at': datetime.utcnow().isoformat() + 'Z',
            'documento_firmado_origen': 'mail',
            'calendar_sync_pending': True,
        }
        if mov.get('estado') == 'aprobada':
            patch['estado'] = 'tomada'
        fetch_patch(f"rrhh_vacaciones_movimientos?id=eq.{mov['id']}", patch)
        print(f"   ✓ Marcado en DB (calendar_sync_pending=true)")

        if args.marcar_leido:
            M.store(num, '+FLAGS', '\\Seen')
            print(f"   ✓ Mail marcado como leído")

        procesados += 1

    print(f"\n━━━ Resumen ━━━")
    print(f"   Procesados:        {procesados}")
    print(f"   Sin PDF adjunto:   {sin_pdf}")
    print(f"   Sin match empleado:{sin_match}")
    print(f"   Ambiguos:          {ambiguos}")

    M.logout()
    if not args.aplicar:
        print(f"\n🔵 DRY-RUN — para aplicar:")
        print(f"   python {Path(__file__).name} --aplicar --marcar-leido")


if __name__ == '__main__':
    main()
