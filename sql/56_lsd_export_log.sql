-- ═══════════════════════════════════════════════════════════════════════
--  56_lsd_export_log.sql
--  Log de generaciones del Libro de Sueldos Digital (AFIP, AGIP, ARBA).
-- ═══════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.rrhh_lsd_export_log (
    id              bigserial PRIMARY KEY,
    fecha_export    timestamptz NOT NULL DEFAULT now(),
    periodo         date NOT NULL,
    tipo            text NOT NULL CHECK (tipo IN ('AFIP_LSD','AGIP_LSD','ARBA_LSD','F931_SICOSS')),
    empleados_count int,
    lineas_count    int,
    errores         text,
    exportado_por   text
);

CREATE INDEX IF NOT EXISTS rrhh_lsd_export_log_periodo
    ON public.rrhh_lsd_export_log(periodo DESC, fecha_export DESC);

ALTER TABLE public.rrhh_lsd_export_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS rrhh_lsd_export_log_admin ON public.rrhh_lsd_export_log;
CREATE POLICY rrhh_lsd_export_log_admin
    ON public.rrhh_lsd_export_log FOR ALL
    USING (rrhh_is_admin()) WITH CHECK (rrhh_is_admin());

COMMENT ON TABLE public.rrhh_lsd_export_log IS
    'Auditoría de generaciones del TXT del Libro de Sueldos Digital (cada vez que JP descarga uno).';

NOTIFY pgrst, 'reload schema';

SELECT count(*) AS logs FROM rrhh_lsd_export_log;
