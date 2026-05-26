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
