-- ═══════════════════════════════════════════════════════════════════════
--  55_lsd_infraestructura.sql
--  Libro de Sueldos Digital (LSD) — Infraestructura base
--  Normativa: RG 5250/2022 (sustituye RG 3781) + RG Conjunta 5249/2022.
--
--  Este SQL es la BASE para reemplazar a MEMOSOFT. Crea:
--   1. Catálogo oficial de conceptos LSD (140+ códigos AFIP)
--   2. Tabla de obras sociales AFIP con códigos oficiales
--   3. Campos extra en rrhh_empleados requeridos por LSD
--   4. Mapeo de nuestros conceptos internos → códigos AFIP
--   5. Catálogo de modalidades de contrato, condiciones, situaciones revista
--
--  La generación del TXT se hace en SQL 56 (próxima sesión).
-- ═══════════════════════════════════════════════════════════════════════

-- ─── 1. Catálogo de CONCEPTOS LSD (AFIP) ────────────────────────────
CREATE TABLE IF NOT EXISTS public.rrhh_lsd_concepto_catalogo (
    codigo         text PRIMARY KEY,        -- ej '110000', '120001', '810002'
    descripcion    text NOT NULL,
    tipo           text NOT NULL CHECK (tipo IN ('remunerativo', 'no_remunerativo', 'descuento')),
    -- Base de cálculo: 30 bits binarios "1" o "0" indicando aporte/contribución a cada subsistema
    -- Posición 1-2: SIPA aporte/contribución
    -- Posición 3-4: INSSJyP aporte/contribución
    -- Posición 5-6: Obra Social aporte/contribución
    -- Posición 7-8: Fondo Solidario Redistribución (ex ANSSAL)
    -- Posición 9-10: RENATEA
    -- Posición 11-12: Asignaciones Familiares
    -- Posición 13-14: Fondo Nacional de Empleo
    -- Posición 15-16: Ley de Riesgos del Trabajo (LRT)
    -- Posición 17-18: Seguro Colectivo de Vida Obligatorio
    -- Posición 19-20: Regímenes Diferenciales
    -- Posición 21-22: Regímenes Especiales
    -- Resto: libre para uso futuro
    base_calculo   text,  -- string de 30 caracteres '0' o '1'
    base_calculo_label text,  -- 'REM 1', 'REM 2', etc. para referencia rápida
    grupo          text,  -- 'Sueldo', 'SAC', 'Horas extras', etc.
    es_uso_libre   boolean NOT NULL DEFAULT false,
    activo         boolean NOT NULL DEFAULT true
);

ALTER TABLE public.rrhh_lsd_concepto_catalogo ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS rrhh_lsd_concepto_select_auth ON public.rrhh_lsd_concepto_catalogo;
CREATE POLICY rrhh_lsd_concepto_select_auth
    ON public.rrhh_lsd_concepto_catalogo FOR SELECT
    USING (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS rrhh_lsd_concepto_admin ON public.rrhh_lsd_concepto_catalogo;
CREATE POLICY rrhh_lsd_concepto_admin
    ON public.rrhh_lsd_concepto_catalogo FOR ALL
    USING (rrhh_is_admin()) WITH CHECK (rrhh_is_admin());

-- ─── Seed: conceptos LSD oficiales (RG 5250/2022) ────────────────────
INSERT INTO public.rrhh_lsd_concepto_catalogo (codigo, descripcion, tipo, grupo) VALUES
-- ── REMUNERATIVOS ──
('110000', 'Sueldo', 'remunerativo', 'Sueldo'),
('110001', 'Preaviso', 'remunerativo', 'Sueldo'),
('110002', 'Remuneraciones en especie', 'remunerativo', 'Sueldo'),
('110003', 'Comida', 'remunerativo', 'Sueldo'),
('110004', 'Habitación', 'remunerativo', 'Sueldo'),
('110005', 'Licencias por estudio', 'remunerativo', 'Sueldo'),
('110006', 'Donación de sangre', 'remunerativo', 'Sueldo'),
('110007', 'Feriado', 'remunerativo', 'Sueldo'),
('110008', 'Prest. Dineraria Ley 24577 (primeros 10d)', 'remunerativo', 'Sueldo'),
('110009', 'Prest. Dineraria Ley 24577 (a cargo de ART)', 'remunerativo', 'Sueldo'),
('110010', 'Sueldo - RG 2252 Actividades simultáneas', 'remunerativo', 'Sueldo'),
('110011', 'Incremento solidario Dec. 14/2020', 'remunerativo', 'Sueldo'),
-- SAC
('120000', 'Sueldo anual complementario', 'remunerativo', 'SAC'),
('120001', 'SAC 1er semestre', 'remunerativo', 'SAC'),
('120002', 'SAC 2do semestre', 'remunerativo', 'SAC'),
('120003', 'SAC proporcional', 'remunerativo', 'SAC'),
('120004', 'SAC - RG 2252 Actividades simultáneas', 'remunerativo', 'SAC'),
-- Horas extras
('130000', 'Horas extras', 'remunerativo', 'Horas extras'),
('130001', 'Horas extras al 50 %', 'remunerativo', 'Horas extras'),
('130002', 'Horas extras al 100 %', 'remunerativo', 'Horas extras'),
('130003', 'Horas extras al 200 %', 'remunerativo', 'Horas extras'),
('130004', 'Horas extras - RG 2252 Actividades simultáneas', 'remunerativo', 'Horas extras'),
-- Zona desfavorable
('140000', 'Zona desfavorable', 'remunerativo', 'Zona desfavorable'),
('140001', 'Zona desfavorable - RG 2252', 'remunerativo', 'Zona desfavorable'),
-- Adelanto vacacional
('150000', 'Adelanto vacacional', 'remunerativo', 'Vacaciones'),
('150001', 'Adelanto vacacional - RG 2252', 'remunerativo', 'Vacaciones'),
-- Adicionales
('160000', 'Adicionales', 'remunerativo', 'Adicionales'),
('160001', 'Adicional por antigüedad', 'remunerativo', 'Adicionales'),
('160002', 'Adicional por título', 'remunerativo', 'Adicionales'),
('160003', 'Adicional por tarea', 'remunerativo', 'Adicionales'),
('160004', 'Adicional por desarraigo', 'remunerativo', 'Adicionales'),
('160005', 'Adicionales - RG 2252', 'remunerativo', 'Adicionales'),
-- Gratificaciones y premios
('170000', 'Gratificaciones y/o Premios', 'remunerativo', 'Gratificaciones'),
('170001', 'Premio por presentismo', 'remunerativo', 'Gratificaciones'),
('170002', 'Premio por producción', 'remunerativo', 'Gratificaciones'),
('170003', 'Comisiones', 'remunerativo', 'Gratificaciones'),
('170004', 'Accesorios', 'remunerativo', 'Gratificaciones'),
('170005', 'Viáticos sin comprobante', 'remunerativo', 'Gratificaciones'),
('170006', 'Propinas habituales no prohibidas', 'remunerativo', 'Gratificaciones'),
('170007', 'Gratificaciones - RG 2252', 'remunerativo', 'Gratificaciones'),
('180000', 'Rectificativa por remuneración Ley 27.742', 'remunerativo', 'Otros'),
('499999', 'Redondeo (Remunerativo)', 'remunerativo', 'Redondeo'),
-- ── NO REMUNERATIVOS ──
('510000', 'Asignaciones Familiares', 'no_remunerativo', 'Asignaciones'),
('510001', 'Ayuda escolar', 'no_remunerativo', 'Asignaciones'),
('510002', 'Asignación por hijo/hijo con discapacidad', 'no_remunerativo', 'Asignaciones'),
('510003', 'Asignación por maternidad', 'no_remunerativo', 'Asignaciones'),
('510004', 'Asignación por maternidad Down', 'no_remunerativo', 'Asignaciones'),
('510005', 'Asignación por matrimonio', 'no_remunerativo', 'Asignaciones'),
('510006', 'Asignación por nacimiento / adopción', 'no_remunerativo', 'Asignaciones'),
('510007', 'Asignación por prenatal', 'no_remunerativo', 'Asignaciones'),
('520000', 'Beneficios sociales', 'no_remunerativo', 'Beneficios'),
('520001', 'Servicio de comedor', 'no_remunerativo', 'Beneficios'),
('520002', 'Gastos médicos', 'no_remunerativo', 'Beneficios'),
('520003', 'Provisión de ropa de trabajo', 'no_remunerativo', 'Beneficios'),
('520004', 'Guardería', 'no_remunerativo', 'Beneficios'),
('520005', 'Provisión de útiles escolares', 'no_remunerativo', 'Beneficios'),
('520006', 'Gastos de sepelio', 'no_remunerativo', 'Beneficios'),
('520007', 'Cursos de capacitación', 'no_remunerativo', 'Beneficios'),
('520014', 'Indemnización por despido', 'no_remunerativo', 'Indemnizaciones'),
('520015', 'Indemnización sustitutiva del preaviso', 'no_remunerativo', 'Indemnizaciones'),
('520016', 'Integración mes de despido', 'no_remunerativo', 'Indemnizaciones'),
('530000', 'Incrementos no remunerativos (con aportes OS)', 'no_remunerativo', 'Incrementos NR'),
('540000', 'Incrementos no remunerativos (con aportes y contribuciones OS)', 'no_remunerativo', 'Incrementos NR'),
('550000', 'Importes no remunerativos especiales', 'no_remunerativo', 'Incrementos NR'),
('560000', 'Mensual - PPC y CCT Especiales', 'no_remunerativo', 'PPC/CCT'),
('560001', 'SAC - PPC y CCT Especiales', 'no_remunerativo', 'PPC/CCT'),
('560005', 'Asignación no Remunerativa Dcto 841/2022', 'no_remunerativo', 'PPC/CCT'),
('560006', 'Asignación no Remunerativa Dcto 438/2023', 'no_remunerativo', 'PPC/CCT'),
('799999', 'Redondeo (No Remunerativo)', 'no_remunerativo', 'Redondeo'),
-- ── DESCUENTOS ──
('810000', 'Sistema previsional', 'descuento', 'Aportes'),
('810001', 'INSSJyP', 'descuento', 'Aportes'),
('810002', 'Obra Social', 'descuento', 'Aportes'),
('810003', 'Fondo Solidario de Redistribución (ex ANSSAL)', 'descuento', 'Aportes'),
('810004', 'Cuota Sindical', 'descuento', 'Aportes'),
('810005', 'Seguro de Vida', 'descuento', 'Aportes'),
('810006', 'RENATEA (ex RENATRE)', 'descuento', 'Aportes'),
('810007', 'Préstamos', 'descuento', 'Otros'),
('810008', 'Impuesto a las Ganancias', 'descuento', 'Otros'),
('810009', 'Obra Social - Adherentes', 'descuento', 'Aportes'),
('810015', 'Sistema previsional no nacional', 'descuento', 'Aportes'),
('810016', 'Obra Social provincial', 'descuento', 'Aportes'),
('820000', 'Otros descuentos', 'descuento', 'Otros')
ON CONFLICT (codigo) DO NOTHING;

-- ─── 2. Catálogo de Obras Sociales AFIP ─────────────────────────────
-- Códigos oficiales AFIP de OS (6 dígitos). Cada OS tiene un código único.
CREATE TABLE IF NOT EXISTS public.rrhh_lsd_obra_social_catalogo (
    codigo         text PRIMARY KEY,        -- 6 dígitos, ej '126203' OSECAC
    nombre         text NOT NULL,
    sigla          text,                    -- ej 'OSECAC', 'OSDE'
    activo         boolean NOT NULL DEFAULT true
);

ALTER TABLE public.rrhh_lsd_obra_social_catalogo ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS rrhh_lsd_os_select_auth ON public.rrhh_lsd_obra_social_catalogo;
CREATE POLICY rrhh_lsd_os_select_auth
    ON public.rrhh_lsd_obra_social_catalogo FOR SELECT USING (auth.uid() IS NOT NULL);
DROP POLICY IF EXISTS rrhh_lsd_os_admin ON public.rrhh_lsd_obra_social_catalogo;
CREATE POLICY rrhh_lsd_os_admin
    ON public.rrhh_lsd_obra_social_catalogo FOR ALL
    USING (rrhh_is_admin()) WITH CHECK (rrhh_is_admin());

-- Seed: OS de las empleadas conocidas (códigos AFIP oficiales)
INSERT INTO public.rrhh_lsd_obra_social_catalogo (codigo, nombre, sigla) VALUES
    ('126203', 'OSECAC - Obra Social Empleados de Comercio y Actividades Civiles', 'OSECAC'),
    ('108807', 'OSDE - Organización de Servicios Directos Empresarios', 'OSDE'),
    ('109111', 'OS Pers. Automóvil Club Argentino', 'OSPACA'),
    ('118901', 'OS Industria Molinera', 'OSPIM'),
    ('108808', 'OS de Pasteleros Confiteros y Pizzeros', 'OSPCP'),
    ('108705', 'OS Personal Control Externo', 'OSPSCE'),
    ('116901', 'OS Unión Personal Civil de la Nación', 'UPCN'),
    ('108501', 'Asoc. Mutual Control Integral', 'AMCI'),
    ('108502', 'OS Ministros, Secretarios y Subsec. Poder Ejecutivo Nacional', 'OSPLN'),
    ('116905', 'OS Entidades Deportivas y Civiles', 'OSEDYC')
ON CONFLICT (codigo) DO NOTHING;

-- ─── 3. Campos extra en rrhh_empleados para LSD ──────────────────────
ALTER TABLE public.rrhh_empleados
    -- Convenio Colectivo de Trabajo (AFIP usa 130 para Empleados Comercio CCT 130/75)
    ADD COLUMN IF NOT EXISTS cct_codigo                  text DEFAULT '130',
    -- Modalidad de contrato: típicos = 008 (Tiempo completo indeterminado), 999 (Director SA bajo LRT)
    ADD COLUMN IF NOT EXISTS modalidad_contrato_codigo   text DEFAULT '008',
    -- Condición: 1 = activo, 11 = jubilado activo
    ADD COLUMN IF NOT EXISTS condicion_codigo            text DEFAULT '1',
    -- Situación de revista del mes (1 = activo, 5 = licencia maternidad, etc.)
    -- Esto es POR LIQUIDACIÓN. Acá guardamos el default, pero puede override por mes.
    ADD COLUMN IF NOT EXISTS situacion_revista_default   text DEFAULT '1',
    -- Siniestrado: 0 = no, 1-4 = sí con diferentes códigos
    ADD COLUMN IF NOT EXISTS siniestrado_codigo          text DEFAULT '0',
    -- Código actividad CIIU (común para todos los empleados de la SRL — comercio)
    -- 478996 = comercio al por menor de bazar, artículos para el hogar
    ADD COLUMN IF NOT EXISTS actividad_codigo            text DEFAULT '478996',
    -- Código OS AFIP (mapeo a rrhh_lsd_obra_social_catalogo.codigo)
    ADD COLUMN IF NOT EXISTS os_codigo_afip              text,
    -- Localidad / provincia para diferenciar AFIP / AGIP / ARBA
    ADD COLUMN IF NOT EXISTS jurisdiccion                text DEFAULT 'NACION';   -- 'NACION' | 'CABA' | 'BSAS'

COMMENT ON COLUMN public.rrhh_empleados.cct_codigo IS
    'CCT AFIP, ej 130 = Empleados Comercio. Lista en https://www.argentina.gob.ar/trabajo/conveniosdetrabajo';
COMMENT ON COLUMN public.rrhh_empleados.os_codigo_afip IS
    'Código OS AFIP (6 dígitos) — debe matchear con rrhh_lsd_obra_social_catalogo.codigo';
COMMENT ON COLUMN public.rrhh_empleados.jurisdiccion IS
    'Para LSD: NACION=AFIP, CABA=AGIP (Alcorta), BSAS=ARBA (Unicenter/Oficina)';

-- ─── 4. Setear códigos OS AFIP para empleadas según su obra_social_codigo ─
UPDATE public.rrhh_empleados SET os_codigo_afip = '126203' WHERE obra_social_codigo = 'osecac';
UPDATE public.rrhh_empleados SET os_codigo_afip = '108807' WHERE obra_social_codigo = 'osde';
UPDATE public.rrhh_empleados SET os_codigo_afip = '109111' WHERE obra_social_codigo = 'aca';
UPDATE public.rrhh_empleados SET os_codigo_afip = '118901' WHERE obra_social_codigo = 'molinera';
UPDATE public.rrhh_empleados SET os_codigo_afip = '108808' WHERE obra_social_codigo = 'pasteleros';
UPDATE public.rrhh_empleados SET os_codigo_afip = '108705' WHERE obra_social_codigo = 'pers_control_externo';
UPDATE public.rrhh_empleados SET os_codigo_afip = '116901' WHERE obra_social_codigo = 'civiles_nacion';
UPDATE public.rrhh_empleados SET os_codigo_afip = '108501' WHERE obra_social_codigo = 'mutual_control_integral';
UPDATE public.rrhh_empleados SET os_codigo_afip = '108502' WHERE obra_social_codigo = 'ministros';
UPDATE public.rrhh_empleados SET os_codigo_afip = '116905' WHERE obra_social_codigo = 'deportivas_civiles';

-- Setear jurisdicción según local
UPDATE public.rrhh_empleados SET jurisdiccion = 'CABA' WHERE local = 'alcorta';
UPDATE public.rrhh_empleados SET jurisdiccion = 'BSAS' WHERE local IN ('unicenter','oficina');

-- Setear modalidad LRT para Director SA (Claudia)
UPDATE public.rrhh_empleados
   SET modalidad_contrato_codigo = '999'  -- LRT Directores SA / municipales
 WHERE apellido ILIKE '%ADORNO%' AND nombre ILIKE '%CLAUDIA%';

-- ─── 5. Mapeo de NUESTROS códigos internos → códigos AFIP ────────────
CREATE TABLE IF NOT EXISTS public.rrhh_lsd_concepto_mapeo (
    codigo_interno   text PRIMARY KEY,    -- Nuestro: '0001', '0022', '0025', etc.
    codigo_afip      text NOT NULL REFERENCES public.rrhh_lsd_concepto_catalogo(codigo),
    notas            text
);

ALTER TABLE public.rrhh_lsd_concepto_mapeo ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS rrhh_lsd_mapeo_select_auth ON public.rrhh_lsd_concepto_mapeo;
CREATE POLICY rrhh_lsd_mapeo_select_auth
    ON public.rrhh_lsd_concepto_mapeo FOR SELECT USING (auth.uid() IS NOT NULL);
DROP POLICY IF EXISTS rrhh_lsd_mapeo_admin ON public.rrhh_lsd_concepto_mapeo;
CREATE POLICY rrhh_lsd_mapeo_admin
    ON public.rrhh_lsd_concepto_mapeo FOR ALL
    USING (rrhh_is_admin()) WITH CHECK (rrhh_is_admin());

INSERT INTO public.rrhh_lsd_concepto_mapeo (codigo_interno, codigo_afip, notas) VALUES
    ('0001', '110000', 'Sueldo Básico'),
    ('0022', '160001', 'Adicional por antigüedad'),
    ('0025', '170001', 'Presentismo (Premio por presentismo)'),
    ('0073', '110011', 'A cuenta futuros aumentos (Incremento solidario)'),
    ('0490', '530000', 'Suma fija no rem 2025 (Incremento no rem con aportes OS)'),
    ('0491', '530000', 'Suma fija no rem 2026'),
    ('0492', '530000', 'Antigüedad no remunerativa'),
    ('0493', '530000', 'Presentismo no remunerativa'),
    ('0494', '530000', 'Ant no rem'),
    ('0495', '530000', 'Pres no rem'),
    ('0496', '530000', 'Recompos no rem Ac 2026'),
    ('0497', '530000', 'REcomp no rem Ac2026'),
    ('1001', '810000', 'Jubilación (Sistema previsional)'),
    ('1002', '810001', 'Ley 19.032 (INSSJyP)'),
    ('1011', '810004', 'SEC (Cuota Sindical)'),
    ('1012', '810004', 'FAECYS (Cuota Sindical complementaria)'),
    ('1031', '810002', 'Obra Social')
ON CONFLICT (codigo_interno) DO UPDATE SET
    codigo_afip = EXCLUDED.codigo_afip,
    notas = EXCLUDED.notas;

NOTIFY pgrst, 'reload schema';

-- ═══════════════════════════════════════════════════════════════════════
--  Verificación
-- ═══════════════════════════════════════════════════════════════════════
SELECT
  (SELECT count(*) FROM rrhh_lsd_concepto_catalogo) AS conceptos_afip,
  (SELECT count(*) FROM rrhh_lsd_obra_social_catalogo) AS os_catalogo,
  (SELECT count(*) FROM rrhh_lsd_concepto_mapeo) AS mapeos,
  (SELECT count(*) FROM rrhh_empleados WHERE os_codigo_afip IS NOT NULL) AS empleados_con_os_afip,
  (SELECT count(*) FROM rrhh_empleados WHERE jurisdiccion = 'CABA') AS empleados_caba,
  (SELECT count(*) FROM rrhh_empleados WHERE jurisdiccion = 'BSAS') AS empleados_bsas;
