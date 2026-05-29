-- ═══════════════════════════════════════════════════════════════════════
--  40_pagos_blanco.sql
--  Tabla para persistir los netos de "recibo blanco" cargados manualmente
--  por JP en el panel "Pagos del mes". No reemplaza a rrhh_liquidacion,
--  que sigue siendo la fuente de verdad del cálculo completo. Esto es una
--  ayuda pragmática: JP carga el neto que sale del PDF de MEMOSOFT, el
--  sistema calcula automáticamente adelantos y préstamos del mes, y le
--  devuelve cuánto transferir a cada empleada.
--
--  Después de correr: NOTIFY pgrst, 'reload schema';
-- ═══════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.rrhh_pagos_blanco (
    id              bigserial PRIMARY KEY,
    empleado_id     bigint NOT NULL REFERENCES public.rrhh_empleados(id) ON DELETE CASCADE,
    periodo         date   NOT NULL,           -- YYYY-MM-01
    neto_cct        numeric(14,2) NOT NULL,    -- lo que sale del PDF
    notas           text,
    cargado_at      timestamptz NOT NULL DEFAULT now(),
    cargado_por     text,
    transferido_at  timestamptz,                -- cuando JP marca "ya transferí"
    UNIQUE (empleado_id, periodo)
);

CREATE INDEX IF NOT EXISTS idx_pagos_blanco_periodo
    ON public.rrhh_pagos_blanco(periodo);

ALTER TABLE public.rrhh_pagos_blanco ENABLE ROW LEVEL SECURITY;

CREATE POLICY rrhh_pagos_blanco_admin_all
    ON public.rrhh_pagos_blanco FOR ALL
    USING (rrhh_is_admin());

COMMENT ON TABLE public.rrhh_pagos_blanco IS
    'Cache del neto blanco cargado manualmente por admin desde el PDF de MEMOSOFT, para calcular cuánto transferir descontando adelantos + préstamos.';

NOTIFY pgrst, 'reload schema';
