"""
═══════════════════════════════════════════════════════════════════════
 anviz_client.py — Cliente Python para la API de CrossChex Cloud
 Doc oficial: https://community.anviz.com/t/how-to-use-api-to-get-the-records-from-the-crosschex-cloud/726

 Flow:
   1. get_token(api_key, api_secret) -> JWT
   2. get_records(token, begin, end) -> list de fichadas paginadas
═══════════════════════════════════════════════════════════════════════
"""
import sys
if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    except Exception:
        pass

import uuid
import json
import time
import logging
from datetime import datetime, timezone
from typing import Optional

import requests

logger = logging.getLogger(__name__)

# Regiones disponibles (mirar URL del panel CrossChex Cloud para confirmar)
ENDPOINTS = {
    'us': 'https://api.us.crosschexcloud.com/',
    'eu': 'https://api.eu.crosschexcloud.com/',
    'ap': 'https://api.ap.crosschexcloud.com/',
    'cn': 'https://api.cn.crosschexcloud.com/',
}


class AnvizError(Exception):
    pass


def _flatten_php(obj, prefix=""):
    """Convierte {'header': {'nameSpace': 'x'}} en {'header[nameSpace]': 'x'}
    para form-encoded estilo PHP/Laravel."""
    flat = {}
    for k, v in obj.items():
        key = f"{prefix}[{k}]" if prefix else k
        if isinstance(v, dict):
            flat.update(_flatten_php(v, key))
        else:
            flat[key] = v
    return flat


class AnvizClient:
    def __init__(self, api_key: str, api_secret: str, region: str = 'us', label: str = ''):
        if region not in ENDPOINTS:
            raise ValueError(f"region invalida: {region}. Usar una de {list(ENDPOINTS.keys())}")
        self.api_key    = api_key
        self.api_secret = api_secret
        self.endpoint   = ENDPOINTS[region]
        self.label      = label or region
        self._token: Optional[str] = None
        self._token_exp: Optional[datetime] = None

    # ── Helpers ─────────────────────────────────────────────────
    @staticmethod
    def _now_iso() -> str:
        return datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%S+00:00')

    @staticmethod
    def _request_id() -> str:
        return str(uuid.uuid4())

    def _post(self, body: dict, retries: int = 2, timeout: int = 30) -> dict:
        """Intenta JSON primero; si la API no devuelve 'code', reintenta form-encoded (PHP-style)."""
        last_err = None
        last_resp_text = None
        last_resp_status = None
        for attempt in range(retries + 1):
            try:
                # 1er intento: JSON anidado
                resp = requests.post(self.endpoint, json=body, timeout=timeout)
                last_resp_text = (resp.text or "")[:800]
                last_resp_status = resp.status_code
                resp.raise_for_status()
                data = None
                try:
                    data = resp.json()
                except ValueError:
                    data = None
                code = (data or {}).get('code') if isinstance(data, dict) else None

                # Fallback: si no devolvio 'code', probar form-encoded
                if code is None:
                    flat = _flatten_php(body)
                    resp2 = requests.post(self.endpoint, data=flat, timeout=timeout)
                    last_resp_text = (resp2.text or "")[:800]
                    last_resp_status = resp2.status_code
                    try:
                        data = resp2.json()
                    except ValueError:
                        data = None
                    code = (data or {}).get('code') if isinstance(data, dict) else None

                if code != 200:
                    raise AnvizError(
                        f"{self.label}: HTTP {last_resp_status} code={code} "
                        f"desc={(data or {}).get('description')} err={(data or {}).get('error')} "
                        f"raw={last_resp_text!r}"
                    )
                return data
            except (requests.RequestException, AnvizError) as e:
                last_err = e
                if attempt < retries:
                    logger.warning(f"{self.label}: intento {attempt+1} fallo ({type(e).__name__}: {e})")
                    time.sleep(2)
        raise AnvizError(
            f"{self.label}: fallaron {retries+1} intentos. "
            f"Ultimo error: {last_err}. Respuesta cruda: {last_resp_text!r}"
        )

    # ── Auth ────────────────────────────────────────────────────
    def get_token(self, force: bool = False) -> str:
        """Pide un nuevo JWT y lo cachea. Usa el cache si esta vigente."""
        if not force and self._token and self._token_exp and datetime.now(timezone.utc) < self._token_exp:
            return self._token

        body = {
            'header': {
                'nameSpace':  'authorize.token',
                'nameAction': 'token',
                'version':    '1.0',
                'requestId':  self._request_id(),
                'timestamp':  self._now_iso(),
            },
            'payload': {
                'api_key':    self.api_key,
                'api_secret': self.api_secret,
            }
        }
        data = self._post(body)
        payload = data.get('data', {}).get('payload', {})
        self._token = payload.get('token')
        exp_str = payload.get('expires')
        if exp_str:
            try:
                self._token_exp = datetime.fromisoformat(exp_str.replace('Z', '+00:00'))
            except Exception:
                self._token_exp = None
        if not self._token:
            raise AnvizError(f"{self.label}: la API no devolvio token. data={data}")
        logger.info(f"{self.label}: token OK (expires={exp_str})")
        return self._token

    # ── Records ─────────────────────────────────────────────────
    def get_records(self, begin: datetime, end: datetime, per_page: int = 1000):
        """Yields registros uno a uno, paginando automaticamente."""
        if begin.tzinfo is None:
            begin = begin.replace(tzinfo=timezone.utc)
        if end.tzinfo is None:
            end = end.replace(tzinfo=timezone.utc)

        token = self.get_token()
        page = 1
        total_fetched = 0

        while True:
            body = {
                'header': {
                    'nameSpace':  'attendance.record',
                    'nameAction': 'getrecord',
                    'version':    '1.0',
                    'requestId':  self._request_id(),
                    'timestamp':  self._now_iso(),
                },
                'authorize': {
                    'type':  'token',
                    'token': token,
                },
                'payload': {
                    'begin_time': begin.strftime('%Y-%m-%dT%H:%M:%S+00:00'),
                    'end_time':   end.strftime('%Y-%m-%dT%H:%M:%S+00:00'),
                    'order':      'asc',
                    'page':       page,
                    'per_page':   per_page,
                }
            }
            data = self._post(body)
            payload = data.get('data', {}).get('payload', {})
            page_count = int(payload.get('pageCount') or 0)
            count_total = int(payload.get('count') or 0)
            items = payload.get('list') or []
            for r in items:
                yield r
            total_fetched += len(items)
            logger.info(f"{self.label}: pagina {page}/{page_count} ({len(items)} registros, acum {total_fetched}/{count_total})")
            if page >= page_count or not items:
                break
            page += 1

    def get_employees(self):
        """Lista los empleados registrados en la cuenta (endpoint: employee.employee/list)."""
        token = self.get_token()
        page = 1
        per_page = 500
        while True:
            body = {
                'header': {
                    'nameSpace':  'employee.employee',
                    'nameAction': 'list',
                    'version':    '1.0',
                    'requestId':  self._request_id(),
                    'timestamp':  self._now_iso(),
                },
                'authorize': { 'type': 'token', 'token': token },
                'payload':   { 'page': page, 'per_page': per_page },
            }
            try:
                data = self._post(body)
            except AnvizError as e:
                logger.warning(f"{self.label}: endpoint employee.list no disponible: {e}")
                return
            payload = data.get('data', {}).get('payload', {})
            items = payload.get('list') or []
            page_count = int(payload.get('pageCount') or 0)
            for emp in items:
                yield emp
            if page >= page_count or not items:
                break
            page += 1


# ── CLI basico para probar ─────────────────────────────────────
if __name__ == '__main__':
    import argparse, os
    from datetime import timedelta

    logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s %(message)s')

    ap = argparse.ArgumentParser()
    ap.add_argument('--api-key',    required=True)
    ap.add_argument('--api-secret', required=True)
    ap.add_argument('--region',     default='us', choices=list(ENDPOINTS.keys()))
    ap.add_argument('--dias',       type=int, default=7, help='Bajar ultimos N dias')
    args = ap.parse_args()

    client = AnvizClient(args.api_key, args.api_secret, args.region, label='TEST')
    print("-> Pidiendo token...")
    token = client.get_token()
    print(f"OK Token: {token[:40]}...")
    print(f"\n-> Bajando registros ultimos {args.dias} dias...")
    end = datetime.now(timezone.utc)
    begin = end - timedelta(days=args.dias)
    total = 0
    for r in client.get_records(begin, end):
        total += 1
        if total <= 3:
            print(f"  {json.dumps(r, ensure_ascii=False, indent=2)}")
    print(f"\nOK {total} registros descargados")
