# RRHH · Claudia Adorno SRL

Sistema de RRHH integral para Claudia Adorno SRL. 19 empleadas activas en 3 locales
(Alcorta 7, Unicenter 7, Oficina 5). CCT 130/75 Empleados de Comercio.

## Qué hace

- **Empleados**: CRUD completo con foto, CUIL, categoría CCT, fecha de ingreso.
- **Sueldos**: cálculo CCT + fórmula Adorno (fijo + comisión + premio + viáticos +
  extras + feriado). Modo `cct_negro` (default) y `doble_blanco` (Contreras/Escasany
  con solver inverso sobre comisiones).
- **Liquidación mensual**: grilla por local con KPIs (Recibo CCT / Total / A
  acreditar banco / Efectivo). Botones por local: Importes, Doble Blanco, Galicia
  (XLSX export), LSD ARCA v49, Imprimir recibos.
- **Préstamos** sistema francés: capital → banco, interés → efectivo. Adelantos = 1
  cuota tasa 0. Flujo solicitud→propuesta→aprobación.
- **Aumentos pedidos**: workflow admin → encargada → aprobación → aplicación.
- **Retiros mercadería**: encargada carga, se descuenta en liquidación.
- **Vacaciones**: flujo dual vendedora → encargada → PDF firmable con QR `VAC-XXXXX`.
  Parser de bandeja Gmail para detectar firmados.
- **Asistencias**: sync Anviz CrossChex (4 cuentas) + calendario mensual + banco
  minutos con tope -42hs.
- **Self-service**: mi calendario, mi legajo, mis recibos, mis fichadas, mis
  vacaciones, mis préstamos.
- **PDF recibos**: con QR `REC-XXXXX`, fuente Forum desde jsdelivr en runtime.
  Parser de Gmail IMAP detecta firmados.
- **Web Push**: VAPID, suscripción por empleada, edge function `enviar-push`.
- **Export Galicia**: XLSX con CBU + fecha último día hábil del mes.

## Stack

- **Frontend**: `index.html` PWA single-file (22k líneas, 1.18 MB), vanilla JS
- **Backend**: Supabase (`kwwiykssrpabncpqtmwi`)
- **Scripts back-office**: Python en `sync_anviz/` y `migrations/`
- **Edge Functions**: `enviar-push`, `sync-ventas-sheets`

## Estructura del repo

```
rrhh-adorno/
├── index.html              # PWA completa
├── service-worker.js       # cache + push handler
├── manifest.webmanifest
├── deploy.ps1
├── sql/                    # gitignored — historial extenso (>70 archivos)
│   ├── 00_install_completo.sql
│   ├── 01_schema.sql
│   ├── 04_seed.sql         # categorías CCT seed (TODO confirmar básicos)
│   ├── 06_turnos_default_seed.sql  # TODO confirmar horarios
│   ├── 30_doble_blanco.sql
│   ├── 41-67_*.sql         # parches LSD/ganancias/overrides one-shot
│   ├── 71_banco_minutos_tope.sql
│   └── 73_rpcs_security_definer.sql
├── sync_anviz/             # gitignored
│   ├── sync_anviz.py       # fichadas Anviz CrossChex
│   ├── procesar_email_outbox.py  # SMTP outbox
│   ├── generar_vapid_keys.py     # one-shot
│   └── .env                # credenciales (NUNCA commitear)
├── migrations/             # gitignored
│   ├── 10_procesar_vacaciones_firmadas.py
│   ├── 11_procesar_recibos_firmados.py
│   └── README.md
└── supabase/functions/
    └── enviar-push/
```

## Roles y permisos

- `admin` (JP, `juanpsimonelli@gmail.com`) → control total
- `gerente` (Soraya, Marisa, etc.) → solo su `local_gerencia`
- `empleado` → solo lo propio (self-service)

Helpers SQL (`SECURITY DEFINER STABLE` con check `auth.uid()` + `activo=true`):
- `rrhh_is_admin()`, `rrhh_is_gerente()`, `rrhh_gerente_local()`,
  `rrhh_mi_empleado_id()`, `rrhh_current_user()`
- Reusables desde otros módulos (ej: banco-adorno los reusa).

## Convención session JS (IMPORTANTE)

```js
session.rol            // es ESPAÑOL (una l) — NO session.role en inglés
session.empleado_id    // bigint del rrhh_empleados
session.empleadoData   // objeto completo del empleado (incluye .local)
session.user?.email
```

Bug recurrente histórico: usar `session.role` en código nuevo. **Siempre `session.rol`.**

## Tablas Supabase principales

| Tabla | Rol |
|---|---|
| `rrhh_empleados` | Padrón empleadas |
| `rrhh_categorias_cct` | Escalafón CCT 130/75 |
| `rrhh_usuarios` | Login + rol |
| `rrhh_sueldos` | Snapshots de sueldo por empleada |
| `rrhh_liquidacion` + `_concepto` | Liquidación mensual + items |
| `rrhh_sueldo_local_config` + `_empleada_config` | Configs de fórmula |
| `rrhh_prestamo` + `_cuota` + `_solicitud` | Préstamos sistema francés |
| `rrhh_vacaciones` + `_movimientos` | Vacaciones |
| `rrhh_fichadas_raw` + `rrhh_asistencias_detalle` | Anviz |
| `rrhh_banco_minutos` | Saldo neto por empleada (tope -2520 min = -42hs) |
| `rrhh_turnos` + `rrhh_turnos_default` | Calendario |
| `rrhh_meses_cerrados` + `_sueldos` | Bloqueo de meses cerrados |
| `rrhh_push_subscriptions` | Web Push |
| `rrhh_email_outbox` | Cola de mails saliente |
| `rrhh_retiro_mercaderia` | Descuentos en liquidación |
| `rrhh_aumento_pedido` + `_detalle` | Workflow aumentos |
| `rrhh_inbox_anonimo` | Mensajes anónimos vendedoras → admin |
| `rrhh_lsd_*` | LSD ARCA |
| `rrhh_solicitudes_borrado_doc` | Workflow borrado docs |

## Integraciones

- **Anviz CrossChex**: 4 cuentas (oficina, unicenter, alcorta, backup). API JWT
  region "us". Sync via `sync_anviz.py --periodo YYYY-MM`. Upsert idempotente.
- **Gmail IMAP**: parser de bandeja `claudiaadornosrl@gmail.com` para:
  - Vacaciones firmadas (QR `VAC-XXXXX`) → `migrations/10_procesar_vacaciones_firmadas.py`
  - Recibos firmados (QR `REC-XXXXX`) → `migrations/11_procesar_recibos_firmados.py`
- **Gmail SMTP**: cola `rrhh_email_outbox` procesada por `procesar_email_outbox.py`.
- **Web Push**: VAPID keys (públlica en JS, privada en Supabase Secrets como
  `VAPID_PRIVATE_KEY` + `VAPID_SUBJECT`). Edge Function `enviar-push`.
- **Google Calendar**: queue `rrhh_calendar_delete_queue` para limpieza.

## Conceptos clave

### Modo `doble_blanco`

Para Contreras y Escasany. La fórmula CCT da neto distinto al pactado; un solver
inverso v2 ajusta el item `0018 Comisiones` para que el neto coincida con lo
pactado. Guarda el delta en `rrhh_liquidacion.ajuste_blanco`.

**Riesgo**: si CCT agrega un item remunerativo nuevo, el solver puede converger
mal silenciosamente. No hay test automático. Recomendación: comparar neto
calculado vs MEMOSOFT antes de cada paritaria.

### Banco de minutos

Cada empleada tiene un saldo neto de minutos que se debe (negativo) o que
acumuló por trabajar más (positivo). Trigger SQL bloquea ir más allá de
**-2520 min (-42hs)**. Escape hatch admin via GUC `app.banco_skip_tope`.

UI advierte al pedir compensar falta. Falta: alerta proactiva cuando se
acerca al tope.

### Sync Anviz

`sync_anviz.py` corre c/N horas (ver Task Scheduler). Si Anviz queda offline,
falla silencioso. UI muestra mensaje en `renderAsistencias` con comando para
correr manual:
```powershell
cd C:\CRM_Adorno\rrhh-adorno\sync_anviz
py sync_anviz.py --periodo 2026-06
```

### Web Push iOS

Solo funciona si PWA está instalada en pantalla de inicio. Si la vendedora
abre desde Safari, no llegan notifs. UI muestra banner explicativo pero NO
deshabilita el botón → mejora pendiente.

## Troubleshooting

### "session.rol is undefined"
Verificar `rrhh_usuarios` tiene la fila correspondiente con `rol` no nulo.

### "RLS bloqueando query"
Bug histórico: `notifAdmins()` y `_buscarEncargadaIdParaPush()` rompían contra
RLS de `rrhh_usuarios`. Fix: usar las RPC `SECURITY DEFINER`
`rrhh_admins_ids()` y `rrhh_encargada_id_local()` (ver `sql/73_*.sql`).

### "Push notif no llega a iOS"
PWA tiene que estar instalada (Compartir → Agregar a pantalla de inicio).
Desde Safari directo NO funciona.

### "Sync Anviz no actualizó fichadas"
1. Logs en `sync_anviz/`.
2. Verificar credenciales en `.env`.
3. Correr manual: `py sync_anviz.py --periodo YYYY-MM`.

### "Liquidación doble_blanco da neto distinto al pactado"
1. Verificar `rrhh_sueldo_empleada_config.modo_liquidacion = 'doble_blanco'`.
2. Si CCT agregó ítems nuevos: actualizar el solver en JS para considerarlos.

## Pendientes activos

De `CLAUDE.md`:
- #42 Probar API Anviz con `probar_anviz.ps1`
- #43 Pedir Developer Mode Anviz (Oficina · Company 110001026)
- #138 JP cumple rol encargado Oficina
- #25 Integración fina control-sueldos al subir recibo
- #27 Drag&drop bulk recibos
- #101 Plan B: levantar fichadas Anviz sin API

QA findings (mañana cuando tengas tiempo):
- 5 `catch(_) {}` silenciosos en index.html — reemplazar por `console.warn`
- Hardcoded `LSD_CUIT_EMPLEADOR`, VAPID public key, URL Supabase → centralizar
- TODO confirmar básicos Vendedor A y Administrativo A en `sql/04_seed.sql`
- TODO confirmar horarios turnos default en `sql/06_*.sql`
- UI para asignar `doble_blanco` por empleada (hoy solo SQL manual)
- Mover los 27 archivos sql/41-67 (parches one-shot) a `sql/historicos/`
- Healthcheck Anviz (edge function diaria + alerta push si no hay fichadas)

Ver `C:\CRM_Adorno\SESSIONS.md` para historial.
