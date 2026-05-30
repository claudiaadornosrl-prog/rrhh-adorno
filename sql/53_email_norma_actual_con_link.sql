-- ═══════════════════════════════════════════════════════════════════════
--  53_email_norma_actual_con_link.sql
--
--  1) Agrega columna `link_norma` a rrhh_ganancias_mni para guardar la URL
--     del PDF oficial de ARCA con la resolución de cada período.
--  2) Carga el link AFIP para H1 2026 (período vigente actual).
--  3) Actualiza el trigger para incluir el link en emails de notificación.
--  4) Función rrhh_encolar_resumen_norma_actual() para encolar un email
--     con el estado actual cuando JP quiera mandárselo a Alegre.
--  5) Ejecución one-shot: encola UN email con los valores actuales + link.
-- ═══════════════════════════════════════════════════════════════════════

-- ─── 1. Agregar columna link_norma ────────────────────────────────────
ALTER TABLE public.rrhh_ganancias_mni
    ADD COLUMN IF NOT EXISTS link_norma text;

-- ─── 2. Cargar link oficial AFIP para H1 2026 ─────────────────────────
UPDATE public.rrhh_ganancias_mni
   SET link_norma = 'https://www.afip.gob.ar/gananciasYBienes/ganancias/personas-humanas-sucesiones-indivisas/deducciones/documentos/Deducciones-personales-art-30-ene-a-jun-2026.pdf'
 WHERE vigente_desde = '2026-01-01';

-- ─── 3. Actualizar trigger para incluir el link ───────────────────────
CREATE OR REPLACE FUNCTION public.rrhh_notificar_norma_ganancias_nueva()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_anterior rrhh_ganancias_mni%ROWTYPE;
    v_diff_mni numeric := 0;
    v_diff_esp numeric := 0;
    v_pct_mni numeric := 0;
    v_pct_esp numeric := 0;
    v_body text;
    v_link_extra text;
BEGIN
    SELECT * INTO v_anterior
      FROM rrhh_ganancias_mni
     WHERE vigente_desde < NEW.vigente_desde
     ORDER BY vigente_desde DESC LIMIT 1;

    IF FOUND THEN
        v_diff_mni := NEW.mni_mensual - v_anterior.mni_mensual;
        v_diff_esp := NEW.especial_mensual - v_anterior.especial_mensual;
        v_pct_mni := CASE WHEN v_anterior.mni_mensual > 0
                          THEN round((v_diff_mni / v_anterior.mni_mensual) * 100, 2)
                          ELSE 0 END;
        v_pct_esp := CASE WHEN v_anterior.especial_mensual > 0
                          THEN round((v_diff_esp / v_anterior.especial_mensual) * 100, 2)
                          ELSE 0 END;
    END IF;

    v_link_extra := CASE
        WHEN NEW.link_norma IS NOT NULL AND NEW.link_norma <> ''
        THEN format(E'\n📄 Texto oficial de la norma:\n   %s\n', NEW.link_norma)
        ELSE E'\n(Link a la norma oficial pendiente — cargar en rrhh_ganancias_mni.link_norma cuando esté disponible)\n'
    END;

    v_body := format(
        E'Se cargaron nuevos valores ARCA Ganancias 4ta categoría en el sistema RRHH:\n\n'
     || E'Período vigente desde: %s\n\n'
     || E'Valores mensuales:\n'
     || E'  • Mínimo No Imponible: $%s%s\n'
     || E'  • Deducción especial:  $%s%s\n'
     || E'  • Cónyuge a cargo:     $%s\n'
     || E'  • Hijo a cargo:        $%s\n\n'
     || E'Notas: %s\n%s\n'
     || E'El sistema usará automáticamente estos valores para los cálculos del próximo mes y siguientes.\n'
     || E'Si hay que ajustar el bruto de Claudia / JP por este cambio, ver el banner Ganancias en el panel Liquidación.\n\n'
     || E'— Sistema RRHH Claudia Adorno',
        NEW.vigente_desde::text,
        trim(to_char(NEW.mni_mensual, 'FM999G999G999D00')),
        CASE WHEN v_anterior.id IS NOT NULL THEN format(' (antes $%s, %s%s%%)',
            trim(to_char(v_anterior.mni_mensual, 'FM999G999G999D00')),
            CASE WHEN v_pct_mni > 0 THEN '+' ELSE '' END, v_pct_mni) ELSE '' END,
        trim(to_char(NEW.especial_mensual, 'FM999G999G999D00')),
        CASE WHEN v_anterior.id IS NOT NULL THEN format(' (antes $%s, %s%s%%)',
            trim(to_char(v_anterior.especial_mensual, 'FM999G999G999D00')),
            CASE WHEN v_pct_esp > 0 THEN '+' ELSE '' END, v_pct_esp) ELSE '' END,
        trim(to_char(NEW.conyuge_mensual, 'FM999G999G999D00')),
        trim(to_char(NEW.hijo_mensual, 'FM999G999G999D00')),
        COALESCE(NEW.notas, '(sin notas)'),
        v_link_extra
    );

    INSERT INTO rrhh_email_outbox (to_addr, cc_addr, subject, body_text, categoria, metadata)
    VALUES (
        'juanpsimonelli@gmail.com',
        'alegr@claudiaadorno.com',
        format('🔔 ARCA Ganancias 4ta — nuevos valores vigentes desde %s', NEW.vigente_desde::text),
        v_body,
        'norma_ganancias_cambio',
        jsonb_build_object(
            'mni_id', NEW.id,
            'vigente_desde', NEW.vigente_desde,
            'mni_mensual', NEW.mni_mensual,
            'especial_mensual', NEW.especial_mensual,
            'diff_mni_pct', v_pct_mni,
            'diff_esp_pct', v_pct_esp,
            'link_norma', NEW.link_norma
        )
    );

    RETURN NEW;
END $$;

-- ─── 4. Función para encolar resumen del estado actual ───────────────
CREATE OR REPLACE FUNCTION public.rrhh_encolar_resumen_norma_actual()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_mni rrhh_ganancias_mni%ROWTYPE;
    v_body text;
    v_link_extra text;
BEGIN
    SELECT * INTO v_mni
      FROM rrhh_ganancias_mni
     ORDER BY vigente_desde DESC LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No hay valores ARCA cargados en rrhh_ganancias_mni';
    END IF;

    v_link_extra := CASE
        WHEN v_mni.link_norma IS NOT NULL AND v_mni.link_norma <> ''
        THEN format(E'\n📄 Texto oficial de la norma:\n   %s\n', v_mni.link_norma)
        ELSE E''
    END;

    v_body := format(
        E'Resumen del estado actual de la normativa ARCA Ganancias 4ta categoría aplicada en el sistema RRHH de Claudia Adorno SRL:\n\n'
     || E'═══════════════════════════════════════════════════════\n'
     || E'  Período vigente desde: %s\n'
     || E'═══════════════════════════════════════════════════════\n\n'
     || E'Valores mensuales (sin SAC) — anuales = mensual × 13 contando SAC:\n\n'
     || E'  • Mínimo No Imponible (MNI):   $%s mensual  /  $%s anual\n'
     || E'  • Deducción especial 4ta cat:  $%s mensual  /  $%s anual\n'
     || E'  • Cónyuge a cargo:             $%s mensual  /  $%s anual\n'
     || E'  • Hijo menor a cargo:          $%s mensual  /  $%s anual\n\n'
     || E'Notas: %s\n%s\n'
     || E'El sistema usa estos valores para:\n'
     || E'  1. Calcular el tope mensual de bruto antes de gatillar retención.\n'
     || E'  2. Cron días 25 y último de cada mes: revisa acumulado y avisa.\n'
     || E'  3. Banner en panel Liquidación marca empleadas al borde / excedidas.\n\n'
     || E'Empleadas controladas: Claudia Adorno (LRT, sin aportes) y JP Simonelli (fuera de convenio).\n\n'
     || E'Cualquier cambio futuro en estos valores debe cargarse en la tabla rrhh_ganancias_mni\n'
     || E'con su vigente_desde y link_norma. El sistema notifica automáticamente al detectar la carga.\n\n'
     || E'— Sistema RRHH Claudia Adorno',
        v_mni.vigente_desde::text,
        trim(to_char(v_mni.mni_mensual, 'FM999G999G999D00')),
        trim(to_char(v_mni.mni_mensual * 13, 'FM999G999G999D00')),
        trim(to_char(v_mni.especial_mensual, 'FM999G999G999D00')),
        trim(to_char(v_mni.especial_mensual * 13, 'FM999G999G999D00')),
        trim(to_char(v_mni.conyuge_mensual, 'FM999G999G999D00')),
        trim(to_char(v_mni.conyuge_mensual * 13, 'FM999G999G999D00')),
        trim(to_char(v_mni.hijo_mensual, 'FM999G999G999D00')),
        trim(to_char(v_mni.hijo_mensual * 13, 'FM999G999G999D00')),
        COALESCE(v_mni.notas, '(sin notas)'),
        v_link_extra
    );

    INSERT INTO rrhh_email_outbox (to_addr, cc_addr, subject, body_text, categoria, metadata)
    VALUES (
        'juanpsimonelli@gmail.com',
        'alegr@claudiaadorno.com',
        format('📋 Resumen actual normativa ARCA Ganancias 4ta — vigente desde %s', v_mni.vigente_desde::text),
        v_body,
        'norma_ganancias_resumen',
        jsonb_build_object(
            'vigente_desde', v_mni.vigente_desde,
            'mni_mensual', v_mni.mni_mensual,
            'link_norma', v_mni.link_norma
        )
    );

    RETURN format('Email "Resumen norma actual" encolado para enviar a juanpsimonelli@gmail.com + alegr@claudiaadorno.com');
END $$;

GRANT EXECUTE ON FUNCTION public.rrhh_encolar_resumen_norma_actual() TO authenticated;

NOTIFY pgrst, 'reload schema';

-- ─── 5. EJECUTAR AHORA: encolar el resumen ────────────────────────────
SELECT public.rrhh_encolar_resumen_norma_actual() AS resultado;

-- (a) Ver el email encolado
SELECT id, subject, status, intentos, body_text
  FROM rrhh_email_outbox
 ORDER BY id DESC LIMIT 1;
