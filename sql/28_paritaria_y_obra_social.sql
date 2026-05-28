-- ═══════════════════════════════════════════════════════════════════════
--  RRHH ADORNO — Paritaria (sumas no rem por período) + Obra Social
--
--  Prerrequisitos para el cálculo del recibo blanco CCT 130/75 (#106):
--    (a) Saber qué sumas no remunerativas aplican a cada mes (cambian con
--        cada paritaria — abr-jun 2026: $100.000 + $20.000).
--    (b) Saber la OS de cada empleada para aplicar la regla del 3% sobre
--        bruto (OSECAC) vs sobre remunerativo (cualquier otra).
-- ═══════════════════════════════════════════════════════════════════════

-- ─── 1. Obra Social en rrhh_empleados ───
ALTER TABLE rrhh_empleados ADD COLUMN IF NOT EXISTS obra_social        text;
ALTER TABLE rrhh_empleados ADD COLUMN IF NOT EXISTS obra_social_codigo text;
-- obra_social_codigo: clave normalizada para reglas. 'osecac' aplica regla
-- A (3% sobre bruto). Cualquier otro = regla B (3% sobre remunerativo).

COMMENT ON COLUMN rrhh_empleados.obra_social        IS 'Nombre legible de la OS, ej "OSECAC", "OSDE"';
COMMENT ON COLUMN rrhh_empleados.obra_social_codigo IS 'Clave normalizada: ''osecac'' o el slug de la otra OS';

-- Seed con los OS del padrón abril 2026 (de la skill control-sueldos-adorno)
WITH datos(apellido, nombre, os_nombre, os_codigo) AS (VALUES
    ('CONTRERAS',       'MARISA ISABEL',         'OSECAC',                                  'osecac'),
    ('BENITEZ',         'ROMINA SOLANGE',        'OS Personal Control Externo',             'pers_control_externo'),
    ('DONZELLI',        'SORAYA BEATRIZ',        'Asoc. Mutual de Control Integral',        'mutual_control_integral'),
    ('QUIROGA',         'ELISABETH LAURA',       'OSECAC',                                  'osecac'),
    ('DAMELA',          'SILVINA ALICIA',        'OS Pers. Automóvil Club Argentino',       'aca'),
    ('COPA',            'LILIANA TERESA',        'OSECAC',                                  'osecac'),
    ('GODOY',           'CINTIA PAMELA',         'OS Industria Molinera',                   'molinera'),
    ('BIANCHI',         'MARIA SOLEDAD',         'OSECAC',                                  'osecac'),
    ('SANCHEZ',         'SONIA LUZ',             'OSDE',                                    'osde'),
    ('MONZON',          'CARLOS IVAN',           'OSECAC',                                  'osecac'),
    ('NICOLA',          'VALERIA ALCIRA',        'OSECAC',                                  'osecac'),
    ('ESCASANY',        'ANGELES',               'OS Personal Control Externo',             'pers_control_externo'),
    ('RIVERA',          'ANALIA BEATRIZ',        'OS Ministros, Secretarios y Subsec.',     'ministros'),
    ('FRECCERO MEZA',   'ESTEFANIA NOEMI',       'OSECAC',                                  'osecac'),
    ('NOGUERA PARRA',   'ADRIAN',                'OS Pasteleros Confiteros',                'pasteleros'),
    ('MOREIRA',         'GABRIELA LILIANA',      'OS Unión Per. In. Trab. Civil Nac.',      'civiles_nacion'),
    ('VERON',           'GEORGINA ELIZABETH',    'OS Entidades Deportivas y Civiles',       'deportivas_civiles')
)
UPDATE rrhh_empleados e
   SET obra_social        = d.os_nombre,
       obra_social_codigo = d.os_codigo
  FROM datos d
 WHERE upper(e.apellido) = d.apellido AND upper(e.nombre) = d.nombre;

-- ─── 2. Sumas no remunerativas vigentes por período (paritaria) ───
CREATE TABLE IF NOT EXISTS rrhh_paritaria_sumas_nr (
    id              bigserial PRIMARY KEY,
    vigente_desde   date NOT NULL UNIQUE,            -- inclusivo
    vigente_hasta   date,                            -- NULL = vigente
    suma_fija_nr    numeric(12,2) NOT NULL,          -- código 0490/0491
    recompos_nr     numeric(12,2) NOT NULL DEFAULT 0,-- código 0496/0497
    notas           text
);

-- Seed: acuerdo paritario abril-junio 2026 (del escalas-vigentes.md de la skill)
--   $100.000 (prórroga $40k+$60k) + $20.000 (Recompos Ac. 2026 nuevo).
--   En julio 2026 se incorporan $100.000 al básico; queda solo $20.000 (si continúa).
INSERT INTO rrhh_paritaria_sumas_nr (vigente_desde, vigente_hasta, suma_fija_nr, recompos_nr, notas) VALUES
    ('2026-04-01', '2026-06-30', 100000.00, 20000.00,
     'Paritaria 26/03/2026 — Suma fija no rem $100.000 (prórroga 40k+60k) + Recompos Ac. 2026 $20.000.')
ON CONFLICT (vigente_desde) DO NOTHING;

-- Función helper para resolver el período aplicable
CREATE OR REPLACE FUNCTION rrhh_paritaria_vigente(p_periodo date)
RETURNS rrhh_paritaria_sumas_nr
LANGUAGE sql STABLE AS $func$
    SELECT * FROM rrhh_paritaria_sumas_nr
     WHERE vigente_desde <= p_periodo
       AND (vigente_hasta IS NULL OR vigente_hasta >= p_periodo)
     ORDER BY vigente_desde DESC LIMIT 1;
$func$;
