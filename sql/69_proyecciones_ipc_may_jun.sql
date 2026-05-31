-- ═══════════════════════════════════════════════════════════════════════
--  69_proyecciones_ipc_may_jun.sql
--
--  Fix: el seed del SQL 68 usaba ON CONFLICT DO NOTHING, entonces si la
--  fila de mayo ya existía con 0% no se actualizó, y junio nunca se
--  insertó porque no estaba en la versión inicial del seed.
--
--  Este script FUERZA el upsert de las proyecciones de consultoras
--  (REM-BCRA + Eco Go / LCG / Equilibra promedio).
-- ═══════════════════════════════════════════════════════════════════════

INSERT INTO public.rrhh_ipc_argentina (mes, variacion_pct, fuente, notas, cargado_at)
VALUES
    ('2026-05-01', 2.5, 'Proyección consultoras',
     'REM-BCRA / Eco Go / LCG promedio. Reemplazar cuando INDEC publique ~12/jun.', now()),
    ('2026-06-01', 2.2, 'Proyección consultoras',
     'Estimado consenso privado. Reemplazar cuando INDEC publique ~14/jul.', now())
ON CONFLICT (mes) DO UPDATE SET
    variacion_pct = EXCLUDED.variacion_pct,
    fuente        = EXCLUDED.fuente,
    notas         = EXCLUDED.notas,
    cargado_at    = EXCLUDED.cargado_at;

NOTIFY pgrst, 'reload schema';

-- Verificación
SELECT mes, variacion_pct, fuente, notas
FROM public.rrhh_ipc_argentina
WHERE mes >= '2026-03-01'
ORDER BY mes;
