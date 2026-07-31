// ═══════════════════════════════════════════════════════════════════════
//  RRHH Adorno · recibos-pdf.js
//  Generación del PDF de recibo (mensual y SAC), pantalla de confirmación,
//  envío a firma por Gmail y el auditor de conceptos.
//
//  Extraído de index.html el 29-jul-2026 (modularización, Fase 2 · módulo 1).
//  Se carga DESPUÉS del script principal, así ve sus variables globales
//  (sb, session, toast, helpers de formato). Ninguna de estas funciones se
//  ejecuta al arrancar: todas salen de un click del usuario.
// ═══════════════════════════════════════════════════════════════════════

let _forumFontLoaded = false;
const _forumFontName = 'AdornoTitulo';   // URW Gothic — clon libre de Avant Garde

async function _loadForumFont(doc) {
  try {
    if (doc.getFontList && doc.getFontList()[_forumFontName]) return true;
  } catch(_) {}
  try {
    // La fuente vive en nuestro repo (fonts/) para no depender de una CDN
    // ajena: en jul-2026 Google reorganizó su repositorio y la URL de
    // jsdelivr empezó a dar 404, así que los PDFs salían con la tipografía
    // de fallback sin que nadie se enterara. La CDN queda como plan B.
    const urls = [
      './fonts/URWGothic-Book.ttf',   // tipografía institucional (Avant Garde)
      './fonts/Forum-Regular.ttf',    // la que se usaba antes
      'https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/forum/Forum-Regular.ttf',
    ];
    let res = null;
    for (const u of urls) {
      try { const r = await fetch(u); if (r.ok) { res = r; break; } } catch (_) {}
    }
    if (!res) throw new Error('fetch failed');
    const buf = await res.arrayBuffer();
    const bytes = new Uint8Array(buf);
    let bin = '';
    for (let i = 0; i < bytes.byteLength; i++) bin += String.fromCharCode(bytes[i]);
    const b64 = btoa(bin);
    doc.addFileToVFS('AdornoTitulo.ttf', b64);
    doc.addFont('AdornoTitulo.ttf', _forumFontName, 'normal');
    _forumFontLoaded = true;
    return true;
  } catch (e) {
    console.warn('No se pudo cargar Forum, fallback a helvetica', e);
    return false;
  }
}

// Helper: ver el recibo PDF en una ventana nueva (vista previa, no descarga)
// ════════════════════════════════════════════════════════════
// CONFIRMACIÓN PREVIA AL PDF — workflow de revisión de faltas
// ════════════════════════════════════════════════════════════
// Muestra un modal con: días trabajados, faltas (compensadas y sin),
// tardanzas acumuladas, préstamos y descuentos. Solo si el usuario
// confirma, se genera el PDF (delegando a verReciboPDF).
async function abrirConfirmacionRecibo(liqId) {
  try {
    // Cargar liquidación + empleado
    const { data: liq, error } = await sb.from('rrhh_liquidacion')
      .select('*, empleado:rrhh_empleados(id, nombre_completo, local, categoria:rrhh_categorias_cct(nombre))')
      .eq('id', liqId).maybeSingle();
    if (error || !liq) { toast('No se pudo cargar la liquidación', 'error'); return; }

    const periodo = (liq.periodo || '').substring(0,7);
    const [y, m] = periodo.split('-').map(Number);
    const fechaDesde = `${y}-${String(m).padStart(2,'0')}-01`;
    const fechaHasta = new Date(y, m, 0).toISOString().split('T')[0];

    // Permisos día completo aprobados del mes (faltas compensadas/justificadas)
    const { data: permisos } = await sb.from('rrhh_permisos_puntuales')
      .select('id, fecha, tipo, motivo, descontar_banco, minutos_descontar, descontar_vacaciones, dias_descontar, estado')
      .eq('empleado_id', liq.empleado_id)
      .gte('fecha', fechaDesde).lte('fecha', fechaHasta)
      .eq('estado', 'aprobado');

    // Asistencias del mes (para tardanzas + ausencias sin compensar)
    const { data: detalles } = await sb.from('rrhh_asistencias_detalle')
      .select('fecha, estado, minutos_tarde, minutos_salida_temp, error_salvado')
      .eq('empleado_id', liq.empleado_id)
      .gte('fecha', fechaDesde).lte('fecha', fechaHasta);

    // Excluir salvadas: si la encargada las salvó (problema de fichada), no
    // deben aparecer como "sin justificar" ni descontar del sueldo.
    const ausentes = (detalles || []).filter(d => d.estado === 'ausente' && !d.error_salvado);
    const permisosByFecha = {};
    (permisos || []).forEach(p => { permisosByFecha[p.fecha] = p; });

    // Clasificar ausencias: con compensación vs sin compensar
    const faltasCompensadas = [];
    const faltasSinCompensar = [];
    ausentes.forEach(d => {
      const p = permisosByFecha[d.fecha];
      if (p && (p.descontar_banco || p.descontar_vacaciones)) {
        faltasCompensadas.push({ fecha: d.fecha, permiso: p });
      } else if (p) {
        // tiene permiso pero sin compensación (descuento de sueldo justificado)
        faltasCompensadas.push({ fecha: d.fecha, permiso: p, descontaSueldo: true });
      } else {
        // sin permiso = injustificada
        faltasSinCompensar.push(d);
      }
    });

    // Tardanzas + salidas tempranas acumuladas
    const acumTarde = (detalles || []).reduce((s,d) => {
      if (d.error_salvado) return s;
      return s + (d.minutos_tarde || 0) + (d.minutos_salida_temp || 0);
    }, 0);

    // Cargar config umbral
    const { data: tol } = await sb.from('rrhh_config_tolerancias')
      .select('umbral_mensual_tardanzas').eq('local', liq.empleado.local).maybeSingle();
    const umbralMensual = tol?.umbral_mensual_tardanzas || 60;

    const fmtFechaCorta = (s) => s ? new Date(s + 'T12:00:00').toLocaleDateString('es-AR', { day:'2-digit', month:'2-digit' }) : '';

    const compHtml = faltasCompensadas.length === 0
      ? '<div style="color:#94a3b8;font-style:italic;">— sin faltas compensadas —</div>'
      : faltasCompensadas.map(f => {
          let cómo = '';
          if (f.permiso.descontar_banco) cómo = `🏦 banco (-${f.permiso.minutos_descontar} min)`;
          else if (f.permiso.descontar_vacaciones) cómo = `🌴 vacaciones (-${f.permiso.dias_descontar} día)`;
          else cómo = `📝 justificada (descuenta sueldo, NO cuenta como falta de fichada)`;
          return `<div style="padding:6px;border-left:3px solid #0d9488;background:#f0fdfa;margin-bottom:4px;font-size:13px;">
            ${fmtFechaCorta(f.fecha)} → ${cómo}
            ${f.permiso.motivo ? `<div style="font-size:11px;color:#64748b;margin-top:2px;">"${escapeHtml(f.permiso.motivo)}"</div>` : ''}
          </div>`;
        }).join('');

    const sinCompHtml = faltasSinCompensar.length === 0
      ? '<div style="color:#16a34a;font-weight:600;">✅ Sin faltas pendientes</div>'
      : `<div style="padding:8px;background:#fef2f2;border:1px solid #fca5a5;border-radius:6px;">
          <div style="color:#991b1b;font-weight:600;margin-bottom:4px;">⚠️ ${faltasSinCompensar.length} falta(s) INJUSTIFICADAS</div>
          ${faltasSinCompensar.map(d => `<div style="font-size:13px;">• ${fmtFechaCorta(d.fecha)}</div>`).join('')}
          <div style="font-size:11px;color:#7f1d1d;margin-top:6px;">Estas faltas descuentan del sueldo Y suman 2 faltas de fichada (entrada + salida) que afectan el premio.</div>
        </div>`;

    const tardanzaHtml = acumTarde === 0
      ? '<div style="color:#16a34a;">✅ Sin tardanzas/salidas tempranas en el mes</div>'
      : acumTarde > umbralMensual
        ? `<div style="color:#dc2626;font-weight:600;">⚠️ ${acumTarde} min acumulados (> umbral ${umbralMensual}) → se descuenta TODO del banco al cerrar el mes</div>`
        : `<div style="color:#16a34a;">${acumTarde} min acumulados (≤ ${umbralMensual} → perdonados)</div>`;

    const fmt = (n) => '$' + (Number(n) || 0).toLocaleString('es-AR', { minimumFractionDigits: 2 });

    const html = `
      <div class="modal-bg" id="conf-recibo-modal" style="position:fixed;inset:0;background:rgba(0,0,0,0.6);z-index:99999;display:flex;align-items:center;justify-content:center;padding:20px;overflow:auto;">
        <div style="background:white;border-radius:12px;padding:24px;max-width:560px;width:100%;box-shadow:0 20px 40px rgba(0,0,0,0.3);max-height:90vh;overflow:auto;">
          <h2 style="margin:0 0 6px 0;font-size:18px;color:#0d9488;">📋 Revisión previa al recibo</h2>
          <div style="font-size:14px;font-weight:600;margin-bottom:12px;">${escapeHtml(liq.empleado.nombre_completo)} · ${LOCALES[liq.empleado.local]?.nombre || liq.empleado.local} · ${periodo}</div>

          <div style="background:#f8fafc;border-radius:8px;padding:12px;margin-bottom:12px;">
            <div style="font-size:12px;color:#64748b;text-transform:uppercase;margin-bottom:6px;">FALTAS DEL MES</div>
            <div style="font-size:13px;font-weight:600;margin-bottom:4px;">✅ Compensadas / justificadas:</div>
            ${compHtml}
            <div style="font-size:13px;font-weight:600;margin:10px 0 4px;">⚠️ Sin compensar:</div>
            ${sinCompHtml}
          </div>

          <div style="background:#f8fafc;border-radius:8px;padding:12px;margin-bottom:12px;">
            <div style="font-size:12px;color:#64748b;text-transform:uppercase;margin-bottom:6px;">TARDANZAS + SALIDAS TEMPRANAS</div>
            ${tardanzaHtml}
          </div>

          <div style="background:#fef3c7;border-radius:8px;padding:12px;margin-bottom:14px;">
            <div style="font-size:12px;color:#92400e;text-transform:uppercase;margin-bottom:4px;">RECIBO CCT (lo que va al estudio)</div>
            <div style="font-size:18px;font-weight:700;color:#92400e;">${fmt(liq.recibo_neto)}</div>
            ${(m === 6 || m === 12) && Number(liq.sac_recibo_neto || 0) > 0 ? `
              <div style="border-top:1px dashed #d97706;margin-top:10px;padding-top:8px;">
                <div style="font-size:12px;color:#92400e;text-transform:uppercase;margin-bottom:4px;">1er SAC ${periodo}</div>
                <div style="font-size:18px;font-weight:700;color:#92400e;">${fmt(liq.sac_recibo_neto)}</div>
              </div>` : ''}
          </div>

          <div style="display:flex;gap:8px;justify-content:flex-end;flex-wrap:wrap;">
            <button class="btn" onclick="document.getElementById('conf-recibo-modal').remove()">← Volver</button>
            ${(m === 6 || m === 12) && Number(liq.sac_recibo_neto || 0) > 0 ? `
              <button class="btn" style="background:#fef3c7;border-color:#d97706;color:#92400e;" onclick="document.getElementById('conf-recibo-modal').remove(); verSacPDF(${liqId}); auditLog('ver_sac_pdf', 'rrhh_liquidacion', ${liqId}, null, null, 'PDF SAC generado');">🎁 PDF SAC</button>` : ''}
            <button class="btn primary" style="background:#0d9488;border-color:#0f766e;" onclick="document.getElementById('conf-recibo-modal').remove(); verReciboPDF(${liqId}); auditLog('confirmar_recibo', 'rrhh_liquidacion', ${liqId}, null, null, 'PDF generado tras confirmación de faltas');">✅ Confirmar y ver PDF</button>
          </div>
        </div>
      </div>
    `;
    document.body.insertAdjacentHTML('beforeend', html);
  } catch (e) {
    console.error('[abrirConfirmacionRecibo]', e);
    toast('Error: ' + (e.message || e), 'error');
  }
}


// Visor embebido (31-jul): el window.open lo bloqueaban los popup-blockers y
// parecía que "no pasaba nada". Ahora el PDF se muestra en un modal con iframe.
function _mostrarPdfInline(doc, titulo) {
  const url = doc.output('bloburl');
  const old = document.getElementById('pdf-preview-modal');
  if (old) old.remove();
  const html = `
    <div id="pdf-preview-modal" style="position:fixed;inset:0;background:rgba(0,0,0,.72);z-index:99999;display:flex;flex-direction:column;">
      <div style="display:flex;justify-content:space-between;align-items:center;gap:8px;padding:8px 14px;background:#0d9488;color:#fff;">
        <b style="font-size:14px;">${titulo}</b>
        <div style="display:flex;gap:8px;">
          <button class="btn" style="font-size:12px;" onclick="window.open(document.getElementById('pdf-preview-frame').src, '_blank')">⧉ Pestaña</button>
          <button class="btn" style="font-size:12px;" onclick="document.getElementById('pdf-preview-modal').remove()">✕ Cerrar</button>
        </div>
      </div>
      <iframe id="pdf-preview-frame" src="${url}" style="flex:1;border:0;background:#525659;"></iframe>
    </div>`;
  document.body.insertAdjacentHTML('beforeend', html);
}

async function verReciboPDF(liqId) {
  try {
    const doc = await generarPDFRecibo(liqId, { autoSave: false });
    if (!doc) return;
    const tit = doc.__tipoLiq === 'proforma' ? '📋 Recibo PROFORMA (preview)' : '📋 Recibo definitivo';
    _mostrarPdfInline(doc, tit);
  } catch (e) {
    toast('Error abriendo recibo: ' + (e.message || e), 'error');
  }
}

// Vista previa del PDF del SAC (junio/diciembre). Lee rrhh_liquidacion_sac_concepto
// y usa sac_recibo_neto. Sin este flag es el recibo mensual normal.
async function verSacPDF(liqId) {
  try {
    const doc = await generarPDFRecibo(liqId, { autoSave: false, esSAC: true });
    if (!doc) return;
    _mostrarPdfInline(doc, '🎁 Recibo SAC');
  } catch (e) {
    toast('Error abriendo SAC: ' + (e.message || e), 'error');
  }
}

async function generarPDFRecibo(liqId, opts = {}) {
  try {
    // opts.esSAC = true → genera PDF del 1er SAC del semestre (junio/diciembre)
    //   lee conceptos desde rrhh_liquidacion_sac_concepto y usa sac_recibo_neto
    const esSAC = !!opts.esSAC;

    // 1. Cargar liquidación + colaborador + conceptos
    const { data: liq, error: e1 } = await sb.from('rrhh_liquidacion')
      .select('*, empleado:rrhh_empleados(*, categoria:rrhh_categorias_cct(nombre, sueldo_basico))')
      .eq('id', liqId).single();
    if (e1 || !liq) { toast('No se pudo cargar la liquidación: ' + (e1?.message || 'no encontrada'), 'error'); return; }

    // (jul 2026) Monotributistas NO llevan recibo de haberes: facturan por su
    // monotributo. La liquidación existe igual (calcula el efectivo a pagar),
    // pero el PDF de recibo CCT no corresponde emitirlo.
    if (liq.empleado?.monotributista) {
      toast(`${liq.empleado.nombre_completo || 'Esta colaboradora'} es monotributista: factura por su cuenta, no lleva recibo de haberes.`, 'error');
      return;
    }

    const _tablaConceptos = esSAC ? 'rrhh_liquidacion_sac_concepto' : 'rrhh_liquidacion_concepto';
    const { data: conceptos } = await sb.from(_tablaConceptos)
      .select('*').eq('liquidacion_id', liqId).order('orden');
    if (esSAC && (!conceptos || conceptos.length === 0)) {
      toast('No hay conceptos SAC cargados para esta liquidación', 'error'); return;
    }
    // Neto que va al banner (mensual o SAC según flag)
    const _netoBanner = esSAC ? Number(liq.sac_recibo_neto || 0) : Number(liq.recibo_neto || 0);

    const emp = liq.empleado;
    const cat = emp?.categoria;

    // 2. Helpers de formato
    const fmt = (n) => '$' + Math.round(Number(n||0)).toLocaleString('es-AR');
    const fmtNeg = (n) => '-$' + Math.round(Number(Math.abs(n)||0)).toLocaleString('es-AR');
    const fmtPct = (n) => (Number(n||0)).toFixed(2) + '%';
    const labelMes = (iso) => {
      if (!iso) return '';
      const [y, m] = iso.split('-').map(Number);
      const mes = new Date(y, m-1, 1).toLocaleDateString('es-AR', { month: 'long', year: 'numeric' });
      return mes.charAt(0).toUpperCase() + mes.slice(1);
    };
    const fmtFechaCorta = (iso) => {
      if (!iso) return '';
      const d = new Date(iso + (iso.length === 10 ? 'T12:00:00' : ''));
      return d.toLocaleDateString('es-AR', { day:'2-digit', month:'2-digit', year:'numeric' });
    };
    const aniosDesde = (iso) => {
      if (!iso) return 0;
      const d = new Date(iso + 'T12:00:00'), hoy = new Date();
      let a = hoy.getFullYear() - d.getFullYear();
      if (hoy < new Date(hoy.getFullYear(), d.getMonth(), d.getDate())) a -= 1;
      return Math.max(0, a);
    };

    // 3. Setup PDF
    const { jsPDF } = window.jspdf;
    const doc = opts.existingDoc || new jsPDF({ unit: 'mm', format: 'a4' });
    if (opts.existingDoc) doc.addPage();
    const W = 210, H = 297, margen = 18, ancho = W - margen * 2;

    const COLOR_TEXT    = [26, 26, 26];
    const COLOR_MUTED   = [95, 94, 90];
    const COLOR_BORDER  = [211, 209, 199];
    const COLOR_GREEN   = [15, 110, 86];   // turquesa Adorno
    const COLOR_GREEN_LT = [240, 253, 244]; // verde clarito p/ box neto
    const COLOR_SOFT    = [248, 250, 252];

    const forumOk = await _loadForumFont(doc);

    // 4. HEADER — Logo "Claudia Adorno" en Forum (con fallback a helvetica bold)
    doc.setTextColor(...COLOR_TEXT);
    if (forumOk) {
      doc.setFont(_forumFontName, 'normal');
      doc.setFontSize(34);
    } else {
      doc.setFont('helvetica', 'bold');
      doc.setFontSize(26);
    }
    doc.text('Claudia Adorno', margen, 26);

    doc.setFont('helvetica', 'normal');
    doc.setFontSize(8);
    doc.setTextColor(...COLOR_MUTED);
    doc.text('Recibo de haberes · Art. 138 LCT', margen, 31);

    // Datos empresa (derecha)
    doc.setFontSize(8);
    doc.setTextColor(...COLOR_MUTED);
    doc.text('CLAUDIA ADORNO SRL', W - margen, 18, { align: 'right' });
    doc.text('CUIT 30-70967311-0', W - margen, 22, { align: 'right' });
    doc.text('Buenos Aires, Argentina', W - margen, 26, { align: 'right' });

    // Línea divisoria turquesa
    doc.setDrawColor(...COLOR_GREEN);
    doc.setLineWidth(0.7);
    doc.line(margen, 36, W - margen, 36);

    // 5. PERÍODO + NETO (banner principal)
    let y = 46;
    doc.setFont('helvetica', 'normal');
    doc.setFontSize(8);
    doc.setTextColor(...COLOR_MUTED);
    doc.text(esSAC ? 'PERÍODO LIQUIDADO (SAC)' : 'PERÍODO LIQUIDADO', margen, y);
    doc.text('NETO A COBRAR', W - margen, y, { align: 'right' });
    doc.setFont('helvetica', 'bold');
    doc.setFontSize(18);
    doc.setTextColor(...COLOR_TEXT);
    doc.text((esSAC ? '1er SAC ' : '') + labelMes(liq.periodo), margen, y + 8);
    doc.setTextColor(...COLOR_GREEN);
    doc.text(fmt(_netoBanner), W - margen, y + 8, { align: 'right' });

    // 6. BOX EMPLEADA
    y = 62;
    doc.setFillColor(...COLOR_SOFT);
    doc.setDrawColor(...COLOR_BORDER);
    doc.setLineWidth(0.3);
    doc.roundedRect(margen, y, ancho, 44, 2, 2, 'FD');
    doc.setFont('helvetica', 'normal');
    doc.setFontSize(7.5);
    doc.setTextColor(...COLOR_MUTED);
    doc.text('EMPLEADA', margen + 4, y + 5);
    doc.setFont('helvetica', 'bold');
    doc.setFontSize(13);
    doc.setTextColor(...COLOR_TEXT);
    doc.text(emp?.nombre_completo || `${emp?.apellido||''}, ${emp?.nombre||''}`, margen + 4, y + 11);

    doc.setFont('helvetica', 'normal');
    doc.setFontSize(8.5);
    doc.setTextColor(...COLOR_MUTED);
    const subInfo = [];
    if (emp?.cuil) subInfo.push(`CUIL ${emp.cuil}`);
    if (emp?.dni)  subInfo.push(`DNI ${emp.dni}`);
    if (emp?.legajo) subInfo.push(`Legajo ${emp.legajo}`);
    doc.text(subInfo.join(' · '), margen + 4, y + 16);

    // Fila inferior: categoría, antigüedad, local, ingreso, OS
    const colX1 = margen + 4, colX2 = margen + 65, colX3 = margen + 125;
    doc.setFontSize(7.5);
    doc.setTextColor(...COLOR_MUTED);
    doc.text('CATEGORÍA',  colX1, y + 24);
    doc.text('ANTIGÜEDAD', colX2, y + 24);
    doc.text('LOCAL',      colX3, y + 24);
    doc.setFont('helvetica', 'bold');
    doc.setFontSize(9);
    doc.setTextColor(...COLOR_TEXT);
    doc.text(cat?.nombre || (emp?.fuera_convenio ? 'Fuera de convenio' : '—'), colX1, y + 29);
    doc.text(`${aniosDesde(emp?.fecha_ingreso)} años`, colX2, y + 29);
    doc.text((emp?.local || '').toUpperCase(), colX3, y + 29);

    doc.setFont('helvetica', 'normal');
    doc.setFontSize(7.5);
    doc.setTextColor(...COLOR_MUTED);
    doc.text('INGRESO',     colX1, y + 33);
    doc.text('OBRA SOCIAL', colX2, y + 33);
    doc.text('DÍAS LIQUIDADOS', colX3, y + 33);

    // Datos en la línea siguiente (y+38)
    doc.setFont('helvetica', 'bold');
    doc.setFontSize(9);
    doc.setTextColor(...COLOR_TEXT);
    const _ingresoTxt = emp?.fecha_ingreso
      ? new Date(emp.fecha_ingreso + 'T12:00:00').toLocaleDateString('es-AR')
      : '—';
    const _osTxt = emp?.obra_social || cat?.obra_social || 'OSECAC';
    // Días trabajados / días del mes — formato 28/30 (en vez de %).
    // Días del mes = días reales del mes calendario del período.
    let _diasMes = 30;
    try {
      if (liq?.periodo) {
        const [_py, _pm] = liq.periodo.split('-').map(Number);
        _diasMes = new Date(_py, _pm, 0).getDate();
      }
    } catch (_) {}
    const _diasTrab = Number(liq?.dias_trabajados || _diasMes);
    doc.text(_ingresoTxt, colX1, y + 38);
    doc.text(String(_osTxt).slice(0, 18), colX2, y + 38);
    doc.text(`${_diasTrab}/${_diasMes}`, colX3, y + 38);

    // 6b. COSTO LABORAL + CONTRIBUCIONES EMPLEADOR (Decreto 407/2026, Anexo III)
    // El recibo nuevo arranca del costo laboral total y baja hasta el neto.
    // Tasas verificadas contra los recibos del estudio contable (jul-2026):
    //   Cont. Seg. Social = 18% × (remunerativo − detracción Dec.814) →
    //     se abre en 16,41% seg. social (SIPA/FNE/AAFF) + 1,59% INSSJP.
    //   Contribución OS = 6% sobre la MISMA base que el 3% del trabajador
    //   (OSECAC = bruto, otras = remunerativo — igual que el descuento).
    const DETRACCION_814 = 7003.68; // detracción vigente jul-2026 (según estudio)
    const _ccAll = conceptos || [];
    const _remT  = _ccAll.filter(c => !c.es_descuento && c.remunerativo).reduce((s,c)=>s+Number(c.importe||0),0);
    const _nrT   = _ccAll.filter(c => !c.es_descuento && !c.remunerativo).reduce((s,c)=>s+Number(c.importe||0),0);
    const _brutoT = _remT + _nrT;
    const _jubTrab = Number(_ccAll.find(c => c.codigo === '1001')?.importe || 0);
    const _osC = _ccAll.find(c => c.codigo === '1031');
    const _baseOS = (_osC && Number(_osC.porcentaje) > 0)
      ? Number(_osC.importe || 0) / (Number(_osC.porcentaje) / 100)
      : _remT;
    const _baseContrib = Math.max(0, _remT - DETRACCION_814);
    const _contribSS   = _baseContrib * 0.18;
    const _ssEmpleador = _baseContrib * 0.1641;
    const _inssjpEmp   = _baseContrib * 0.0159;
    const _contribOS   = _baseOS * 0.06;
    const _contribTot  = _contribSS + _contribOS;
    const _costoTotal  = _brutoT + _contribTot;

    y = 111;
    doc.setFont('helvetica', 'normal');
    doc.setFontSize(8);
    doc.setTextColor(...COLOR_MUTED);
    doc.text('COSTO LABORAL · CONTRIBUCIONES DEL EMPLEADOR', margen, y);
    doc.text('Decreto 407/2026 · Anexo III', W - margen, y, { align: 'right' });
    doc.setDrawColor(...COLOR_BORDER);
    doc.setLineWidth(0.3);
    doc.line(margen, y + 1.5, W - margen, y + 1.5);
    y += 6.5;
    doc.setFont('helvetica', 'bold');
    doc.setFontSize(10);
    doc.setTextColor(...COLOR_TEXT);
    doc.text('Costo laboral total del empleador', margen, y);
    doc.text(fmt(_costoTotal), W - margen, y, { align: 'right' });
    y += 5.5;
    doc.setFont('helvetica', 'normal');
    doc.setFontSize(8.5);
    doc.text('Cont. Seguridad Social (SIPA · FNE · Asig. Familiares · INSSJP)', margen, y);
    doc.text(fmt(_contribSS), W - margen, y, { align: 'right' });
    y += 4.5;
    doc.text('Contribución Obra Social (6%)', margen, y);
    doc.text(fmt(_contribOS), W - margen, y, { align: 'right' });
    y += 2.5;
    doc.line(margen, y, W - margen, y);
    y += 4;
    doc.setFont('helvetica', 'bold');
    doc.setFontSize(9);
    doc.text('Subtotal contribuciones del empleador', margen, y);
    doc.text(fmt(_contribTot), W - margen, y, { align: 'right' });

    // ── Columna derecha: COMPOSICIÓN DEL COSTO LABORAL (torta) ──
    const colDerX = margen + 112;                 // arranque columna derecha
    const colIzqAmt = margen + 96;                // importes tablas izquierda
    const colIzqFlag = margen + 104;              // flag R/NR
    const _tortaTopY = y + 8;
    let _colDerBottom = _tortaTopY;               // se actualiza al dibujar la torta
    {
      const _netoSlice = Math.max(0, _costoTotal - (_ssEmpleador + _jubTrab) - _contribOS - _inssjpEmp);
      const _slices = [
        { label: 'Sueldo neto',      v: _netoSlice,               color: COLOR_GREEN },
        { label: 'Seguridad social', v: _ssEmpleador + _jubTrab,  color: [83, 74, 183] },
        { label: 'Obra social',      v: _contribOS,               color: [255, 107, 0] },
        { label: 'INSSJP',           v: _inssjpEmp,               color: [245, 166, 35] },
        { label: 'Sindical · ART · SCVO', v: 0,                   color: [160, 158, 150] },
      ];
      const _tot = _slices.reduce((s, x) => s + x.v, 0) || 1;
      let ty = _tortaTopY;
      doc.setFont('helvetica', 'normal');
      doc.setFontSize(8);
      doc.setTextColor(...COLOR_MUTED);
      doc.text('COMPOSICIÓN DEL COSTO LABORAL', colDerX, ty);
      doc.line(colDerX, ty + 1.5, W - margen, ty + 1.5);
      // Torta (abanico de triángulos, jsPDF no tiene arcos con relleno)
      const cx = colDerX + 20, cyP = ty + 26, r = 17;
      let ang = -Math.PI / 2;
      for (const s of _slices) {
        const frac = s.v / _tot;
        if (frac <= 0) continue;
        const fin = ang + frac * Math.PI * 2;
        doc.setFillColor(...s.color);
        const paso = Math.PI / 60;
        for (let a = ang; a < fin; a += paso) {
          const b = Math.min(a + paso, fin);
          doc.triangle(cx, cyP, cx + r * Math.cos(a), cyP + r * Math.sin(a),
                       cx + r * Math.cos(b), cyP + r * Math.sin(b), 'F');
        }
        ang = fin;
      }
      // Leyenda a la derecha de la torta
      let ly = ty + 12;
      const lx = cx + r + 6;
      doc.setFontSize(7.2);
      for (const s of _slices) {
        const pct = Math.round((s.v / _tot) * 100);
        doc.setFillColor(...s.color);
        doc.rect(lx, ly - 2.2, 2.6, 2.6, 'F');
        doc.setTextColor(...COLOR_TEXT);
        doc.text(`${s.label} ${pct}%`, lx + 4, ly);
        ly += 4.4;
      }
      // Desglose de totales (estilo "Detalle de la Composición Salarial")
      let dy = cyP + r + 7;
      doc.setFontSize(7.2);
      const _fila = (lbl, val) => {
        doc.setTextColor(...COLOR_MUTED); doc.text(lbl, colDerX, dy);
        doc.setTextColor(...COLOR_TEXT);  doc.text(fmt(val), W - margen, dy, { align: 'right' });
        dy += 3.8;
      };
      doc.setFont('helvetica', 'bold');
      _fila('Total seguridad social', _ssEmpleador + _jubTrab);
      doc.setFont('helvetica', 'normal');
      _fila('    Empleador', _ssEmpleador);
      _fila('    Trabajador', _jubTrab);
      doc.setFont('helvetica', 'bold');
      _fila('Total obra social (empleador)', _contribOS);
      _fila('Total INSSJP (empleador)', _inssjpEmp);
      _fila('Costo sindical · ART · SCVO', 0);
      doc.setFont('helvetica', 'normal');
      doc.setFontSize(6.3);
      doc.setTextColor(...COLOR_MUTED);
      const _nota = doc.splitTextToSize('Nota: la seguridad social del empleador incluye SIPA, Fondo Nacional de Empleo y Asignaciones Familiares.', (W - margen) - colDerX);
      doc.text(_nota, colDerX, dy + 1);
      _colDerBottom = dy + 1 + _nota.length * 2.8;
    }

    // 7. TABLA DEVENGADO (columna izquierda)
    y = _tortaTopY;
    doc.setFont('helvetica', 'normal');
    doc.setFontSize(8);
    doc.setTextColor(...COLOR_MUTED);
    doc.text('DEVENGADO', margen, y);
    doc.text('R/NR', colIzqFlag + 4, y, { align: 'right' });
    doc.setDrawColor(...COLOR_BORDER);
    doc.setLineWidth(0.3);
    doc.line(margen, y + 1.5, colIzqFlag + 4, y + 1.5);

    y += 6;
    const conceptosDevengados = (conceptos || []).filter(c => !c.es_descuento);
    doc.setFont('helvetica', 'normal');
    doc.setFontSize(9);
    doc.setTextColor(...COLOR_TEXT);

    let totalRem = 0, totalNR = 0;
    for (const c of conceptosDevengados) {
      const desc = c.nombre || '';
      const pct  = c.porcentaje != null && c.porcentaje > 0 ? ` (${fmtPct(c.porcentaje)})` : '';
      const importe = Number(c.importe || 0);
      const flagRem = c.remunerativo ? 'R' : 'NR';
      if (c.remunerativo) totalRem += importe; else totalNR += importe;

      doc.text(String(desc + pct).slice(0, 42), margen, y);
      doc.text(fmt(importe), colIzqAmt, y, { align: 'right' });
      doc.setTextColor(...COLOR_MUTED);
      doc.setFontSize(8);
      doc.text(flagRem, colIzqFlag + 4, y, { align: 'right' });
      doc.setTextColor(...COLOR_TEXT);
      doc.setFontSize(9);
      y += 4.5;
      if (y > H - 80) { doc.addPage(); y = 22; }
    }
    // Total bruto
    const totalBruto = totalRem + totalNR;
    doc.setDrawColor(...COLOR_BORDER);
    doc.line(margen, y, colIzqFlag + 4, y);
    y += 4.5;
    doc.setFont('helvetica', 'bold');
    doc.setFontSize(10);
    doc.text('Total bruto', margen, y);
    doc.text(fmt(totalBruto), colIzqAmt, y, { align: 'right' });

    // 8. TABLA DESCUENTOS
    y += 9;
    doc.setFont('helvetica', 'normal');
    doc.setFontSize(8);
    doc.setTextColor(...COLOR_MUTED);
    doc.text('DESCUENTOS', margen, y);
    doc.line(margen, y + 1.5, colIzqFlag + 4, y + 1.5);
    y += 6;

    const descuentos = (conceptos || []).filter(c => c.es_descuento);
    doc.setFont('helvetica', 'normal');
    doc.setFontSize(9);
    doc.setTextColor(...COLOR_TEXT);
    let totalDesc = 0;
    for (const c of descuentos) {
      const desc = c.nombre || '';
      const pct  = c.porcentaje != null && c.porcentaje > 0 ? ` (${fmtPct(c.porcentaje)})` : '';
      const importe = Number(c.importe || 0);
      totalDesc += importe;
      doc.text(String(desc + pct).slice(0, 42), margen, y);
      doc.text(fmtNeg(importe), colIzqAmt, y, { align: 'right' });
      y += 4.5;
      if (y > H - 60) { doc.addPage(); y = 22; }
    }
    doc.line(margen, y, colIzqFlag + 4, y);
    y += 4.5;
    doc.setFont('helvetica', 'bold');
    doc.setFontSize(10);
    doc.text('Total descuentos', margen, y);
    doc.text(fmtNeg(totalDesc), colIzqAmt, y, { align: 'right' });

    // 9. BANNER NETO A COBRAR (debajo de ambas columnas)
    y = Math.max(y + 9, _colDerBottom + 5);
    if (y > H - 72) y = H - 72;  // no pisar QR/firmas
    doc.setFillColor(...COLOR_GREEN_LT);
    doc.setDrawColor(...COLOR_GREEN);
    doc.setLineWidth(0.4);
    doc.roundedRect(margen, y, ancho, 14, 2, 2, 'FD');
    doc.setFont('helvetica', 'bold');
    doc.setFontSize(12);
    doc.setTextColor(...COLOR_GREEN);
    doc.text('Neto a cobrar', margen + 5, y + 9);
    doc.setFontSize(16);
    doc.text(fmt(_netoBanner), W - margen - 5, y + 9.5, { align: 'right' });

    // 10. QR con código identificador REC-XXXXX (mensual) o SAC-XXXXX (aguinaldo)
    // para escaneo bulk de firmados y distinguirlos visualmente
    try {
      if (typeof qrcode === 'function') {
        const codigoQR = (esSAC ? 'SAC-' : 'REC-') + String(liq.id).padStart(5, '0');
        const qr = qrcode(0, 'M');  // tipo 0 (auto), corrección media
        qr.addData(codigoQR);
        qr.make();
        const qrDataUrl = qr.createDataURL(4, 0);  // celdas de 4px, sin margen
        // 22mm × 22mm en esquina inferior izquierda (debajo del bloque de firmas)
        const qrSize = 22;
        const qrX = margen;
        const qrY = H - qrSize - 32;  // espacio extra para el nuevo footer alineado con vacaciones
        doc.addImage(qrDataUrl, 'PNG', qrX, qrY, qrSize, qrSize);
        // Caption chica al lado
        doc.setFont('helvetica', 'normal');
        doc.setFontSize(7);
        doc.setTextColor(...COLOR_MUTED);
        doc.text(codigoQR, qrX + qrSize + 2, qrY + qrSize - 1);
      }
    } catch (e) { console.warn('No se pudo generar QR:', e); }

    // 11. FIRMAS (al pie de la página, no flotante)
    const yFirma = Math.min(H - 35, y + 35);
    doc.setDrawColor(...COLOR_BORDER);
    doc.setLineWidth(0.3);
    const mitad = W / 2;
    doc.line(margen + 10, yFirma, mitad - 10, yFirma);
    doc.line(mitad + 10, yFirma, W - margen - 10, yFirma);

    // Embeber firma del admin (JP) automáticamente — encima de la línea derecha.
    // Si el archivo no existe (404), seguimos sin firma — graceful fallback.
    try {
      const resFirma = await fetch('./assets/firma_admin.png');
      if (resFirma.ok) {
        const blob = await resFirma.blob();
        const dataUrl = await new Promise(res => {
          const r = new FileReader();
          r.onloadend = () => res(r.result);
          r.readAsDataURL(blob);
        });
        // Dimensiones: ~35mm de ancho, 18mm de alto, centrada en el bloque derecho de firma
        const firmaW = 35, firmaH = 18;
        const firmaCenterX = (mitad + 10 + W - margen - 10) / 2;
        doc.addImage(dataUrl, 'PNG', firmaCenterX - firmaW/2, yFirma - firmaH - 1, firmaW, firmaH);
      }
    } catch(e) { console.warn('No se pudo cargar firma_admin.png', e); }

    doc.setFont('helvetica', 'normal');
    doc.setFontSize(8);
    doc.setTextColor(...COLOR_MUTED);
    doc.text('Recibí conforme', (margen + 10 + mitad - 10) / 2, yFirma + 4, { align: 'center' });
    doc.text('Firma empleado/a', (margen + 10 + mitad - 10) / 2, yFirma + 8, { align: 'center' });
    doc.text('Por Claudia Adorno SRL', (mitad + 10 + W - margen - 10) / 2, yFirma + 4, { align: 'center' });
    doc.text('Firma y sello', (mitad + 10 + W - margen - 10) / 2, yFirma + 8, { align: 'center' });

    // 12. Bloque CÓDIGO DE SEGUIMIENTO + asunto del mail (estilo vacaciones)
    const codigoSeg = 'REC-' + String(liq.id).padStart(5, '0');
    const periodoCorto = (liq.periodo || '').slice(0, 7);

    // Cuadro destacado a la derecha con el código (encima del QR)
    doc.setDrawColor(...COLOR_BORDER);
    doc.setLineWidth(0.3);
    const segBoxW = 60;
    const segBoxX = W - margen - segBoxW;
    const segBoxY = H - 50;
    doc.roundedRect(segBoxX, segBoxY, segBoxW, 22, 2, 2, 'S');
    doc.setFont('helvetica', 'bold');
    doc.setFontSize(8);
    doc.setTextColor(...COLOR_MUTED);
    doc.text('CÓDIGO DE SEGUIMIENTO', segBoxX + segBoxW/2, segBoxY + 6, { align: 'center' });
    doc.setFont('helvetica', 'bold');
    doc.setFontSize(14);
    doc.setTextColor(...COLOR_GREEN);
    doc.text(codigoSeg, segBoxX + segBoxW/2, segBoxY + 15, { align: 'center' });
    doc.setFont('helvetica', 'normal');
    doc.setFontSize(7);
    doc.setTextColor(...COLOR_MUTED);
    doc.text(`Asunto del mail: "RECIBO ${periodoCorto} ${codigoSeg}"`, segBoxX + segBoxW/2, segBoxY + 20, { align: 'center' });

    // Frase + mail (estilo vacaciones)
    doc.setDrawColor(...COLOR_BORDER);
    doc.setLineWidth(0.3);
    doc.line(margen, H - 22, W - margen, H - 22);
    doc.setFont('helvetica', 'normal');
    doc.setFontSize(7);
    doc.setTextColor(...COLOR_MUTED);
    doc.text('Una vez firmado, escaneá esta hoja y enviála a', W/2, H - 17, { align: 'center' });
    doc.setFont('helvetica', 'bold');
    doc.setTextColor(...COLOR_GREEN);
    doc.text('claudiaadornosrl@gmail.com', W/2, H - 13.5, { align: 'center' });

    // Fecha + liquidación id
    doc.setFont('helvetica', 'normal');
    doc.setTextColor(...COLOR_MUTED);
    doc.setFontSize(6.5);
    const ahora = new Date().toLocaleString('es-AR', { day:'2-digit', month:'2-digit', year:'numeric', hour:'2-digit', minute:'2-digit' });
    doc.text(`Generado automáticamente · ${ahora} · Liquidación #${liq.id}`, W/2, H - 9, { align: 'center' });

    // 12b. Marca de agua PROFORMA (31-jul): mientras la liquidación no sea
    // definitiva, el PDF lo dice bien grande — no es un recibo emitible.
    doc.__tipoLiq = liq.tipo || 'definitivo';
    if (!esSAC && liq.tipo === 'proforma') {
      try {
        doc.saveGraphicsState();
        doc.setGState(new doc.GState({ opacity: 0.13 }));
        doc.setFont('helvetica', 'bold');
        doc.setFontSize(72);
        doc.setTextColor(220, 38, 38);
        doc.text('PROFORMA', W / 2, H / 2 + 30, { align: 'center', angle: 45 });
        doc.restoreGraphicsState();
      } catch (_) {
        // fallback sin opacidad (jsPDF viejo): gris clarito
        doc.setFont('helvetica', 'bold');
        doc.setFontSize(60);
        doc.setTextColor(243, 232, 232);
        doc.text('PROFORMA', W / 2, H / 2 + 30, { align: 'center', angle: 45 });
        doc.setTextColor(...COLOR_TEXT);
      }
      // Aviso chico arriba, al lado del período
      doc.setFont('helvetica', 'bold');
      doc.setFontSize(8);
      doc.setTextColor(220, 38, 38);
      doc.text('PROFORMA — preview, no válido como recibo', W - margen, 40, { align: 'right' });
      doc.setTextColor(...COLOR_TEXT);
    }

    // 13. Descargar
    const apellido = (emp?.apellido || 'empleada').toUpperCase().replace(/\s+/g, '_');
    const periodoSafe = liq.periodo ? liq.periodo.slice(0, 7) : 'periodo';
    const fileName = `Recibo_${apellido}_${periodoSafe}.pdf`;
    if (opts.autoSave !== false) {
      doc.save(fileName);
      await sb.from('rrhh_liquidacion').update({ pdf_generado_at: new Date().toISOString() }).eq('id', liqId);
      toast('Recibo descargado ✓', 'success');
    }
    return doc;
  } catch (e) {
    console.error(e);
    toast('Error al generar el PDF: ' + e.message, 'error');
  }
}

// ═══════════════════════════════════════════════════════════════════
//  Workflow firma: descarga PDF + abre Gmail con asunto pre-armado
//  La colaboradora firma a mano (o desde su Drive) y reenvía por mail.
//  El script 11_procesar_recibos_firmados.py lo procesa automáticamente.
// ═══════════════════════════════════════════════════════════════════
async function enviarReciboFirma(liqId) {
  try {
    // 1. Levantar datos de la liquidación + empleada
    const { data: liq, error } = await sb.from('rrhh_liquidacion')
      .select('id, periodo, recibo_neto, empleado:rrhh_empleados(id, apellido, nombre, nombre_completo, email)')
      .eq('id', liqId).single();
    if (error || !liq) { toast('No se pudo cargar la liquidación', 'error'); return; }
    const emp = liq.empleado;
    if (!emp) { toast('Liquidación sin colaboradora asociada', 'error'); return; }

    // 2. Asunto + cuerpo del mail
    const periodo = (liq.periodo || '').slice(0, 7);
    const labelMes = (() => {
      const [y, m] = periodo.split('-').map(Number);
      const mes = new Date(y, m-1, 1).toLocaleDateString('es-AR', { month: 'long', year: 'numeric' });
      return mes.charAt(0).toUpperCase() + mes.slice(1);
    })();
    const codigo = 'REC-' + String(liq.id).padStart(5, '0');
    const apellido = (emp.apellido || '').toUpperCase();
    const subject = `RECIBO ${periodo} ${apellido} ${codigo}`;
    const body = [
      `Hola ${emp.nombre || ''},`,
      '',
      `Te adjunto el recibo de haberes correspondiente a ${labelMes}.`,
      '',
      'Para confirmar la recepción, por favor:',
      '  1. Imprimilo, firmalo y escaneá la versión firmada (o firmalo digitalmente).',
      `  2. Respondé este mismo mail con el PDF firmado adjunto.`,
      '',
      `Importante: mantené el código ${codigo} en el subject del mail de respuesta.`,
      '',
      'Cualquier consulta, avisame.',
      '',
      'Saludos,',
      'Juan Pablo · Claudia Adorno SRL',
    ].join('\n');

    // 3. Descargar el PDF (sin marcar pdf_enviado_at todavía — eso se marca cuando confirme el envío)
    await generarPDFRecibo(liqId);

    // 4. Mostrar modal con la info del mail + botones
    const mailTo = emp.email || '';
    const gmailUrl = `https://mail.google.com/mail/?view=cm&fs=1&to=${encodeURIComponent(mailTo)}&su=${encodeURIComponent(subject)}&body=${encodeURIComponent(body)}`;
    const html = `
      <h3 style="margin:0 0 14px;">📧 Enviar recibo a ${escapeHtml(emp.nombre_completo || '')}</h3>
      <div style="background:#f9fafb;padding:12px;border-radius:8px;margin-bottom:14px;font-size:13px;">
        <div><strong>Período:</strong> ${escapeHtml(labelMes)}</div>
        <div><strong>Código:</strong> <code>${codigo}</code></div>
        <div><strong>Para:</strong> ${mailTo ? escapeHtml(mailTo) : '<span style="color:#dc2626;">⚠ Sin email cargado en el legajo</span>'}</div>
        <div><strong>Asunto:</strong> ${escapeHtml(subject)}</div>
      </div>

      <div style="background:#eef2ff;padding:10px 12px;border-radius:6px;font-size:12px;color:#3730a3;margin-bottom:14px;">
        <strong>Cómo seguir:</strong>
        <ol style="margin:4px 0 0 18px;padding:0;">
          <li>Cliquéa <strong>Abrir Gmail</strong> abajo.</li>
          <li>Arrastrá el PDF descargado al draft.</li>
          <li>Revisá / completá el destinatario y envialo.</li>
          <li>Volvé acá y cliquéa <strong>Marcar como enviado</strong>.</li>
        </ol>
      </div>

      <div style="display:flex;gap:8px;justify-content:flex-end;flex-wrap:wrap;">
        <button class="btn" onclick="closeModal()">Cancelar</button>
        <a class="btn primary" href="${gmailUrl}" target="_blank" rel="noopener" style="text-decoration:none;">📨 Abrir Gmail</a>
        <button class="btn" style="background:#16a34a;color:white;" onclick="marcarReciboEnviado(${liqId}); closeModal();">✓ Marcar como enviado</button>
      </div>
    `;
    openModal(html, '600px');
  } catch (e) {
    console.error(e);
    toast('Error: ' + e.message, 'error');
  }
}

async function marcarReciboEnviado(liqId) {
  const { error } = await sb.from('rrhh_liquidacion').update({
    pdf_enviado_at: new Date().toISOString(),
    pdf_enviado_por: session.user?.email || 'admin',
  }).eq('id', liqId);
  if (error) { toast('Error: ' + error.message, 'error'); return; }
  toast('Marcado como enviado ✓', 'success');
  // 🔔 Push a la colaboradora — recibo listo para firmar
  const { data: liq } = await sb.from('rrhh_liquidacion').select('empleado_id, periodo').eq('id', liqId).single();
  if (liq && liq.empleado_id) {
    const periodo = (liq.periodo || '').slice(0, 7);
    const mesTxt = (() => {
      const [y, m] = periodo.split('-').map(Number);
      if (!y || !m) return '';
      const txt = new Date(y, m-1, 1).toLocaleDateString('es-AR', { month:'long', year:'numeric' });
      return txt.charAt(0).toUpperCase() + txt.slice(1);
    })();
    enviarPush(
      liq.empleado_id,
      'Recibo listo para firmar ✏️',
      `Te llegó al mail el recibo de ${mesTxt}. Por favor firmalo y respondé con el PDF.`,
      { url: './#mis-recibos', tag: 'recibo-' + liqId }
    );
  }
  switchTab('liquidaciones');
}




// ═══════════════════════════════════════════════════════════════════════
//  AUDITOR DE RECIBOS — Parsea PDFs MEMOSOFT y los valida contra
//  el cálculo del CCT 130/75 hecho por salaryEngine.
// ═══════════════════════════════════════════════════════════════════════
const reciboAuditor = (() => {
  // Normaliza un nombre de concepto para matcheo flexible
  function normalizar(s) {
    return (s || '')
      .toLowerCase()
      .replace(/[áÁ]/g, 'a')
      .replace(/[éÉ]/g, 'e')
      .replace(/[íÍ]/g, 'i')
      .replace(/[óÓ]/g, 'o')
      .replace(/[úÚ]/g, 'u')
      .replace(/[ñÑ]/g, 'n')
      .replace(/[^a-z0-9\s]/g, ' ')
      .replace(/\s+/g, ' ')
      .trim();
  }

  // Mapeo de patrón de nombre PDF → clave del salaryEngine.totales
  // Cada patrón es un set de keywords que deben TODOS aparecer en el nombre normalizado.
  const REGLAS = [
    { keys: ['sueldo','basico'],            campo: 'basico',        es_descuento: false },
    { keys: ['adic','antiguedad'],          campo: 'antiguedad',    es_descuento: false },
    { keys: ['antiguedad'],                 campo: 'antiguedad',    es_descuento: false },
    { keys: ['presentismo','rem'],          campo: 'pres_nr',       es_descuento: false, no_si: ['nr'] },
    { keys: ['presentismo','no','rem'],     campo: 'pres_nr',       es_descuento: false },
    { keys: ['presentismo','nr'],           campo: 'pres_nr',       es_descuento: false },
    { keys: ['presentismo'],                campo: 'presentismo',   es_descuento: false },
    { keys: ['suma','fija'],                campo: 'sumafija_nr',   es_descuento: false },
    { keys: ['ant','no','rem'],             campo: 'ant_nr',        es_descuento: false },
    { keys: ['antiguedad','no','rem'],      campo: 'ant_nr',        es_descuento: false },
    { keys: ['recompos'],                   campo: 'recompos_nr',   es_descuento: false },
    { keys: ['jubilacion'],                 campo: 'jubilacion',    es_descuento: true },
    { keys: ['19032'],                      campo: 'ley19032',      es_descuento: true },
    { keys: ['pami'],                       campo: 'ley19032',      es_descuento: true },
    { keys: ['sec'],                        campo: 'sec',           es_descuento: true },
    { keys: ['sindicato'],                  campo: 'sec',           es_descuento: true },
    { keys: ['faecys'],                     campo: 'faecys',        es_descuento: true },
    { keys: ['obra','social'],              campo: 'obra_social',   es_descuento: true },
    { keys: ['a','cuenta','aumentos'],      campo: 'otros_rem',     es_descuento: false },
  ];

  function matchearConcepto(nombrePdf) {
    const n = normalizar(nombrePdf);
    const tokens = n.split(' ');
    for (const r of REGLAS) {
      const todosOk = r.keys.every(k => tokens.includes(k));
      const noOk = !r.no_si || !r.no_si.some(k => tokens.includes(k));
      if (todosOk && noOk) return r;
    }
    return null;
  }

  /**
   * Parsea el texto extraído de un recibo MEMOSOFT.
   * Devuelve { ok, empleado, periodo, conceptos, totales } o { ok:false, error }.
   */
  function parsear(textoCompleto) {
    if (!textoCompleto) return { ok: false, error: 'PDF vacío' };

    const lineas = textoCompleto.split(/\n+/).map(l => l.trim()).filter(Boolean);

    // ─── Empleado: buscar línea con "DNI ..."
    let nombre = '', dni = '', cuil = '', categoria = '', periodo = '';
    for (const l of lineas) {
      const mDni = l.match(/^([A-ZÁÉÍÓÚÑ\s,]+?)\s+DNI\s+([\d\.]+)/i);
      if (mDni && !nombre) {
        nombre = mDni[1].trim();
        dni = mDni[2].replace(/\./g, '');
      }
      const mCuil = l.match(/(\d{2}-\d{8}-\d)/);
      if (mCuil && !cuil) cuil = mCuil[1];
      const mPer = l.match(/(Enero|Febrero|Marzo|Abril|Mayo|Junio|Julio|Agosto|Septiembre|Octubre|Noviembre|Diciembre)\s+(\d{4})/i);
      if (mPer && !periodo) {
        const mes = {Enero:1,Febrero:2,Marzo:3,Abril:4,Mayo:5,Junio:6,Julio:7,Agosto:8,Septiembre:9,Octubre:10,Noviembre:11,Diciembre:12}[mPer[1]];
        periodo = `${mPer[2]}-${String(mes).padStart(2,'0')}`;
      }
    }

    // ─── Conceptos: líneas tipo "Sueldo Básico 0001    30,00    1112876,00"
    // Patrón flexible: el código va al principio o al final del nombre, los importes son la última o las últimas dos columnas con coma decimal.
    const conceptos = [];
    // Greedy en el nombre para que el codigo sea el ULTIMO grupo de 4 digitos antes del importe
    // (sino "Suma fija no rem 2025 0490" matcheaba 2025 como codigo).
    const reLinea = /^(.+)\s+(\d{4})\s+([\d\.,]+)(?:\s+([\d\.,]+))?(?:\s+([\d\.,]+))?\s*$/;
    for (const l of lineas) {
      const m = l.match(reLinea);
      if (!m) continue;
      const nombre_c = m[1].trim();
      const codigo = m[2];
      // Los importes pueden estar en 1, 2 o 3 columnas. El último es el importe del concepto.
      const cols = [m[3], m[4], m[5]].filter(Boolean);
      if (cols.length === 0) continue;
      const importe = parseImporte(cols[cols.length - 1]);
      if (!isFinite(importe) || importe <= 0) continue;
      conceptos.push({ codigo, nombre: nombre_c, importe });
    }

    // ─── Totales: buscar "TOTAL NETO" y la línea "Son pesos ..."
    let neto = null, rem = null, desc = null;
    for (const l of lineas) {
      const mSon = l.match(/Son\s+pesos.+?_([\d\.,\s]+)$/i);
      if (mSon) {
        // El "Son pesos..." termina con los totales: rem, desc
        const nums = (mSon[1].match(/[\d\.,]+/g) || []).map(parseImporte).filter(n => isFinite(n));
        if (nums.length >= 2) { rem = nums[0]; desc = nums[1]; }
        if (nums.length >= 3) neto = nums[2];
      }
    }
    if (neto == null) {
      // Buscar línea aislada con monto grande después de "TOTAL NETO"
      for (let i = 0; i < lineas.length - 1; i++) {
        if (/total\s+neto/i.test(lineas[i])) {
          const next = lineas[i+1] || '';
          const n = parseImporte(next);
          if (isFinite(n) && n > 0) { neto = n; break; }
        }
      }
    }

    return {
      ok: true,
      empleado: { nombre, dni, cuil, categoria },
      periodo,
      conceptos,
      totales: { remuneraciones: rem, descuentos: desc, neto },
    };
  }

  function parseImporte(s) {
    if (typeof s === 'number') return s;
    if (!s) return NaN;
    // Formato AR: 1.234.567,89 → quitar puntos, coma a punto
    const limpio = String(s).replace(/\s/g, '').replace(/\./g, '').replace(',', '.');
    return Number(limpio);
  }

  /**
   * Valida un parsed-pdf contra los totales calculados por salaryEngine.
   * Devuelve un array de discrepancias [{ concepto, esperado, declarado, diff, severity }].
   */
  function validar(parsedPdf, calculo, opts = {}) {
    const tolerancia = opts.tolerancia ?? 1.0;  // $1 de tolerancia por redondeo
    const discrepancias = [];

    // Sumar por campo del salaryEngine los importes del PDF
    const declarado = {
      basico: 0, antiguedad: 0, presentismo: 0,
      sumafija_nr: 0, ant_nr: 0, pres_nr: 0, recompos_nr: 0, otros_rem: 0,
      jubilacion: 0, ley19032: 0, sec: 0, faecys: 0, obra_social: 0,
    };
    const sinMatch = [];
    for (const c of parsedPdf.conceptos) {
      const regla = matchearConcepto(c.nombre);
      if (!regla || !(regla.campo in declarado)) {
        sinMatch.push(c);
        continue;
      }
      declarado[regla.campo] += c.importe;
    }

    // Comparar campo por campo
    const labels = {
      basico: 'Sueldo Básico', antiguedad: 'Antigüedad', presentismo: 'Presentismo',
      sumafija_nr: 'Suma fija no rem', ant_nr: 'Antig no rem', pres_nr: 'Presentismo no rem',
      recompos_nr: 'Recompos no rem', otros_rem: 'Otros remunerativos',
      jubilacion: 'Jubilación 11%', ley19032: 'Ley 19032 (3%)',
      sec: 'SEC (2%)', faecys: 'FAECYS (0.5%)', obra_social: 'Obra Social (3%)',
    };
    for (const k of Object.keys(declarado)) {
      const esperado = Math.round((calculo[k] || 0) * 100) / 100;
      const decl = Math.round(declarado[k] * 100) / 100;
      if (Math.abs(esperado - decl) > tolerancia) {
        discrepancias.push({
          concepto: labels[k] || k,
          campo: k,
          esperado, declarado: decl,
          diff: decl - esperado,
          severity: (decl > esperado && k !== 'jubilacion' && k !== 'ley19032' && k !== 'obra_social' && k !== 'sec' && k !== 'faecys') ? 'info' : 'warn',
        });
      }
    }

    // Comparar TOTAL NETO si lo tenemos
    if (parsedPdf.totales.neto != null && calculo.neto != null) {
      const diffNeto = parsedPdf.totales.neto - calculo.neto;
      if (Math.abs(diffNeto) > tolerancia) {
        discrepancias.push({
          concepto: 'TOTAL NETO',
          campo: 'neto',
          esperado: Math.round(calculo.neto * 100) / 100,
          declarado: parsedPdf.totales.neto,
          diff: diffNeto,
          severity: diffNeto < 0 ? 'error' : 'info',
        });
      }
    }

    return { discrepancias, sinMatch };
  }

  return { parsear, validar, normalizar, parseImporte };
})();

// ═══════════════════════════════════════════════════════════════════════
//  UI: Modal drag&drop para subir varios recibos MEMOSOFT a la vez
// ═══════════════════════════════════════════════════════════════════════
