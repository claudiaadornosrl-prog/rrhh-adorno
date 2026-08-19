// ═══════════════════════════════════════════════════════════════════════
//  RRHH Adorno · manuales.js
//  Manuales de uso para encargadas y colaboradoras (texto estático + render).
//  Extraído de index.html el 30-jul-2026 (modularización, Fase 2).
//  Se carga después del script principal; nada de esto corre al arrancar.
// ═══════════════════════════════════════════════════════════════════════

const MANUAL_GERENTE = [
  {
    tab: 'dashboard', icon: '📊', titulo: 'Mi local',
    desc: 'Vista rápida del estado del local: colaboradoras activas, próximas vacaciones, alertas y tareas pendientes.',
    pasos: [
      'Al entrar al sistema arrancás directo acá.',
      'Las tarjetas de arriba muestran los puntos críticos (vacaciones por aprobar, asistencias por cerrar, etc.).',
      'Click en cualquier tarjeta te lleva al módulo correspondiente.',
    ],
    img: null,
  },
  {
    tab: 'empleados', icon: '👥', titulo: 'Mi equipo',
    desc: 'Listado de todas las colaboradoras de tu local con datos básicos y acceso a sus legajos completos.',
    pasos: [
      'Click sobre una colaboradora abre su ficha completa.',
      'Desde la ficha podés ver datos personales, asistencias del mes, vacaciones, préstamos y más.',
      'Los datos personales no los podés modificar — eso lo hace el admin desde su panel.',
    ],
    img: null,
  },
  {
    tab: 'asistencias', icon: '🕐', titulo: 'Asistencias',
    desc: 'Control mensual de fichadas, tardanzas, faltas y permisos. Acá se cierra el mes.',
    pasos: [
      'Antes de cerrar el mes, revisá el "Resumen mensual" — listado por colaboradora con sus errores.',
      'El panel de sugerencias compara fichadas contra turnos y permisos: si detecta una extra, la cargás con "✔ Cargar extra" (podés ajustar los minutos); si algo no corresponde, "Ignorar".',
      'Importante: las horas extra ya NO van solas al banco de minutos al cerrar el mes — solo entran las que cargás vos con el botón de extras o desde las sugerencias.',
      'Si una colaboradora tiene un día mal cargado (turno equivocado), click en "⋮ Otro turno" para corregirlo.',
      'Los permisos solo se pueden cargar con fecha de hoy en adelante — los de fecha pasada los carga el admin.',
      'Cuando todo está OK, apretás el botón rojo "🔒 Cerrar mes" — esto materializa el banco de minutos y aplica las cuotas de préstamo.',
      'Importante: una vez cerrado, las modificaciones quedan registradas con aviso.',
    ],
    img: null,
  },
  {
    tab: 'vacaciones', icon: '🌴', titulo: 'Vacaciones',
    desc: 'Saldos de vacaciones por empleada, aprobar pedidos y registrar tomas de vacaciones.',
    pasos: [
      'La tab "Saldos" muestra todas tus colaboradoras con días correspondientes / tomados / pendientes.',
      'Click en una colaboradora abre el detalle con los movimientos del año + botón para descargar PDF de cada uno.',
      'En "Pendientes" aprobás o rechazás los pedidos que mandaron las vendedoras.',
      'Botón "+ Asignar vacaciones" carga directo (sin pasar por aprobación).',
    ],
    img: null,
  },
  {
    tab: 'retiros', icon: '🛍', titulo: 'Retiros mercadería',
    desc: 'Cargás los retiros de mercadería de las colaboradoras que se descuentan en la liquidación.',
    pasos: [
      'Cargás monto y colaboradora → queda registrado.',
      'En el cierre del mes, el monto se descuenta del Efectivo final.',
    ],
    img: null,
  },
  {
    tab: 'aumentos', icon: '📈', titulo: 'Aumentos',
    desc: 'Cuando JP envía rangos de aumento mensual, vos definís el monto exacto para cada colaboradora dentro del rango.',
    pasos: [
      'Vas a recibir un push cuando JP envíe los rangos.',
      'En la tabla cargás el monto del nuevo fijo de cada colaboradora (dentro del rango).',
      'Para tu propia fila viene pre-marcado el MAX del rango.',
      'Click "💾 Aplicar aumentos" — se actualizan los fijos vigentes desde el período del envío.',
    ],
    img: null,
  },
  {
    tab: 'prestamos', icon: '💵', titulo: 'Préstamos',
    desc: 'Vista solo lectura de los préstamos activos del equipo. Para otorgar, refinanciar o cancelar contactá al admin.',
    pasos: [
      'KPIs arriba: cantidad de préstamos, capital total, saldo pendiente, interés pendiente.',
      'Tabla por colaboradora con detalle de cada préstamo activo.',
      'Para gestionar préstamos, las acciones las hace el admin.',
    ],
    img: null,
  },
  {
    tab: 'liquidaciones', icon: '🧮', titulo: 'Liquidación',
    desc: 'Cálculo final del recibo de cada colaboradora — fijo + comisión + premio + viáticos + extras.',
    pasos: [
      'Solo lectura para vos — el cálculo lo hace el admin.',
      'Click en la celda amarilla "Recibo" para ver el desglose completo del recibo CCT.',
      'Click sobre los íconos de Acciones para descargar el PDF de cada recibo.',
    ],
    img: null,
  },
];

const MANUAL_EMPLEADO = [
  {
    tab: 'mi-calendario', icon: '📅', titulo: 'Mi calendario',
    desc: 'Vista mensual de tus turnos planificados, vacaciones, feriados y fichadas reales.',
    pasos: [
      'Cada día muestra el turno asignado, el horario y los iconitos de fichada (entrada / salida).',
      'Si ves un día rojo con "💰 Compensar falta" significa que tenés una falta sin justificar.',
      'Click en "💰 Compensar falta" para pedir que se descuente de tu banco de minutos o de tus vacaciones.',
    ],
    img: null,
  },
  {
    tab: 'mi-legajo', icon: '👤', titulo: 'Mi legajo',
    desc: 'Tus datos personales, CUIL, dirección, contacto. Editás vos sin pasar por la encargada.',
    pasos: [
      'Cargá tu CBU para que te transfiramos el sueldo directo al banco.',
      'Mantené tus datos de contacto al día por si necesitamos comunicarnos.',
      'Activá el botón "🔔 Notificaciones" para recibir avisos (turnos, recibos, permisos). En iPhone solo funcionan si instalaste la app en la pantalla de inicio (Compartir → Agregar a pantalla de inicio).',
      'Si querés cambiar nombre o datos legales, avisá a la encargada.',
    ],
    img: null,
  },
  {
    tab: 'mis-recibos', icon: '💰', titulo: 'Mis recibos',
    desc: 'Acá ves los recibos de sueldo de cada mes para descargar, firmar y devolver.',
    pasos: [
      'Click "📄 Descargar" para bajar el PDF.',
      'Imprimilo y firmalo, escanealo y reenvialo al mail que figura abajo (claudiaadornosrl@gmail.com).',
      'El sistema identifica el recibo por el código QR del PDF — mandá el escaneo completo y legible, sin cortar el QR.',
      'Si el QR no se pudo leer, te llega un mail automático pidiendo rehacer el escaneo.',
      'El sistema lo va a procesar automático y vas a ver "✓ Firmada" cuando esté guardado.',
    ],
    img: null,
  },
  {
    tab: 'mis-vacaciones', icon: '🌴', titulo: 'Mis vacaciones',
    desc: 'Saldo de tus días de vacaciones + pedir tomarlas o cobrarlas.',
    pasos: [
      'Arriba ves cuántos días tenés disponibles.',
      'Click "+ Pedir vacaciones" para solicitar días.',
      'También podés pedir que se te paguen días sin tomarlos (botón "💵 Solicitar pago").',
      'Todo lo que pidas queda pendiente hasta que la encargada apruebe.',
    ],
    img: null,
  },
  {
    tab: 'mis-permisos', icon: '🙋', titulo: 'Mis permisos',
    desc: 'Pedís permisos puntuales (retirarte antes, llegar tarde, día completo, salir y volver).',
    pasos: [
      'Click "+ Pedir nuevo permiso" → elegís fecha (desde hoy en adelante), tipo y motivo.',
      'Podés elegir cómo compensarlo: banco de minutos, días de vacaciones, o sin compensar (te descuenta del sueldo).',
      'La encargada va a recibir el pedido y lo aprueba o rechaza.',
    ],
    img: null,
  },
  {
    tab: 'mi-banco', icon: '🏦', titulo: 'Mi banco',
    desc: 'Saldo de minutos a favor o en contra. Si te quedaste más, ganás banco; si te fuiste antes, te descuenta.',
    pasos: [
      'Tu saldo actual aparece arriba en grande.',
      'Si tenés muchos minutos a favor podés pedir días extra de vacaciones o que se te paguen.',
      'Si estás en contra (negativo), se descuenta del sueldo o de las vacaciones.',
      'Los movimientos pendientes aparecen en amarillo hasta que la encargada cierra el mes.',
    ],
    img: null,
  },
  {
    tab: 'mis-prestamos', icon: '💵', titulo: 'Mis préstamos',
    desc: 'Tus préstamos activos, propuestas pendientes y la opción de pedir adelantos o refinanciaciones.',
    pasos: [
      'Si tenés un préstamo activo, ves todas las cuotas con su estado.',
      'Podés pedir un "Adelanto de sueldo" entre el 5 y 14 de cada mes (50% del neto del mes pasado, tope). El día 14 te llega un recordatorio: es el último día.',
      'Podés pedir "Refinanciar" (más capital sobre el saldo del préstamo viejo) o "Adelantar cuotas" (terminar antes).',
      'Todo queda pendiente hasta que el admin lo apruebe.',
    ],
    img: null,
  },
  {
    tab: 'mis-certif', icon: '🏥', titulo: 'Mis certificados médicos',
    desc: 'Subís tus certificados médicos cuando faltaste por enfermedad.',
    pasos: [
      'Click "+ Subir certificado" → adjuntás foto/PDF + fechas.',
      'La encargada lo revisa y aprueba.',
      'Los días cubiertos por certificado no se descuentan de tu sueldo.',
    ],
    img: null,
  },
  {
    tab: 'buzon', icon: '✉️', titulo: 'Buzón anónimo',
    desc: 'Reportar algo a JP de forma confidencial — sugerencias, problemas, denuncias.',
    pasos: [
      'Escribí tu mensaje libremente.',
      'No se registra tu nombre ni email — es 100% anónimo.',
      'JP lo recibe y puede tomar acciones sin saber quién lo envió.',
    ],
    img: null,
  },
];

async function renderManual() {
  const isGerente = session.rol === 'gerente';
  const items = isGerente ? MANUAL_GERENTE : MANUAL_EMPLEADO;
  const tituloRol = isGerente ? 'Manual de la encargada' : 'Manual de la empleada';
  const subtitulo = isGerente
    ? 'Guía rápida de cada herramienta del sistema. Click en una sección para ir directo.'
    : 'Guía rápida para usar el sistema. Click en una sección para ir directo a la herramienta.';

  return `
    <div class="page-header">
      <h2>📖 ${tituloRol}</h2>
      <div class="subtitle">${subtitulo}</div>
    </div>

    <div class="card" style="background:#eff6ff;border-left:4px solid #3b82f6;padding:14px;margin-bottom:18px;">
      <div style="font-size:13px;color:#1e40af;">
        💡 <strong>Tip:</strong> Este manual se actualiza cuando cambia el sistema.
        Si una herramienta nueva o un cambio no figura acá, escribilo en el Buzón anónimo
        para que lo agreguemos.
      </div>
    </div>

    <div style="display:grid;gap:18px;">
      ${items.map((s, i) => `
        <div class="card" style="padding:0;overflow:hidden;border-left:4px solid #0d9488;">
          <div style="padding:18px 22px;background:linear-gradient(135deg, #f0fdfa, #ccfbf1);display:flex;align-items:center;gap:14px;cursor:pointer;" onclick="switchTab('${s.tab}')">
            <div style="font-size:36px;">${s.icon}</div>
            <div style="flex:1;">
              <h3 style="margin:0 0 4px;font-size:18px;color:#065f46;">${i+1}. ${escapeHtml(s.titulo)}</h3>
              <div style="font-size:13px;color:#065f46;">${escapeHtml(s.desc)}</div>
            </div>
            <button class="btn small" style="background:white;border:1px solid #0d9488;color:#0d9488;">Ir →</button>
          </div>
          <div style="padding:18px 22px;">
            <div style="font-size:13px;font-weight:600;color:var(--text);margin-bottom:8px;">¿Cómo se usa?</div>
            <ol style="margin:0 0 14px 18px;padding:0;color:var(--text);font-size:13px;line-height:1.7;">
              ${s.pasos.map(p => `<li>${escapeHtml(p)}</li>`).join('')}
            </ol>
            ${s.img ? `
              <div style="margin-top:14px;border:1px solid var(--border);border-radius:8px;overflow:hidden;">
                <img src="${escapeHtml(s.img)}" alt="${escapeHtml(s.titulo)}" style="width:100%;display:block;">
              </div>
            ` : `
              <div style="margin-top:14px;background:#f9fafb;border:1px dashed var(--border);border-radius:8px;padding:30px;text-align:center;color:var(--muted);font-size:12px;">
                📷 Imagen pendiente
              </div>
            `}
          </div>
        </div>
      `).join('')}
    </div>

    <div class="card" style="margin-top:20px;background:#fef3c7;border-left:4px solid #d97706;padding:14px;">
      <div style="font-size:13px;color:#92400e;">
        ❓ <strong>¿Algo no funciona o te falta una herramienta?</strong><br>
        Mandá un mensaje desde el Buzón anónimo o avisale directo a JP.
        Cuando se agregue/modifique algo en el sistema, este manual se va a actualizar.
      </div>
    </div>
  `;
}
