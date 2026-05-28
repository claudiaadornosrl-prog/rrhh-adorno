# -*- coding: utf-8 -*-
"""
═══════════════════════════════════════════════════════════════════════
 RRHH ADORNO — Sync de ventas mensuales por local (Google Sheets → Supabase)
═══════════════════════════════════════════════════════════════════════

 Lee las planillas de Ventas {Local} 2026 desde Google Sheets y vuelca el
 total $ del mes de cada local en rrhh_ventas_local_mes (que alimenta el
 cálculo de comisión del módulo de sueldos).

 SETUP (una sola vez):
   1. En el proyecto de Google Cloud (el mismo del Calendar/Forms):
      APIs & Services → Library → "Google Sheets API" → ENABLE
   2. Pantalla de consentimiento OAuth → Acceso a los datos → agregá:
        .../auth/spreadsheets.readonly
   3. Borrá el token viejo si existe:
        del sync_anviz\\google_token_ventas.json
   4. Corré el DRY-RUN: se abrirá el navegador para autorizar.

 USO:
   python sync_ventas.py                       # mes actual, DRY-RUN
   python sync_ventas.py --periodo 2026-05     # mes específico, DRY-RUN
   python sync_ventas.py --aplicar             # mes actual, escribe en Supabase
   python sync_ventas.py --periodo 2026-05 --aplicar
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
from datetime import datetime
from urllib import request as urlrequest

try:
    from dotenv import load_dotenv
    load_dotenv(Path(__file__).parent / '.env')
except ImportError:
    pass

SUPA_URL = os.environ.get('SUPABASE_URL', 'https://kwwiykssrpabncpqtmwi.supabase.co')
SUPA_KEY = os.environ.get('SUPABASE_SERVICE_KEY')

SYNC_DIR   = Path(__file__).parent
CRED_FILE  = SYNC_DIR / 'google_credentials.json'
TOKEN_FILE = SYNC_DIR / 'google_token_ventas.json'

SCOPES = ['https://www.googleapis.com/auth/spreadsheets.readonly']

# Planillas de ventas por local (anuales — la hoja del mes la elegimos según el período)
SHEETS = {
    'alcorta':   '1AQRrGQWAbeg4PL5bKvmgPn_3dI2i0QBQPTWCwkPA7l0',
    'unicenter': '1VhLzDYjn-4sdZBkp2shEZQ1ZCQjzwMHXd5Y3MCDSJNs',
    'oficina':   '1R9bmAxhzKS0CNao8pDXivtkhD7sUsc0fri9zMTVYuao',
}

MESES = ['Enero','Febrero','Marzo','Abril','Mayo','Junio',
         'Julio','Agosto','Septiembre','Octubre','Noviembre','Diciembre']

# ─────────────────────────── Supabase ───────────────────────────
H = {
    "apikey": SUPA_KEY or '',
    "Authorization": f"Bearer {SUPA_KEY or ''}",
    "Content-Type": "application/json",
}

def supa_upsert_venta(local, periodo_iso, monto):
    """Upsert (local, periodo). El UNIQUE de la tabla lo resuelve."""
    data = json.dumps([{
        "local": local,
        "periodo": periodo_iso,
        "monto_ventas": monto,
        "origen": "sheet_ventas",
    }]).encode()
    url = f"{SUPA_URL}/rest/v1/rrhh_ventas_local_mes?on_conflict=local,periodo"
    req = urlrequest.Request(
        url, data=data,
        headers={**H, "Prefer": "resolution=merge-duplicates,return=minimal"},
        method='POST'
    )
    with urlrequest.urlopen(req) as r:
        return r.status in (200, 201, 204)

# ─────────────────────────── Google Sheets ───────────────────────────
def get_sheets_service():
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
    return build('sheets', 'v4', credentials=creds)


def parse_money(s):
    """Convierte '$1.234.567,89' o '1.234.567,89' o número a float."""
    if s is None or s == '':
        return None
    if isinstance(s, (int, float)):
        return float(s)
    txt = str(s).strip().replace('$', '').replace(' ', '')
    # Formato argentino: punto miles, coma decimal → quitar puntos, coma→punto
    if ',' in txt:
        txt = txt.replace('.', '').replace(',', '.')
    try:
        return float(txt)
    except ValueError:
        return None


def chequear_control_g1(values):
    """
    Verifica que el control G1 esté en OK (checkbox marcado).
    Replica la lógica del importrange original:
        =IF(importrange(SHEET, "mes!G1")=TRUE, ...)
    G1 es la celda que la oficina marca cuando termina de controlar la planilla.
    Acepta True, "OK", "SI", "YES" (case-insensitive).
    """
    if not values or len(values) < 1:
        return False, "Hoja vacía"
    fila0 = values[0]
    # G es la columna 7 (índice 6)
    if len(fila0) <= 6:
        return False, "Celda G1 sin valor (oficina aún no controló)"
    g1 = fila0[6]
    if g1 is True:
        return True, None
    if isinstance(g1, str) and g1.strip().upper() in ('OK', 'SI', 'SÍ', 'YES', 'TRUE', '✓'):
        return True, None
    return False, f"G1 = {g1!r} (la oficina todavía no marcó OK)"


def extraer_total_mes(values):
    """
    Dado el rango 2D de la hoja del mes, encuentra la celda con el total $ del mes.
    Estrategia:
      1. Encontrar la fila de encabezado (contiene 'Fecha' en col A o B).
      2. Identificar el índice de la columna 'Total' (no 'Acumulado').
      3. Encontrar la fila con 'Total' en col A.
      4. Devolver el valor en (fila_total, col_total).
    """
    header_row = None
    total_col = None
    for i, row in enumerate(values):
        norm = [str(c).strip().lower() for c in row]
        if 'fecha' in norm:
            header_row = i
            # Buscar el índice exacto de 'total' (no acumulado)
            for j, c in enumerate(norm):
                if c == 'total':
                    total_col = j
                    break
            break
    if header_row is None or total_col is None:
        return None, "No se encontró encabezado o columna 'Total'"

    # Fila de totales: 'total' en col A (después del header)
    for row in values[header_row+1:]:
        if row and str(row[0]).strip().lower() == 'total':
            if total_col < len(row):
                val = parse_money(row[total_col])
                if val is not None:
                    return val, None
    return None, "No se encontró la fila de total"


def main():
    ap = argparse.ArgumentParser()
    hoy = datetime.now()
    default_periodo = f"{hoy.year}-{hoy.month:02d}"
    ap.add_argument('--periodo', default=default_periodo, help="YYYY-MM (default: mes actual)")
    ap.add_argument('--aplicar', action='store_true', help="Escribir en Supabase")
    args = ap.parse_args()

    if not SUPA_KEY:
        sys.exit("❌ Falta SUPABASE_SERVICE_KEY en sync_anviz/.env")

    y, m = map(int, args.periodo.split('-'))
    mes_hoja = MESES[m-1]
    periodo_iso = f"{args.periodo}-01"
    print(f"\n📅 Período: {args.periodo}  (hoja: '{mes_hoja}')\n")

    service = get_sheets_service()
    resultados = []
    for local, sheet_id in SHEETS.items():
        try:
            # Leer un rango amplio del mes (A1:N50 cubre todos los layouts vistos)
            rng = f"{mes_hoja}!A1:N50"
            resp = service.spreadsheets().values().get(
                spreadsheetId=sheet_id, range=rng,
                valueRenderOption='UNFORMATTED_VALUE'
            ).execute()
            values = resp.get('values', [])
            if not values:
                print(f"  AVISO {local}: hoja '{mes_hoja}' vacia o no existe")
                continue
            # Chequear el control G1 (la oficina marca OK cuando termina de controlar)
            ok, err_ctrl = chequear_control_g1(values)
            if not ok:
                print(f"  PAUSADO {local}: {err_ctrl} -- salteo este local")
                continue
            monto, err = extraer_total_mes(values)
            if err:
                print(f"  AVISO {local}: {err}")
                continue
            resultados.append((local, monto))
            print(f"  OK {local}: ${monto:,.2f}  (G1 = OK)".replace(',', '.'))
        except Exception as e:
            print(f"  ERROR {local}: {e}")

    if not args.aplicar:
        print("\nDRY-RUN. Si todo se ve bien, corre con --aplicar para guardar en Supabase.")
        return

    escritas = 0
    for local, monto in resultados:
        if supa_upsert_venta(local, periodo_iso, monto):
            escritas += 1
    print(f"\n{escritas} ventas sincronizadas en rrhh_ventas_local_mes.")


if __name__ == '__main__':
    main()
