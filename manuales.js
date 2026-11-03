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
      'En tablet o celular no hay mouse: dejá el dedo apoyado sobre cualquier ícono (medio segundo) y aparece una pastilla con su nombre, sin ejecutar nada; si sin levantar el dedo lo arrastrás a otro ícono, la pastilla cambia al nombre de ese. Con un toque normal se ejecuta.',
      'Las tarjetas de arriba muestran los puntos críticos (vacaciones por aprobar, asistencias por cerrar, etc.).',
      'Click en cualquier tarjeta te lleva al módulo correspondiente.',
      'Las monedas de arriba giran al pasar el mouse y, al tocarlas, muestran el detalle (cumpleaños, aniversarios, préstamos activos, retiros del mes).',
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
      'El panel de sugerencias compara fichadas contra turnos y permisos: si detecta una extra, la cargás con "✔ Cargar extra" (podés ajustar los minutos). OJO con "✖ Ignorar" en "llegó tarde" o "se retiró antes": ignorar NO perdona nada, esos minutos quedan para el cierre y, si el mes pasa de 60 min, se descuentan del banco. Si la salida estaba autorizada, cargá el permiso; si fue un cambio de turno, corregí el turno.',
      'Importante: las horas extra ya NO van solas al banco de minutos al cerrar el mes — solo entran las que cargás vos con el botón de extras o desde las sugerencias.',
      'Sugerencias nuevas: 🌅 "entró más de 45 min antes del horario real" (revisá si fue una extra pedida) y 📅 "trabajó en su franco". Si la chica trabajó el franco y lo toma otro día, NO cargues extra: usá "⋮ Otro turno → 🔁 Trabaja este franco → trasladarlo" en ese día: elegís el nuevo día de franco y el día trabajado computa DOBLE al banco solo al cruzar el mes.',
      '🔄 "¿Fue cambio de turno?": aparece cuando alguien entró antes y se fue antes (o entró tarde y se fue tarde) más o menos lo mismo, trabajando el turno completo. Ejemplo: el turno cargado era 12:45 a 19:00 y fichó 10:02 a 16:02. Si fue un cambio de turno, apretá "🔄 Fue cambio de turno": el turno de ese día pasa al horario que trabajó, se recalcula el mes y el día queda en regla. Si lo ignorás, al cierre se cuenta como salida temprana o llegada tarde.',
      'Al trasladar un franco, el día destino se elige tocándolo en un calendario que muestra el turno de cada día (los francos aparecen en gris y no se pueden elegir).',
      'Entrás una sola vez: si en el Hub tildás "Confiar en esta computadora", pasás a todos los módulos sin volver a escribir la clave en ese equipo. En las computadoras de los locales no se tilda y cada módulo sigue pidiendo usuario y contraseña.',
      'Si un reloj de fichadas se desconfigura y levanta horas falsas, corregir el aparato NO arregla lo ya registrado: el sistema guarda la hora que el reloj estampó. Hay un vigía diario que lo detecta (compara los dos relojes de Alcorta entre sí, y en los tres locales avisa si todas las empleadas aparecen corridas lo mismo respecto de su turno) y le manda un aviso a JP. La corrección de las fichadas viejas la hace JP.',
      'Franco trabajado: computa DOBLE, pero se descuentan las horas reales del turno del día al que se traslada el franco (ese día no se trabaja). Ejemplo: trabajó 6 h 16 min el sábado → 12 h 32 min, menos las 6 h del miércoles que se toma = 6 h 32 min al banco. Si definís el día destino después de cruzar el mes, el próximo cruce ajusta la extra solo.',
      'El calendario muestra los francos como 🛌 Franco (y 🔁 Franco trabajado cuando lo marcaste como trasladado). Tocando una celda de franco también tenés la opción "🔁 Trabaja este franco → trasladarlo". En el horario habitual de cada chica, un día "Sin asignar" se genera como franco al armar el mes.',
      'Tope mensual de extras por local (regla JP): 1 hora por cada $10.000.000 vendidos en el mes + las horas de turno de los días en que alguien faltó, estuvo de vacaciones o con licencia. El panel verde arriba de la lista muestra cuánto queda; si te pasás, el sistema no deja cargar (pedile a JP). El admin no tiene tope.',
      'Las extras van SIEMPRE al banco de minutos. El pago en efectivo lo pide la colaboradora desde "Mi banco" recién cuando junta una semana entera de extras (sus horas semanales del legajo) y lo aprueba JP.',
      'Tardanzas — cómo funciona (dos sistemas separados): (1) ERROR de fichada: entrar pasada la tolerancia (Oficina 25 min desde el turno cargado, locales 20) quema 1 error contra el premio. (2) MINUTOS al banco: TODOS los minutos desde el horario real (turno + 15) suman a un pool mensual, haya error o no; si el pool pasa los 60 minutos en el mes, se descuenta TODO del banco al cerrar. Ejemplo: llegar 7 min tarde no quema error pero suma 7 minutos. Las salidas tempranas (irse más de 5 min antes del fin del turno) suman al mismo acumulado. En el Resumen mensual, la columna "Al cierre" muestra ese acumulado de cada colaboradora: en rojo lo que se va a descontar, en gris lo que no llega a 60. Si ese día ya le descontaste minutos a mano con un ajuste, el cierre no los vuelve a cobrar.',
      'Si una colaboradora tiene un día mal cargado (turno equivocado), click en "⋮ Otro turno" para corregirlo.',
      'Los permisos solo se pueden cargar con fecha de hoy en adelante — los de fecha pasada los carga el admin.',
      'Ajuste manual del banco (pestaña Banco → "+ Ajuste manual"): elegís primero ➕ Sumar o ➖ Restar y después los minutos SIEMPRE en positivo. Restar = se fue antes, entró más tarde, permiso que no se cargó a tiempo; Sumar = se quedó de más o vino un día que no le tocaba. Antes de guardar te muestra en rojo o verde qué le pasa al banco. Ojo: si cargás "se fue una hora antes" como Sumar, el banco SUBE en vez de bajar.',
      'Corregir un ajuste manual: en Banco, tocá la colaboradora y en la fila del ajuste (🔧 Ajuste manual) apretá ✏️. Cambiás Sumar/Restar, minutos y motivo; al guardar, a la colaboradora le llega una notificación con el cambio y su saldo nuevo — siempre, no se puede corregir en silencio. El ajuste queda marcado "✏️ editado" con lo que decía antes. Solo se editan los ajustes manuales: lo que genera el sistema (cierre de mes, extras del cruce, permisos) no.',
      'Cuando todo está OK, apretás el botón rojo "🔒 Cerrar mes" — esto materializa el banco de minutos y aplica las cuotas de préstamo. Antes de cerrar te muestra a quién se le van a descontar minutos y por qué días: si alguno fue un cambio de turno o una salida autorizada, cancelá y corregilo primero.',
      'Importante: una vez cerrado, las modificaciones quedan registradas con aviso.',
      'Asistencias arranca en el último mes que te falta cerrar; cuando lo cerrás pasa al mes actual. Las pestañas son solo íconos: pasá el mouse para ver el nombre.',
      'Permisos: no se puede cargar uno que se pise con otro del mismo día (mismo horario, o mismo tipo sin horario). Si es otro horario, la app avisa y te pide confirmar. Un permiso aprobado de hoy o ayer lo puede corregir la propia colaboradora (vuelve a pendiente y te avisa).',
      'Cuando se carga un retiro de mercadería de alguien de tu local (del sync de Dragonfish o a mano), te llega un push con el nombre y el importe.',
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
      'El cálculo lo hace el admin; vos lo ves, descargás los recibos y cerrás el mes de sueldos de tu local cuando los papeles ya están firmados.',
      'Arriba, al lado de la búsqueda, cada local muestra su cierre con íconos: el reloj es Asistencias y el candado es el mes de sueldos. En naranja está abierto y en verde, cerrado. Pasá el mouse por encima (en el celular, tocalo) para ver qué significa.',
      'Si las asistencias del local siguen abiertas aparece una flecha: te lleva directo al Resumen mensual de Asistencias de ese local y ese mes, donde se cierra el mes.',
      'Click en la celda amarilla "Recibo" para ver el desglose completo del recibo CCT.',
      'Click sobre los íconos de Acciones para descargar el PDF de cada recibo. En Acciones: candado (mes abierto 🔓 / cerrado 🔒), firma (✍️ falta firmar · 🖋️ firmada) y 🖨️ imprime todos los recibos.',
      '🔒 Cerrar el mes de sueldos de tu local (desde el 3-nov-2026): en la pestaña Sueldo, cuando los recibos ya se firmaron y mandaron, tocá el candado 🔒 de la barra. El sistema controla que haya ventas, que las asistencias del local estén cerradas y que se haya respondido el aumento si lo hubo; te pide confirmar y una observación opcional. Al cerrar: las liquidaciones quedan firmadas, se aplican las cuotas de préstamo del mes, se pre-cargan los borradores del mes siguiente y se publica el resumen "Mi sueldo" a cada colaboradora con su push. Si alguna liquidación no se pudo firmar te lo dice; avisale a JP. Reabrir un mes cerrado es solo de JP.',
      'Cuando se cierra el mes de sueldos, cada colaboradora recibe un push y puede abrir una sola vez su resumen (pestaña "Mi sueldo"): solo iniciales y números, sin nombre ni empresa. Vos también lo tenés.',
      'En SEPTIEMBRE el recibo trae el "Día del Gremio" (26/9, Día del Empleado de Comercio): el básico va por 29 días y se suma 1 día pagado como básico ÷ 25. Lo calcula solo el sistema, igual que el estudio.',
      '👤 Personal eventual (Nora): aparece en la grilla con el chip "eventual", una fila por cada local donde cubrió ese mes. No se liquida acá: sale de los recibos que la encargada carga en Tesorería con la categoría "Pago Nora", según los DÍAS que cubre cada recibo (no la fecha de pago) y la caja que pagó. Suma al Total (costo del mes) pero no al Efectivo, porque ya se le pagó en mano. Click en el nombre → los recibos del mes, con ✏️ para corregir los días.',
    ],
    img: null,
  },
];


// (3-nov-2026, JP) Manual del ADMIN (JP). Antes el admin usaba el de la encargada y Clodi no sabía responder sobre
// préstamos/adelantos, Liquidación, Aumentos, Usuarios, etc. Clodi toma este texto cuando el rol es admin.
const MANUAL_ADMIN = [
  {
    tab: 'dashboard', icon: '📊', titulo: 'Dashboard',
    desc: 'Pantalla de inicio: monedas con los números del mes y las listas "Para hacer" y "Para saber".',
    pasos: [
      'En tablet o celular no hay mouse: dejá el dedo apoyado sobre cualquier ícono (medio segundo) y aparece una pastilla con su nombre, sin ejecutar nada; si sin levantar el dedo lo arrastrás a otro ícono, la pastilla cambia al nombre de ese. Con un toque normal se ejecuta.',
      'Las monedas giran al pasar el mouse y al tocarlas abren el detalle debajo: colaboradores por local, cumpleaños y aniversarios del mes, próximo feriado, quién está de vacaciones hoy, préstamos activos (con capital y lista) y retiros de mercadería del mes (del último mes sin cerrar).',
      '"🚨 Para hacer" junta lo pendiente: vacaciones y permisos por aprobar, pagos de vacaciones, meses sin cerrar, documentos sin firmar, quién puede perder el premio, tardanzas de más de 60 minutos, lactancias por vencer, solicitudes de borrado y de préstamos/adelantos. Click en cada tarjeta te lleva al lugar.',
      '"ℹ️ Para saber" es informativo: cumpleaños y aniversarios de la semana, quién está o pidió vacaciones y quién lleva más de 30 días sin tomar.',
      '"🔔 Novedades" son avisos que quedan hasta que los tocás (desaparecen al abrirlos).',
    ],
    img: null,
  },
  {
    tab: 'empleados', icon: '👥', titulo: 'Colaboradores',
    desc: 'Padrón completo: legajos, categoría, local, fechas, foto (la moneda gira al pasar el mouse), documentos y configuración de sueldo de cada una.',
    pasos: [
      'Arriba a la derecha del título, ➕ da de alta un empleado nuevo. Los filtros (buscar, local, estado) van en un renglón.',
      'Click en una ficha abre el legajo completo: datos, CBU, obra social, categoría CCT, fecha de ingreso, foto, documentos y la pestaña de sueldo (fijo, comisión, premio, viáticos, modo de liquidación cct_negro o doble_blanco).',
      'Contreras y Escasany están en modo doble blanco: cobran todo por recibo; el sistema les arma el ítem 0018 Comisiones para que el neto del recibo sea el total.',
      'Desde la ficha también se da de baja o se reactiva, y se ve el historial de aumentos.',
      'Foto: en la ficha, tocá el círculo de la foto (o las iniciales) y elegí una imagen JPG, PNG o WebP de hasta 5 MB; la de WhatsApp sirve. Se ve en el padrón, en el calendario y en los avisos.',
    ],
    img: null,
  },
  {
    tab: 'liquidaciones', icon: '🧮', titulo: 'Liquidación',
    desc: 'La grilla de sueldos del mes: Sueldo (parte en efectivo) y Banco (recibo CCT). Proforma, definitivo, doble blanco, cierre del mes y publicación del resumen a las chicas.',
    pasos: [
      'Pestaña Sueldo: Fijo + Comisión + Premio + Viáticos + Feriado + Extras = Total. Recibo es el neto CCT; la celda se pinta según el estado: amarillo = proforma, naranja = definitivo sin firmar, verde = firmado y guardado, gris = sin recibo (click descarga el PDF, click derecho el desglose). Banco = Recibo − cuotas de préstamo − adelantos. Subtotal = Total − Recibo; de ahí se restan Mercadería, Intereses y Ajustes para llegar al Efectivo que va en mano.',
      'Pestaña Banco: el recibo CCT de cada una (bruto, descuentos, neto), préstamos y adelantos que salen del banco, y las acciones por fila: candado (abierto 🔓 / cerrado negro 🔒; click para reabrir una liquidación), firma (✍️ falta firmar, 🖋️ firmada con link al archivo) y ✏️ editar. Al tocar el recibo se descarga directo el PDF (Recibo_APELLIDO_AAAA-MM.pdf), en compu y en celular.',
      'Íconos de la barra (Banco): 📋 Proforma = liquidación provisoria para el banco; ✅ Definitivo = recibos finales con la escala vigente (sirve para captar cambios de escala/paritaria de último momento; NO depende de que Asistencias esté cerrada); 💎 Doble blanco = recalcula a Contreras y Escasany con el ítem 0018 (correrlo después de cerrar las asistencias de su local para que entren premio y viáticos); 🖨️ imprime todos los recibos; 📤 exporta Galicia, LSD ARCA y planilla blanca; 🔄 refresca; ⚙️ elige columnas.',
      'En el celular, los íconos de Banco están dentro del menú ⋮ (arriba a la derecha), con su nombre. Las ventas del mes se ven solo en la pestaña Sueldo.',
      'Escala CCT: el sistema la busca sola en FAECYS. Cuando el estudio liquida con otros básicos, los cargamos a mano en la escala del mes con origen "manual" y ya no se pisan ni en proforma ni en definitivo.',
      'Pestaña Sueldo, 🔒 Cerrar mes: valida ventas, asistencias y aumentos; marca las liquidaciones como firmadas, aplica las cuotas de préstamo, genera los borradores del mes siguiente y PUBLICA el resumen de sueldo a cada colaboradora (ver "Mi sueldo"). Desde el 3-nov-2026 cada encargada también puede cerrar el mes de SU local (ellas saben cuándo se firmaron y mandaron los papeles); reabrir sigue siendo solo tuyo: se vuelve a tocar el candado. El recordatorio del 5º día hábil te sigue llegando a vos si algún local quedó sin cerrar.',
      'Click en una celda de Fijo, Comisión, Premio, Viáticos, Feriado, Extras o Mercadería la edita a mano (queda en violeta como override y el recálculo no la pisa). La celda Ajustes abre el ajuste del mes: parte manual + adelantos de efectivo.',
      'Las ventas del mes se cargan arriba (o vienen del Sheets); la comisión se recalcula sola al abrir la grilla.',
      'Arriba a la izquierda cada local muestra su cierre con íconos: reloj = Asistencias, candado = mes de sueldos; naranja abierto, verde cerrado; la flecha te lleva al Resumen mensual para cerrar asistencias.',
    ],
    img: null,
  },
  {
    tab: 'mi-sueldo', icon: '🧾', titulo: 'Mi sueldo (lo que ven las chicas)',
    desc: 'Al cerrar el mes de sueldos, cada colaboradora recibe un push y puede abrir UNA sola vez un resumen anónimo de su sueldo.',
    pasos: [
      'Se publica solo al cerrar el mes con 🔒 en Liquidación › Sueldo. Le llega el push "Tu sueldo de <mes> ya está".',
      'En su menú aparece "Mi sueldo" únicamente mientras tenga un resumen sin abrir. Toca "Abrir ahora" y ve solo iniciales y números: FI fijo, CO comisión, PR premio, VI viáticos, FE feriado, EX extras, SA SAC, TO total; RE recibo, RS recibo SAC, CP cuota préstamo, AD adelantos, BA banco; SU subtotal, ME mercadería, IN interés, AJ ajustes, EF efectivo.',
      'Al cerrarlo, salir de la pestaña, cambiar de app o intentar capturar, se cierra y no se puede volver a abrir; la pestaña desaparece hasta el próximo mes. Si no lo abre, vence a las 24 horas.',
      'Si hay que reenviárselo a alguien, se vuelve a publicar desde la consola (liqPublicarResumen) o se le muestra en persona.',
    ],
    img: null,
  },
  {
    tab: 'retiros', icon: '🛍', titulo: 'Retiros de mercadería',
    desc: 'Lo que las colaboradoras se llevan del local y se descuenta del efectivo, en una o más cuotas.',
    pasos: [
      'El sync de Dragonfish trae los retiros solo; también se pueden cargar a mano con ➕. Al cargarse, le llega un push a la colaboradora y a la encargada del local.',
      'Arranca en el último mes sin cerrar de Asistencias; con el selector se cambia de mes.',
      'Monedas arriba: retiros del mes, total, pendientes de asignar (click: va al recuadro para asignarle la colaboradora) y posibles duplicados (click: va al recuadro; se descarta el que no corresponde y el par desaparece).',
      'En cada retiro se puede cambiar la cantidad de cuotas: el importe se reparte en los meses siguientes.',
    ],
    img: null,
  },
  {
    tab: 'adelantos-ef', icon: '💸', titulo: 'Adelantos de efectivo',
    desc: 'Retiros de plata o compras pagadas con la cuenta de la empresa (nafta con factura A, etc.) que se descuentan del efectivo del mes. No es una baja de sueldo.',
    pasos: [
      'La pantalla arranca filtrada en tu usuario (con el desplegable podés ver a otra colaboradora o a todas). ➕ carga un adelanto: colaboradora (por defecto vos), fecha, importe, tipo (retiro de efectivo o compra pagada por la empresa), concepto y, si querés, el comprobante.',
      'Se imputa al mes que elijas; por defecto el último mes sin cerrar.',
      'La suma del mes entra en la columna Ajustes de Liquidación y baja el Efectivo. Total, recibo y banco no cambian. En "Mi sueldo" aparece dentro de AJ.',
      'Pasando el mouse por la celda Ajustes de la grilla ves el detalle: cada adelanto con fecha, concepto e importe, y la parte manual. Click en la celda abre el ajuste para editar la parte manual. Borrar un adelanto devuelve el importe al efectivo.',
      'Si el mes de sueldos de ese local ya está cerrado (candado), el adelanto no entra: imputalo al mes siguiente o reabrí el mes.',
    ],
    img: null,
  },
  {
    tab: 'aumentos', icon: '📈', titulo: 'Aumentos',
    desc: 'Rangos para las encargadas, aumento general, aumento puntual, IPC del INDEC e histórico.',
    pasos: [
      'Izquierda, tres pastillas: 📤 Disparar rangos (las encargadas fijan el fijo de cada una dentro del rango), 💼 Aumento general (fijo y viáticos de todas) y 🎯 Aumento puntual (una sola colaboradora).',
      'Derecha, 📈 Inflación INDEC: muestra 6 meses (▾ ver 12); los meses que faltan aparecen como pendientes y se cargan escribiendo el % y guardando. "A compensar" compara la inflación acumulada contra los aumentos dados.',
      'Abajo, el histórico de envíos a encargadas y el aumento del mes.',
      '"Vigente a partir del sueldo de X" = entra en la liquidación de ese mes (que se paga a principios del siguiente).',
    ],
    img: null,
  },
  {
    tab: 'prestamos', icon: '💵', titulo: 'Préstamos y adelantos a colaboradoras',
    desc: 'Préstamos en cuotas (sistema francés) y adelantos de sueldo (1 cuota sin interés). El capital se descuenta del banco; el interés, del efectivo.',
    pasos: [
      'La lista arranca en Activos; con el filtro ves propuestos, pagados, cancelados y rechazados. Íconos a la derecha del renglón de filtros: ➕ crear préstamo, 💵 nuevo adelanto, 📊 exportar adelantos para Galicia, 🔓 activar propuestas.',
      'Préstamo: colaboradora, capital, cuotas, tasa mensual, mes de la primera cuota. Si tildás "Esperar confirmación", queda como propuesta: la colaboradora lo acepta o rechaza desde su celular y a vos te llega un push; también podés activarlo con 🔓.',
      'Adelanto de sueldo: una cuota sin interés que se descuenta del banco del mes elegido. Las chicas lo piden solas desde "Mis préstamos" entre el 5 y el 14 de cada mes (tope 50% del neto anterior) y te llega la solicitud al dashboard ("Préstamos/Adelantos pendientes").',
      'Acciones por fila: 📝 detalle y cuotas, 💸 refinanciar (sumar capital al saldo y rearmar el plan), 📌 marcar cuotas viejas como pagadas (préstamos migrados), 🚫 cancelar; en propuestas, ✏️ editar y 🗑️ borrar.',
      'Al cerrar el mes de sueldos las cuotas del mes pasan a "aplicada" y, si era la última, el préstamo queda pagado. Reabrir el mes las vuelve a pendiente.',
      '📊 Exportar Galicia adelantos: baja el .xls con los adelantos del mes para el Office Banking (cuenta de 14 dígitos, concepto 01). Marisa también lo tiene desde su usuario.',
    ],
    img: null,
  },
  {
    tab: 'asistencias', icon: '🕐', titulo: 'Asistencias',
    desc: 'Calendarios de turnos, resumen mensual, banco de minutos, permisos, extras, reportes de turno, fichadas y horarios. Un renglón: pestañas solo ícono + filtros del mes y local.',
    pasos: [
      'Arranca en el último mes sin cerrar del local que mirás (o de los tres con "Todos"); cuando están todos cerrados pasa al mes actual. Con ‹ › cambiás de mes.',
      '📅 Calendarios: turnos planificados por día; ⚡ genera el mes desde el horario habitual de cada una y 🗑️ lo limpia. Tocando un día cambiás el turno, marcás franco trabajado o compensás una falta.',
      '📊 Resumen mensual: monedas con procesados, puntuales, llegadas tarde (con minutos), ausencias, quién pierde premio y a quién se le descuenta al cierre; sugerencias de fichadas de a 3 (▾ Ver más); tabla por colaboradora con Δ banco (lo ya descontado por permisos/extras) y "Al cierre" (tardanzas + salidas tempranas sin permiso: si pasan 60 min se descuenta todo). ⚙️ procesa el mes (cruza fichadas con turnos), 🔒 cierra el mes del local o todos los pendientes, 🔓 reabre.',
      'El cierre de asistencias carga premio, viáticos, feriado y días trabajados en la liquidación de cada una. En doble blanco (Contreras/Escasany) después hay que correr 💎 para que esos conceptos entren al recibo.',
      '🏦 Banco de minutos: saldo de cada una, movimientos, ajustes manuales (➕ sumar / ➖ restar) y compensación con vacaciones. Tope −42 h.',
      '🙋 Permisos: pendientes de aprobar y cargados. Vos podés cargar con fecha pasada; las encargadas solo desde hoy. Un permiso aprobado de hoy o ayer lo puede corregir la propia colaboradora (vuelve a pendiente y te avisa). No se puede cargar un permiso que se pise con otro del mismo día (mismo horario o mismo tipo sin horario); si es otro horario, la app avisa y pide confirmar.',
      '⏰ Extras: horas extra aprobadas del mes (➕ cargar). Van al banco; el pago en efectivo lo pide la colaboradora cuando junta una semana. Tope mensual por local según ventas (el admin no tiene tope).',
      '🚩 Reportes de turno: lo que las chicas reportan desde su calendario ("me pusieron franco pero trabajé", etc.). Se resuelve cambiando el turno.',
      '🕐 Fichadas: marcas crudas de los relojes. 🕰️ Horarios: el horario habitual de cada una (base para generar el mes).',
    ],
    img: null,
  },
  {
    tab: 'vacaciones', icon: '🌴', titulo: 'Vacaciones',
    desc: 'Pendientes de aprobar, próximas, saldos por año e historial. Asignar, pagar días y carga masiva.',
    pasos: [
      'Pestañas: ⏳ Pendientes (aprobar/rechazar; avisa si se superpone con otra del local), ✅ Próximas, 🧮 Saldos (días correspondientes / tomados / pendientes por año) y 📋 Historial. Íconos: ➕ asignar directo, 💵 pagar días sin tomarlos, 📥 carga masiva.',
      'Los saldos del año se generan solos a partir de julio (cron) según la antigüedad al 31/12: menos de 5 años 14 días, 5 a 9 → 21, 10 a 19 → 28, 20 o más → 35 (Oficina en días hábiles: 10/15/20/25). Las tomas descuentan primero del año más viejo.',
      'Cada toma o pago genera su papel de conformidad para firmar; vuelve por mail con QR y queda archivado en Documentos.',
    ],
    img: null,
  },
  {
    tab: 'buzon-admin', icon: '✉️', titulo: 'Buzón anónimo',
    desc: 'Mensajes anónimos de las colaboradoras: sugerencias, problemas, denuncias.',
    pasos: [
      'Los leés acá; no se guarda quién lo mandó.',
      'Si piden una herramienta nueva o un cambio del manual, es el lugar donde lo escriben.',
    ],
    img: null,
  },
  {
    tab: 'config', icon: '⚙️', titulo: 'Configuración',
    desc: 'Usuarios y accesos, parámetros de sueldo por local, feriados, categorías CCT y escala, notificaciones.',
    pasos: [
      'Usuarios: cada fila con ✏️ editar (colaboradora vinculada, rol admin/gerente/empleado/directora, local), 🔑 setear contraseña, ⏸️/▶️ desactivar o activar, 🗑️ borrar el usuario (no borra el legajo).',
      'Roles: admin (vos) ve todo; gerente (encargada) su local; empleado su propia información; directora (Claudia) ve colaboradores y la liquidación de los meses cerrados; administracion@ solo Banco y Préstamos.',
      'Escala CCT y categorías: básicos por mes y categoría, origen faecys/estimada/manual; lo manual no se pisa.',
      'Feriados: cargar los del año (cierra oficina / shoppings) para calendarios y feriado trabajado.',
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
      'En tablet o celular no hay mouse: dejá el dedo apoyado sobre cualquier ícono (medio segundo) y aparece una pastilla con su nombre, sin ejecutar nada; si sin levantar el dedo lo arrastrás a otro ícono, la pastilla cambia al nombre de ese. Con un toque normal se ejecuta.',
      'Si ves un día rojo con "💰 Compensar falta" significa que tenés una falta sin justificar.',
      'Click en "💰 Compensar falta" para pedir que se descuente de tu banco de minutos o de tus vacaciones.',
      'Arriba a la derecha: 🙋 pedir permiso y 🚩 reportar un problema del turno (por ejemplo, te pusieron franco pero trabajaste). La encargada lo resuelve cambiando el turno.',
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
    tab: 'mi-sueldo', icon: '🧾', titulo: 'Mi sueldo',
    desc: 'Cuando se cierra el mes, podés ver UNA sola vez un resumen de tu sueldo: total, lo que va por banco y lo que va en efectivo.',
    pasos: [
      'Te llega una notificación "Tu sueldo de <mes> ya está". La pestaña "Mi sueldo" aparece en el menú solo mientras tengas un resumen sin abrir.',
      'Tocás "Abrir ahora" y lo ves una sola vez: tené papel y lápiz a mano. Al cerrarlo, salir de la pestaña o cambiar de app, desaparece hasta el próximo mes. Si no lo abrís, vence a las 24 horas.',
      'Se muestran solo iniciales y números: FI fijo, CO comisión, PR premio, VI viáticos, FE feriado, EX extras, SA SAC, TO total · RE recibo, CP cuota de préstamo, AD adelantos, BA lo que se acredita en el banco · SU subtotal, ME mercadería, IN interés, AJ ajustes, EF lo que cobrás en efectivo.',
      'Si tenés dudas con algún número, hablalo con tu encargada o con JP.',
    ],
    img: null,
  },
  {
    tab: 'mis-vacaciones', icon: '🌴', titulo: 'Mis vacaciones',
    desc: 'Saldo de tus días de vacaciones + pedir tomarlas o cobrarlas.',
    pasos: [
      'Arriba ves cuántos días tenés disponibles.',
      'Para pedir días, en la tarjeta "Solicitar vacaciones" elegí "Desde" y "Hasta" (si querés, agregá una observación) y tocá "Solicitar".',
      'Debajo de las fechas aparece cuántos días se te descuentan: en Oficina se cuentan días hábiles (de lunes a viernes, una semana son 5); en los locales, días corridos (una semana son 7).',
      'En los locales, si el pedido toma un solo día del fin de semana, el sistema te muestra cómo sumar el otro para que el finde quede completo y te pide confirmarlo.',
      'También podés pedir que se te paguen días sin tomarlos (botón "💵 Solicitar pago").',
      'Todo lo que pidas queda pendiente hasta que la encargada apruebe. Mientras está pendiente, en "Mis solicitudes" lo podés modificar o anular.',
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
      'Si llegaste antes o después de lo que pediste, podés corregir un permiso ya aprobado el mismo día o al día siguiente (botón ✏️): vuelve a pendiente y la encargada lo re-aprueba.',
      'No se puede pedir un permiso que se pise con otro que ya tenés ese día. Si es otro horario, la app te lo muestra y te pide confirmar.',
    ],
    img: null,
  },
  {
    tab: 'mi-banco', icon: '🏦', titulo: 'Mi banco',
    desc: 'Saldo de minutos a favor o en contra. Si te quedaste más, ganás banco; si te fuiste antes, te descuenta.',
    pasos: [
      'Si tu encargada te carga o corrige un ajuste manual del banco, te llega una notificación con el motivo y tu saldo nuevo, y el movimiento aparece marcado "✏️ corregido" con lo que decía antes. Si no estás de acuerdo, hablalo con ella o con JP.',
      'Tu saldo actual aparece arriba en grande.',
      'Tus horas extra se suman al banco. Cuando las extras acumuladas llegan a una semana entera de trabajo (tus horas semanales), aparece el botón "💵 Pedir pago de extras": JP lo aprueba y se te paga en efectivo con el sueldo; esos minutos se descuentan del banco.',
      'Si estás en contra (negativo), se descuenta del sueldo o de las vacaciones.',
      'Con saldo en contra aparece el botón "🌴 Compensar con días de vacaciones": elegís cuántos días de tus vacaciones pendientes usar y el sistema salda los minutos. Nunca acredita de más.',
      'Los movimientos pendientes aparecen en amarillo hasta que la encargada cierra el mes.',
      'Al cerrar el mes, si tus llegadas tarde y tus salidas antes de hora suman más de 60 minutos, se descuenta todo del banco. El movimiento se llama "Tardanzas y salidas tempranas" y dice qué días cuentan. Si alguno fue un cambio de turno, avisale a la encargada antes del cierre.',
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
      'Todo queda pendiente hasta que el admin lo apruebe. Si el admin te propone un préstamo, lo aceptás o rechazás desde acá.',
      'Cuando se carga un retiro de mercadería tuyo (del sistema de ventas o a mano) te llega un aviso con el importe; se descuenta del efectivo del mes, en una o más cuotas.',
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
  const isAdmin = session.rol === 'admin';
  const isGerente = session.rol === 'gerente' || session.rol === 'directora';
  let items = isAdmin ? MANUAL_ADMIN : (isGerente ? MANUAL_GERENTE : MANUAL_EMPLEADO);
  if (session.puedeAdelantos && !isAdmin) items = items.concat([MANUAL_ADELANTOS]);
  const tituloRol = isAdmin ? 'Manual del administrador' : (isGerente ? 'Manual de la encargada' : 'Manual de la empleada');
  const subtitulo = isGerente
    ? 'Guía rápida de cada herramienta del sistema. Click en una sección para ir directo.'
    : 'Guía rápida para usar el sistema. Click en una sección para ir directo a la herramienta.';

  return `
    <div class="page-header">
      <h2>📖 ${tituloRol}</h2>
      <div class="subtitle">${subtitulo}</div>
      <div style="display:flex;gap:8px;align-items:center;margin-top:10px;flex-wrap:wrap">
        <input type="search" id="manual-lupa" placeholder="🔍 Buscar en el manual (por ej.: vacaciones, banco, recibo)…"
          style="flex:1;min-width:220px;padding:9px 12px;border:1px solid var(--border);border-radius:9px;font-size:14px;font-family:inherit"
          oninput="clearTimeout(window._mLupaT); const v=this.value; window._mLupaT=setTimeout(()=>_mLupaFiltrar(document.getElementById('manual-grid'),'.m-card',v,document.getElementById('manual-lupa-info')),250)">
        <span id="manual-lupa-info" style="font-size:12px;color:var(--muted)"></span>
      </div>
    </div>

    <div class="card" style="background:#eff6ff;border-left:4px solid #3b82f6;padding:14px;margin-bottom:18px;">
      <div style="font-size:13px;color:#1e40af;">
        💡 <strong>Tip:</strong> Este manual se actualiza cuando cambia el sistema.
        Si una herramienta nueva o un cambio no figura acá, escribilo en el Buzón anónimo
        para que lo agreguemos.
      </div>
    </div>

    <div id="manual-grid" style="display:grid;gap:18px;">
      ${items.map((s, i) => `
        <div class="card m-card" style="padding:0;overflow:hidden;border-left:4px solid #0d9488;">
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

// ── 🔍 Lupa del manual (29-sep, pedido Contreras): busca por palabra, sin tildes ni mayúsculas.
//    Deja solo las secciones que la contienen, dentro de ellas los pasos que la contienen,
//    y resalta la palabra. Mismo bloque en todos los módulos (el de RRHH usa _mLupaFiltrar).
function _mLupaNorm(s){ return String(s).normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase(); }
function _mLupaMarcar(el, q){
  const nodos = [], w = document.createTreeWalker(el, NodeFilter.SHOW_TEXT);
  while (w.nextNode()) nodos.push(w.currentNode);
  nodos.forEach(n => {
    const t = n.nodeValue; let norm = '', mapa = [];
    for (let i = 0; i < t.length; i++){ const c = _mLupaNorm(t[i]); for (let k = 0; k < c.length; k++){ norm += c[k]; mapa.push(i); } }
    let desde = 0, pos, frag = null, ult = 0;
    while (q && (pos = norm.indexOf(q, desde)) >= 0){
      frag = frag || document.createDocumentFragment();
      const a = mapa[pos], b = mapa[pos + q.length - 1] + 1;
      if (a > ult) frag.appendChild(document.createTextNode(t.slice(ult, a)));
      const m = document.createElement('mark'); m.textContent = t.slice(a, b);
      m.style.cssText = 'background:#fde047;color:inherit;padding:0 1px;border-radius:3px'; frag.appendChild(m);
      ult = b; desde = pos + q.length;
    }
    if (frag){ if (ult < t.length) frag.appendChild(document.createTextNode(t.slice(ult))); n.parentNode.replaceChild(frag, n); }
  });
}
function _mLupaFiltrar(cont, selSec, texto, info){
  if (!cont) return;
  const q = _mLupaNorm(String(texto || '').trim());
  let vistas = 0;
  cont.querySelectorAll(selSec).forEach(sec => {
    if (sec.dataset.mOrig == null) sec.dataset.mOrig = sec.innerHTML; else sec.innerHTML = sec.dataset.mOrig;
    if (!q){ sec.style.display = ''; return; }
    const lis = [...sec.querySelectorAll('li')];
    const enLis = lis.filter(li => _mLupaNorm(li.textContent).includes(q));
    const hay = _mLupaNorm(sec.textContent).includes(q);
    sec.style.display = hay ? '' : 'none';
    if (!hay) return;
    vistas++;
    if (enLis.length) lis.forEach(li => { if (!enLis.includes(li)) li.style.display = 'none'; });
    _mLupaMarcar(sec, q);
  });
  if (info) info.textContent = !q ? '' : vistas ? `${vistas} ${vistas === 1 ? 'sección' : 'secciones'} con «${String(texto).trim()}»` : `No encontré «${String(texto).trim()}» en el manual.`;
  const primera = q && cont.querySelector('mark');
  if (primera) primera.scrollIntoView({block: 'center', behavior: 'smooth'});
}
function _manualLupa(ov){
  const head = ov && ov.querySelector('.m-head'); if (!head) return;
  head.style.flexWrap = 'wrap';
  const box = document.createElement('div');
  box.style.cssText = 'flex-basis:100%;display:flex;gap:8px;align-items:center;margin-top:8px';
  box.innerHTML = '<input type="search" placeholder="🔍 Buscar en el manual (por ej.: equivalencias, remito, echeq)…" '
    + 'style="flex:1;min-width:0;padding:8px 11px;border-radius:9px;border:none;font-size:14px;color:#0f172a;font-family:inherit">'
    + '<span class="m-lupa-info" style="font-size:12px;opacity:.9;white-space:nowrap"></span>';
  head.appendChild(box);
  const inp = box.querySelector('input'), info = box.querySelector('.m-lupa-info');
  let t = null;
  inp.addEventListener('input', () => { clearTimeout(t); t = setTimeout(() => _mLupaFiltrar(ov, '.m-sec', inp.value, info), 250); });
  inp.addEventListener('keydown', e => { if (e.key === 'Escape' && inp.value){ e.stopPropagation(); inp.value = ''; _mLupaFiltrar(ov, '.m-sec', '', info); } });
  setTimeout(() => inp.focus(), 50);
}
