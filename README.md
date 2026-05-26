# RRHH Adorno

Módulo de Recursos Humanos de Claudia Adorno SRL.

App separada que comparte Supabase con el CRM. Tablas con prefijo `rrhh_*`. PWA.

## URLs

- **Producción** (cuando esté desplegada): https://claudiaadornosrl-prog.github.io/rrhh-adorno/
- **CRM (hermano)**: https://claudiaadornosrl-prog.github.io/crm-adorno/
- **Landing hub**: https://claudiaadornosrl-prog.github.io/hub-adorno/

## Stack

- Frontend: HTML/JS/CSS single-file (`index.html`, ~140KB, ~2900 líneas) + PWA
- Backend: Supabase (PostgREST + Auth + Storage)
- Hosting: GitHub Pages
- Auth: Supabase Auth (email + password con recovery)

## Roles

| Rol | Acceso |
|-----|--------|
| **admin** | Todo: ABM empleados, sueldos, asistencias, vacaciones, documentos, reportes, configuración, audit log |
| **gerente** | Su local: ver equipo, asistencias, aprobar vacaciones |
| **empleado** | Self-service: mi legajo, mis recibos, mis vacaciones, mis fichadas, mis certif |

## Estado actual (Fase 0-8)

| Fase | Estado | Qué hace |
|---|---|---|
| **0** Setup | ✅ | Schema (15 tablas), RLS, Storage (6 buckets), Seed (19 empleados, escalas CCT, feriados, vacaciones) |
| **1** Empleados | ✅ | Listado con filtros, vista 360° con 9 tabs (datos editables, documentos, sueldos, asistencias, vacaciones, certif, apercibimientos, premios, notas), audit log en cada cambio |
| **2** Sueldos | ✅ | Dashboard mensual con métricas, tabla por empleado con bruto/neto/estado de validación. Bulk upload vía `migrations/01_migrar_recibos.py`. Integración fina con skill control-sueldos = next step |
| **3** Asistencias | ✅ | Dashboard mensual por local, tabla con días/ausencias/tardanzas/HS extras. Import vía skill `control-asistencias-crosschex` |
| **4** Vacaciones | ✅ | 4 tabs: pendientes (aprobar/rechazar), próximas, saldos del año, calendario 90 días con barras por local |
| **5** Documentos | ✅ | Vista global con filtros, alertas de vencimiento, tab dentro del 360 con upload a Storage y signed URLs |
| **6** Self-service | ✅ | 5 vistas: mi legajo, mis recibos, mis vacaciones (con form solicitud + validación saldo), mis fichadas, mis certif (upload) |
| **7** Gerentes | ✅ | Filtrado por local en RLS + frontend. Configuración admin con tabs Usuarios/CCT/Feriados/Audit log |
| **8** Landing hub | ✅ | Carpeta `../hub-adorno/` con tarjetas CRM, RRHH y Tablero de resultados (futuro) |

## Setup completo (primera vez)

### 1. Correr los SQL en Supabase

En Supabase → SQL Editor, ejecutar en orden:
- `sql/01_schema.sql`
- `sql/02_rls.sql`
- `sql/03_storage.sql`
- `sql/04_seed.sql`

(Hay también `sql/00_install_completo.sql` con los 4 unidos para correr de una.)

### 2. Crear usuario admin

1. Supabase → Authentication → Users → Add user
   - Email: `juanpsimonelli@gmail.com`
   - Password: la que quieras
   - ✅ Auto Confirm User
2. Copiar el UUID
3. SQL Editor:
```sql
INSERT INTO rrhh_usuarios (auth_user_id, empleado_id, email, rol, activo)
VALUES (
  '<UUID>',
  (SELECT id FROM rrhh_empleados WHERE dni = '36754687'),
  'juanpsimonelli@gmail.com', 'admin', true
);
```

### 3. (Opcional) Migración histórica

```powershell
cd C:\CRM_Adorno\rrhh-adorno\migrations
$env:SUPABASE_SERVICE_KEY = "<service_role key de Supabase>"

# Recibos de sueldo (probar con un empleado primero)
python 01_migrar_recibos.py --empleado "BIANCHI" --dry-run
python 01_migrar_recibos.py --empleado "BIANCHI"

# Vacaciones históricas
python 02_migrar_vacaciones.py --dry-run
python 02_migrar_vacaciones.py
```

### 4. Probar local

Doble clic en `index.html` (Supabase Auth funciona desde file:// también).

### 5. Deploy a GitHub Pages

```powershell
cd C:\CRM_Adorno\rrhh-adorno
.\deploy.ps1
```

## Estructura

```
rrhh-adorno/
├── README.md
├── index.html              ← App completa (PWA)
├── manifest.json           ← PWA manifest
├── service-worker.js       ← SW network-first
├── deploy.ps1              ← Script PowerShell para GitHub Pages
├── sql/
│   ├── 00_install_completo.sql   ← Todo en uno
│   ├── 01_schema.sql             ← 15 tablas
│   ├── 02_rls.sql                ← Seguridad por rol
│   ├── 03_storage.sql            ← 6 buckets + políticas
│   └── 04_seed.sql               ← Datos iniciales
└── migrations/
    ├── README.md
    ├── 01_migrar_recibos.py     ← Sube recibos OneDrive → Storage
    └── 02_migrar_vacaciones.py  ← Importa vacaciones tomadas
```

## Pendientes / próximos pasos

- Integración fina con skill `control-sueldos-adorno` para validar recibos al subirlos
- Upload directo de Excel CrossChex desde la UI (hoy se hace vía script)
- Upload bulk de recibos desde la UI con drag&drop
- Scripts de migración para certificados médicos y documentación general
- Notificaciones por email cuando se aprueba/rechaza una vacación
- WhatsApp Business API: avisos de cumpleaños, vencimientos
- Reportes Excel/PDF descargables (lista empleados, vacaciones tomadas, etc.)
