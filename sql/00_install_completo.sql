-- ═══════════════════════════════════════════════════════════════════════
--  RRHH ADORNO — INSTALACIÓN COMPLETA (Fase 0)
--  Combina: 01_schema + 02_rls + 03_storage + 04_seed
--  Ejecutar UNA VEZ en Supabase SQL Editor
-- ═══════════════════════════════════════════════════════════════════════

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- ARCHIVO 1/4: SCHEMA
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- ═══════════════════════════════════════════════════════════════════════
--  MÓDULO RRHH — Claudia Adorno SRL
--  Schema completo: 15 tablas + índices
--  Ejecutar UNA VEZ en Supabase SQL Editor
--  Después correr: 02_rls.sql, 03_storage.sql, 04_seed.sql
-- ═══════════════════════════════════════════════════════════════════════

-- ───────────────────────────────────────────────────────────────────────
-- 1. CATEGORÍAS CCT 130/75 (referencial)
-- ───────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS rrhh_categorias_cct (
    id              bigserial PRIMARY KEY,
    codigo          text UNIQUE NOT NULL,       -- 'admin_A', 'vendedor_B', 'cajero_A', etc.
    nombre          text NOT NULL,              -- 'Administrativo A', 'Vendedor B'
    sueldo_basico   numeric(12,2) NOT NULL,     -- básico de convenio vigente
    fecha_vigencia  date NOT NULL,              -- desde cuándo aplica esta escala
    activa          boolean DEFAULT true,
    created_at      timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_cct_activa  ON rrhh_categorias_cct(activa) WHERE activa = true;
CREATE INDEX IF NOT EXISTS idx_cct_codigo  ON rrhh_categorias_cct(codigo);

-- ───────────────────────────────────────────────────────────────────────
-- 2. EMPLEADOS (maestro)
-- ───────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS rrhh_empleados (
    id                          bigserial PRIMARY KEY,
    -- Identidad
    dni                         text UNIQUE,
    cuil                        text UNIQUE,
    apellido                    text NOT NULL,
    nombre                      text NOT NULL,
    nombre_completo             text GENERATED ALWAYS AS (apellido || ', ' || nombre) STORED,
    fecha_nacimiento            date,
    sexo                        text,            -- 'F', 'M', 'X'
    estado_civil                text,            -- soltero/casado/divorciado/viudo/conviviente
    nacionalidad                text DEFAULT 'Argentina',
    -- Contacto
    direccion                   text,
    localidad                   text,
    provincia                   text,
    cp                          text,
    telefono                    text,
    email                       text,
    -- Contacto de emergencia
    emergencia_nombre           text,
    emergencia_telefono         text,
    emergencia_vinculo          text,            -- madre, padre, pareja, hijo, etc.
    -- Laboral
    local                       text NOT NULL,   -- 'unicenter', 'alcorta', 'oficina'
    categoria_cct_id            bigint REFERENCES rrhh_categorias_cct(id),
    tipo_contrato               text DEFAULT 'relacion_dependencia', -- 'relacion_dependencia' | 'monotributista'
    fecha_ingreso               date,
    fecha_baja                  date,
    motivo_baja                 text,            -- renuncia, despido, jubilación, acuerdo, abandono
    estado                      text DEFAULT 'activo', -- activo | licencia | baja
    -- Pago
    cbu                         text,
    banco                       text,
    -- Familia
    hijos                       jsonb DEFAULT '[]'::jsonb,  -- [{nombre, dni, fecha_nac}]
    -- Extra
    foto_url                    text,
    notas_internas              text,
    -- Metadata
    created_at                  timestamptz DEFAULT now(),
    updated_at                  timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_emp_dni       ON rrhh_empleados(dni);
CREATE INDEX IF NOT EXISTS idx_emp_cuil      ON rrhh_empleados(cuil);
CREATE INDEX IF NOT EXISTS idx_emp_local     ON rrhh_empleados(local);
CREATE INDEX IF NOT EXISTS idx_emp_estado    ON rrhh_empleados(estado);
CREATE INDEX IF NOT EXISTS idx_emp_fnac      ON rrhh_empleados(fecha_nacimiento);
CREATE INDEX IF NOT EXISTS idx_emp_apellido  ON rrhh_empleados(apellido);

-- Trigger para updated_at
CREATE OR REPLACE FUNCTION rrhh_set_updated_at()
RETURNS TRIGGER AS $$ BEGIN NEW.updated_at = now(); RETURN NEW; END; $$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_emp_updated ON rrhh_empleados;
CREATE TRIGGER trg_emp_updated BEFORE UPDATE ON rrhh_empleados
    FOR EACH ROW EXECUTE FUNCTION rrhh_set_updated_at();

-- ───────────────────────────────────────────────────────────────────────
-- 3. USUARIOS (auth bridge a Supabase Auth)
-- ───────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS rrhh_usuarios (
    id                  bigserial PRIMARY KEY,
    auth_user_id        uuid UNIQUE,             -- linkea a auth.users.id de Supabase Auth
    empleado_id         bigint REFERENCES rrhh_empleados(id) ON DELETE CASCADE,
    email               text UNIQUE NOT NULL,
    rol                 text NOT NULL,           -- 'admin' | 'gerente' | 'empleado'
    local_gerencia      text,                    -- si rol='gerente', qué local
    activo              boolean DEFAULT true,
    last_login          timestamptz,
    created_at          timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_usr_auth_id   ON rrhh_usuarios(auth_user_id);
CREATE INDEX IF NOT EXISTS idx_usr_empleado  ON rrhh_usuarios(empleado_id);
CREATE INDEX IF NOT EXISTS idx_usr_rol       ON rrhh_usuarios(rol);

-- ───────────────────────────────────────────────────────────────────────
-- 4. SUELDOS (liquidaciones mes a mes)
-- ───────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS rrhh_sueldos (
    id                  bigserial PRIMARY KEY,
    empleado_id         bigint NOT NULL REFERENCES rrhh_empleados(id) ON DELETE CASCADE,
    periodo             text NOT NULL,           -- 'YYYY-MM'
    -- Conceptos remunerativos
    sueldo_basico       numeric(12,2) DEFAULT 0,
    antiguedad          numeric(12,2) DEFAULT 0,
    presentismo         numeric(12,2) DEFAULT 0,
    comisiones          numeric(12,2) DEFAULT 0,
    horas_extras_50     numeric(12,2) DEFAULT 0,
    horas_extras_100    numeric(12,2) DEFAULT 0,
    premios             numeric(12,2) DEFAULT 0,
    sac                 numeric(12,2) DEFAULT 0,           -- aguinaldo
    vacaciones_pagas    numeric(12,2) DEFAULT 0,
    otros_remun         numeric(12,2) DEFAULT 0,
    -- Conceptos NO remunerativos
    no_remun            numeric(12,2) DEFAULT 0,
    -- Totales
    total_remun         numeric(12,2) DEFAULT 0,
    bruto               numeric(12,2) DEFAULT 0,
    -- Descuentos
    desc_jubilacion     numeric(12,2) DEFAULT 0,
    desc_obra_social    numeric(12,2) DEFAULT 0,
    desc_ley_19032      numeric(12,2) DEFAULT 0,
    desc_sindicato      numeric(12,2) DEFAULT 0,
    desc_otros          numeric(12,2) DEFAULT 0,
    total_descuentos    numeric(12,2) DEFAULT 0,
    -- Neto
    neto                numeric(12,2) DEFAULT 0,
    -- Pago
    fecha_pago          date,
    banco_pago          text,
    -- Archivos
    recibo_url          text,                    -- PDF en Storage
    -- Validación automática (skill control-sueldos-adorno)
    validado            boolean DEFAULT false,
    errores_detectados  jsonb DEFAULT '[]'::jsonb,
    -- Meta
    observaciones       text,
    created_at          timestamptz DEFAULT now(),
    created_by          text,                    -- email del usuario que cargó
    UNIQUE(empleado_id, periodo)
);
CREATE INDEX IF NOT EXISTS idx_sue_emp       ON rrhh_sueldos(empleado_id);
CREATE INDEX IF NOT EXISTS idx_sue_periodo   ON rrhh_sueldos(periodo DESC);
CREATE INDEX IF NOT EXISTS idx_sue_validado  ON rrhh_sueldos(validado) WHERE validado = false;

-- ───────────────────────────────────────────────────────────────────────
-- 5. ASISTENCIAS (resumen mensual por empleado)
-- ───────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS rrhh_asistencias (
    id                      bigserial PRIMARY KEY,
    empleado_id             bigint NOT NULL REFERENCES rrhh_empleados(id) ON DELETE CASCADE,
    periodo                 text NOT NULL,           -- 'YYYY-MM'
    dias_corresponden       int DEFAULT 0,           -- días laborables del mes para ese empleado
    dias_trabajados         int DEFAULT 0,
    dias_ausente            int DEFAULT 0,
    dias_vacaciones         int DEFAULT 0,
    dias_licencia           int DEFAULT 0,
    dias_feriado            int DEFAULT 0,
    llegadas_tarde          int DEFAULT 0,
    salidas_tempranas       int DEFAULT 0,
    minutos_tarde_total     int DEFAULT 0,
    horas_extras            numeric(6,2) DEFAULT 0,
    anomalias_fichada       int DEFAULT 0,           -- fichadas faltantes/inconsistentes
    reporte_crosschex_url   text,                    -- Excel original CrossChex
    analisis_url            text,                    -- Excel procesado por la skill
    observaciones           text,
    created_at              timestamptz DEFAULT now(),
    UNIQUE(empleado_id, periodo)
);
CREATE INDEX IF NOT EXISTS idx_asi_emp       ON rrhh_asistencias(empleado_id);
CREATE INDEX IF NOT EXISTS idx_asi_periodo   ON rrhh_asistencias(periodo DESC);

-- ───────────────────────────────────────────────────────────────────────
-- 6. ASISTENCIAS DETALLE (día por día — opcional)
-- ───────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS rrhh_asistencias_detalle (
    id                  bigserial PRIMARY KEY,
    empleado_id         bigint NOT NULL REFERENCES rrhh_empleados(id) ON DELETE CASCADE,
    fecha               date NOT NULL,
    entrada             time,
    salida              time,
    estado              text NOT NULL,         -- 'puntual' | 'tarde' | 'ausente' | 'vacaciones' | 'licencia' | 'feriado' | 'franco'
    minutos_tarde       int DEFAULT 0,
    minutos_salida_temp int DEFAULT 0,
    horas_trabajadas    numeric(5,2),
    observaciones       text,
    UNIQUE(empleado_id, fecha)
);
CREATE INDEX IF NOT EXISTS idx_asid_emp_fecha ON rrhh_asistencias_detalle(empleado_id, fecha DESC);
CREATE INDEX IF NOT EXISTS idx_asid_fecha     ON rrhh_asistencias_detalle(fecha DESC);
CREATE INDEX IF NOT EXISTS idx_asid_estado    ON rrhh_asistencias_detalle(estado);

-- ───────────────────────────────────────────────────────────────────────
-- 7. VACACIONES (saldo anual por empleado)
-- ───────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS rrhh_vacaciones (
    id                      bigserial PRIMARY KEY,
    empleado_id             bigint NOT NULL REFERENCES rrhh_empleados(id) ON DELETE CASCADE,
    año                     int NOT NULL,
    dias_correspondientes   int NOT NULL,        -- según antigüedad LCT (14/21/28/35)
    dias_tomados            int DEFAULT 0,
    dias_pendientes         int GENERATED ALWAYS AS (dias_correspondientes - dias_tomados) STORED,
    actualizado_at          timestamptz DEFAULT now(),
    UNIQUE(empleado_id, año)
);
CREATE INDEX IF NOT EXISTS idx_vac_emp_año  ON rrhh_vacaciones(empleado_id, año DESC);

-- ───────────────────────────────────────────────────────────────────────
-- 8. VACACIONES MOVIMIENTOS (pedidos / aprobaciones)
-- ───────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS rrhh_vacaciones_movimientos (
    id                  bigserial PRIMARY KEY,
    vacaciones_id       bigint NOT NULL REFERENCES rrhh_vacaciones(id) ON DELETE CASCADE,
    empleado_id         bigint NOT NULL REFERENCES rrhh_empleados(id),
    fecha_desde         date NOT NULL,
    fecha_hasta         date NOT NULL,
    dias                int NOT NULL,
    estado              text DEFAULT 'solicitada',   -- 'solicitada' | 'aprobada' | 'tomada' | 'cancelada' | 'rechazada'
    solicitado_por      text,                        -- email
    fecha_solicitud     timestamptz DEFAULT now(),
    aprobado_por        text,
    fecha_aprobacion    timestamptz,
    motivo_rechazo      text,
    observaciones       text
);
CREATE INDEX IF NOT EXISTS idx_vacmov_emp     ON rrhh_vacaciones_movimientos(empleado_id);
CREATE INDEX IF NOT EXISTS idx_vacmov_estado  ON rrhh_vacaciones_movimientos(estado);
CREATE INDEX IF NOT EXISTS idx_vacmov_fechas  ON rrhh_vacaciones_movimientos(fecha_desde, fecha_hasta);

-- ───────────────────────────────────────────────────────────────────────
-- 9. LICENCIAS especiales (LCT art. 158)
-- ───────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS rrhh_licencias (
    id                  bigserial PRIMARY KEY,
    empleado_id         bigint NOT NULL REFERENCES rrhh_empleados(id) ON DELETE CASCADE,
    tipo                text NOT NULL,    -- 'matrimonio' | 'nacimiento_hijo' | 'fallecimiento' | 'examen' | 'enfermedad' | 'ART' | 'maternidad' | 'excedencia' | 'otra'
    fecha_desde         date NOT NULL,
    fecha_hasta         date NOT NULL,
    dias                int NOT NULL,
    paga                boolean DEFAULT true,
    certificado_url     text,
    observaciones       text,
    aprobado_por        text,
    created_at          timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_lic_emp    ON rrhh_licencias(empleado_id);
CREATE INDEX IF NOT EXISTS idx_lic_tipo   ON rrhh_licencias(tipo);
CREATE INDEX IF NOT EXISTS idx_lic_fechas ON rrhh_licencias(fecha_desde, fecha_hasta);

-- ───────────────────────────────────────────────────────────────────────
-- 10. CERTIFICADOS MÉDICOS
-- ───────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS rrhh_certificados_medicos (
    id                  bigserial PRIMARY KEY,
    empleado_id         bigint NOT NULL REFERENCES rrhh_empleados(id) ON DELETE CASCADE,
    fecha_desde         date NOT NULL,
    fecha_hasta         date NOT NULL,
    dias                int NOT NULL,
    diagnostico         text,
    medico              text,
    especialidad        text,
    matricula           text,
    archivo_url         text,
    validado            boolean DEFAULT false,
    validador           text,
    fecha_validacion    timestamptz,
    observaciones       text,
    created_at          timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_cert_emp       ON rrhh_certificados_medicos(empleado_id);
CREATE INDEX IF NOT EXISTS idx_cert_fechas    ON rrhh_certificados_medicos(fecha_desde, fecha_hasta);
CREATE INDEX IF NOT EXISTS idx_cert_validado  ON rrhh_certificados_medicos(validado) WHERE validado = false;

-- ───────────────────────────────────────────────────────────────────────
-- 11. APERCIBIMIENTOS
-- ───────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS rrhh_apercibimientos (
    id                  bigserial PRIMARY KEY,
    empleado_id         bigint NOT NULL REFERENCES rrhh_empleados(id) ON DELETE CASCADE,
    fecha               date NOT NULL,
    motivo              text NOT NULL,
    severidad           text DEFAULT 'leve',   -- 'leve' | 'grave' | 'gravisima'
    archivo_url         text,
    firmado             boolean DEFAULT false,
    firmado_at          timestamptz,
    cargado_por         text,
    created_at          timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_aper_emp     ON rrhh_apercibimientos(empleado_id);
CREATE INDEX IF NOT EXISTS idx_aper_fecha   ON rrhh_apercibimientos(fecha DESC);

-- ───────────────────────────────────────────────────────────────────────
-- 12. DOCUMENTOS (repositorio general por empleado)
-- ───────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS rrhh_documentos (
    id                  bigserial PRIMARY KEY,
    empleado_id         bigint NOT NULL REFERENCES rrhh_empleados(id) ON DELETE CASCADE,
    tipo                text NOT NULL,    -- 'contrato' | 'alta_afip' | 'cbu' | 'dni_frente' | 'dni_dorso' | 'cv' | 'titulo' | 'cuit_monotrib' | 'planilla_horaria' | 'otro'
    nombre              text NOT NULL,
    archivo_url         text NOT NULL,
    fecha_alta          date DEFAULT CURRENT_DATE,
    fecha_vencimiento   date,
    cargado_por         text,
    created_at          timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_doc_emp       ON rrhh_documentos(empleado_id);
CREATE INDEX IF NOT EXISTS idx_doc_tipo      ON rrhh_documentos(tipo);
CREATE INDEX IF NOT EXISTS idx_doc_venc      ON rrhh_documentos(fecha_vencimiento) WHERE fecha_vencimiento IS NOT NULL;

-- ───────────────────────────────────────────────────────────────────────
-- 13. PREMIOS / RECONOCIMIENTOS
-- ───────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS rrhh_premios (
    id                  bigserial PRIMARY KEY,
    empleado_id         bigint NOT NULL REFERENCES rrhh_empleados(id) ON DELETE CASCADE,
    fecha               date NOT NULL,
    tipo                text,             -- 'venta_trimestre' | 'antiguedad' | 'reconocimiento' | 'otros'
    monto               numeric(12,2),
    motivo              text,
    otorgado_por        text,
    created_at          timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_prem_emp ON rrhh_premios(empleado_id);

-- ───────────────────────────────────────────────────────────────────────
-- 14. AUDIT LOG (mismo patrón que pedidos_log del CRM)
-- ───────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS rrhh_log (
    id              bigserial PRIMARY KEY,
    timestamp       timestamptz DEFAULT now(),
    usuario         text,
    rol             text,
    accion          text NOT NULL,    -- 'crear' | 'editar' | 'eliminar' | 'login' | 'aprobar_vacaciones' | etc.
    tabla           text,
    registro_id     bigint,
    campo           text,
    valor_anterior  text,
    valor_nuevo     text,
    ip              text,
    user_agent      text
);
CREATE INDEX IF NOT EXISTS idx_log_ts    ON rrhh_log(timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_log_usr   ON rrhh_log(usuario);
CREATE INDEX IF NOT EXISTS idx_log_reg   ON rrhh_log(tabla, registro_id);

-- ───────────────────────────────────────────────────────────────────────
-- 15. FERIADOS (calendario AR — compartido con skill control-asistencias)
-- ───────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS rrhh_feriados (
    id              bigserial PRIMARY KEY,
    fecha           date UNIQUE NOT NULL,
    nombre          text NOT NULL,
    tipo            text DEFAULT 'nacional',   -- 'nacional' | 'puente' | 'no_laborable' | 'turistico'
    created_at      timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_fer_fecha ON rrhh_feriados(fecha);

-- ═══════════════════════════════════════════════════════════════════════
-- FIN del schema. Siguiente: 02_rls.sql
-- ═══════════════════════════════════════════════════════════════════════

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- ARCHIVO 2/4: ROW LEVEL SECURITY
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- ═══════════════════════════════════════════════════════════════════════
--  MÓDULO RRHH — Row Level Security
--  Ejecutar DESPUÉS de 01_schema.sql
--
--  Lógica:
--   - admin: ve y modifica todo
--   - gerente: ve empleados de su local + asistencias / aprueba vacaciones de su local
--   - empleado: ve solo SU propio registro (mi_legajo, mis_sueldos, mis_asistencias…)
--   - service_role / anon (CRM): NO acceso a tablas rrhh_* (separación de módulos)
--
--  Auth: Supabase Auth — auth.uid() devuelve el UUID del usuario logueado
--  Tabla puente: rrhh_usuarios (auth_user_id → empleado_id + rol)
-- ═══════════════════════════════════════════════════════════════════════

-- ───────────────────────────────────────────────────────────────────────
-- Helpers (funciones SECURITY DEFINER que leen rrhh_usuarios)
-- ───────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION rrhh_current_user()
RETURNS rrhh_usuarios
LANGUAGE sql STABLE SECURITY DEFINER AS $$
    SELECT * FROM rrhh_usuarios WHERE auth_user_id = auth.uid() AND activo = true LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION rrhh_is_admin()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER AS $$
    SELECT EXISTS (SELECT 1 FROM rrhh_usuarios WHERE auth_user_id = auth.uid() AND rol = 'admin' AND activo = true);
$$;

CREATE OR REPLACE FUNCTION rrhh_is_gerente()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER AS $$
    SELECT EXISTS (SELECT 1 FROM rrhh_usuarios WHERE auth_user_id = auth.uid() AND rol = 'gerente' AND activo = true);
$$;

CREATE OR REPLACE FUNCTION rrhh_gerente_local()
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER AS $$
    SELECT local_gerencia FROM rrhh_usuarios WHERE auth_user_id = auth.uid() AND rol = 'gerente' AND activo = true LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION rrhh_mi_empleado_id()
RETURNS bigint LANGUAGE sql STABLE SECURITY DEFINER AS $$
    SELECT empleado_id FROM rrhh_usuarios WHERE auth_user_id = auth.uid() AND activo = true LIMIT 1;
$$;

-- ───────────────────────────────────────────────────────────────────────
-- Aplicar RLS a todas las tablas
-- ───────────────────────────────────────────────────────────────────────
ALTER TABLE rrhh_categorias_cct           ENABLE ROW LEVEL SECURITY;
ALTER TABLE rrhh_empleados                ENABLE ROW LEVEL SECURITY;
ALTER TABLE rrhh_usuarios                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE rrhh_sueldos                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE rrhh_asistencias              ENABLE ROW LEVEL SECURITY;
ALTER TABLE rrhh_asistencias_detalle      ENABLE ROW LEVEL SECURITY;
ALTER TABLE rrhh_vacaciones               ENABLE ROW LEVEL SECURITY;
ALTER TABLE rrhh_vacaciones_movimientos   ENABLE ROW LEVEL SECURITY;
ALTER TABLE rrhh_licencias                ENABLE ROW LEVEL SECURITY;
ALTER TABLE rrhh_certificados_medicos     ENABLE ROW LEVEL SECURITY;
ALTER TABLE rrhh_apercibimientos          ENABLE ROW LEVEL SECURITY;
ALTER TABLE rrhh_documentos               ENABLE ROW LEVEL SECURITY;
ALTER TABLE rrhh_premios                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE rrhh_log                      ENABLE ROW LEVEL SECURITY;
ALTER TABLE rrhh_feriados                 ENABLE ROW LEVEL SECURITY;

-- ───────────────────────────────────────────────────────────────────────
-- 1. CATEGORIAS CCT — todos pueden leer, solo admin escribe
-- ───────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS cct_read  ON rrhh_categorias_cct;
DROP POLICY IF EXISTS cct_write ON rrhh_categorias_cct;
CREATE POLICY cct_read  ON rrhh_categorias_cct FOR SELECT USING (true);
CREATE POLICY cct_write ON rrhh_categorias_cct FOR ALL    USING (rrhh_is_admin()) WITH CHECK (rrhh_is_admin());

-- ───────────────────────────────────────────────────────────────────────
-- 2. EMPLEADOS
--    admin: todo | gerente: su local | empleado: solo el suyo
-- ───────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS emp_admin    ON rrhh_empleados;
DROP POLICY IF EXISTS emp_gerente  ON rrhh_empleados;
DROP POLICY IF EXISTS emp_self     ON rrhh_empleados;
CREATE POLICY emp_admin   ON rrhh_empleados FOR ALL
    USING (rrhh_is_admin()) WITH CHECK (rrhh_is_admin());
CREATE POLICY emp_gerente ON rrhh_empleados FOR SELECT
    USING (rrhh_is_gerente() AND local = rrhh_gerente_local());
CREATE POLICY emp_self    ON rrhh_empleados FOR SELECT
    USING (id = rrhh_mi_empleado_id());

-- ───────────────────────────────────────────────────────────────────────
-- 3. USUARIOS — solo admin gestiona, cada uno ve el suyo
-- ───────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS usr_admin ON rrhh_usuarios;
DROP POLICY IF EXISTS usr_self  ON rrhh_usuarios;
CREATE POLICY usr_admin ON rrhh_usuarios FOR ALL
    USING (rrhh_is_admin()) WITH CHECK (rrhh_is_admin());
CREATE POLICY usr_self  ON rrhh_usuarios FOR SELECT
    USING (auth_user_id = auth.uid());

-- ───────────────────────────────────────────────────────────────────────
-- 4. SUELDOS — admin todo | empleado solo los suyos
--    (gerentes NO ven sueldos del equipo por privacidad)
-- ───────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS sue_admin ON rrhh_sueldos;
DROP POLICY IF EXISTS sue_self  ON rrhh_sueldos;
CREATE POLICY sue_admin ON rrhh_sueldos FOR ALL
    USING (rrhh_is_admin()) WITH CHECK (rrhh_is_admin());
CREATE POLICY sue_self  ON rrhh_sueldos FOR SELECT
    USING (empleado_id = rrhh_mi_empleado_id());

-- ───────────────────────────────────────────────────────────────────────
-- 5-6. ASISTENCIAS (resumen + detalle)
--    admin: todo | gerente: su local | empleado: las suyas
-- ───────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS asi_admin    ON rrhh_asistencias;
DROP POLICY IF EXISTS asi_gerente  ON rrhh_asistencias;
DROP POLICY IF EXISTS asi_self     ON rrhh_asistencias;
CREATE POLICY asi_admin   ON rrhh_asistencias FOR ALL
    USING (rrhh_is_admin()) WITH CHECK (rrhh_is_admin());
CREATE POLICY asi_gerente ON rrhh_asistencias FOR ALL
    USING (rrhh_is_gerente() AND empleado_id IN (SELECT id FROM rrhh_empleados WHERE local = rrhh_gerente_local()))
    WITH CHECK (rrhh_is_gerente() AND empleado_id IN (SELECT id FROM rrhh_empleados WHERE local = rrhh_gerente_local()));
CREATE POLICY asi_self    ON rrhh_asistencias FOR SELECT
    USING (empleado_id = rrhh_mi_empleado_id());

DROP POLICY IF EXISTS asid_admin    ON rrhh_asistencias_detalle;
DROP POLICY IF EXISTS asid_gerente  ON rrhh_asistencias_detalle;
DROP POLICY IF EXISTS asid_self     ON rrhh_asistencias_detalle;
CREATE POLICY asid_admin   ON rrhh_asistencias_detalle FOR ALL
    USING (rrhh_is_admin()) WITH CHECK (rrhh_is_admin());
CREATE POLICY asid_gerente ON rrhh_asistencias_detalle FOR ALL
    USING (rrhh_is_gerente() AND empleado_id IN (SELECT id FROM rrhh_empleados WHERE local = rrhh_gerente_local()))
    WITH CHECK (rrhh_is_gerente() AND empleado_id IN (SELECT id FROM rrhh_empleados WHERE local = rrhh_gerente_local()));
CREATE POLICY asid_self    ON rrhh_asistencias_detalle FOR SELECT
    USING (empleado_id = rrhh_mi_empleado_id());

-- ───────────────────────────────────────────────────────────────────────
-- 7-8. VACACIONES (saldo + movimientos)
-- ───────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS vac_admin    ON rrhh_vacaciones;
DROP POLICY IF EXISTS vac_gerente  ON rrhh_vacaciones;
DROP POLICY IF EXISTS vac_self     ON rrhh_vacaciones;
CREATE POLICY vac_admin   ON rrhh_vacaciones FOR ALL
    USING (rrhh_is_admin()) WITH CHECK (rrhh_is_admin());
CREATE POLICY vac_gerente ON rrhh_vacaciones FOR SELECT
    USING (rrhh_is_gerente() AND empleado_id IN (SELECT id FROM rrhh_empleados WHERE local = rrhh_gerente_local()));
CREATE POLICY vac_self    ON rrhh_vacaciones FOR SELECT
    USING (empleado_id = rrhh_mi_empleado_id());

DROP POLICY IF EXISTS vacmov_admin   ON rrhh_vacaciones_movimientos;
DROP POLICY IF EXISTS vacmov_gerente ON rrhh_vacaciones_movimientos;
DROP POLICY IF EXISTS vacmov_self    ON rrhh_vacaciones_movimientos;
CREATE POLICY vacmov_admin   ON rrhh_vacaciones_movimientos FOR ALL
    USING (rrhh_is_admin()) WITH CHECK (rrhh_is_admin());
-- gerente: ve y aprueba/rechaza pedidos de su local
CREATE POLICY vacmov_gerente ON rrhh_vacaciones_movimientos FOR ALL
    USING (rrhh_is_gerente() AND empleado_id IN (SELECT id FROM rrhh_empleados WHERE local = rrhh_gerente_local()))
    WITH CHECK (rrhh_is_gerente() AND empleado_id IN (SELECT id FROM rrhh_empleados WHERE local = rrhh_gerente_local()));
-- empleado: ve los suyos + puede solicitar (INSERT en estado 'solicitada')
CREATE POLICY vacmov_self ON rrhh_vacaciones_movimientos FOR SELECT
    USING (empleado_id = rrhh_mi_empleado_id());
DROP POLICY IF EXISTS vacmov_self_insert ON rrhh_vacaciones_movimientos;
CREATE POLICY vacmov_self_insert ON rrhh_vacaciones_movimientos FOR INSERT
    WITH CHECK (empleado_id = rrhh_mi_empleado_id() AND estado = 'solicitada');

-- ───────────────────────────────────────────────────────────────────────
-- 9. LICENCIAS
-- ───────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS lic_admin    ON rrhh_licencias;
DROP POLICY IF EXISTS lic_gerente  ON rrhh_licencias;
DROP POLICY IF EXISTS lic_self     ON rrhh_licencias;
CREATE POLICY lic_admin   ON rrhh_licencias FOR ALL
    USING (rrhh_is_admin()) WITH CHECK (rrhh_is_admin());
CREATE POLICY lic_gerente ON rrhh_licencias FOR SELECT
    USING (rrhh_is_gerente() AND empleado_id IN (SELECT id FROM rrhh_empleados WHERE local = rrhh_gerente_local()));
CREATE POLICY lic_self    ON rrhh_licencias FOR SELECT
    USING (empleado_id = rrhh_mi_empleado_id());

-- ───────────────────────────────────────────────────────────────────────
-- 10. CERTIFICADOS MÉDICOS
-- ───────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS cert_admin    ON rrhh_certificados_medicos;
DROP POLICY IF EXISTS cert_gerente  ON rrhh_certificados_medicos;
DROP POLICY IF EXISTS cert_self     ON rrhh_certificados_medicos;
DROP POLICY IF EXISTS cert_self_ins ON rrhh_certificados_medicos;
CREATE POLICY cert_admin   ON rrhh_certificados_medicos FOR ALL
    USING (rrhh_is_admin()) WITH CHECK (rrhh_is_admin());
CREATE POLICY cert_gerente ON rrhh_certificados_medicos FOR ALL
    USING (rrhh_is_gerente() AND empleado_id IN (SELECT id FROM rrhh_empleados WHERE local = rrhh_gerente_local()))
    WITH CHECK (rrhh_is_gerente() AND empleado_id IN (SELECT id FROM rrhh_empleados WHERE local = rrhh_gerente_local()));
CREATE POLICY cert_self    ON rrhh_certificados_medicos FOR SELECT
    USING (empleado_id = rrhh_mi_empleado_id());
-- el empleado puede subir su certificado (validado=false hasta que admin lo valide)
CREATE POLICY cert_self_ins ON rrhh_certificados_medicos FOR INSERT
    WITH CHECK (empleado_id = rrhh_mi_empleado_id() AND validado = false);

-- ───────────────────────────────────────────────────────────────────────
-- 11. APERCIBIMIENTOS
-- ───────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS aper_admin   ON rrhh_apercibimientos;
DROP POLICY IF EXISTS aper_gerente ON rrhh_apercibimientos;
DROP POLICY IF EXISTS aper_self    ON rrhh_apercibimientos;
CREATE POLICY aper_admin   ON rrhh_apercibimientos FOR ALL
    USING (rrhh_is_admin()) WITH CHECK (rrhh_is_admin());
CREATE POLICY aper_gerente ON rrhh_apercibimientos FOR ALL
    USING (rrhh_is_gerente() AND empleado_id IN (SELECT id FROM rrhh_empleados WHERE local = rrhh_gerente_local()))
    WITH CHECK (rrhh_is_gerente() AND empleado_id IN (SELECT id FROM rrhh_empleados WHERE local = rrhh_gerente_local()));
CREATE POLICY aper_self    ON rrhh_apercibimientos FOR SELECT
    USING (empleado_id = rrhh_mi_empleado_id());

-- ───────────────────────────────────────────────────────────────────────
-- 12. DOCUMENTOS
-- ───────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS doc_admin ON rrhh_documentos;
DROP POLICY IF EXISTS doc_self  ON rrhh_documentos;
CREATE POLICY doc_admin ON rrhh_documentos FOR ALL
    USING (rrhh_is_admin()) WITH CHECK (rrhh_is_admin());
CREATE POLICY doc_self  ON rrhh_documentos FOR SELECT
    USING (empleado_id = rrhh_mi_empleado_id());

-- ───────────────────────────────────────────────────────────────────────
-- 13. PREMIOS
-- ───────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS prem_admin   ON rrhh_premios;
DROP POLICY IF EXISTS prem_gerente ON rrhh_premios;
DROP POLICY IF EXISTS prem_self    ON rrhh_premios;
CREATE POLICY prem_admin   ON rrhh_premios FOR ALL
    USING (rrhh_is_admin()) WITH CHECK (rrhh_is_admin());
CREATE POLICY prem_gerente ON rrhh_premios FOR SELECT
    USING (rrhh_is_gerente() AND empleado_id IN (SELECT id FROM rrhh_empleados WHERE local = rrhh_gerente_local()));
CREATE POLICY prem_self    ON rrhh_premios FOR SELECT
    USING (empleado_id = rrhh_mi_empleado_id());

-- ───────────────────────────────────────────────────────────────────────
-- 14. AUDIT LOG — solo admin lee, todos pueden insertar (vía función)
-- ───────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS log_admin  ON rrhh_log;
DROP POLICY IF EXISTS log_insert ON rrhh_log;
CREATE POLICY log_admin  ON rrhh_log FOR SELECT USING (rrhh_is_admin());
CREATE POLICY log_insert ON rrhh_log FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

-- ───────────────────────────────────────────────────────────────────────
-- 15. FERIADOS — todos leen, solo admin escribe
-- ───────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS fer_read  ON rrhh_feriados;
DROP POLICY IF EXISTS fer_write ON rrhh_feriados;
CREATE POLICY fer_read  ON rrhh_feriados FOR SELECT USING (true);
CREATE POLICY fer_write ON rrhh_feriados FOR ALL    USING (rrhh_is_admin()) WITH CHECK (rrhh_is_admin());

-- ═══════════════════════════════════════════════════════════════════════
-- FIN RLS. Siguiente: 03_storage.sql
-- ═══════════════════════════════════════════════════════════════════════

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- ARCHIVO 3/4: STORAGE
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- ═══════════════════════════════════════════════════════════════════════
--  MÓDULO RRHH — Storage buckets + políticas
--  Ejecutar DESPUÉS de 02_rls.sql
--
--  Buckets:
--   rrhh-recibos          → recibos de sueldo PDF
--   rrhh-certificados     → certificados médicos PDF/imagen
--   rrhh-apercibimientos  → apercibimientos PDF firmados
--   rrhh-documentos       → contratos, DNI, CBU, CV, etc.
--   rrhh-fotos            → fotos de empleados (jpg/png)
--   rrhh-asistencias-raw  → Excel originales de CrossChex
--
--  Convención de paths:
--   {empleado_id}/{tipo}/{nombre_archivo}
--   ej: 42/recibo/2026-04.pdf
-- ═══════════════════════════════════════════════════════════════════════

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES
    ('rrhh-recibos',          'rrhh-recibos',          false, 10485760,  ARRAY['application/pdf']::text[]),
    ('rrhh-certificados',     'rrhh-certificados',     false, 10485760,  ARRAY['application/pdf','image/jpeg','image/png']::text[]),
    ('rrhh-apercibimientos',  'rrhh-apercibimientos',  false, 10485760,  ARRAY['application/pdf','image/jpeg','image/png']::text[]),
    ('rrhh-documentos',       'rrhh-documentos',       false, 20971520,  ARRAY['application/pdf','image/jpeg','image/png','application/msword','application/vnd.openxmlformats-officedocument.wordprocessingml.document']::text[]),
    ('rrhh-fotos',            'rrhh-fotos',            false,  5242880,  ARRAY['image/jpeg','image/png','image/webp']::text[]),
    ('rrhh-asistencias-raw',  'rrhh-asistencias-raw',  false, 52428800,  ARRAY['application/vnd.ms-excel','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet']::text[])
ON CONFLICT (id) DO NOTHING;

-- ───────────────────────────────────────────────────────────────────────
-- Políticas Storage — patrón: admin todo, empleado solo su carpeta
-- (storage.objects usa storage.foldername(name) para extraer el primer segmento del path)
-- ───────────────────────────────────────────────────────────────────────

-- Helper común: el primer segmento del path es el empleado_id
-- (storage.foldername devuelve array, tomamos índice 1)

-- ===== RECIBOS =====
DROP POLICY IF EXISTS rrhh_recibos_admin  ON storage.objects;
DROP POLICY IF EXISTS rrhh_recibos_self   ON storage.objects;
CREATE POLICY rrhh_recibos_admin ON storage.objects FOR ALL TO authenticated
    USING (bucket_id = 'rrhh-recibos' AND rrhh_is_admin())
    WITH CHECK (bucket_id = 'rrhh-recibos' AND rrhh_is_admin());
CREATE POLICY rrhh_recibos_self ON storage.objects FOR SELECT TO authenticated
    USING (bucket_id = 'rrhh-recibos'
           AND (storage.foldername(name))[1] = rrhh_mi_empleado_id()::text);

-- ===== CERTIFICADOS =====
DROP POLICY IF EXISTS rrhh_cert_admin   ON storage.objects;
DROP POLICY IF EXISTS rrhh_cert_self    ON storage.objects;
DROP POLICY IF EXISTS rrhh_cert_gerente ON storage.objects;
CREATE POLICY rrhh_cert_admin ON storage.objects FOR ALL TO authenticated
    USING (bucket_id = 'rrhh-certificados' AND rrhh_is_admin())
    WITH CHECK (bucket_id = 'rrhh-certificados' AND rrhh_is_admin());
CREATE POLICY rrhh_cert_self ON storage.objects FOR ALL TO authenticated
    USING (bucket_id = 'rrhh-certificados' AND (storage.foldername(name))[1] = rrhh_mi_empleado_id()::text)
    WITH CHECK (bucket_id = 'rrhh-certificados' AND (storage.foldername(name))[1] = rrhh_mi_empleado_id()::text);
CREATE POLICY rrhh_cert_gerente ON storage.objects FOR SELECT TO authenticated
    USING (bucket_id = 'rrhh-certificados'
           AND rrhh_is_gerente()
           AND (storage.foldername(name))[1]::bigint IN
               (SELECT id FROM rrhh_empleados WHERE local = rrhh_gerente_local()));

-- ===== APERCIBIMIENTOS =====
DROP POLICY IF EXISTS rrhh_aper_admin   ON storage.objects;
DROP POLICY IF EXISTS rrhh_aper_gerente ON storage.objects;
DROP POLICY IF EXISTS rrhh_aper_self    ON storage.objects;
CREATE POLICY rrhh_aper_admin ON storage.objects FOR ALL TO authenticated
    USING (bucket_id = 'rrhh-apercibimientos' AND rrhh_is_admin())
    WITH CHECK (bucket_id = 'rrhh-apercibimientos' AND rrhh_is_admin());
CREATE POLICY rrhh_aper_gerente ON storage.objects FOR ALL TO authenticated
    USING (bucket_id = 'rrhh-apercibimientos' AND rrhh_is_gerente()
           AND (storage.foldername(name))[1]::bigint IN
               (SELECT id FROM rrhh_empleados WHERE local = rrhh_gerente_local()))
    WITH CHECK (bucket_id = 'rrhh-apercibimientos' AND rrhh_is_gerente()
           AND (storage.foldername(name))[1]::bigint IN
               (SELECT id FROM rrhh_empleados WHERE local = rrhh_gerente_local()));
CREATE POLICY rrhh_aper_self ON storage.objects FOR SELECT TO authenticated
    USING (bucket_id = 'rrhh-apercibimientos'
           AND (storage.foldername(name))[1] = rrhh_mi_empleado_id()::text);

-- ===== DOCUMENTOS =====
DROP POLICY IF EXISTS rrhh_doc_admin ON storage.objects;
DROP POLICY IF EXISTS rrhh_doc_self  ON storage.objects;
CREATE POLICY rrhh_doc_admin ON storage.objects FOR ALL TO authenticated
    USING (bucket_id = 'rrhh-documentos' AND rrhh_is_admin())
    WITH CHECK (bucket_id = 'rrhh-documentos' AND rrhh_is_admin());
CREATE POLICY rrhh_doc_self ON storage.objects FOR SELECT TO authenticated
    USING (bucket_id = 'rrhh-documentos'
           AND (storage.foldername(name))[1] = rrhh_mi_empleado_id()::text);

-- ===== FOTOS =====
DROP POLICY IF EXISTS rrhh_foto_admin ON storage.objects;
DROP POLICY IF EXISTS rrhh_foto_self  ON storage.objects;
DROP POLICY IF EXISTS rrhh_foto_read  ON storage.objects;
CREATE POLICY rrhh_foto_admin ON storage.objects FOR ALL TO authenticated
    USING (bucket_id = 'rrhh-fotos' AND rrhh_is_admin())
    WITH CHECK (bucket_id = 'rrhh-fotos' AND rrhh_is_admin());
CREATE POLICY rrhh_foto_self ON storage.objects FOR ALL TO authenticated
    USING (bucket_id = 'rrhh-fotos' AND (storage.foldername(name))[1] = rrhh_mi_empleado_id()::text)
    WITH CHECK (bucket_id = 'rrhh-fotos' AND (storage.foldername(name))[1] = rrhh_mi_empleado_id()::text);
-- todos los logueados pueden ver las fotos (para listados, ABM, etc.)
CREATE POLICY rrhh_foto_read ON storage.objects FOR SELECT TO authenticated
    USING (bucket_id = 'rrhh-fotos');

-- ===== ASISTENCIAS RAW =====
DROP POLICY IF EXISTS rrhh_asi_admin   ON storage.objects;
DROP POLICY IF EXISTS rrhh_asi_gerente ON storage.objects;
CREATE POLICY rrhh_asi_admin ON storage.objects FOR ALL TO authenticated
    USING (bucket_id = 'rrhh-asistencias-raw' AND rrhh_is_admin())
    WITH CHECK (bucket_id = 'rrhh-asistencias-raw' AND rrhh_is_admin());
CREATE POLICY rrhh_asi_gerente ON storage.objects FOR SELECT TO authenticated
    USING (bucket_id = 'rrhh-asistencias-raw' AND rrhh_is_gerente());

-- ═══════════════════════════════════════════════════════════════════════
-- FIN Storage. Siguiente: 04_seed.sql
-- ═══════════════════════════════════════════════════════════════════════

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- ARCHIVO 4/4: SEED INICIAL
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- ═══════════════════════════════════════════════════════════════════════
--  MÓDULO RRHH — Seed inicial
--  Ejecutar DESPUÉS de 03_storage.sql
--
--  Carga:
--   - Categorías CCT 130/75 vigentes abril 2026
--   - 19 empleados activos (padrón actualizado abril 2026)
--   - Feriados nacionales Argentina 2026
--   - Saldos de vacaciones 2026 calculados según antigüedad
-- ═══════════════════════════════════════════════════════════════════════

-- ───────────────────────────────────────────────────────────────────────
-- CATEGORÍAS CCT 130/75 — Vigente abril 2026
-- (Mayo: +1.5%, Junio: +1.5% adicional sobre estos básicos)
-- ───────────────────────────────────────────────────────────────────────
INSERT INTO rrhh_categorias_cct (codigo, nombre, sueldo_basico, fecha_vigencia, activa) VALUES
    ('vendedor_b',         'Vendedor B',                      1117925.00, '2026-04-01', true),
    ('vendedor_a',         'Vendedor A',                      1117925.00, '2026-04-01', true),  -- TODO confirmar
    ('administrativo_b',   'Administrativo B',                1095297.00, '2026-04-01', true),
    ('administrativo_a',   'Administrativo A',                1095297.00, '2026-04-01', true),  -- TODO confirmar
    ('maestranza_b',       'Maestranza B',                    1082029.00, '2026-04-01', true),
    ('aux_especializado_b','Auxiliar Especializado B',        1117922.00, '2026-04-01', true),
    ('cajero_a',           'Cajero A',                              0.00, '2026-04-01', false), -- pendiente paritaria
    ('encargada',          'Encargada (no estándar)',         1117925.00, '2026-04-01', true),
    ('franquera',          'Franquera (no estándar)',         1117925.00, '2026-04-01', true),
    ('fuera_convenio',     'Fuera de convenio',                     0.00, '2026-04-01', true),
    ('directora',          'Directora SRL',                         0.00, '2026-04-01', true)
ON CONFLICT (codigo) DO NOTHING;

-- ───────────────────────────────────────────────────────────────────────
-- EMPLEADOS ACTIVOS (19) — Padrón abril 2026
-- ───────────────────────────────────────────────────────────────────────
INSERT INTO rrhh_empleados (
    dni, cuil, apellido, nombre, local, categoria_cct_id, tipo_contrato, fecha_ingreso, estado
) VALUES
    -- ===== OFICINA (Don Torcuato) — administración =====
    ('21939672', '23-21939672-4', 'CONTRERAS', 'MARISA ISABEL',          'oficina',   (SELECT id FROM rrhh_categorias_cct WHERE codigo='administrativo_b'), 'relacion_dependencia', '2006-03-22', 'activo'),
    ('13531903', '27-13531903-7', 'ADORNO',    'CLAUDIA VIVIANA',        'oficina',   (SELECT id FROM rrhh_categorias_cct WHERE codigo='directora'),         'relacion_dependencia', '2007-10-01', 'activo'),
    ('36754687', '20-36754687-6', 'SIMONELLI', 'JUAN PABLO',             'oficina',   (SELECT id FROM rrhh_categorias_cct WHERE codigo='fuera_convenio'),    'relacion_dependencia', '2015-07-15', 'activo'),
    ('37356286', '20-37356286-7', 'MONZON',    'CARLOS IVAN',            'oficina',   (SELECT id FROM rrhh_categorias_cct WHERE codigo='maestranza_b'),      'relacion_dependencia', '2016-11-21', 'activo'),
    ('34736736', '27-34736736-8', 'RIVERA',    'ANALIA BEATRIZ',         'oficina',   (SELECT id FROM rrhh_categorias_cct WHERE codigo='administrativo_b'), 'relacion_dependencia', '2019-06-13', 'activo'),

    -- ===== UNICENTER (Martínez) — 7 vendedoras =====
    ('31741055', '27-31741055-2', 'DONZELLI',  'SORAYA BEATRIZ',         'unicenter', (SELECT id FROM rrhh_categorias_cct WHERE codigo='encargada'),         'relacion_dependencia', '2008-11-01', 'activo'),
    ('18717942', '23-18717942-4', 'DAMELA',    'SILVINA ALICIA',         'unicenter', (SELECT id FROM rrhh_categorias_cct WHERE codigo='vendedor_b'),        'relacion_dependencia', '2010-04-22', 'activo'),
    ('36248849', '23-36248849-4', 'GODOY',     'CINTIA PAMELA',          'unicenter', (SELECT id FROM rrhh_categorias_cct WHERE codigo='vendedor_b'),        'relacion_dependencia', '2014-05-05', 'activo'),
    ('22275528', '27-22275528-5', 'SANCHEZ',   'SONIA LUZ',              'unicenter', (SELECT id FROM rrhh_categorias_cct WHERE codigo='vendedor_b'),        'relacion_dependencia', '2015-07-27', 'activo'),
    ('33980834', '27-33980834-7', 'ESCASANY',  'ANGELES',                'unicenter', (SELECT id FROM rrhh_categorias_cct WHERE codigo='franquera'),         'relacion_dependencia', '2018-06-18', 'activo'),
    ('29951723', '27-29951723-9', 'FRECCERO MEZA', 'ESTEFANIA NOEMI',    'unicenter', (SELECT id FROM rrhh_categorias_cct WHERE codigo='vendedor_b'),        'relacion_dependencia', '2022-12-01', 'activo'),
    ('29168551', '20-29168551-0', 'MOREIRA',   'GABRIELA LILIANA',       'unicenter', (SELECT id FROM rrhh_categorias_cct WHERE codigo='vendedor_b'),        'relacion_dependencia', '2023-11-27', 'activo'),

    -- ===== ALCORTA (CABA Paseo Alcorta) — 7 vendedoras =====
    ('29695460', '27-29695460-3', 'BENITEZ',   'ROMINA SOLANGE',         'alcorta',   (SELECT id FROM rrhh_categorias_cct WHERE codigo='vendedor_b'),        'relacion_dependencia', '2007-07-23', 'activo'),
    ('22041488', '23-22041488-4', 'QUIROGA',   'ELISABETH LAURA',        'alcorta',   (SELECT id FROM rrhh_categorias_cct WHERE codigo='vendedor_b'),        'relacion_dependencia', '2009-04-16', 'activo'),
    ('26933834', '27-26933834-8', 'COPA',      'LILIANA TERESA',         'alcorta',   (SELECT id FROM rrhh_categorias_cct WHERE codigo='vendedor_b'),        'relacion_dependencia', '2011-10-01', 'activo'),
    ('26186117', '27-26186117-3', 'BIANCHI',   'MARIA SOLEDAD',          'alcorta',   (SELECT id FROM rrhh_categorias_cct WHERE codigo='vendedor_b'),        'relacion_dependencia', '2015-06-01', 'activo'),
    ('28188721', '27-28188721-7', 'NICOLA',    'VALERIA ALCIRA',         'alcorta',   (SELECT id FROM rrhh_categorias_cct WHERE codigo='vendedor_b'),        'relacion_dependencia', '2017-07-01', 'activo'),
    ('95925193', '20-95925193-3', 'NOGUERA PARRA', 'ADRIAN',             'alcorta',   (SELECT id FROM rrhh_categorias_cct WHERE codigo='vendedor_b'),        'relacion_dependencia', '2023-09-05', 'activo'),
    ('34798072', '27-34798072-8', 'VERON',     'GEORGINA ELIZABETH',     'alcorta',   (SELECT id FROM rrhh_categorias_cct WHERE codigo='vendedor_b'),        'relacion_dependencia', '2025-05-02', 'activo')
ON CONFLICT (dni) DO NOTHING;

-- ───────────────────────────────────────────────────────────────────────
-- SALDOS DE VACACIONES 2026 — calculados según antigüedad (LCT Art. 150)
--   < 5 años:  14 días corridos
--   5-10 años: 21 días corridos
--   10-20 años: 28 días corridos
--   > 20 años: 35 días corridos
-- ───────────────────────────────────────────────────────────────────────
INSERT INTO rrhh_vacaciones (empleado_id, año, dias_correspondientes, dias_tomados)
SELECT
    e.id,
    2026,
    CASE
        WHEN (DATE '2026-12-31' - e.fecha_ingreso) / 365 >= 20 THEN 35
        WHEN (DATE '2026-12-31' - e.fecha_ingreso) / 365 >= 10 THEN 28
        WHEN (DATE '2026-12-31' - e.fecha_ingreso) / 365 >=  5 THEN 21
        ELSE 14
    END,
    0
FROM rrhh_empleados e
WHERE e.estado = 'activo'
ON CONFLICT (empleado_id, año) DO NOTHING;

-- ───────────────────────────────────────────────────────────────────────
-- FERIADOS NACIONALES ARGENTINA 2026
-- ───────────────────────────────────────────────────────────────────────
INSERT INTO rrhh_feriados (fecha, nombre, tipo) VALUES
    ('2026-01-01', 'Año Nuevo',                                              'nacional'),
    ('2026-02-16', 'Carnaval',                                               'nacional'),
    ('2026-02-17', 'Carnaval',                                               'nacional'),
    ('2026-03-24', 'Día Nacional de la Memoria por la Verdad y la Justicia','nacional'),
    ('2026-04-02', 'Día del Veterano y de los Caídos en la Guerra de Malvinas','nacional'),
    ('2026-04-03', 'Viernes Santo',                                          'nacional'),
    ('2026-05-01', 'Día del Trabajador',                                     'nacional'),
    ('2026-05-25', 'Día de la Revolución de Mayo',                           'nacional'),
    ('2026-06-15', 'Paso a la Inmortalidad del Gral. Manuel Belgrano (trasladado)', 'nacional'),
    ('2026-07-09', 'Día de la Independencia',                                'nacional'),
    ('2026-08-17', 'Paso a la Inmortalidad del Gral. José de San Martín (trasladado)', 'nacional'),
    ('2026-10-12', 'Día del Respeto a la Diversidad Cultural',               'nacional'),
    ('2026-11-23', 'Día de la Soberanía Nacional (trasladado)',              'nacional'),
    ('2026-12-08', 'Inmaculada Concepción de María',                         'nacional'),
    ('2026-12-25', 'Navidad',                                                'nacional')
ON CONFLICT (fecha) DO NOTHING;

-- ───────────────────────────────────────────────────────────────────────
-- USUARIO ADMIN INICIAL (JP)
-- ───────────────────────────────────────────────────────────────────────
-- NOTA: Después de crear el usuario en Supabase Auth (Authentication → Users)
-- con email juanpsimonelli@gmail.com, correr manualmente:
--
--   INSERT INTO rrhh_usuarios (auth_user_id, empleado_id, email, rol, activo)
--   VALUES (
--     '<UUID del usuario en auth.users>',
--     (SELECT id FROM rrhh_empleados WHERE dni = '36754687'),
--     'juanpsimonelli@gmail.com',
--     'admin',
--     true
--   );

-- ═══════════════════════════════════════════════════════════════════════
-- FIN SEED.
--
-- Para verificar carga:
--   SELECT COUNT(*), local FROM rrhh_empleados GROUP BY local;
--     → oficina: 5, unicenter: 7, alcorta: 7  (total 19)
--   SELECT COUNT(*) FROM rrhh_categorias_cct;  → 11
--   SELECT COUNT(*) FROM rrhh_feriados;        → 15
--   SELECT COUNT(*) FROM rrhh_vacaciones;      → 19
-- ═══════════════════════════════════════════════════════════════════════
