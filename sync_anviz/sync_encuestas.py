# -*- coding: utf-8 -*-
"""
═══════════════════════════════════════════════════════════════════════
 CRM ADORNO — Sync de encuestas de satisfacción (Google Forms → Supabase)
═══════════════════════════════════════════════════════════════════════

 Lee las respuestas de los Google Forms de satisfacción (uno por local) vía
 la API de Google Forms y las vuelca en la tabla crm_encuestas de Supabase.
 Las encuestas son anónimas: solo puntaje + comentario.

 SETUP (una sola vez):
   1. En el proyecto de Google Cloud (el mismo del Calendar):
      APIs & Services → Library → "Google Forms API" → ENABLE
   2. Pantalla de consentimiento OAuth → Scopes → agregá:
        .../auth/forms.responses.readonly
        .../auth/forms.body.readonly
      (y asegurate de que claudiaadornosrl@gmail.com siga como test user)
   3. Borrá el token viejo de forms si existe, para forzar el re-consentimiento:
        del sync_anviz\\google_token_forms.json
   4. Corré el DRY-RUN: se abrirá el navegador para autorizar.

 USO:
   python sync_encuestas.py             # DRY-RUN (no escribe en Supabase)
   python sync_encuestas.py --aplicar   # Inserta/actualiza en crm_encuestas
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
from urllib import request as urlrequest, error as urlerror

try:
    from dotenv import load_dotenv
    load_dotenv(Path(__file__).parent / '.env')
except ImportError:
    pass

SUPA_URL = os.environ.get('SUPABASE_URL', 'https://kwwiykssrpabncpqtmwi.supabase.co')
SUPA_KEY = os.environ.get('SUPABASE_SERVICE_KEY')

SYNC_DIR   = Path(__file__).parent
CRED_FILE  = SYNC_DIR / 'google_credentials.json'
TOKEN_FILE = SYNC_DIR / 'google_token_forms.json'   # token propio (scopes de Forms)

SCOPES = [
    'https://www.googleapis.com/auth/forms.responses.readonly',
    'https://www.googleapis.com/auth/forms.body.readonly',
]

# Los dos formularios de satisfacción (claudiaadornosrl@gmail.com).
# El local se deriva del título del form, pero dejamos el mapeo explícito por ID
# como fallback por si algún día renombran el título.
FORM_IDS = [
    '1FPCp_a7o8cX_WYnAbNvg4sfOvYQwysonoO9VvD5tvg0',
    '1gPz_GEG-Ic-BRS1bJIgUN4g9P6GiQdltcidMESgDDno',
]
LOCAL_POR_FORM = {
    # se completan automáticamente leyendo el título; este dict es solo override manual
}

# ─────────────────────────── Supabase REST ───────────────────────────
H = {
    "apikey": SUPA_KEY or '',
    "Authorization": f"Bearer {SUPA_KEY or ''}",
    "Content-Type": "application/json",
}

def supa_upsert(rows):
    """Upsert por response_id (merge-duplicates sobre la unique key)."""
    if not rows:
        return 0
    data = json.dumps(rows).encode()
    url = f"{SUPA_URL}/rest/v1/crm_encuestas?on_conflict=response_id"
    req = urlrequest.Request(
        url, data=data,
        headers={**H, "Prefer": "resolution=merge-duplicates,return=minimal"},
        method='POST')
    with urlrequest.urlopen(req) as r:
        return len(rows) if r.status in (200, 201, 204) else 0

# ─────────────────────────── Google Forms ───────────────────────────
def get_forms_service():
    from google.oauth2.credentials import Credentials
    from google_auth_oauthlib.flow import InstalledAppFlow
    from google.auth.transport.requests import Request
    from googleapiclient.discovery import build

    creds = None
    if TOKEN_FILE.exists():
        creds = Credentials.from_authorized_user_file(str(TOKEN_FILE), SCOPES)
    if not creds or not creds.valid:
        if creds and creds.expired and creds.refresh_token:
            creds.refresh(Request())
        else:
            flow = InstalledAppFlow.from_client_secrets_file(str(CRED_FILE), SCOPES)
            creds = flow.run_local_server(port=0)
        with open(TOKEN_FILE, 'w') as f:
            f.write(creds.to_json())
    return build('forms', 'v1', credentials=creds)


def local_desde_titulo(titulo):
    t = (titulo or '').lower()
    if 'unicenter' in t: return 'unicenter'
    if 'alcorta'   in t: return 'alcorta'
    if 'oficina'   in t: return 'oficina'
    return None


def clasificar_preguntas(form):
    """Devuelve (rating_qid, rating_max, comentario_qid) leyendo la estructura."""
    rating_qid = rating_max = comentario_qid = None
    for item in form.get('items', []):
        qi = item.get('questionItem')
        if not qi:
            continue
        q = qi.get('question', {})
        qid = q.get('questionId')
        if 'scaleQuestion' in q and rating_qid is None:
            rating_qid = qid
            rating_max = q['scaleQuestion'].get('high')
        elif 'ratingQuestion' in q and rating_qid is None:
            rating_qid = qid
            rating_max = q['ratingQuestion'].get('ratingScaleLevel')
        elif 'textQuestion' in q and comentario_qid is None:
            comentario_qid = qid
    return rating_qid, rating_max, comentario_qid


def valor_respuesta(answers, qid):
    if not qid or qid not in answers:
        return None
    ta = answers[qid].get('textAnswers', {}).get('answers', [])
    return ta[0].get('value') if ta else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--aplicar', action='store_true', help='Escribir en Supabase')
    args = ap.parse_args()

    if not SUPA_KEY:
        sys.exit("❌ Falta SUPABASE_SERVICE_KEY en sync_anviz/.env")

    service = get_forms_service()
    total_filas = []

    for fid in FORM_IDS:
        form = service.forms().get(formId=fid).execute()
        titulo = form.get('info', {}).get('title', '')
        local = LOCAL_POR_FORM.get(fid) or local_desde_titulo(titulo)
        rating_qid, rating_max, com_qid = clasificar_preguntas(form)
        print(f"\n📋 {titulo}  →  local={local}  (rating_max={rating_max})")

        if not local:
            print("   ⚠ No pude derivar el local del título; salteo este form.")
            continue

        page_token = None
        n = 0
        while True:
            resp = service.forms().responses().list(
                formId=fid, pageToken=page_token).execute()
            for r in resp.get('responses', []):
                answers = r.get('answers', {})
                puntaje_raw = valor_respuesta(answers, rating_qid)
                comentario  = valor_respuesta(answers, com_qid)
                try:
                    puntaje = float(puntaje_raw) if puntaje_raw is not None else None
                except ValueError:
                    puntaje = None
                fila = {
                    "local_id": local,
                    "form_id": fid,
                    "response_id": r.get('responseId'),
                    "creado_at": r.get('lastSubmittedTime') or r.get('createTime'),
                    "puntaje": puntaje,
                    "puntaje_max": rating_max,
                    "comentario": comentario,
                    "raw": json.dumps(answers),
                }
                total_filas.append(fila)
                n += 1
            page_token = resp.get('nextPageToken')
            if not page_token:
                break
        print(f"   {n} respuesta(s) leída(s).")

    print(f"\n🔢 Total: {len(total_filas)} respuesta(s).")
    if not args.aplicar:
        muestra = total_filas[:5]
        print("DRY-RUN (no escribo). Muestra:")
        for f in muestra:
            print(f"   [{f['local_id']}] {f['creado_at']}  puntaje={f['puntaje']}/{f['puntaje_max']}  "
                  f"coment={(f['comentario'] or '')[:50]!r}")
        print("\n→ Si está OK, corré:  python sync_encuestas.py --aplicar")
        return

    escritas = 0
    BATCH = 200
    for i in range(0, len(total_filas), BATCH):
        escritas += supa_upsert(total_filas[i:i+BATCH])
    print(f"✅ {escritas} respuesta(s) sincronizada(s) en crm_encuestas.")


if __name__ == '__main__':
    main()
