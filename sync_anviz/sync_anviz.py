"""
═══════════════════════════════════════════════════════════════════════
 sync_anviz.py — Sincronización mensual de fichadas Anviz → Supabase RRHH
═══════════════════════════════════════════════════════════════════════

Pipeline:
  1. Para cada cuenta Anviz (Oficina, Unicenter, Alcorta1, Alcorta2),
     baja los registros del período via CrossChex Cloud API.
  2. Mergea Alcorta1 + Alcorta2 (segundo equipo es backup).
  3. Clasifica cada fichada como entrada / salida (heurística por hora).
  4. Para cada (empleado × día):
       - Calcula entrada/salida del día
       - Aplica tolerancias por local (oficina 25min, locales 20min)
       - Detecta tardanzas, salidas tempranas, ausencias
       - Cruza con vacaciones (rrhh_vacaciones_movimientos)
       - Cruza con feriados (rrhh_feriados) — solo si el local no trabaja en feriado
       - Cruza con licencias / certificados médicos
  5. Upserta en rrhh_asistencias (resumen mes) y rrhh_asistencias_detalle (día a día).

USO:
   python sync_anviz.py --periodo 2026-04
   python sync_anviz.py --periodo 2026-04 --solo-local oficina
   python sync_anviz.py --periodo 2026-04 --dry-run    # No escribe en Supabase

Programación automática (ver scheduler/install_task.ps1):
   python sync_anviz.py --periodo mes-anterior  # día 1 de cada mes
"""
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

# ───────────────────────────────────────────────────────────────
# Setup paths
# ───────────────────────────────────────────────────────────────
SCRIPT_DIR = Path(__file__).parent
sys.path.insert(0, str(SCRIPT_DIR))

# Cargar .env
try:
    from dotenv import load_dotenv
    load_dotenv(SCRIPT_DIR / '.env')
except ImportError:
    print("⚠️  python-dotenv no instalado. Instalá con: pip install python-dotenv")

from anviz_client import AnvizClient

# ───────────────────────────────────────────────────────────────
# CONFIG — Cuentas Anviz (1 por local)
# ───────────────────────────────────────────────────────────────
# Cada cuenta debe tener api_key + api_secret. Las creds vienen del .env.
ANVIZ_ACCOUNTS = [
    {
        'local':      'oficina',
        'label':      'Oficina (Don Torcuato)',
        'api_key':    os.environ.get('ANVIZ_OFICINA_KEY'),
        'api_secret': os.environ.get('ANVIZ_OFICINA_SECRET'),
        'region':     os.environ.get('ANVIZ_OFICINA_REGION', 'us'),
        'es_backup_de': None,
    },
    {
        'local':      'unicenter',
        'label':      'Unicenter (Martínez)',
        'api_key':    os.environ.get('ANVIZ_UNICENTER_KEY'),
        'api_secret': os.environ.get('ANVIZ_UNICENTER_SECRET'),
        'region':     os.environ.get('ANVIZ_UNICENTER_REGION', 'us'),
        'es_backup_de': None,
    },
    {
        'local':      'alcorta',
        'label':      'Alcorta principal',
        'api_key':    os.environ.get('ANVIZ_ALCORTA_KEY'),
        'api_secret': os.environ.get('ANVIZ_ALCORTA_SECRET'),
        'region':     os.environ.get('ANVIZ_ALCORTA_REGION', 'us'),
        'es_backup_de': None,
    },
    {
        'local':      'alcorta',
        'label':      'Alcorta backup',
        'api_key':    os.environ.get('ANVIZ_ALCORTA_BACKUP_KEY'),
        'api_secret': os.environ.get('ANVIZ_ALCORTA_BACKUP_SECRET'),
        'region':     os.environ.get('ANVIZ_ALCORTA_BACKUP_REGION', 'us'),
        'es_backup_de': 'alcorta',
    },
]

# ───────────────────────────────────────────────────────────────
# CONFIG — Tolerancias por local (en minutos)
# ───────────────────────────────────────────────────────────────
TOLERANCIAS = {
    'oficina':   {'tarde_min': 25, 'temprano_min': 5, 'trabaja_feriados': False},
    'unicenter': {'tarde_min': 20, 'temprano_min': 5, 'trabaja_feriados': True},
    'alcorta':   {'tarde_min': 20, 'temprano_min': 5, 'trabaja_feriados': True},
}

# Horario por defecto si Anviz no envía jornada
HORARIO_DEFAULT = {
    'oficina':   {'entrada': dtime(9, 0),  'salida': dtime(18, 0)},
    'unicenter': {'entrada': dtime(10, 0), 'salida': dtime(20, 0)},
    'alcorta':   {'entrada': dtime(10, 0), 'salida': dtime(20, 0)},
}

# ───────────────────────────────────────────────────────────────
# Supabase
# ───────────────────────────────────────────────────────────────
SUPA_URL = os.environ.get('SUPABASE_URL', 'https://kwwiykssrpabncpqtmwi.supabase.co')
SUPA_KEY = os.environ.get('SUPABASE_SERVICE_KEY')

# ───────────────────────────────────────────────────────────────
# Helpers
# ───────────────────────────────────────────────────────────────
def slug(s: str) -> str:
    """Normaliza para matching: sin tildes, lowercase, solo letras."""
    if not s: return ''
    s = unicodedata.normalize('NFD', s)
    s = ''.join(c for c in s if unicodedata.category(c) != 'Mn')
    return re.sub(r'[^a-z0-9]', '', s.lower())


def parse_periodo(s: str) -> tuple:
    """'2026-04' o 'mes-anterior' → (year, month, fecha_desde, fecha_hasta)"""
    if s == 'mes-anterior':
        hoy = date.today()
        y, m = hoy.year, hoy.month - 1
        if m == 0: m, y = 12, y - 1
    else:
        y, m = map(int, s.split('-'))
    fecha_desde = date(y, m, 1)
    fecha_hasta = (date(y, m + 1, 1) if m < 12 else date(y + 1, 1, 1)) - timedelta(days=1)
    return y, m, fecha_desde, fecha_hasta


def es_entrada_o_salida(hora: dtime, jornada_entrada: dtime, jornada_salida: dtime) -> str:
    """Heurística: si la hora está más cerca de la entrada que de la salida → 'entrada'."""
    def mins(t): return t.hour * 60 + t.minute
    h = mins(hora)
    dist_entrada = abs(h - mins(jornada_entrada))
    dist_salida  = abs(h - mins(jornada_salida))
    # Salida cruza medianoche → simplificado
    return 'entrada' if dist_entrada <= dist_salida else 'salida'


def minutos_diff(t1: dtime, t2: dtime) -> int:
    """Diferencia en minutos entre dos times. Positivo si t1 > t2."""
    return (t1.hour * 60 + t1.minute) - (t2.hour * 60 + t2.minute)


# ───────────────────────────────────────────────────────────────
# Sync principal
# ───────────────────────────────────────────────────────────────
class SyncAnviz:
    def __init__(self, periodo: str, solo_local: str = None, dry_run: bool = False):
        self.year, self.month, self.fecha_desde, self.fecha_hasta = parse_periodo(periodo)
        self.periodo_str = f"{self.year:04d}-{self.month:02d}"
        self.solo_local = solo_local
        self.dry_run = dry_run

        self.logger = logging.getLogger('sync_anviz')
        self.supabase = None
        self.empleados = []  # cargados de Supabase
        self.empleados_by_local = defaultdict(list)
        self.empleado_match = {}  # slug(apellido+nombre) o slug(workno) → empleado_id

        self.vacaciones_por_emp = defaultdict(list)  # emp_id → [(desde, hasta)]
        self.licencias_por_emp = defaultdict(list)
        self.certif_por_emp = defaultdict(list)
        self.feriados = set()  # set de date

    def init_supabase(self):
        from supabase import create_client
        if not SUPA_KEY:
            raise SystemExit("❌ Falta SUPABASE_SERVICE_KEY en .env")
        self.supabase = create_client(SUPA_URL, SUPA_KEY)
        self.logger.info("✓ Conectado a Supabase")

    def load_empleados(self):
        data = self.supabase.table('rrhh_empleados').select(
            'id, dni, apellido, nombre, nombre_completo, local, estado, fecha_ingreso'
        ).eq('estado', 'activo').execute().data
        self.empleados = data
        for e in data:
            self.empleados_by_local[e['local']].append(e)
            # Matching por varios criterios
            self.empleado_match[slug(e['apellido'] + e['nombre'])] = e['id']
            self.empleado_match[slug(e['apellido'])] = e['id']
            if e.get('dni'):
                self.empleado_match[slug(e['dni'])] = e['id']
        self.logger.info(f"✓ {len(data)} empleados activos cargados")

    def load_cruces(self):
        """Carga vacaciones, licencias, certif médicos del período + feriados."""
        # Vacaciones aprobadas o tomadas que se superpongan al mes
        vacs = self.supabase.table('rrhh_vacaciones_movimientos').select(
            'empleado_id, fecha_desde, fecha_hasta, estado'
        ).in_('estado', ['aprobada', 'tomada']).execute().data
        for v in vacs:
            d1 = datetime.fromisoformat(v['fecha_desde']).date()
            d2 = datetime.fromisoformat(v['fecha_hasta']).date()
            if d2 >= self.fecha_desde and d1 <= self.fecha_hasta:
                self.vacaciones_por_emp[v['empleado_id']].append((d1, d2))

        # Licencias
        try:
            lics = self.supabase.table('rrhh_licencias').select(
                'empleado_id, fecha_desde, fecha_hasta, tipo'
            ).execute().data
            for l in lics:
                d1 = datetime.fromisoformat(l['fecha_desde']).date()
                d2 = datetime.fromisoformat(l['fecha_hasta']).date()
                if d2 >= self.fecha_desde and d1 <= self.fecha_hasta:
                    self.licencias_por_emp[l['empleado_id']].append((d1, d2, l['tipo']))
        except Exception as e:
            self.logger.warning(f"No se pudieron cargar licencias: {e}")

        # Certificados médicos validados
        try:
            certs = self.supabase.table('rrhh_certificados_medicos').select(
                'empleado_id, fecha_desde, fecha_hasta, validado'
            ).execute().data
            for c in certs:
                d1 = datetime.fromisoformat(c['fecha_desde']).date()
                d2 = datetime.fromisoformat(c['fecha_hasta']).date()
                if d2 >= self.fecha_desde and d1 <= self.fecha_hasta:
                    self.certif_por_emp[c['empleado_id']].append((d1, d2))
        except Exception as e:
            self.logger.warning(f"No se pudieron cargar certif. médicos: {e}")

        # Feriados del mes
        fers = self.supabase.table('rrhh_feriados').select(
            'fecha'
        ).gte('fecha', self.fecha_desde.isoformat()).lte('fecha', self.fecha_hasta.isoformat()).execute().data
        for f in fers:
            self.feriados.add(datetime.fromisoformat(f['fecha']).date())

        self.logger.info(f"✓ Cruces cargados: {sum(len(v) for v in self.vacaciones_por_emp.values())} vacaciones, "
                         f"{sum(len(v) for v in self.licencias_por_emp.values())} licencias, "
                         f"{sum(len(v) for v in self.certif_por_emp.values())} certif, "
                         f"{len(self.feriados)} feriados")

    def descargar_fichadas(self) -> dict:
        """Descarga fichadas de todas las cuentas. Devuelve dict {local: [registros]}."""
        begin = datetime.combine(self.fecha_desde, dtime.min).replace(tzinfo=timezone.utc)
        end   = datetime.combine(self.fecha_hasta, dtime.max).replace(tzinfo=timezone.utc)

        registros_por_local = defaultdict(list)
        for cuenta in ANVIZ_ACCOUNTS:
            if self.solo_local and cuenta['local'] != self.solo_local:
                continue
            if not cuenta['api_key'] or not cuenta['api_secret']:
                self.logger.warning(f"⚠️ Cuenta '{cuenta['label']}' sin credenciales en .env — skip")
                continue
            self.logger.info(f"\n📡 Descargando {cuenta['label']}...")
            try:
                client = AnvizClient(
                    cuenta['api_key'], cuenta['api_secret'],
                    region=cuenta['region'], label=cuenta['label']
                )
                count = 0
                for r in client.get_records(begin, end):
                    r['_local'] = cuenta['local']
                    r['_cuenta'] = cuenta['label']
                    registros_por_local[cuenta['local']].append(r)
                    count += 1
                self.logger.info(f"   ✓ {count} fichadas")
            except Exception as e:
                self.logger.error(f"   ❌ Error en {cuenta['label']}: {e}")

        return registros_por_local

    def match_empleado(self, r: dict) -> int:
        """Intenta matchear un registro Anviz con un empleado_id de Supabase."""
        emp = r.get('employee') or {}
        first = emp.get('first_name', '')
        last  = emp.get('last_name', '')
        workno = emp.get('workno', '')

        # Probar varios slugs
        for k in [slug(last + first), slug(first + last), slug(last), slug(workno)]:
            if k and k in self.empleado_match:
                return self.empleado_match[k]
        return None

    def consolidar_dias(self, registros: list, local: str) -> dict:
        """Convierte lista de fichadas crudas en dict {(emp_id, fecha): {entrada, salida, anomalias}}."""
        jornada = HORARIO_DEFAULT[local]
        dias = defaultdict(lambda: {'entrada': None, 'salida': None, 'fichadas': []})

        for r in registros:
            emp_id = self.match_empleado(r)
            if not emp_id:
                continue  # ignorar fichadas de empleados que no están en RRHH
            check_iso = r.get('checktime')
            if not check_iso:
                continue
            try:
                dt = datetime.fromisoformat(check_iso.replace('Z', '+00:00'))
                # Convertir UTC → Argentina (UTC-3)
                dt_local = dt - timedelta(hours=3)
                fecha = dt_local.date()
                hora = dt_local.time().replace(microsecond=0)
            except Exception:
                continue
            if fecha < self.fecha_desde or fecha > self.fecha_hasta:
                continue

            key = (emp_id, fecha)
            dias[key]['fichadas'].append(hora)

        # Consolidar entrada/salida: primer registro del día = entrada, último = salida
        for key, info in dias.items():
            sorted_h = sorted(info['fichadas'])
            if len(sorted_h) == 1:
                # Un solo fichaje — clasificar por cercanía a entrada/salida
                kind = es_entrada_o_salida(sorted_h[0], jornada['entrada'], jornada['salida'])
                info[kind] = sorted_h[0]
            else:
                info['entrada'] = sorted_h[0]
                info['salida']  = sorted_h[-1]
        return dias

    def procesar_local(self, local: str, registros: list) -> dict:
        """Procesa fichadas de un local y devuelve estructura completa por empleado."""
        tol = TOLERANCIAS[local]
        jornada = HORARIO_DEFAULT[local]
        dias = self.consolidar_dias(registros, local)

        # Para cada empleado del local, recorrer cada día del período
        resultados_por_emp = defaultdict(lambda: {
            'dias_trabajados': 0,
            'dias_ausente': 0,
            'dias_vacaciones': 0,
            'dias_licencia': 0,
            'dias_feriado': 0,
            'llegadas_tarde': 0,
            'salidas_tempranas': 0,
            'minutos_tarde_total': 0,
            'anomalias_fichada': 0,
            'detalle': []
        })

        empleados_local = self.empleados_by_local.get(local, [])

        for emp in empleados_local:
            emp_id = emp['id']
            cursor = self.fecha_desde
            while cursor <= self.fecha_hasta:
                fecha = cursor
                cursor = cursor + timedelta(days=1)
                fichadas = dias.get((emp_id, fecha))
                estado, mins_tarde, mins_temp = self._clasificar_dia(emp_id, fecha, local, fichadas, tol, jornada)
                r = resultados_por_emp[emp_id]
                if estado == 'puntual':
                    r['dias_trabajados'] += 1
                elif estado == 'tarde':
                    r['dias_trabajados'] += 1; r['llegadas_tarde'] += 1; r['minutos_tarde_total'] += mins_tarde
                    if mins_temp > 0: r['salidas_tempranas'] += 1
                elif estado == 'ausente':
                    r['dias_ausente'] += 1
                elif estado == 'vacaciones':
                    r['dias_vacaciones'] += 1
                elif estado == 'licencia':
                    r['dias_licencia'] += 1
                elif estado == 'feriado':
                    r['dias_feriado'] += 1
                elif estado == 'falta_fichada':
                    r['anomalias_fichada'] += 1
                    r['dias_trabajados'] += 1
                # Guardar detalle día
                r['detalle'].append({
                    'fecha': fecha.isoformat(),
                    'entrada': fichadas['entrada'].isoformat() if fichadas and fichadas.get('entrada') else None,
                    'salida':  fichadas['salida'].isoformat() if fichadas and fichadas.get('salida') else None,
                    'estado':  estado,
                    'minutos_tarde': mins_tarde,
                    'minutos_salida_temp': mins_temp,
                })

        return resultados_por_emp

    def _clasificar_dia(self, emp_id, fecha, local, fichadas, tol, jornada):
        """Devuelve (estado, mins_tarde, mins_temp). Estados:
        puntual / tarde / ausente / vacaciones / licencia / feriado / falta_fichada / franco
        """
        # Vacaciones
        for d1, d2 in self.vacaciones_por_emp.get(emp_id, []):
            if d1 <= fecha <= d2: return ('vacaciones', 0, 0)
        # Licencia
        for d1, d2, _t in self.licencias_por_emp.get(emp_id, []):
            if d1 <= fecha <= d2: return ('licencia', 0, 0)
        # Certif médico
        for d1, d2 in self.certif_por_emp.get(emp_id, []):
            if d1 <= fecha <= d2: return ('licencia', 0, 0)
        # Feriado
        if fecha in self.feriados and not tol['trabaja_feriados']:
            return ('feriado', 0, 0)
        # Domingo y oficina no trabaja
        if fecha.weekday() == 6 and local == 'oficina':
            return ('franco', 0, 0)
        # Fichadas presentes?
        if not fichadas:
            return ('ausente', 0, 0)
        entrada = fichadas.get('entrada')
        salida  = fichadas.get('salida')
        if not entrada or not salida:
            return ('falta_fichada', 0, 0)
        mins_tarde = max(0, minutos_diff(entrada, jornada['entrada']))
        mins_temp  = max(0, minutos_diff(jornada['salida'], salida))
        if mins_tarde > tol['tarde_min'] or mins_temp > tol['temprano_min']:
            return ('tarde', mins_tarde, mins_temp)
        return ('puntual', mins_tarde, mins_temp)

    def upsert_supabase(self, local: str, resultados: dict):
        """Sube los resultados a rrhh_asistencias y rrhh_asistencias_detalle."""
        if self.dry_run:
            self.logger.info(f"   [DRY-RUN] skip upload de {local}")
            return
        for emp_id, r in resultados.items():
            # Upsert asistencias (resumen)
            self.supabase.table('rrhh_asistencias').upsert({
                'empleado_id': emp_id,
                'periodo': self.periodo_str,
                'dias_corresponden': (self.fecha_hasta - self.fecha_desde).days + 1,
                'dias_trabajados': r['dias_trabajados'],
                'dias_ausente': r['dias_ausente'],
                'dias_vacaciones': r['dias_vacaciones'],
                'dias_licencia': r['dias_licencia'],
                'dias_feriado': r['dias_feriado'],
                'llegadas_tarde': r['llegadas_tarde'],
                'salidas_tempranas': r['salidas_tempranas'],
                'minutos_tarde_total': r['minutos_tarde_total'],
                'anomalias_fichada': r['anomalias_fichada'],
            }, on_conflict='empleado_id,periodo').execute()

            # Borrar detalle previo del período (para no duplicar al re-correr)
            self.supabase.table('rrhh_asistencias_detalle').delete()\
                .eq('empleado_id', emp_id)\
                .gte('fecha', self.fecha_desde.isoformat())\
                .lte('fecha', self.fecha_hasta.isoformat()).execute()
            # Insertar nuevo detalle
            detalle_rows = [{'empleado_id': emp_id, **d} for d in r['detalle']]
            # Insertar en batches de 100
            for i in range(0, len(detalle_rows), 100):
                self.supabase.table('rrhh_asistencias_detalle').insert(detalle_rows[i:i+100]).execute()

    def run(self):
        self.logger.info(f"═══ Sync Anviz — Período {self.periodo_str} ({self.fecha_desde} → {self.fecha_hasta}) ═══")
        if self.dry_run:
            self.logger.info("🔵 DRY-RUN — no se escribe en Supabase")

        self.init_supabase()
        self.load_empleados()
        self.load_cruces()

        registros_por_local = self.descargar_fichadas()

        for local, registros in registros_por_local.items():
            self.logger.info(f"\n🔎 Procesando {local} ({len(registros)} fichadas crudas)…")
            resultados = self.procesar_local(local, registros)
            self.logger.info(f"   ✓ {len(resultados)} empleados procesados")
            # Stats
            total_tarde = sum(r['llegadas_tarde'] for r in resultados.values())
            total_aus   = sum(r['dias_ausente'] for r in resultados.values())
            self.logger.info(f"   📊 Total tardanzas: {total_tarde} · Ausencias: {total_aus}")
            self.upsert_supabase(local, resultados)

        self.logger.info("\n✅ Sync completo")


# ───────────────────────────────────────────────────────────────
# CLI
# ───────────────────────────────────────────────────────────────
def main():
    logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s %(message)s')
    ap = argparse.ArgumentParser(description='Sincronización mensual de fichadas Anviz → Supabase RRHH')
    ap.add_argument('--periodo',    default='mes-anterior', help='Período a procesar: YYYY-MM o "mes-anterior"')
    ap.add_argument('--solo-local', choices=['unicenter','alcorta','oficina'], help='Procesar solo un local')
    ap.add_argument('--dry-run',    action='store_true', help='No escribir en Supabase')
    args = ap.parse_args()

    sync = SyncAnviz(args.periodo, solo_local=args.solo_local, dry_run=args.dry_run)
    try:
        sync.run()
    except KeyboardInterrupt:
        sync.logger.warning("Interrumpido por usuario")
        sys.exit(130)
    except Exception as e:
        sync.logger.exception(f"❌ Error: {e}")
        sys.exit(1)


if __name__ == '__main__':
    main()
