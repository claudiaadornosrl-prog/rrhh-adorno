-- ═══════════════════════════════════════════════════════════════════════
--  65_paritaria_mayo_junio_2026.sql
--
--  CCT 130/75 Empleados de Comercio · Acuerdo paritario 26/03/2026
--  homologado 27/04/2026.
--
--  Aumento ESCALONADO sobre básicos de marzo 2026:
--    Abril 2026: +2%   (ya cargado)
--    Mayo 2026:  +1.5% adicional
--    Junio 2026: +1.5% adicional
--
--  Este script:
--   1) Relaja el constraint UNIQUE(codigo) a UNIQUE(codigo, fecha_vigencia)
--      para permitir versionado de escalas mes a mes.
--   2) Inserta escalas vigentes mayo 2026 y junio 2026.
--   3) salaryWorkflow.cargarEmpleadoCompleto ya hace SELECT por código +
--      fecha_vigencia <= periodo, así que las liquidaciones futuras
--      tomarán automáticamente la escala correcta según el mes.
-- ═══════════════════════════════════════════════════════════════════════

BEGIN;

-- ─── 1. Permitir múltiples versiones por categoría ─────────────────
ALTER TABLE public.rrhh_categorias_cct
    DROP CONSTRAINT IF EXISTS rrhh_categorias_cct_codigo_key;

ALTER TABLE public.rrhh_categorias_cct
    ADD CONSTRAINT rrhh_categorias_cct_codigo_vigencia_key
    UNIQUE (codigo, fecha_vigencia);

-- ─── 2. Escalas MAYO 2026 (+1.5% sobre abril) ─────────────────────
INSERT INTO public.rrhh_categorias_cct (codigo, nombre, sueldo_basico, fecha_vigencia, activa) VALUES
    ('vendedor_b',          'Vendedor B',                1134694.00, '2026-05-01', true),
    ('vendedor_a',          'Vendedor A',                1134694.00, '2026-05-01', true),
    ('administrativo_b',    'Administrativo B',          1111726.00, '2026-05-01', true),
    ('administrativo_a',    'Administrativo A',          1111726.00, '2026-05-01', true),
    ('maestranza_b',        'Maestranza B',              1098260.00, '2026-05-01', true),
    ('aux_especializado_b', 'Auxiliar Especializado B',  1134691.00, '2026-05-01', true),
    ('encargada',           'Encargada (no estándar)',   1134694.00, '2026-05-01', true),
    ('franquera',           'Franquera (no estándar)',   1134694.00, '2026-05-01', true)
ON CONFLICT (codigo, fecha_vigencia) DO UPDATE
   SET sueldo_basico = EXCLUDED.sueldo_basico,
       nombre        = EXCLUDED.nombre,
       activa        = EXCLUDED.activa;

-- ─── 3. Escalas JUNIO 2026 (+1.5% sobre mayo) ─────────────────────
INSERT INTO public.rrhh_categorias_cct (codigo, nombre, sueldo_basico, fecha_vigencia, activa) VALUES
    ('vendedor_b',          'Vendedor B',                1151714.00, '2026-06-01', true),
    ('vendedor_a',          'Vendedor A',                1151714.00, '2026-06-01', true),
    ('administrativo_b',    'Administrativo B',          1128402.00, '2026-06-01', true),
    ('administrativo_a',    'Administrativo A',          1128402.00, '2026-06-01', true),
    ('maestranza_b',        'Maestranza B',              1114734.00, '2026-06-01', true),
    ('aux_especializado_b', 'Auxiliar Especializado B',  1151711.00, '2026-06-01', true),
    ('encargada',           'Encargada (no estándar)',   1151714.00, '2026-06-01', true),
    ('franquera',           'Franquera (no estándar)',   1151714.00, '2026-06-01', true)
ON CONFLICT (codigo, fecha_vigencia) DO UPDATE
   SET sueldo_basico = EXCLUDED.sueldo_basico,
       nombre        = EXCLUDED.nombre,
       activa        = EXCLUDED.activa;

-- ─── 4. Notas para paritaria_sumas_nr ─────────────────────────────
-- La paritaria de NRs ($100k + $20k) ya está cargada con vigente_desde=2026-04-01
-- y vigente_hasta=2026-06-30 en SQL 28. NO se modifica.

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── Verificación ─────────────────────────────────────────────────
SELECT
  codigo,
  nombre,
  fecha_vigencia,
  TO_CHAR(sueldo_basico, 'FM$999,999,999') AS basico,
  activa
FROM public.rrhh_categorias_cct
WHERE codigo IN ('vendedor_b', 'administrativo_b', 'maestranza_b', 'aux_especializado_b', 'encargada')
ORDER BY codigo, fecha_vigencia;
