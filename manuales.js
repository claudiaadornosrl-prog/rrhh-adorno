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
      'Sugerencias nuevas: 🌅 "entró más de 45 min antes del horario real" (revisá si fue una extra pedida) y 📅 "trabajó en su franco". Si la chica trabajó el franco y lo toma otro día, NO cargues extra: usá "⋮ Otro turno → 🔁 Trabaja este franco → trasladarlo" en ese día: elegís el nuevo día de franco y el día trabajado computa DOBLE al banco solo al cruzar el mes.',
      'Al trasladar un franco, el día destino se elige tocándolo en un calendario que muestra el turno de cada día (los francos aparecen en gris y no se pueden elegir).',
      'Entrás una sola vez: si en el Hub tildás "Confiar en esta computadora", pasás a todos los módulos sin volver a escribir la clave en ese equipo. En las computadoras de los locales no se tilda y cada módulo sigue pidiendo usuario y contraseña.',
      'Si un reloj de fichadas se desconfigura y levanta horas falsas, corregir el aparato NO arregla lo ya registrado: el sistema guarda la hora que el reloj estampó. Hay un vigía diario que lo detecta (compara los dos relojes de Alcorta entre sí, y en los tres locales avisa si todas las empleadas aparecen corridas lo mismo respecto de su turno) y le manda un aviso a JP. La corrección de las fichadas viejas la hace JP.',
      'Franco trabajado: computa DOBLE, pero se descuentan las horas reales del turno del día al que se traslada el franco (ese día no se trabaja). Ejemplo: trabajó 6 h 16 min el sábado → 12 h 32 min, menos las 6 h del miércoles que se toma = 6 h 32 min al banco. Si definís el día destino después de cruzar el mes, el próximo cruce ajusta la extra solo.',
      'El calendario muestra los francos como 🛌 Franco (y 🔁 Franco trabajado cuando lo marcaste como trasladado). Tocando una celda de franco también tenés la opción "🔁 Trabaja este franco → trasladarlo". En el horario habitual de cada chica, un día "Sin asignar" se genera como franco al armar el mes.',
      'Tope mensual de extras por local (regla JP): 1 hora por cada $10.000.000 vendidos en el mes + las horas de turno de los días en que alguien faltó, estuvo de vacaciones o con licencia. El panel verde arriba de la lista muestra cuánto queda; si te pasás, el sistema no deja cargar (pedile a JP). El admin no tiene tope.',
      'Las extras van SIEMPRE al banco de minutos. El pago en efectivo lo pide la colaboradora desde "Mi banco" recién cuando junta una semana entera de extras (sus horas semanales del legajo) y lo aprueba JP.',
      'Tardanzas — cómo funciona (dos sistemas separados): (1) ERROR de fichada: entrar pasada la tolerancia (Oficina 25 min desde el turno cargado, locales 20) quema 1 error contra el premio. (2) MINUTOS al banco: TODOS los minutos desde el horario real (turno + 15) suman a un pool mensual, haya error o no; si el pool pasa los 60 minutos en el mes, se descuenta TODO del banco al cerrar. Ejemplo: llegar 7 min tarde no quema error pero suma 7 minutos.',
      'Si una colaboradora tiene un día mal cargado (turno equivocado), click en "⋮ Otro turno" para corregirlo.',
      'Los permisos solo se pueden cargar con fecha de hoy en adelante — los de fecha pasada los carga el admin.',
      'Ajuste manual del banco (pestaña Banco → "+ Ajuste manual"): elegís primero ➕ Sumar o ➖ Restar y después los minutos SIEMPRE en positivo. Restar = se fue antes, entró más tarde, permiso que no se cargó a tiempo; Sumar = se quedó de más o vino un día que no le tocaba. Antes de guardar te muestra en rojo o verde qué le pasa al banco. Ojo: si cargás "se fue una hora antes" como Sumar, el banco SUBE en vez de bajar.',
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
      '⚠ Superposición: si en esas fechas ya hay otra persona del local de vacaciones (o pidiéndolas), el pedido aparece marcado en rojo, el push de aviso lo dice, y al aprobar el sistema pide confirmación explícita. Se puede aprobar igual, pero nunca por descuido.',
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
      '"Vigente a partir del sueldo de SEPTIEMBRE" significa que el aumento entra en la liquidación de septiembre (la que se paga a principios de octubre). El sueldo del mes anterior sale con los valores viejos.',
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
      'Activá el botón "🔔 Notificaciones" para recibir avisos (turnos, recibos, permisos). En iPhone solo funcionan si instalaste la app en la pantalla de inicio (Compartir → Agregar a pantalla de inicio). Si iOS las apaga solo, la app las reactiva automáticamente al abrirla.',
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
      'Si tu banco está en negativo, en "Mi banco" tenés el botón 🌴 para compensar con días de vacaciones. El valor del día es según tu lugar: Oficina 9,5 horas · locales 7 horas (casos especiales se ajustan a mano).',
      'La compensación queda como un movimiento de vacaciones ("⏱ Compensa banco") con su papel de conformidad para firmar — igual que una notificación de vacaciones: se imprime, se firma, se escanea y se manda por mail; el QR lo archiva solo.',
      'La encargada va a recibir el pedido y lo aprueba o rechaza.',
    ],
    img: null,
  },
  {
    tab: 'mi-banco', icon: '🏦', titulo: 'Mi banco',
    desc: 'Saldo de minutos a favor o en contra. Si te quedaste más, ganás banco; si te fuiste antes, te descuenta.',
    pasos: [
      'Tu saldo actual aparece arriba en grande.',
      'Tus horas extra se suman al banco. Cuando las extras acumuladas llegan a una semana entera de trabajo (tus horas semanales), aparece el botón "💵 Pedir pago de extras": JP lo aprueba y se te paga en efectivo con el sueldo; esos minutos se descuentan del banco.',
      'Si estás en contra (negativo), se descuenta del sueldo o de las vacaciones.',
      'Con saldo en contra aparece el botón "🌴 Compensar con días de vacaciones": elegís cuántos días de tus vacaciones pendientes usar y el sistema salda los minutos. Nunca acredita de más.',
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

// (15-sep) Sección que ve SOLO quien tiene habilitado el archivo de adelantos
// (hoy Marisa, con sus dos usuarios). No se suma al manual de todas porque el
// resto de las colaboradoras no tiene ese botón.
const MANUAL_ADELANTOS = {
  tab: 'adelantos-galicia', icon: '📊', titulo: 'Adelantos Galicia',
  desc: 'El Excel con los adelantos del mes para subir al Office Banking del Galicia.',
  pasos: [
    'El ítem 📊 "Adelantos Galicia" del menú no abre una pantalla: baja el archivo directo.',
    'Es el .xls con el formato del Office Banking (hojas "Ayuda" y "Template Liquidaciones", columnas Cuenta · Nombre · Importe · Concepto) — el mismo que sale para los sueldos. Se sube por GO → Haberes → Acreditaciones → Envío Archivo de Acreditaciones.',
    'Trae TODOS los adelantos otorgados en el mes en curso. La cuenta es la de 14 dígitos del Galicia (no el CBU) y el concepto va "01".',
    'Si a alguna colaboradora le falta la cuenta Galicia en su legajo, el sistema te lo dice ANTES de generar y te deja elegir si seguís con el resto: a esa hay que pagarle aparte.',
    'Desde administracion@ el mismo botón está adentro de 💵 Préstamos, arriba a la derecha.',
  ],
  img: null,
};

async function renderManual() {
  const isGerente = session.rol === 'gerente';
  let items = isGerente ? MANUAL_GERENTE : MANUAL_EMPLEADO;
  if (session.puedeAdelantos) items = items.concat([MANUAL_ADELANTOS]);
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
