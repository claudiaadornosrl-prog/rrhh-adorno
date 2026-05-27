-- ═══════════════════════════════════════════════════════════════════════
--  RRHH ADORNO — Buzón anónimo (vendedora → admin)
--
--  Canal directo y anónimo: las vendedoras envían quejas / recomendaciones
--  / consultas al dueño (admin), sin "dar la cara".
--
--  Anonimato por diseño:
--    - La tabla NO guarda empleado_id, auth_user_id ni local.
--    - Solo categoría + mensaje + fecha.
--    - INSERT permitido a cualquier autenticado, pero SIN registrar quién.
--    - SELECT solo para admin → ni la propia vendedora puede releer lo que
--      envió (garantiza que nadie más que el admin lo ve).
-- ═══════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS rrhh_inbox_anonimo (
    id         bigserial PRIMARY KEY,
    categoria  text NOT NULL CHECK (categoria IN ('queja','recomendacion','consulta')),
    mensaje    text NOT NULL,
    creado_at  timestamptz DEFAULT now(),
    leido      boolean DEFAULT false
);

CREATE INDEX IF NOT EXISTS idx_inbox_no_leido
    ON rrhh_inbox_anonimo(creado_at DESC)
    WHERE leido = false;

ALTER TABLE rrhh_inbox_anonimo ENABLE ROW LEVEL SECURITY;

-- Cualquier usuario autenticado puede ENVIAR (sin que se registre quién)
DROP POLICY IF EXISTS inbox_insert ON rrhh_inbox_anonimo;
CREATE POLICY inbox_insert ON rrhh_inbox_anonimo FOR INSERT TO authenticated
    WITH CHECK (true);

-- Solo admin puede LEER los mensajes
DROP POLICY IF EXISTS inbox_admin_select ON rrhh_inbox_anonimo;
CREATE POLICY inbox_admin_select ON rrhh_inbox_anonimo FOR SELECT TO authenticated
    USING (rrhh_is_admin());

-- Solo admin puede marcar como leído / borrar
DROP POLICY IF EXISTS inbox_admin_update ON rrhh_inbox_anonimo;
CREATE POLICY inbox_admin_update ON rrhh_inbox_anonimo FOR UPDATE TO authenticated
    USING (rrhh_is_admin()) WITH CHECK (rrhh_is_admin());

DROP POLICY IF EXISTS inbox_admin_delete ON rrhh_inbox_anonimo;
CREATE POLICY inbox_admin_delete ON rrhh_inbox_anonimo FOR DELETE TO authenticated
    USING (rrhh_is_admin());
