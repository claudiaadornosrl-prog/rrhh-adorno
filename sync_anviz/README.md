# sync_anviz — Descarga de fichadas Anviz → Supabase

**Rol:** este script solo se ocupa de traer las fichadas crudas. Todo el procesamiento (tolerancias, turnos planificados, banco de minutos, vacaciones, feriados, licencias) vive dentro del módulo RRHH.

Conecta cada cuenta de **Anviz CrossChex Cloud** (una por local + backup Alcorta), baja las fichadas vía API REST, las matchea con `rrhh_empleados` por nombre+apellido o DNI, y las inserta idempotentemente en `rrhh_fichadas_raw`.

## Setup (primera vez)

### 1. Instalar Python 3.10+ y dependencias

```powershell
cd C:\CRM_Adorno\rrhh-adorno\sync_anviz
pip install -r requirements.txt
```

### 2. Configurar credenciales

```powershell
copy .env.example .env
notepad .env
```

Completar:
- `SUPABASE_SERVICE_KEY` — Service role key (Supabase → Settings → API → service_role)
- `ANVIZ_OFICINA_KEY` + `ANVIZ_OFICINA_SECRET`
- `ANVIZ_UNICENTER_KEY` + `ANVIZ_UNICENTER_SECRET`
- `ANVIZ_ALCORTA_KEY` + `ANVIZ_ALCORTA_SECRET`
- `ANVIZ_ALCORTA_BACKUP_KEY` + `ANVIZ_ALCORTA_BACKUP_SECRET`

Para conseguir api_key + api_secret en CrossChex Cloud:
1. Entrar a https://us.crosschexcloud.com (o tu región)
2. **Settings → Open API → Developer Mode**
3. Si no está habilitado, pedir activación a Anviz Community: https://community.anviz.com/

### 3. Probar la conexión (sin escribir nada)

```powershell
# Probar conexión de las 4 cuentas con sus regiones
.\probar_anviz.ps1

# Probar solo cliente bajo (último mes)
python anviz_client.py --api-key TU_KEY --api-secret TU_SECRET --region us --dias 30

# Sincronización en dry-run (no escribe en Supabase)
python sync_anviz.py --periodo 2026-04 --dry-run
python sync_anviz.py --dias 7        --dry-run

# Solo un local
python sync_anviz.py --periodo 2026-04 --solo-local oficina --dry-run
```

### 4. Sincronización real

```powershell
# Sincronizar mes específico
python sync_anviz.py --periodo 2026-04

# Sincronizar el mes anterior (uso típico el día 1)
python sync_anviz.py --periodo mes-anterior
```

## Programar día 1 de cada mes (Task Scheduler)

Ver `scheduler/install_task.ps1` (PowerShell con permisos de admin) — crea la tarea automática que corre cada día 1 a las 7 AM.

## Cómo funciona

1. Para cada cuenta Anviz definida en `.env` (4 cuentas: oficina, unicenter, alcorta principal, alcorta backup):
   - Pide token JWT con `api_key + api_secret`
   - Baja todas las fichadas del período paginadas (1000 por página)
2. Convierte UTC → hora Argentina (UTC-3)
3. Matchea cada fichada con `rrhh_empleados` por:
   - apellido + nombre normalizados, o
   - workno = DNI
4. Upsert idempotente en `rrhh_fichadas_raw` con unique constraint en `(fecha_hora, dispositivo_serial, anviz_workno)` — se puede re-correr sin duplicar.

Lo que **NO** hace este script:
- No clasifica fichadas (puntual/tarde/etc) — eso lo hace el cruce contra turnos planificados, dentro del módulo RRHH.
- No actualiza el banco de minutos.
- No calcula tolerancias.

## Matching empleado Anviz → RRHH

El script intenta matchear por varios criterios, en orden:
1. `slug(last_name + first_name)` contra apellido+nombre del legajo
2. `slug(first_name + last_name)` (invertido)
3. `slug(last_name)` solo
4. `slug(workno)` contra DNI

Si en Anviz tenés el "Workno" cargado con el DNI del empleado, el match es directo. Si lo tenés con apellido, también funciona.

**Si algún empleado no se matchea**, sus fichadas se ignoran y aparece en los warnings. Ajustá el nombre en Anviz para que coincida con el legajo en RRHH.

## Troubleshooting

### "API code=401" o "token rejected"
La cuenta no tiene Developer Mode activo. Pedirlo en https://community.anviz.com/ con tu Company ID.

### "Cuenta sin credenciales en .env — skip"
Falta completar `.env` con esa cuenta. Si todavía no tenés todas las credenciales, podés correr con `--solo-local oficina` para procesar solo lo que tenés.

### Algunos empleados no aparecen
Mirar los logs. Si dice "no matcheado" significa que el nombre en Anviz no coincide con el legajo. Editar en CrossChex Cloud para que coincida.
