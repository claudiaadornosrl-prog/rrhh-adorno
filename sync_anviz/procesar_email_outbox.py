"""
procesar_email_outbox.py — Envía emails encolados en rrhh_email_outbox
                          usando SMTP de Gmail (App Password).

Uso:
    python procesar_email_outbox.py [--dry-run] [--limit N]

Programar en Task Scheduler cada 1 hora:
    schtasks /create /tn "RRHH_ProcesarEmailOutbox" /tr ^
        "C:\\Users\\Usuario\\AppData\\Local\\Programs\\Python\\Python313\\python.exe ^
         C:\\CRM_Adorno\\rrhh-adorno\\sync_anviz\\procesar_email_outbox.py" ^
        /sc hourly /mo 1 /st 09:00
"""

from __future__ import annotations

import argparse
import os
import smtplib
import sys
import traceback
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from email.utils import formataddr
from typing import Optional

from dotenv import load_dotenv
from supabase import create_client, Client

# Cargar .env del mismo directorio que este script
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
load_dotenv(os.path.join(SCRIPT_DIR, ".env"))

SUPABASE_URL = os.environ["SUPABASE_URL"]
SUPABASE_SERVICE_KEY = os.environ["SUPABASE_SERVICE_KEY"]
GMAIL_USER = os.environ["GMAIL_USER"]
GMAIL_APP_PASSWORD = os.environ["GMAIL_APP_PASSWORD"]

SMTP_HOST = "smtp.gmail.com"
SMTP_PORT = 587
FROM_NAME = "Sistema RRHH Claudia Adorno"
MAX_INTENTOS = 3


def enviar_smtp(to_addr: str, cc_addr: Optional[str], subject: str,
                body_text: str, body_html: Optional[str] = None) -> None:
    msg = MIMEMultipart("alternative")
    msg["From"] = formataddr((FROM_NAME, GMAIL_USER))
    msg["To"] = to_addr
    if cc_addr:
        msg["Cc"] = cc_addr
    msg["Subject"] = subject

    msg.attach(MIMEText(body_text, "plain", "utf-8"))
    if body_html:
        msg.attach(MIMEText(body_html, "html", "utf-8"))

    recipients = [to_addr]
    if cc_addr:
        recipients.append(cc_addr)

    with smtplib.SMTP(SMTP_HOST, SMTP_PORT) as smtp:
        smtp.ehlo()
        smtp.starttls()
        smtp.ehlo()
        smtp.login(GMAIL_USER, GMAIL_APP_PASSWORD)
        smtp.sendmail(GMAIL_USER, recipients, msg.as_string())


def procesar(dry_run: bool = False, limit: int = 20) -> None:
    sb: Client = create_client(SUPABASE_URL, SUPABASE_SERVICE_KEY)

    resp = (
        sb.table("rrhh_email_outbox")
          .select("*")
          .eq("status", "pendiente")
          .lt("intentos", MAX_INTENTOS)
          .order("created_at")
          .limit(limit)
          .execute()
    )
    pendientes = resp.data or []
    if not pendientes:
        print("No hay emails pendientes.")
        return

    print(f"Procesando {len(pendientes)} email(s) pendiente(s)…")
    for email in pendientes:
        eid = email["id"]
        to = email["to_addr"]
        cc = email.get("cc_addr")
        subject = email["subject"]
        body = email["body_text"]
        cat = email["categoria"]
        intentos_actual = email.get("intentos", 0)
        print(f"  → [{eid}] {cat} → {to}{(' + cc ' + cc) if cc else ''}")
        print(f"      Asunto: {subject}")

        if dry_run:
            print("      [DRY RUN] no se envió.")
            continue

        try:
            enviar_smtp(to, cc, subject, body, email.get("body_html"))
            sb.table("rrhh_email_outbox").update({
                "status": "enviado",
                "sent_at": "now()",
                "intentos": intentos_actual + 1,
            }).eq("id", eid).execute()
            print(f"      ✓ Enviado")
        except Exception as e:
            err = f"{type(e).__name__}: {e}"
            print(f"      ✗ Error: {err}")
            traceback.print_exc()
            nuevos_intentos = intentos_actual + 1
            sb.table("rrhh_email_outbox").update({
                "status": "error" if nuevos_intentos >= MAX_INTENTOS else "pendiente",
                "intentos": nuevos_intentos,
                "error_msg": err,
            }).eq("id", eid).execute()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true", help="No enviar; solo listar.")
    ap.add_argument("--limit", type=int, default=20)
    args = ap.parse_args()
    procesar(dry_run=args.dry_run, limit=args.limit)


if __name__ == "__main__":
    main()
