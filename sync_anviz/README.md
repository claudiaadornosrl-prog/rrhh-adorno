# sync_anviz — Sincronización automática de fichadas

Conecta cada cuenta de **Anviz CrossChex Cloud** (una por local), baja las fichadas vía API REST, las procesa con tolerancias por local + cruce de vacaciones/feriados/licencias, y sube todo a Supabase RRHH.

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
# Probar solo el cliente Anviz para Oficina (últimos 7 días)
python anviz_client.py --api-key TU_KEY --api-secret TU_SECRET --region us --dias 7

# Probar la sincronización completa en modo dry-run
python sync_anviz.py --periodo 2026-04 --dry-run

# Procesar solo un local
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
2. Mergea Alcorta principal + backup en el mismo local
3. Convierte UTC → hora Argentina (UTC-3)
4. Consolida por (empleado, fecha): primer fichada del día = entrada, última = salida
5. Aplica tolerancias por local:
   - **Oficina:** 25min tarde · 5min temprano · no trabaja feriados
   - **Locales:** 20min tarde · 5min temprano · trabajan feriados
6. Cruza con:
   - `rrhh_vacaciones_movimientos` (estado aprobada/tomada)
   - `rrhh_licencias` (todas)
   - `rrhh_certificados_medicos` (todos los validados)
   - `rrhh_feriados`
7. Clasifica cada día como: `puntual`, `tarde`, `ausente`, `vacaciones`, `licencia`, `feriado`, `franco`, `falta_fichada`
8. Upsert en `rrhh_asistencias` (resumen mes) y `rrhh_asistencias_detalle` (día a día)

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
