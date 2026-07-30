// ═══════════════════════════════════════════════════════════════════════
//  RRHH Adorno · vacaciones-pdf.js
//  PDF de notificación de vacaciones (Architects Daughter, fechas largas).
//  Extraído de index.html el 30-jul-2026 (modularización, Fase 2).
//  Se carga después del script principal; nada de esto corre al arrancar.
// ═══════════════════════════════════════════════════════════════════════

const MESES_ES = ['enero','febrero','marzo','abril','mayo','junio',
                  'julio','agosto','septiembre','octubre','noviembre','diciembre'];

function _fechaLargaEs(ymd) {
  if (!ymd) return '';
  const d = new Date(ymd + 'T12:00:00');
  return `${d.getDate()} de ${MESES_ES[d.getMonth()]} de ${d.getFullYear()}`;
}

function _diaSiguiente(ymd) {
  const d = new Date(ymd + 'T12:00:00');
  d.setDate(d.getDate() + 1);
  return d.toISOString().split('T')[0];
}

// Calcula el próximo día de REINTEGRO a vacaciones.
// - Locales (alcorta/unicenter): trabajan todos los días → día siguiente literal
// - Oficina (Don Torcuato): no trabaja sáb/dom ni feriados que cierran oficina
//   → saltar al próximo día hábil
async function _proximoDiaReintegro(ymd, local) {
  let d = new Date(ymd + 'T12:00:00');
  d.setDate(d.getDate() + 1);
  if (local !== 'oficina') return d.toISOString().split('T')[0];

  // Para oficina: cargar feriados de los próximos 14 días que cierran oficina
  const fechaIni = d.toISOString().split('T')[0];
  const fechaFin = new Date(d); fechaFin.setDate(fechaFin.getDate() + 14);
  const feriadosCierra = new Set();
  try {
    const { data: fer } = await sb.from('rrhh_feriados')
      .select('fecha, cierra_oficina')
      .gte('fecha', fechaIni)
      .lte('fecha', fechaFin.toISOString().split('T')[0]);
    (fer || []).forEach(f => { if (f.cierra_oficina) feriadosCierra.add(f.fecha); });
  } catch(_) {}

  // Saltar sábado(6), domingo(0) y feriados que cierran oficina
  for (let i = 0; i < 14; i++) {
    const dow = d.getDay();
    const ymdActual = d.toISOString().split('T')[0];
    if (dow !== 0 && dow !== 6 && !feriadosCierra.has(ymdActual)) {
      return ymdActual;
    }
    d.setDate(d.getDate() + 1);
  }
  return d.toISOString().split('T')[0];  // fallback (no debería pasar)
}

// Cache para la fuente del logo (se carga una sola vez)
let _logoFontLoaded = false;
let _logoFontName = 'ArchitectsDaughter';

async function _loadLogoFont(doc) {
  // Si ya está cargada en este doc, no hacemos nada
  try {
    // Intentar usar la fuente — si ya está, no tira error
    if (doc.getFontList && doc.getFontList()[_logoFontName]) return true;
  } catch(_) {}

  try {
    // Intentar bajar el TTF desde jsdelivr (CDN allowlisted)
    // Fuente servida desde nuestro repo (fonts/), CDN como plan B — ver
    // comentario en recibos-pdf.js: la URL de jsdelivr empezó a dar 404.
    const urls = [
      './fonts/ArchitectsDaughter-Regular.ttf',
      'https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/architectsdaughter/ArchitectsDaughter-Regular.ttf',
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
    doc.addFileToVFS('ArchitectsDaughter-Regular.ttf', b64);
    doc.addFont('ArchitectsDaughter-Regular.ttf', _logoFontName, 'normal');
    _logoFontLoaded = true;
    return true;
  } catch (e) {
    console.warn('[PDF] No se pudo cargar Architects Daughter, fallback a helvetica:', e);
    return false;
  }
}

// Helper para escribir texto con letter-spacing (tracking) — emula Avant Garde
function _textTracked(doc, text, x, y, options = {}) {
  const { align = 'left', tracking = 0, fontSize = 11 } = options;
  if (tracking === 0) {
    doc.text(text, x, y, { align });
    return;
  }
  // Para emular tracking: separar letras y posicionarlas
  doc.setFontSize(fontSize);
  const chars = text.split('');
  const widths = chars.map(c => doc.getStringUnitWidth(c) * fontSize / doc.internal.scaleFactor);
  const totalWidth = widths.reduce((s,w) => s + w, 0) + (tracking * (chars.length - 1));
  let startX = x;
  if (align === 'center') startX = x - totalWidth / 2;
  else if (align === 'right') startX = x - totalWidth;
  let cursor = startX;
  chars.forEach((c, i) => {
    doc.text(c, cursor, y);
    cursor += widths[i] + tracking;
  });
}

async function generarNotificacionVacaciones(movId) {
  // Cargar movimiento + colaborador + saldo de vacaciones (para sacar el año fiscal correcto)
  const { data: mov, error } = await sb.from('rrhh_vacaciones_movimientos')
    .select('*, empleado:rrhh_empleados(nombre_completo, dni, local), saldo:rrhh_vacaciones(año)')
    .eq('id', movId).single();
  if (error || !mov) { toast('No se pudo cargar la vacación', 'error'); return; }

  const emp = mov.empleado;
  const fechaActual = _fechaLargaEs(new Date().toISOString().split('T')[0]);
  const desde = _fechaLargaEs(mov.fecha_desde);
  const hasta = _fechaLargaEs(mov.fecha_hasta);
  // Reintegro: si la colaboradora es de oficina, salta sáb/dom y feriados que cierran oficina
  // (la oficina trabaja días hábiles). Para locales (alcorta/unicenter) es el día siguiente literal.
  const reintegroYmd = await _proximoDiaReintegro(mov.fecha_hasta, emp?.local);
  const reintegro = _fechaLargaEs(reintegroYmd);
  // El año correcto es el del saldo fiscal imputado (vacaciones_id),
  // NO el de fecha_desde — la vendedora puede tomar en 2026 días pendientes de 2025.
  const año = mov.saldo?.año || mov.fecha_desde.substring(0, 4);
  const dias = mov.dias;
  const nombre = emp?.nombre_completo || '—';
  const dni = emp?.dni || '';
  const codigo = `VAC-${String(movId).padStart(5,'0')}`;

  // ─── Detectar si es PAGO (no toma) ───
  const esPago = mov.estado === 'pagada' || mov.tipo_solicitud === 'pago';

  // Colores de marca
  const COLOR_PRIMARY = [13, 148, 136];   // #0d9488 turquesa
  const COLOR_TEXT    = [30, 41, 59];     // #1e293b
  const COLOR_MUTED   = [148, 163, 184];  // #94a3b8
  const COLOR_BORDER  = [226, 232, 240];  // #e2e8f0

  // ─── Generar PDF ───
  const { jsPDF } = window.jspdf;
  const doc = new jsPDF({ unit: 'mm', format: 'a4' });
  const W = 210;
  const margen = 22;
  const ancho = W - margen * 2;

  // Cargar fuente Architects Daughter para el logo (de Google Fonts vía jsdelivr)
  const logoFontOk = await _loadLogoFont(doc);

  // ═══ HEADER ═══
  // Logo "Claudia Adorno" en Architects Daughter (si cargó OK) o helvetica (fallback)
  doc.setTextColor(...COLOR_TEXT);
  if (logoFontOk) {
    doc.setFont(_logoFontName, 'normal');
    doc.setFontSize(32);
    doc.text('Claudia Adorno', margen, 28);
  } else {
    doc.setFont('helvetica', 'bold');
    _textTracked(doc, 'Claudia Adorno', margen, 25, { tracking: 1.2, fontSize: 26 });
  }

  // Datos de empresa (derecha)
  doc.setFont('helvetica', 'normal');
  doc.setFontSize(8);
  doc.setTextColor(...COLOR_MUTED);
  doc.text('CLAUDIA ADORNO SRL', W - margen, 17, { align: 'right' });
  doc.text('CUIT 30-70967311-0', W - margen, 22, { align: 'right' });
  doc.text('Buenos Aires, Argentina', W - margen, 27, { align: 'right' });

  // Línea divisoria turquesa
  doc.setDrawColor(...COLOR_PRIMARY);
  doc.setLineWidth(0.6);
  doc.line(margen, 32, W - margen, 32);
  // Pequeño detalle decorativo
  doc.setLineWidth(1.5);
  doc.line(margen, 32, margen + 30, 32);

  // ═══ TÍTULO ═══
  doc.setFont('helvetica', 'bold');
  doc.setFontSize(15);
  doc.setTextColor(...COLOR_TEXT);
  _textTracked(doc, esPago ? 'CONFORMIDAD DE PAGO DE VACACIONES' : 'NOTIFICACIÓN DE COMIENZO DE VACACIONES', W/2, 50, {
    align: 'center', tracking: 0.5, fontSize: 13,
  });

  // Lugar y fecha
  doc.setFont('helvetica', 'normal');
  doc.setFontSize(10);
  doc.setTextColor(...COLOR_MUTED);
  doc.text(`Buenos Aires, ${fechaActual}`, W - margen, 62, { align: 'right' });

  // ═══ BOX DATOS DEL EMPLEADO ═══
  let y = 75;
  doc.setDrawColor(...COLOR_BORDER);
  doc.setFillColor(248, 250, 252); // gris muy clarito
  doc.setLineWidth(0.3);
  doc.roundedRect(margen, y, ancho, 18, 2, 2, 'FD');
  doc.setFont('helvetica', 'normal');
  doc.setFontSize(8);
  doc.setTextColor(...COLOR_MUTED);
  doc.text('EMPLEADO/A', margen + 5, y + 6);
  doc.setFont('helvetica', 'bold');
  doc.setFontSize(12);
  doc.setTextColor(...COLOR_TEXT);
  doc.text(nombre, margen + 5, y + 13);
  if (dni) {
    doc.setFont('helvetica', 'normal');
    doc.setFontSize(9);
    doc.setTextColor(...COLOR_MUTED);
    doc.text(`DNI ${dni}`, W - margen - 5, y + 13, { align: 'right' });
  }

  // ═══ CUERPO ═══
  y = 105;
  doc.setFont('helvetica', 'normal');
  doc.setFontSize(11);
  doc.setTextColor(...COLOR_TEXT);
  const cuerpo = esPago
    ? `Por la presente dejamos constancia de que, a su solicitud, se procede al pago de ${dias} día/s de vacaciones correspondientes al año ${año}, los cuales no serán gozados como descanso. El importe correspondiente se abonará junto con la próxima liquidación de haberes. Con la firma del presente, el/la trabajador/a presta su conformidad con la modalidad de pago y confirma la imputación de los días al saldo del año ${año}.`
    : `Le comunicamos que, de acuerdo con las disposiciones legales vigentes, gozará de las vacaciones correspondientes al año ${año} por el período de ${dias} día/s. Dichas vacaciones comenzarán a regir desde el día ${desde} hasta el día ${hasta}, inclusive, debiendo reintegrarse a sus tareas el día ${reintegro}.`;
  const lineas = doc.splitTextToSize(cuerpo, ancho);
  doc.text(lineas, margen, y, { lineHeightFactor: 1.7 });
  y += lineas.length * 7 + 8;

  // ═══ FIRMAS — AUTORIZANTE ═══
  y = 165;
  doc.setDrawColor(...COLOR_BORDER);
  doc.setLineWidth(0.4);
  // Bloque autorizante (izq)
  doc.line(margen, y + 14, margen + 75, y + 14);
  doc.setFont('helvetica', 'italic');
  doc.setFontSize(9);
  doc.setTextColor(...COLOR_MUTED);
  doc.text('Firma del autorizante', margen + 37.5, y + 19, { align: 'center' });

  // Línea de aclaración autorizante
  doc.line(margen, y + 32, margen + 75, y + 32);
  doc.text('Aclaración', margen + 37.5, y + 37, { align: 'center' });

  // ═══ DECLARACIÓN DEL TRABAJADOR ═══
  y = 215;
  doc.setFont('helvetica', 'italic');
  doc.setFontSize(10.5);
  doc.setTextColor(...COLOR_TEXT);
  doc.text('"Quedo debidamente notificado de la comunicación precedente."', W/2, y, { align: 'center' });

  // ═══ FIRMAS — TRABAJADOR ═══
  y = 230;
  doc.setLineWidth(0.4);
  doc.setDrawColor(...COLOR_BORDER);
  // Bloque trabajador (izq)
  doc.line(margen, y + 14, margen + 75, y + 14);
  doc.setFont('helvetica', 'italic');
  doc.setFontSize(9);
  doc.setTextColor(...COLOR_MUTED);
  doc.text('Firma del trabajador/a', margen + 37.5, y + 19, { align: 'center' });

  doc.line(margen, y + 32, margen + 75, y + 32);
  doc.text('Aclaración', margen + 37.5, y + 37, { align: 'center' });

  // ═══ CÓDIGO IDENTIFICADOR (esquina derecha del bloque de firmas) ═══
  doc.setDrawColor(...COLOR_PRIMARY);
  doc.setLineWidth(0.5);
  doc.roundedRect(W - margen - 60, 235, 60, 22, 2, 2, 'S');
  doc.setFont('helvetica', 'bold');
  doc.setFontSize(8);
  doc.setTextColor(...COLOR_MUTED);
  doc.text('CÓDIGO DE SEGUIMIENTO', W - margen - 30, 241, { align: 'center' });
  doc.setFont('helvetica', 'bold');
  doc.setFontSize(14);
  doc.setTextColor(...COLOR_PRIMARY);
  doc.text(codigo, W - margen - 30, 250, { align: 'center' });
  doc.setFont('helvetica', 'normal');
  doc.setFontSize(7);
  doc.setTextColor(...COLOR_MUTED);
  doc.text(`Asunto del mail: "VACACIONES ${codigo}"`, W - margen - 30, 255, { align: 'center' });

  // ═══ QR con código VAC-XXXXX (para escaneo automático cuando llega firmada) ═══
  try {
    if (typeof qrcode === 'function') {
      const qr = qrcode(0, 'M');  // tipo 0 (auto), corrección media
      qr.addData(codigo);
      qr.make();
      const qrDataUrl = qr.createDataURL(4, 0);
      // 22mm × 22mm en esquina inferior izquierda
      const qrSize = 22;
      const qrX = margen;
      const qrY = 260;
      doc.addImage(qrDataUrl, 'PNG', qrX, qrY, qrSize, qrSize);
      doc.setFont('helvetica', 'normal');
      doc.setFontSize(7);
      doc.setTextColor(...COLOR_MUTED);
      doc.text(codigo, qrX + qrSize + 2, qrY + qrSize - 1);
    }
  } catch (e) { console.warn('No se pudo generar QR en notif vacaciones:', e); }

  // ═══ FOOTER ═══
  doc.setDrawColor(...COLOR_BORDER);
  doc.setLineWidth(0.3);
  doc.line(margen, 283, W - margen, 283);
  doc.setFont('helvetica', 'normal');
  doc.setFontSize(7);
  doc.setTextColor(...COLOR_MUTED);
  doc.text('Una vez firmada, escaneá esta hoja y enviála a', W/2, 288, { align: 'center' });
  doc.setFont('helvetica', 'bold');
  doc.setTextColor(...COLOR_PRIMARY);
  doc.text('claudiaadornosrl@gmail.com', W/2, 291.5, { align: 'center' });
  doc.setFont('helvetica', 'normal');
  doc.setTextColor(...COLOR_MUTED);
  doc.setFontSize(6.5);
  doc.text(`Generado automáticamente · ${new Date().toLocaleString('es-AR')} · ${codigo}`, W/2, 296, { align: 'center' });

  // Nombre del archivo — formato JP: "VACACIONES AAAA NOMBRE APELLIDO - DD-MM-AAAA HASTA DD-MM-AAAA.pdf"
  // AAAA = año devengado (mov.saldo.año). Fechas en DD-MM-AAAA (no ISO).
  const _fmtDdMmAaaa = (ymd) => {
    if (!ymd || !/^\d{4}-\d{2}-\d{2}$/.test(ymd)) return ymd || '';
    const [Y, M, D] = ymd.split('-');
    return `${D}-${M}-${Y}`;
  };
  // "nombre_completo" viene como "APELLIDO, NOMBRE" o "APELLIDO NOMBRE"
  const nombreLimpio = String(nombre || 'EMPLEADO').replace(/,/g, '').trim().toUpperCase();
  const fDesde = _fmtDdMmAaaa(mov.fecha_desde);
  const fHasta = _fmtDdMmAaaa(mov.fecha_hasta);
  const fname = `VACACIONES ${año} ${nombreLimpio} - ${fDesde} HASTA ${fHasta}.pdf`;
  doc.save(fname);
  toast('✓ PDF generado y descargado', 'success');
}

// ════════════════════════════════════════════════════════════
// CARGA MASIVA DE VACACIONES (admin/gerente)
//   Permite cargar varias vacaciones de varias colaboradoras de una vez,
//   sin pasar por el flujo de aprobación. Quedan en estado='tomada'.
// ════════════════════════════════════════════════════════════
