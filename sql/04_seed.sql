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
