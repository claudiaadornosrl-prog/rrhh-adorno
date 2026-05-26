# Migraciones — Carga inicial desde OneDrive

Scripts para poblar la base RRHH con el histórico digitalizado.

## Setup

```powershell
# 1) Instalar dependencias
pip install supabase python-dotenv

# 2) Obtener la SERVICE_ROLE key de Supabase
#    En Supabase → Settings → API → service_role (secret)
#    ⚠️ NUNCA pongas la service_role key en el frontend ni la subas a git.

# 3) Setearla como variable de entorno (solo esta sesión)
$env:SUPABASE_SERVICE_KEY = "eyJ..."

# (o, persistente, agregar al perfil de PowerShell)
```

## Scripts disponibles

### `01_migrar_recibos.py` — Recibos de sueldo
Sube todos los PDFs de `EMPLEADOS/RECIBOS DE SUELDO/{LOCAL}/{AÑO}/Liqui {Apellido}/*.pdf` al bucket `rrhh-recibos` y crea registros en `rrhh_sueldos`.

```powershell
# Probar sin subir nada (ver qué procesaría)
python 01_migrar_recibos.py --dry-run

# Limitar a un año / empleado / local
python 01_migrar_recibos.py --año 2026
python 01_migrar_recibos.py --empleado "BIANCHI"
python 01_migrar_recibos.py --local unicenter --año 2026 --dry-run

# Migrar TODO (cuidado, son ~3300 PDFs — anda a tomarte un café)
python 01_migrar_recibos.py
```

### `02_migrar_vacaciones.py` — Vacaciones históricas
Parsea los nombres de archivos de `EMPLEADOS/VACACIONES/{NOMBRE}/VACACIONES YYYY [NOMBRE] DD-MM-YYYY AL DD-MM-YYYY.pdf` y crea movimientos en `rrhh_vacaciones_movimientos` con estado `'tomada'`.

```powershell
python 02_migrar_vacaciones.py --dry-run
python 02_migrar_vacaciones.py
```

## Pendientes (próximos scripts)

- `03_migrar_certificados.py` — desde `CERTIFICADOS MEDICOS/`
- `04_migrar_apercibimientos.py` — desde `APERCIBIMIENTOS/` (solo 1 archivo)
- `05_migrar_documentacion.py` — contratos y demás desde `DOCUMENTACION/`

## Idempotencia

Los scripts usan `upsert` en lo posible — se pueden correr varias veces sin duplicar:
- Recibos: `rrhh_sueldos` tiene UNIQUE (empleado_id, periodo), Storage hace overwrite con `upsert: true`.
- Vacaciones: los movimientos NO tienen unique constraint — si corrés 2x vas a tener movimientos duplicados. Borrar con SQL si pasa.

## Recuperar / rollback

Si necesitás limpiar una migración:

```sql
-- Borrar todos los recibos cargados por migración
DELETE FROM rrhh_sueldos WHERE created_by IS NULL AND bruto = 0;

-- Borrar movimientos de vacaciones de la migración
DELETE FROM rrhh_vacaciones_movimientos
WHERE solicitado_por = 'migracion-historica';
```

Storage: hay que limpiarlo por separado desde la UI de Supabase o con un script.
