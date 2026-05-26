"""
═══════════════════════════════════════════════════════════════════════
 sync_anviz.py — Descarga fichadas Anviz → rrhh_fichadas_raw (Supabase)
═══════════════════════════════════════════════════════════════════════

Versión SIMPLIFICADA: solo baja fichadas crudas. Todo el procesamiento
(tolerancias, cruces, banco de minutos) vive ahora dentro del módulo RRHH.

Pipeline:
  1. Para cada cuenta Anviz (Oficina, Unicenter, Alcorta principal, Alcorta backup):
       a. Pide token JWT con api_key + api_secret
       b. Descarga registros del período (paginado)
  2. Convierte timestamps UTC → hora Argentina (UTC-3)
  3. Matchea con rrhh_empleados (por apellido + nombre o workno = DNI)
  4. Upsert idempotente en rrhh_fichadas_raw

USO:
   python sync_anviz.py --periodo 2026-04
   python sync_anviz.py --periodo 2026-04 --solo-local oficina
   python sync_anviz.py --periodo 2026-04 --dry-run    # No escribe en Supabase
   python sync_anviz.py --dias 7                       # Últimos N días
"""
import sys
if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    except Exception:
        pass


import os
import sys
import json
import argparse
import logging
import unicodedata
import re
from datetime import datetime, timedelta, timezone, date, time as dtime
from pathlib import Path
from collections import defaultdict

SCRIPT_DIR = Path(__file__).parent
sys.path.insert(0, str(SCRIPT_DIR))

try:
    from dotenv import load_dotenv
    load_dotenv(SCRIPT_DIR / '.env')
except ImportError:
    print("⚠️  python-dotenv no instalado. Instalá: pip install python-dotenv")

from anviz_client import AnvizClient

# ───────────────────────────────────────────────────────────────
# CONFIG — Cuentas Anviz (1 por local + backup Alcorta)
# ───────────────────────────────────────────────────────────────
ANVIZ_ACCOUNTS = [
    {
        'local':      'oficina',
        'label':      'Oficina (Don Torcuato)',
        'cuenta':     'oficina',
        'api_key':    os.environ.get('ANVIZ_OFICINA_KEY'),
        'api_secret': os.environ.get('ANVIZ_OFICINA_SECRET'),
        'region':     os.environ.get('ANVIZ_OFICINA_REGION', 'us'),
    },
    {
        'local':      'unicenter',
        'label':      'Unicenter (Martínez)',
        'cuenta':     'unicenter',
        'api_key':    os.environ.get('ANVIZ_UNICENTER_KEY'),
        'api_secret': os.environ.get('ANVIZ_UNICENTER_SECRET'),
        'region':     os.environ.get('ANVIZ_UNICENTER_REGION', 'us'),
    },
    {
        'local':      'alcorta',
        'label':      'Alcorta principal',
        'cuenta':     'alcorta',
        'api_key':    os.environ.get('ANVIZ_ALCORTA_KEY'),
        'api_secret': os.environ.get('ANVIZ_ALCORTA_SECRET'),
        'region':     os.environ.get('ANVIZ_ALCORTA_REGION', 'us'),
    },
    {
        'local':      'alcorta',
        'label':      'Alcorta backup',
        'cuenta':     'alcorta_backup',
        'api_key':    os.environ.get('ANVIZ_ALCORTA_BACKUP_KEY'),
        'api_secret': os.environ.get('ANVIZ_ALCORTA_BACKUP_SECRET'),
        'region':     os.environ.get('ANVIZ_ALCORTA_BACKUP_REGION', 'us'),
    },
]

SUPA_URL = os.environ.get('SUPABASE_URL', 'https://kwwiykssrpabncpqtmwi.supabase.co')
SUPA_KEY = os.environ.get('SUPABASE_SERVICE_KEY')

# ───────────────────────────────────────────────────────────────
# Helpers
# ───────────────────────────────────────────────────────────────
def slug(s: str) -> str:
    if not s: return ''
    s = unicodedata.normalize('NFD', s)
    s = ''.join(c for c in s if unicodedata.category(c) != 'Mn')
    return re.sub(r'[^a-z0-9]', '', s.lower())


def parse_periodo_o_dias(periodo: str = None, dias: int = None):
    """Calcula (fecha_desde, fecha_hasta) según --periodo YYYY-MM o --dias N."""
    if dias:
        end = date.today()
        start = end - timedelta(days=dias)
        return start, end
    if periodo == 'mes-anterior':
        hoy = date.today()
        m, y = hoy.month - 1, hoy.year
        if m == 0: m, y = 12, y - 1
    elif periodo:
        y, m = map(int, periodo.split('-'))
    else:
        raise ValueError("Falta --periodo o --dias")
    fecha_desde = date(y, m, 1)
    fecha_hasta = (date(y, m + 1, 1) if m < 12 else date(y + 1, 1, 1)) - timedelta(days=1)
    return fecha_desde, fecha_hasta


# ───────────────────────────────────────────────────────────────
# Sync principal
# ───────────────────────────────────────────────────────────────
class SyncAnviz:
    def __init__(self, fecha_desde, fecha_hasta, solo_local=None, dry_run=False):
        self.fecha_desde = fecha_desde
        self.fecha_hasta = fecha_hasta
        self.solo_local = solo_local
        self.dry_run = dry_run

        self.logger = logging.getLogger('sync_anviz')
        self.supabase = None
        self.empleado_match = {}    # slug → empleado_id

    def init_supabase(self):
        from supabase import create_client
        if self.dry_run:
            self.logger.info("🔵 DRY-RUN — no se escribirá en Supabase")
            return
        if not SUPA_KEY:
            raise SystemExit("❌ Falta SUPABASE_SERVICE_KEY en .env")
        self.supabase = create_client(SUPA_URL, SUPA_KEY)
        self.logger.info("✓ Conectado a Supabase")

    def load_empleados(self):
        """Carga el mapeo apellido+nombre→empleado_id para matchear las fichadas."""
        if self.dry_run:
            self.logger.info("⏭ Skip carga empleados (dry-run)")
            return
        data = self.supabase.table('rrhh_empleados').select(
            'id, dni, apellido, nombre, local'
        ).execute().data
        for e in data:
            apellido_slug = slug(e['apellido'])
            nombre_slug   = slug(e['nombre'])
            # Variantes de matching, por orden de prioridad
            for k in [
                slug(e['apellido'] + e['nombre']),
                slug(e['nombre'] + e['apellido']),
                apellido_slug,
                slug(e.get('dni', '')),
                # Primer nombre solo
                slug(e['apellido'] + (e['nombre'].split()[0] if e['nombre'] else '')),
            ]:
                if k and k not in self.empleado_match:
                    self.empleado_match[k] = e['id']
        self.logger.info(f"✓ {len(data)} empleados → {len(self.empleado_match)} variantes de match")

    def match_empleado(self, anviz_emp: dict):
        """Intenta matchear un empleado Anviz con uno del RRHH. Devuelve empleado_id o None."""
        first  = (anviz_emp.get('first_name') or '').strip()
        last   = (anviz_emp.get('last_name')  or '').strip()
        workno = (anviz_emp.get('workno')     or '').strip()
        for k in [slug(last + first), slug(first + last), slug(last), slug(workno)]:
            if k and k in self.empleado_match:
                return self.empleado_match[k]
        return None

    def descargar_cuenta(self, cuenta):
        """Descarga fichadas de una cuenta Anviz, mapea a filas para rrhh_fichadas_raw."""
        begin = datetime.combine(self.fecha_desde, dtime.min).replace(tzinfo=timezone.utc)
        end   = datetime.combine(self.fecha_hasta, dtime.max).replace(tzinfo=timezone.utc)

        client = AnvizClient(
            cuenta['api_key'], cuenta['api_secret'],
            region=cuenta['region'], label=cuenta['label']
        )

        registros_db = []
        sin_match = defaultdict(int)
        total = 0

        for r in client.get_records(begin, end):
            total += 1
            emp_anviz = r.get('employee') or {}
            check_iso = r.get('checktime')
            if not check_iso:
                continue
            try:
                dt_utc = datetime.fromisoformat(check_iso.replace('Z', '+00:00'))
            except Exception as e:
                self.logger.warning(f"checktime inválido: {check_iso} ({e})")
                continue

            # UTC → Argentina (UTC-3)
            dt_local = dt_utc.astimezone(timezone(timedelta(hours=-3)))
            fecha = dt_local.date()
            hora  = dt_local.time().replace(microsecond=0)

            # Solo registros del rango
            if fecha < self.fecha_desde or fecha > self.fecha_hasta:
                continue

            emp_id = self.match_empleado(emp_anviz) if not self.dry_run else None
            if not emp_id and not self.dry_run:
                key = (emp_anviz.get('last_name','') + ' ' + emp_anviz.get('first_name','')).strip()
                sin_match[key] += 1

            device = r.get('device') or {}
            row = {
                'empleado_id':        emp_id,
                'anviz_workno':       emp_anviz.get('workno'),
                'anviz_first_name':   emp_anviz.get('first_name'),
                'anviz_last_name':    emp_anviz.get('last_name'),
                'fecha':              fecha.isoformat(),
                'hora':               hora.isoformat(),
                'fecha_hora':         dt_utc.isoformat(),
                'local':              cuenta['local'],
                'dispositivo_serial': device.get('serial_number'),
                'dispositivo_nombre': device.get('name'),
                'checktype':          r.get('checktype'),
                'cuenta_anviz':       cuenta['cuenta'],
                'raw_data':           json.dumps(r, ensure_ascii=False),
            }
            registros_db.append(row)

        self.logger.info(f"   ✓ {total} registros descargados ({len(registros_db)} en rango)")
        if sin_match:
            self.logger.warning(f"   ⚠ Empleados sin match en RRHH (revisar nombres en CrossChex Cloud):")
            for nombre, cnt in sin_match.items():
                self.logger.warning(f"      «{nombre}»: {cnt} fichadas")
        return registros_db

    def upsert_supabase(self, registros: list, local: str):
        if self.dry_run:
            self.logger.info(f"   [DRY-RUN] skip upsert de {len(registros)} fichadas")
            # Mostrar primeras 3 como ejemplo
            for r in registros[:3]:
                self.logger.info(f"      ej. {r['fecha']} {r['hora']} {r['anviz_last_name']} {r['anviz_first_name']} [{r['dispositivo_nombre']}]")
            return

        # Upsert en batches de 200 — usa el unique constraint (fecha_hora, dispositivo_serial, anviz_workno)
        BATCH = 200
        for i in range(0, len(registros), BATCH):
            batch = registros[i:i+BATCH]
            try:
                self.supabase.table('rrhh_fichadas_raw').upsert(
                    batch,
                    on_conflict='fecha_hora,dispositivo_serial,anviz_workno'
                ).execute()
            except Exception as e:
                self.logger.error(f"   ❌ Error batch {i}: {e}")
                raise

    def run(self):
        self.logger.info(f"═══ Sync Anviz → rrhh_fichadas_raw ({self.fecha_desde} → {self.fecha_hasta}) ═══")
        self.init_supabase()
        self.load_empleados()

        # Procesar cada cuenta
        for cuenta in ANVIZ_ACCOUNTS:
            if self.solo_local and cuenta['local'] != self.solo_local:
                continue
            if not cuenta['api_key'] or not cuenta['api_secret']:
                self.logger.warning(f"⚠️ '{cuenta['label']}' sin credenciales en .env — skip")
                continue

            self.logger.info(f"\n📡 {cuenta['label']}")
            try:
                registros = self.descargar_cuenta(cuenta)
                if registros:
                    self.upsert_supabase(registros, cuenta['local'])
            except Exception as e:
                self.logger.error(f"❌ Error en {cuenta['label']}: {e}")
                import traceback
                self.logger.error(traceback.format_exc())

        self.logger.info("\n✅ Sync completo")


def main():
    logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s %(message)s')
    ap = argparse.ArgumentParser(description='Descarga fichadas Anviz → rrhh_fichadas_raw')
    grp = ap.add_mutually_exclusive_group(required=True)
    grp.add_argument('--periodo', help='YYYY-MM o "mes-anterior"')
    grp.add_argument('--dias',    type=int, help='Últimos N días')
    ap.add_argument('--solo-local', choices=['unicenter','alcorta','oficina'])
    ap.add_argument('--dry-run', action='store_true', help='No escribir en Supabase')
    args = ap.parse_args()

    fecha_desde, fecha_hasta = parse_periodo_o_dias(args.periodo, args.dias)
    sync = SyncAnviz(fecha_desde, fecha_hasta, solo_local=args.solo_local, dry_run=args.dry_run)
    try:
        sync.run()
    except KeyboardInterrupt:
        sync.logger.warning("Interrumpido por usuario")
        sys.exit(130)
    except Exception as e:
        sync.logger.exception(f"❌ Error fatal: {e}")
        sys.exit(1)


if __name__ == '__main__':
    main()
