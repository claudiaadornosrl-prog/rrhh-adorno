-- ═══════════════════════════════════════════════════════════════════════
--  60_lsd_fix_os_codigos_reales_estudio.sql
--
--  Códigos AFIP de obra social REALES extraídos del TXT LSD del estudio
--  (abril 2026, archivo Liquidacion_1_30709673110_20260530161745.txt).
--
--  Mis códigos previos (SQL 55) estaban CASI TODOS MAL — solo OSECAC
--  coincidía. Este SQL los corrige a los oficiales AFIP.
-- ═══════════════════════════════════════════════════════════════════════

BEGIN;

-- ─── Actualizar códigos AFIP de OS per empleada (CUIL ↔ código) ──────
UPDATE rrhh_empleados SET os_codigo_afip = '126205' WHERE cuil = '23-21939672-4'; -- CONTRERAS OSECAC
UPDATE rrhh_empleados SET os_codigo_afip = '000406' WHERE cuil = '27-29695460-3'; -- BENITEZ
UPDATE rrhh_empleados SET os_codigo_afip = '000000' WHERE cuil = '27-13531903-7'; -- CLAUDIA ADORNO (sin OS / no informa)
UPDATE rrhh_empleados SET os_codigo_afip = '904708' WHERE cuil = '27-31741055-2'; -- DONZELLI
UPDATE rrhh_empleados SET os_codigo_afip = '126205' WHERE cuil = '23-22041488-4'; -- QUIROGA OSECAC
UPDATE rrhh_empleados SET os_codigo_afip = '101604' WHERE cuil = '23-18717942-4'; -- DAMELA (ACA)
UPDATE rrhh_empleados SET os_codigo_afip = '126205' WHERE cuil = '27-26933834-8'; -- COPA OSECAC
UPDATE rrhh_empleados SET os_codigo_afip = '112608' WHERE cuil = '23-36248849-4'; -- GODOY (Molinera)
UPDATE rrhh_empleados SET os_codigo_afip = '126205' WHERE cuil = '27-26186117-3'; -- BIANCHI OSECAC
UPDATE rrhh_empleados SET os_codigo_afip = '400800' WHERE cuil = '20-36754687-6'; -- JP SIMONELLI
UPDATE rrhh_empleados SET os_codigo_afip = '400800' WHERE cuil = '27-22275528-5'; -- SANCHEZ (estudio carga 400800)
UPDATE rrhh_empleados SET os_codigo_afip = '126205' WHERE cuil = '20-37356286-7'; -- MONZON OSECAC
UPDATE rrhh_empleados SET os_codigo_afip = '126205' WHERE cuil = '27-28188721-7'; -- NICOLA OSECAC
UPDATE rrhh_empleados SET os_codigo_afip = '000406' WHERE cuil = '27-33980834-7'; -- ESCASANY
UPDATE rrhh_empleados SET os_codigo_afip = '002501' WHERE cuil = '27-34736736-8'; -- RIVERA (Ministros)
UPDATE rrhh_empleados SET os_codigo_afip = '126205' WHERE cuil = '27-29951723-9'; -- FRECCERO OSECAC
UPDATE rrhh_empleados SET os_codigo_afip = '114307' WHERE cuil = '20-95925193-3'; -- NOGUERA (Pasteleros)
UPDATE rrhh_empleados SET os_codigo_afip = '125707' WHERE cuil = '20-29168551-0'; -- MOREIRA
UPDATE rrhh_empleados SET os_codigo_afip = '106005' WHERE cuil = '27-34798072-8'; -- VERON

-- ─── Limpiar catálogo viejo (códigos inventados) y re-poblar ─────────
DELETE FROM rrhh_lsd_obra_social_catalogo;

INSERT INTO rrhh_lsd_obra_social_catalogo (codigo, nombre, sigla) VALUES
    ('126205', 'OSECAC - Empleados de Comercio', 'OSECAC'),
    ('000406', 'OS Personal Sup. Control Externo', 'OSPSCE'),
    ('000000', 'No informa / Sin OS', 'NULL'),
    ('904708', 'Asoc. Mutual Control Integral', 'AMCI'),
    ('101604', 'OS Personal Automóvil Club Argentino', 'OSPACA'),
    ('112608', 'OS Industria Molinera', 'OSPIM'),
    ('400800', 'Cobertura especial / Autónomos / OSDE adherente', 'AUT'),
    ('002501', 'OS Ministros Secretarios Subsec. Poder Ejecutivo', 'OSPLN'),
    ('114307', 'OS Pasteleros Confiteros y Pizzeros', 'OSPCP'),
    ('125707', 'OS Unión Personal Civil de la Nación', 'UPCN'),
    ('106005', 'OS Entidades Deportivas y Civiles', 'OSEDYC')
ON CONFLICT (codigo) DO UPDATE
   SET nombre = EXCLUDED.nombre, sigla = EXCLUDED.sigla;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── Verificación ────────────────────────────────────────────────────
SELECT
  e.apellido,
  e.cuil,
  e.obra_social_codigo AS os_slug_interno,
  e.os_codigo_afip     AS os_codigo_afip,
  cat.nombre           AS os_nombre,
  cat.sigla            AS os_sigla
FROM rrhh_empleados e
LEFT JOIN rrhh_lsd_obra_social_catalogo cat
       ON cat.codigo = e.os_codigo_afip
WHERE e.estado = 'activo'
ORDER BY e.apellido;
