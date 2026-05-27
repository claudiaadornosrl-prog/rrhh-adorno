r"""
═══════════════════════════════════════════════════════════════════════
 11_sync_google_calendar.py
 Sincroniza vacaciones pendientes (calendar_sync_pending=true) con
 Google Calendar de cada local.

 SETUP INICIAL (una sola vez, ~10 minutos):

   A) Habilitar Google Calendar API
      1. Andá a https://console.cloud.google.com/
      2. Creá un proyecto nuevo (ej. "Adorno RRHH")
      3. APIs & Services → Library → buscá "Google Calendar API" → ENABLE

   B) Crear credenciales OAuth
      4. APIs & Services → Credentials → "+ CREATE CREDENTIALS" → OAuth client ID
      5. Configurar la pantalla de consentimiento (si te lo pide):
         - User type: Internal (si tu cuenta es Workspace) o External
         - App name: "Adorno RRHH Calendar Sync"
         - User support email: claudiaadornosrl@gmail.com
         - Developer contact: claudiaadornosrl@gmail.com
         - Scopes: agregá ".../auth/calendar.events"
         - Test users (si External): claudiaadornosrl@gmail.com
      6. Volvé a Credentials → CREATE CREDENTIALS → OAuth client ID
         - Application type: Desktop app
         - Name: "Sync vacaciones"
         - DOWNLOAD el JSON
      7. Guardalo como:
         C:\CRM_Adorno\rrhh-adorno\sync_anviz\google_credentials.json

   C) Instalar libs Python
      pip install google-auth google-auth-oauthlib google-api-python-client

   D) Primera ejecución (autorización del browser)
      python 11_sync_google_calendar.py --aplicar
      → Se abre el browser, autorizás con claudiaadornosrl@gmail.com
      → El script guarda automáticamente sync_anviz/google_token.json
      → Próximas ejecuciones NO requieren browser

 USO:
   python 11_sync_google_calendar.py              # DRY-RUN
   python 11_sync_google_calendar.py --aplicar    # Crear eventos en Calendar
═══════════════════════════════════════════════════════════════════════
"""
import sys
if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    except Exception:
        pass

import os, json, argparse, re
from pathlib import Path
from urllib import request as urlrequest
from urllib.parse import quote
from datetime import datetime, timedelta

try:
    from dotenv import load_dotenv
    load_dotenv(Path(__file__).parent.parent / 'sync_anviz' / '.env')
except ImportError:
    pass

SUPA_URL = os.environ.get('SUPABASE_URL', 'https://kwwiykssrpabncpqtmwi.supabase.co')
SUPA_KEY = os.environ.get('SUPABASE_SERVICE_KEY')

# Rutas de credenciales Google
SYNC_DIR = Path(__file__).parent.parent / 'sync_anviz'
CRED_FILE  = SYNC_DIR / 'google_credentials.json'
TOKEN_FILE = SYNC_DIR / 'google_token.json'

# Scopes para Calendar (read + write events)
SCOPES = ['https://www.googleapis.com/auth/calendar.events']

# Mapeo local → calendar_id (revisado por JP)
CALENDAR_POR_LOCAL = {
    'unicenter': 'unicenter@claudiaadorno.com',
    'alcorta':   'alcorta@claudiaadorno.com',
    'oficina':   'claudiaadornosrl@gmail.com',
}

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

def fetch_delete(path):
    req = urlrequest.Request(f"{SUPA_URL}/rest/v1/{_encode_url(path)}",
                             headers=H, method='DELETE')
    with urlrequest.urlopen(req, timeout=30) as r: return r.status


def normalizar_nombre_para_titulo(nombre_completo):
    """ "BENITEZ, ROMINA SOLANGE" → "Romina Benitez"
        "NOGUERA PARRA, ADRIAN"   → "Adrian Noguera Parra" (apellidos compuestos)
        "SANCHEZ, SONIA LUZ"      → "Sonia Sanchez"   """
    if not nombre_completo: return '?'
    partes = [p.strip() for p in nombre_completo.split(',')]
    if len(partes) == 2:
        apellido, nombre = partes
    else:
        # No tiene coma: asumir "APELLIDO NOMBRE"
        tokens = nombre_completo.split()
        if len(tokens) >= 2:
            apellido = tokens[0]
            nombre = ' '.join(tokens[1:])
        else:
            return nombre_completo.title()
    # Tomar solo primer nombre
    primer_nombre = nombre.split()[0] if nombre else ''
    # Capitalize
    primer_nombre = primer_nombre.capitalize()
    apellido = apellido.title()
    return f"{primer_nombre} {apellido}".strip()


def get_calendar_service():
    """Devuelve un service de Google Calendar autenticado."""
    try:
        from google.oauth2.credentials import Credentials
        from google_auth_oauthlib.flow import InstalledAppFlow
        from google.auth.transport.requests import Request
        from googleapiclient.discovery import build
    except ImportError:
        sys.exit("❌ Faltan libs. Instalá:\n   pip install google-auth google-auth-oauthlib google-api-python-client")

    creds = None
    if TOKEN_FILE.exists():
        creds = Credentials.from_authorized_user_file(str(TOKEN_FILE), SCOPES)

    if not creds or not creds.valid:
        if creds and creds.expired and creds.refresh_token:
            creds.refresh(Request())
        else:
            if not CRED_FILE.exists():
                sys.exit(f"❌ Falta {CRED_FILE}. Seguí el SETUP del script.")
            flow = InstalledAppFlow.from_client_secrets_file(str(CRED_FILE), SCOPES)
            creds = flow.run_local_server(port=0)
        with open(TOKEN_FILE, 'w') as f:
            f.write(creds.to_json())

    return build('calendar', 'v3', credentials=creds)


def procesar_borrados(service, aplicar):
    """Lee la cola rrhh_calendar_delete_queue y borra los eventos correspondientes
    de Google Calendar. Marca processed_at en cada item exitoso, error_msg si falla.
    410 Gone / 404 Not Found se consideran éxito (el evento ya no existe)."""
    print("\n🗑  Procesando cola de borrados...")
    cola = fetch_get("rrhh_calendar_delete_queue?processed_at=is.null&select=id,calendar_id,event_id,empleado_id,fecha_desde,fecha_hasta&order=queued_at.asc&limit=100")
    print(f"   {len(cola)} en cola")

    if not cola:
        return (0, 0)

    ok = fail = 0
    print(f"\n{'#':>3} {'Calendar':40} {'Event':45} {'Fechas':25}")
    print("─" * 115)

    for c in cola:
        fechas = f"{c.get('fecha_desde','?')}→{c.get('fecha_hasta','?')}"
        print(f"   {c['id']:>3} {(c['calendar_id'] or '?')[:40]:40} {(c['event_id'] or '?')[:45]:45} {fechas}")

        if not aplicar:
            ok += 1
            continue

        try:
            if c['calendar_id'] in (None, '', 'unknown'):
                raise ValueError("calendar_id no mapeado (empleado sin local o local inválido)")
            service.events().delete(calendarId=c['calendar_id'], eventId=c['event_id']).execute()
            print(f"        ✓ Borrado del Calendar")
            fetch_patch(f"rrhh_calendar_delete_queue?id=eq.{c['id']}", {
                'processed_at': datetime.utcnow().isoformat() + 'Z',
                'error_msg': None,
            })
            ok += 1
        except Exception as e:
            msg = str(e)
            # 410 Gone / 404 → el evento ya no existe → lo damos por procesado
            if '410' in msg or '404' in msg or 'deleted' in msg.lower() or 'not found' in msg.lower():
                print(f"        ✓ Evento ya no existía (lo damos por OK)")
                fetch_patch(f"rrhh_calendar_delete_queue?id=eq.{c['id']}", {
                    'processed_at': datetime.utcnow().isoformat() + 'Z',
                    'error_msg': 'already_gone',
                })
                ok += 1
            else:
                print(f"        ❌ Error: {msg[:120]}")
                fetch_patch(f"rrhh_calendar_delete_queue?id=eq.{c['id']}", {
                    'error_msg': msg[:500],
                })
                fail += 1

    return (ok, fail)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--aplicar', action='store_true')
    args = ap.parse_args()

    if not SUPA_KEY: sys.exit("❌ Falta SUPABASE_SERVICE_KEY en .env")

    # Conectar a Google Calendar
    print("🔐 Conectando a Google Calendar...")
    service = get_calendar_service()
    print("   ✓ Autenticado")

    # ───── PASO 1: procesar cola de borrados ─────
    del_ok, del_fail = procesar_borrados(service, args.aplicar)

    # ───── PASO 2: procesar pendientes de creación ─────
    print("\n📥 Buscando vacaciones con calendar_sync_pending=true...")
    select = "id,fecha_desde,fecha_hasta,dias,observaciones,aprobado_por,empleado_id,vacaciones_id"
    pendientes = fetch_get(f"rrhh_vacaciones_movimientos?calendar_sync_pending=eq.true&calendar_event_id=is.null&select={select}&order=fecha_desde.desc&limit=100")
    print(f"   {len(pendientes)} pendiente/s")
    if not pendientes:
        print("\n━━━ Resumen ━━━")
        print(f"   Borrados OK:  {del_ok}")
        print(f"   Borrados fail: {del_fail}")
        print(f"   Creaciones:    0")
        if not args.aplicar and (del_ok + del_fail) > 0:
            print(f"\n🔵 DRY-RUN — Para aplicar: python {Path(__file__).name} --aplicar")
        return

    # Cargar empleados y saldos (para nombre + año)
    emp_ids = list({p['empleado_id'] for p in pendientes if p.get('empleado_id')})
    vac_ids = list({p['vacaciones_id'] for p in pendientes if p.get('vacaciones_id')})

    empleados = fetch_get(f"rrhh_empleados?id=in.({','.join(map(str,emp_ids))})&select=id,nombre_completo,local")
    emp_by = {e['id']: e for e in empleados}
    saldos = fetch_get(f"rrhh_vacaciones?id=in.({','.join(map(str,vac_ids))})&select=id,año") if vac_ids else []
    saldo_by = {s['id']: s.get('año') for s in saldos}

    ok = 0
    fail = 0
    print(f"\n{'#':>3} {'Empleado':30} {'Local':10} {'Desde→Hasta':25} {'Calendar':35}")
    print("─" * 110)

    for p in pendientes:
        emp = emp_by.get(p['empleado_id'])
        if not emp:
            print(f"   ⚠ id={p['id']}: sin empleado, salto")
            fail += 1
            continue
        local = emp['local']
        cal_id = CALENDAR_POR_LOCAL.get(local)
        if not cal_id:
            print(f"   ⚠ id={p['id']} ({emp['nombre_completo']}): local '{local}' sin calendar mapeado")
            fail += 1
            continue

        año_saldo = saldo_by.get(p.get('vacaciones_id')) or p['fecha_desde'][:4]
        titulo = f"{normalizar_nombre_para_titulo(emp['nombre_completo'])} ({año_saldo})"

        # Google Calendar: end es exclusivo para eventos de día completo → sumar 1 día
        fin_excl = (datetime.strptime(p['fecha_hasta'], '%Y-%m-%d') + timedelta(days=1)).strftime('%Y-%m-%d')

        codigo = f"VAC-{str(p['id']).zfill(5)}"
        descr = f"{codigo} · {p['dias']} días · saldo {año_saldo}"
        if p.get('aprobado_por'):
            descr += f" · aprobado por {p['aprobado_por']}"
        if p.get('observaciones'):
            descr += f"\n\n{p['observaciones']}"

        print(f"   {p['id']:>3} {emp['nombre_completo'][:30]:30} {local:10} {p['fecha_desde']}→{p['fecha_hasta']} → {cal_id[:35]}")
        print(f"        Título: '{titulo}'")

        if not args.aplicar:
            ok += 1
            continue

        # Crear evento en Google Calendar
        try:
            event_body = {
                'summary': titulo,
                'description': descr,
                'start': {'date': p['fecha_desde']},
                'end':   {'date': fin_excl},
            }
            created = service.events().insert(calendarId=cal_id, body=event_body).execute()
            event_id = created.get('id')
            print(f"        ✓ Evento creado: {event_id}")

            # Marcar en Supabase
            fetch_patch(f"rrhh_vacaciones_movimientos?id=eq.{p['id']}", {
                'calendar_event_id': event_id,
                'calendar_sync_pending': False,
            })
            ok += 1
        except Exception as e:
            print(f"        ❌ Error: {e}")
            fail += 1

    print(f"\n━━━ Resumen ━━━")
    print(f"   Borrados OK:           {del_ok}")
    print(f"   Borrados fail:         {del_fail}")
    print(f"   Creaciones {'a procesar' if not args.aplicar else 'OK     '}: {ok}")
    print(f"   Creaciones fallaron:   {fail}")
    if not args.aplicar:
        print(f"\n🔵 DRY-RUN — Para aplicar:")
        print(f"   python {Path(__file__).name} --aplicar")


if __name__ == '__main__':
    main()
