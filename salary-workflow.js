const salaryWorkflow = (() => {

  // Días del mes para un periodo 'YYYY-MM'
  function diasDelMes(periodo) {
    const [y, m] = periodo.split('-').map(Number);
    return new Date(y, m, 0).getDate();
  }

  // Mapea código de OS a 'osecac' / otro (case-insensitive)
  function esOsecac(codigo) {
    return (codigo || '').toLowerCase() === 'osecac';
  }

  // Cuenta puntos del mes (tarde=1, ausente=2) excluyendo errores salvados
  async function calcularPuntosMes(empleadoId, periodo) {
    const [y, m] = periodo.split('-').map(Number);
    const desde = `${periodo}-01`;
    const hasta = `${y}-${String(m).padStart(2,'0')}-${String(diasDelMes(periodo)).padStart(2,'0')}`;
    const { data } = await sb.from('rrhh_asistencias_detalle')
      .select('estado, error_salvado')
      .eq('empleado_id', empleadoId)
      .gte('fecha', desde).lte('fecha', hasta);
    let pts = 0;
    (data || []).forEach(d => {
      if (d.error_salvado) return;
      if (d.estado === 'tarde')   pts += 1;
      if (d.estado === 'ausente') pts += 2;
    });
    return pts;
  }

  // Lee la config vigente del local al período (de rrhh_sueldo_local_config)
  async function cargarConfigLocal(local, periodo) {
    const periodoFull = periodo + '-01';
    const { data } = await sb.from('rrhh_sueldo_local_config')
      .select('*').eq('local', local).lte('vigente_desde', periodoFull)
      .order('vigente_desde', { ascending: false }).limit(1);
    return data?.[0] || null;
  }

  // Lee la config vigente de la colaboradora al período
  async function cargarConfigEmpleada(empleadoId, periodo) {
    const periodoFull = periodo + '-01';
    const { data } = await sb.from('rrhh_sueldo_empleada_config')
      .select('*').eq('empleado_id', empleadoId).lte('vigente_desde', periodoFull)
      .order('vigente_desde', { ascending: false }).limit(1);
    return data?.[0] || null;
  }

  // Lee la paritaria vigente al período
  // ══════════════════════════════════════════════════════════════════════
  //  Guardián de escala CCT (27-ago-2026)
  //  El sistema liquidaba con "la escala más reciente ANTERIOR al período":
  //  si el mes nuevo no estaba cargado, usaba la del mes anterior EN
  //  SILENCIO. Así salieron las proformas de agosto con la escala de julio
  //  (~$24.000 menos por empleada; lo detectó la comparación contra los
  //  recibos del estudio). Regla nueva: NO se liquida un mes que no tenga
  //  escala propia cargada — el sistema frena y lo dice, no adivina.
  //  Solo aplica desde abr-2026 (antes no existía la tabla de escalas).
  // ══════════════════════════════════════════════════════════════════════
  // (26-sep) La escala se busca SOLA en FAECYS cuando falta el mes (proforma o
  // definitivo), y en el definitivo se vuelve a mirar la circular si la escala
  // del mes vino de ahí (puede haber salido un acuerdo nuevo). Lo cargado a mano
  // (origen='manual', las del estudio) nunca se pisa.
  // Circuito: Edge Function rrhh-escala-faecys (lee el PDF) → RPC
  // rrhh_escala_importar (admin, valida y guarda categorías + no remunerativo).
  const _escalaMesOk = {};
  const _escalaBuscando = {};
  const _MESES_ES = ['','enero','febrero','marzo','abril','mayo','junio','julio',
                     'agosto','septiembre','octubre','noviembre','diciembre'];
  const _$ar = n => '$' + Math.round(Number(n) || 0).toLocaleString('es-AR');
  async function verificarEscalaDelMes(periodo, tipo) {
    if (periodo < '2026-04') return;                    // legacy: sin tabla
    const esDef = tipo === 'definitivo';
    const key = periodo + (esDef ? '|def' : '');
    if (_escalaMesOk[key] || (!esDef && _escalaMesOk[periodo + '|def'])) return;
    const { data } = await sb.from('rrhh_categorias_cct')
      .select('id, origen').eq('fecha_vigencia', periodo + '-01');
    const hay  = (data || []).length > 0;
    const auto = (data || []).some(r => r.origen && r.origen !== 'manual');
    // (29-oct-2026, JP) En proforma también: si la escala del mes vino de FAECYS (faecys/estimada) se
    // vuelve a mirar la circular, como mucho una vez por día por período. Octubre quedó con la escala
    // de septiembre (la circular 07/2026 "incluía" octubre) y nadie la buscó hasta el definitivo.
    // Lo manual (del estudio) nunca se pisa: eso lo garantiza la RPC.
    let recheck = false;
    if (hay && !esDef && auto) {
      const k = 'rrhh_escala_recheck_' + periodo, hoy = new Date().toISOString().slice(0, 10);
      try { recheck = localStorage.getItem(k) !== hoy; if (recheck) localStorage.setItem(k, hoy); }
      catch (_) { recheck = true; }
    }
    if (!hay || (esDef && auto) || recheck) {
      if (!_escalaBuscando[key]) _escalaBuscando[key] = _importarEscalaFaecys(periodo, tipo, hay);
      try { await _escalaBuscando[key]; } finally { delete _escalaBuscando[key]; }
    }
    await _avisarBasicosFueraEscala(periodo);
    _escalaMesOk[key] = true;
  }

  // (1-oct-2026, JP) Claudia (directora) y JP (fuera_convenio) NO salen de la escala CCT ni de
  // FAECYS: el estudio les sube el básico 1,5–2 % cuando quiere. Si el mes no tiene fila
  // propia, el motor usa la última cargada (igual que hace el estudio cuando no sube), pero
  // hay que avisarlo para cargar la del mes cuando lleguen los recibos. Solo avisa, no frena.
  async function _avisarBasicosFueraEscala(periodo) {
    // Solo al admin: las encargadas también pasan por acá al cerrar Asistencias y no
    // tienen por qué ver un aviso sobre los básicos de Claudia y JP.
    if (typeof session === 'undefined' || !session || session.rol !== 'admin') return;
    try {
      const { data } = await sb.from('rrhh_categorias_cct')
        .select('codigo, nombre, sueldo_basico, fecha_vigencia')
        .in('codigo', ['directora', 'fuera_convenio'])
        .lte('fecha_vigencia', periodo + '-01')
        .order('fecha_vigencia', { ascending: false });
      const [y, m] = periodo.split('-');
      const MES = `${_MESES_ES[Number(m)]} ${y}`;
      const faltan = [];
      ['directora', 'fuera_convenio'].forEach(cod => {
        const ult = (data || []).find(r => r.codigo === cod);
        if (!ult) { faltan.push(`• ${cod}: sin ningún básico cargado`); return; }
        if (String(ult.fecha_vigencia).slice(0, 7) !== periodo) {
          const [uy, um] = String(ult.fecha_vigencia).split('-');
          faltan.push(`• ${ult.nombre}: se usa el básico de ${_MESES_ES[Number(um)]} ${uy} (${_$ar(ult.sueldo_basico)})`);
        }
      });
      if (faltan.length) {
        alert(`⚠ Básicos de Claudia y JP para ${MES}\n\nNo salen de la escala CCT: los fija el estudio cada mes.\n` +
          faltan.join('\n') + `\n\nSi el estudio los subió, pasale los recibos a Claude para cargar los de ${MES}.`);
      }
    } catch (e) { console.warn('[avisarBasicosFueraEscala]', e); }
  }

  async function _importarEscalaFaecys(periodo, tipo, hay) {
    const [y, m] = periodo.split('-');
    const MES = `${_MESES_ES[Number(m)]} ${y}`;
    try { toast(`🔎 Buscando la escala de ${MES} en FAECYS…`); } catch (_) {}
    let r = null;
    try {
      const { data, error } = await sb.functions.invoke('rrhh-escala-faecys', { body: { periodo } });
      if (error) throw error;
      r = data;
    } catch (e) {
      if (hay) { try { toast(`⚠ No pude revisar FAECYS (${e.message || e}). Sigo con la escala cargada.`, 'warn'); } catch (_) {} return; }
      throw new Error(`No hay escala CCT para ${MES} y no pude consultar FAECYS (${e.message || e}). Probá de nuevo en un rato.`);
    }
    if (!r || !r.ok) {
      if (hay) return;                                   // definitivo: se queda con la que está
      throw new Error(`No hay escala CCT para ${MES}: FAECYS todavía no publicó una circular que incluya ese mes. ` +
        `Volvé a generar cuando salga (o pasale a Claude la escala del estudio).`);
    }
    const { data: res, error: e2 } = await sb.rpc('rrhh_escala_importar',
      { p_periodo: periodo, p_datos: r, p_modo: tipo === 'definitivo' ? 'definitivo' : 'proforma' });
    if (e2) throw new Error(`No se pudo cargar la escala de ${MES}: ${e2.message}`);
    const lineas = [];
    if (res.insertadas) lineas.push(`✓ Cargué la escala de ${MES} desde FAECYS (acuerdo ${res.acuerdo || '—'}).`);
    (res.cambios || []).forEach(c => lineas.push(`• ${c.codigo}: ${_$ar(c.antes)} → ${_$ar(c.ahora)} (cambió la circular)`));
    if (res.no_remunerativo) lineas.push(`• No remunerativo del mes: ${_$ar(res.no_remunerativo.antes)} → ${_$ar(res.no_remunerativo.ahora)}`);
    if ((res.estimadas || []).length) {
      lineas.push('', '⚠ Estas categorías no están en la circular; las estimé con el mismo % que Vendedor B. Confirmalas con el estudio:');
      res.estimadas.forEach(x => lineas.push(`• ${x.codigo}: ${_$ar(x.mes_anterior)} → ${_$ar(x.basico)} (+${String(x.pct).replace('.', ',')}%)`));
    }
    (res.avisos || []).forEach(a => lineas.push('⚠ ' + a));
    if (lineas.length) alert(lineas.join('\n') + `\n\nFuente: ${r.fuente}`);
  }

  async function cargarParitaria(periodo) {
    const periodoFull = periodo + '-01';
    const { data } = await sb.from('rrhh_paritaria_sumas_nr')
      .select('*').lte('vigente_desde', periodoFull)
      .order('vigente_desde', { ascending: false }).limit(1);
    return data?.[0] || null;
  }

  // Lee el colaborador completo + su categoría CCT vigente
  async function cargarEmpleadoCompleto(empleadoId, periodo) {
    const periodoFull = periodo + '-01';
    const { data: emp } = await sb.from('rrhh_empleados')
      .select('*, categoria:rrhh_categorias_cct(*)')
      .eq('id', empleadoId).single();
    if (!emp) return null;
    // Resolver la escala vigente al período (puede ser la actual o una con vigente_desde más reciente)
    const { data: esc } = await sb.from('rrhh_categorias_cct')
      .select('*').eq('codigo', emp.categoria?.codigo)
      .lte('fecha_vigencia', periodoFull)
      .order('fecha_vigencia', { ascending: false }).limit(1);
    if (esc?.[0]) emp.categoria = esc[0];
    return emp;
  }

  // Ventas del local del mes — fuente PRIMARIA: ventas_diarias (Dragonfish
  // real-time). Fallback: rrhh_ventas_local_mes (para meses históricos previos
  // al módulo Ventas o carga manual).
  async function cargarVentasLocalMes(local, periodo) {
    // 1) Sumar de ventas_diarias
    const [py, pm] = periodo.split('-').map(Number);
    const desdeF = `${periodo}-01`;
    const hastaFExcl = (pm === 12)
      ? `${py+1}-01-01`
      : `${py}-${String(pm+1).padStart(2,'0')}-01`;
    try {
      const { data: diarias } = await sb.from('ventas_diarias')
        .select('efectivo, tarjeta, qr, vales, online, fc_oficina, transferencia, cc')
        .eq('local', local)
        .gte('fecha', desdeF).lt('fecha', hastaFExcl);
      if (diarias && diarias.length > 0) {
        return diarias.reduce((s, v) => s
          + Number(v.efectivo||0) + Number(v.tarjeta||0) + Number(v.qr||0) + Number(v.vales||0)
          + Number(v.online||0)   + Number(v.fc_oficina||0) + Number(v.transferencia||0) + Number(v.cc||0), 0);
      }
    } catch (e) { console.warn('[cargarVentasLocalMes:diarias]', e); }
    // 2) Fallback: rrhh_ventas_local_mes (legacy / meses históricos)
    const { data } = await sb.from('rrhh_ventas_local_mes')
      .select('monto_ventas').eq('local', local).eq('periodo', periodo + '-01').limit(1);
    return data?.[0]?.monto_ventas || 0;
  }

  // Días no pagados (a descontar del prorrateo CCT/viaticos/comisión).
  // Reglas:
  //   - ausente            → cuenta SIEMPRE (no vino, no se paga)
  //   - licencia paga=false → cuenta (licencia sin goce de sueldo)
  //   - licencia paga=true  → NO cuenta (con goce: matrimonio, fallecimiento, etc.)
  //   - vacaciones          → NO cuenta (pagas por LCT)
  // Si no se encuentra registro en rrhh_licencias para una fecha con estado='licencia',
  // por seguridad se asume sin goce (descuenta) y se loguea warning a consola.
  async function cargarDiasNoPagos(empleadoId, periodo) {
    return (await cargarDiasNoPagosDetalle(empleadoId, periodo)).count;
  }
  // (1-oct-2026) Misma cuenta, pero devolviendo el desglose: además de los días que NO se
  // pagan (count), cuántas licencias fueron CON goce. Esas no bajan el sueldo pero sí el
  // viático (no viajó al local).
  async function cargarDiasNoPagosDetalle(empleadoId, periodo) {
    const [y, m] = periodo.split('-').map(Number);
    const desde = `${periodo}-01`;
    const hasta = `${y}-${String(m).padStart(2,'0')}-${String(diasDelMes(periodo)).padStart(2,'0')}`;
    // IMPORTANTE: traemos error_salvado para NO descontar sueldo cuando la
    // encargada "salvó" la ausencia (ej. reloj Anviz que no fichó pero la
    // colaboradora sí vino a trabajar). El día queda como 'ausente' visualmente
    // pero con error_salvado=true → no debe restar del sueldo.
    const { data: dias } = await sb.from('rrhh_asistencias_detalle')
      .select('fecha, estado, error_salvado').eq('empleado_id', empleadoId)
      .gte('fecha', desde).lte('fecha', hasta)
      .in('estado', ['vacaciones','licencia','ausente']);
    if (!dias || dias.length === 0) return { count: 0, licPagas: 0, licNoPagas: 0 };

    // ── COMPENSACIÓN — días con permiso aprobado NO descuentan sueldo ──
    // Si el día tiene permiso 'dia_completo' aprobado (compensado con banco o
    // vacaciones), no cuenta como falta. El descuento real lo hace
    // (a) la lógica del banco de minutos, o (b) el saldo de vacaciones.
    const { data: permisosAprobados } = await sb.from('rrhh_permisos_puntuales')
      .select('fecha, descontar_banco, descontar_vacaciones')
      .eq('empleado_id', empleadoId)
      .eq('estado', 'aprobado')
      .eq('tipo', 'dia_completo')
      .gte('fecha', desde).lte('fecha', hasta);
    const fechasCompensadas = new Set(
      (permisosAprobados || [])
        .filter(p => p.descontar_banco || p.descontar_vacaciones)
        .map(p => p.fecha)
    );

    // Para los dias con licencia, consultar rrhh_licencias y rrhh_certificados_medicos
    // para saber si es paga o no. Un certificado médico cuenta como licencia PAGA
    // (por ley: hasta 3 días con certificado — Adorno paga todos por buena voluntad).
    const fechasLic = dias.filter(d => d.estado === 'licencia').map(d => d.fecha);
    const licMap = {}; // fecha -> paga (boolean)
    if (fechasLic.length > 0) {
      const { data: lics } = await sb.from('rrhh_licencias')
        .select('fecha_desde, fecha_hasta, paga, tipo')
        .eq('empleado_id', empleadoId)
        .lte('fecha_desde', hasta).gte('fecha_hasta', desde);
      // También traemos certificados médicos que cubran alguna de esas fechas
      const { data: certsMed } = await sb.from('rrhh_certificados_medicos')
        .select('fecha_desde, fecha_hasta')
        .eq('empleado_id', empleadoId)
        .lte('fecha_desde', hasta).gte('fecha_hasta', desde);
      for (const f of fechasLic) {
        const matchLic = (lics || []).find(l => l.fecha_desde <= f && l.fecha_hasta >= f);
        if (matchLic) {
          licMap[f] = !!matchLic.paga;
          continue;
        }
        const matchCert = (certsMed || []).find(c => c.fecha_desde <= f && c.fecha_hasta >= f);
        if (matchCert) {
          licMap[f] = true; // Certificado médico → licencia paga
          continue;
        }
        console.warn(`Licencia en asistencias_detalle sin registro en rrhh_licencias ni certificado médico: emp=${empleadoId} fecha=${f}. Se descuenta por defecto.`);
        licMap[f] = false;
      }
    }

    let count = 0, licPagas = 0, licNoPagas = 0;
    for (const d of dias) {
      if (fechasCompensadas.has(d.fecha)) continue;  // Compensado con banco/vacaciones → no descontar fijo
      // Ausencia SALVADA por la encargada (ej. reloj Anviz no fichó pero la
      // colaboradora sí trabajó) → NO descontar sueldo. Se sigue viendo como
      // ausente visualmente pero no impacta la liquidación.
      if (d.estado === 'ausente' && d.error_salvado) continue;
      if (d.estado === 'ausente') count++;
      else if (d.estado === 'licencia' && licMap[d.fecha] === false) { count++; licNoPagas++; }
      else if (d.estado === 'licencia') licPagas++;
      // vacaciones y licencia con goce: no suman al descuento de sueldo
    }
    return { count, licPagas, licNoPagas };
  }

  // Alias para retro-compatibilidad (otras partes del codigo siguen llamando al nombre viejo)
  async function cargarDiasNoTrabajados(empleadoId, periodo) {
    return cargarDiasNoPagos(empleadoId, periodo);
  }

  // Cuenta cuántas colaboradoras activas hay en el local en ese período (para reparto 'dividido_activos')
  async function contarActivasLocal(local, periodoFull) {
    const { data } = await sb.from('rrhh_sueldo_empleada_config')
      .select('empleado_id, fraccion_comision, rrhh_empleados!inner(local, estado)')
      .lte('vigente_desde', periodoFull)
      .eq('activa_en_modulo', true);
    // Deduplicar por empleado_id: cada colaborador puede tener varias configs vigentes
    // (la del aumento previo + la actual). Si no deduplicamos, contamos doble y la
    // comisión por colaboradora queda dividida incorrectamente.
    // Además, excluimos colaboradoras con fraccion_comision = 0 (administrativos puros)
    // del divisor de comisión.
    const ids = new Set();
    (data || []).forEach(d => {
      if (d.rrhh_empleados?.local !== local) return;
      if (d.rrhh_empleados?.estado !== 'activo') return;
      if (Number(d.fraccion_comision || 0) <= 0) return; // no contar fraccion 0
      ids.add(d.empleado_id);
    });
    return ids.size;
  }

  /**
   * Liquida una colaboradora para un período. Inputs opcionales del usuario:
   *   { dias_trabajados, mercaderia, ajuste, uniforme_ok, extras, otros_remunerativos, observaciones }
   * Si no se pasan, se infieren (días = 30 - dias_no_trabajados, uniforme_ok = true, etc.)
   */
  async function liquidarEmpleada(empleadoId, periodo, inputs = {}) {
    await verificarEscalaDelMes(periodo, inputs.tipo);   // frena si el mes no tiene escala propia (y la busca en FAECYS)
    // Cargas
    const _cache = inputs._cache || {};
    const [emp, configLocal, configEmp, paritaria] = await Promise.all([
      cargarEmpleadoCompleto(empleadoId, periodo),
      null,            // se carga después con emp.local
      cargarConfigEmpleada(empleadoId, periodo),
      _cache.paritaria ? Promise.resolve(_cache.paritaria) : cargarParitaria(periodo),
    ]);
    if (!emp) throw new Error('Colaborador no encontrado');

    // ══════════════════════════════════════════════════════════════════════
    //  Cierre del mes de Asistencias del local — flag transversal
    //  Si NO está cerrado, no se prorratean días ni se calculan
    //  premio/viáticos/feriado (todo eso se resuelve al cierre).
    // ══════════════════════════════════════════════════════════════════════
    let asistenciasCerradas = false;
    try {
      const [_pyLE, _pmLE] = periodo.split('-').map(Number);
      const { data: _cierreLE } = await sb.from('rrhh_meses_cerrados')
        .select('id').eq('local', emp.local).eq('año', _pyLE).eq('mes', _pmLE).maybeSingle();
      asistenciasCerradas = !!_cierreLE;
    } catch (e) { console.warn('[liquidarEmpleada:cierreAsis]', e); }

    // ─── CASO ESPECIAL: monotributista (Andrea Adorno) ─────────────────
    // Factura un monto fijo mensual. Se le transfiere por banco. NO tiene
    // recibo CCT, NO va al LSD ARCA, NO va al F.931. El efectivo extra (si
    // corresponde) se carga manual desde el Liquidador.
    if (emp.monotributista) {
      // ─── MONOTRIBUTISTA (Andrea Adorno) ──────────────────────────────
      // Modelo correcto:
      //   * Fijo de configEmp (ej $3.4M) = sueldo total
      //   * monto_factura_mensual (ej $1M) = lo que va por banco como factura
      //   * Efectivo = Fijo + Viaticos − monto_factura_mensual (la diferencia)
      //   * Comision y premio NO aplican (config tiene fraccion_comision=0 y premio=0)
      //   * Se prorratea fijo y viaticos por dias_trabajados/30 (sin goce/ausentes)
      const periodoFull = periodo + '-01';
      const configMono = await cargarConfigEmpleada(empleadoId, periodo);
      if (!configMono) throw new Error(`Monotributista ${emp.nombre_completo} sin config en rrhh_sueldo_empleada_config`);
      const fijoFull = Number(configMono.fijo || 0);
      const viaticosFull = Number(configMono.viaticos || 0);
      const banco = Number(emp.monto_factura_mensual || 0);
      // Prorrateo por sin goce/ausentes (solo si Asistencias está cerrado,
      // sino defaultea a 30 días → fijo completo sin prorratear).
      const diasNoPagos = asistenciasCerradas ? await cargarDiasNoPagos(empleadoId, periodo) : 0;
      const diasTrabajados = Math.max(0, 30 - diasNoPagos);
      const fijo = fijoFull * (diasTrabajados / 30);
      // Viáticos: solo al cierre de asistencias (igual que cct_negro)
      const viaticos = asistenciasCerradas ? viaticosFull * (diasTrabajados / 30) : 0;
      const totalNegro = fijo + viaticos;
      // Mercadería: cuotas del mes desde la tabla nueva (respeta cuotas + estado).
      // BUG fix 19-jun-2026: usaba rrhh_retiro_mercaderia (singular vieja).
      let mercaderia_mono = 0;
      try {
        const [_y, _m] = periodo.split('-').map(Number);
        const { data: _sumMono } = await sb.rpc('rrhh_sum_retiros_mes', {
          p_empleado_id: empleadoId, p_anio: _y, p_mes: _m
        });
        mercaderia_mono = Number(_sumMono || 0);
        console.log('[merc mono] emp', empleadoId, 'total cuotas mes', mercaderia_mono);
      } catch (e) { console.warn('mercaderia monotributista', e); }
      const efectivo = Math.max(0, totalNegro - banco - mercaderia_mono);
      const { data: existing } = await sb.from('rrhh_liquidacion')
        .select('id, ajuste, observaciones')
        .eq('empleado_id', empleadoId).eq('periodo', periodoFull).limit(1);
      const payload = {
        empleado_id: empleadoId, periodo: periodoFull, local: emp.local,
        estado: 'borrador',
        dias_trabajados: diasTrabajados,
        mercaderia: mercaderia_mono,
        ajuste: existing?.[0]?.ajuste || 0,
        uniforme_ok: true, puntos_mes: 0,
        observaciones: existing?.[0]?.observaciones || `Monotributista — factura $${banco.toLocaleString('es-AR')} por banco + diferencia en efectivo`,
        // Recibo CCT: todo en 0 (no aplica), excepto recibo_neto = banco (lo facturado)
        recibo_basico: 0, recibo_antiguedad: 0, recibo_presentismo: 0,
        recibo_sumafija_nr: 0, recibo_antig_nr: 0, recibo_pres_nr: 0, recibo_recompos_nr: 0,
        recibo_otros_rem: 0,
        recibo_jubilacion: 0, recibo_ley19032: 0, recibo_obra_social: 0,
        recibo_sec: 0, recibo_faecys: 0,
        recibo_total_rem: 0, recibo_total_nr: 0, recibo_bruto: 0,
        recibo_descuentos: 0,
        recibo_neto: banco,       // ← lo que va por banco (factura monotributo)
        // Negro/Total
        fijo: fijo, comision: 0, premio_cobra: false, premio_monto: 0,
        viaticos: viaticos, extras: 0, feriado_dias: 0, feriado_monto: 0,
        prestamo_interes: 0,
        total_negro: totalNegro,
        efectivo: efectivo,
      };
      if (existing?.[0]) {
        await sb.from('rrhh_liquidacion').update(payload).eq('id', existing[0].id);
      } else {
        await sb.from('rrhh_liquidacion').insert(payload);
      }
      return { recibo: null, monotributista: true, fijo, viaticos, banco, efectivo, totalNegro };
    }

    if (!configEmp) throw new Error(`Empleada ${emp.nombre_completo} no tiene config de sueldo`);
    if (!configEmp.activa_en_modulo) throw new Error(`Empleada ${emp.nombre_completo} no está activa en el módulo`);
    if (!emp.categoria) throw new Error('Empleada sin categoría CCT asignada');
    if (!paritaria) throw new Error('No hay paritaria vigente para ' + periodo);

    // ── Filtros de scope para botones "⚡ Importes" y "💎 Doble Blanco" ──
    const esDobleBlanco = configEmp.modo_liquidacion === 'doble_blanco';
    if (inputs.soloImportes && esDobleBlanco) {
      return { skipped: true, motivo: 'doble_blanco — usar botón Doble Blanco' };
    }
    if (inputs.soloDobleBlanco && !esDobleBlanco) {
      return { skipped: true, motivo: 'cct_negro — usar botón Importes' };
    }
    // soloAsistencias: SÍ aplica a doble_blanco (Contreras/Escasany).
    // Para ellas también actualiza premio/viáticos/feriado + total_negro,
    // pero NO toca el recibo — el solver inverso se corre después con
    // 💎 Doble Blanco cuando el sueldo real ya está definitivo.

    const cfgLocal = (_cache.cfgLocal && _cache.local === emp.local)
      ? _cache.cfgLocal
      : await cargarConfigLocal(emp.local, periodo);
    if (!cfgLocal) throw new Error('Local sin config de sueldo: ' + emp.local);

    // Días del mes y días no trabajados
    const _dnpDet = await cargarDiasNoPagosDetalle(empleadoId, periodo);
    let diasNoTrab = _dnpDet.count;
    // Descuento especial (faltas/suspensiones extra ingresadas al armar la proforma)
    const diasExtraDescuento = Number(inputs.descuento_especial?.dias_extra || 0);
    if (diasExtraDescuento > 0) diasNoTrab += diasExtraDescuento;
    const diasMes = diasDelMes(periodo);
    let diasTrabajadosInferidos = Math.max(0, 30 - diasNoTrab);

    // Para colaboradoras con dias_prorrateo_modo='dias_local' (caso Escasany):
    // contar los días que EFECTIVAMENTE trabajó (no 30 - ausentes).
    // Una franquera viene solo unos días, así que el resto NO son 'ausente',
    // simplemente no estaba agendada. Acá los descartamos correctamente.
    if (configEmp.dias_prorrateo_modo === 'dias_local') {
      const [yEsc, mEsc] = periodo.split('-').map(Number);
      const desdeEsc = `${periodo}-01`;
      const hastaEsc = `${yEsc}-${String(mEsc).padStart(2,'0')}-${String(diasDelMes(periodo)).padStart(2,'0')}`;
      const { data: detsEsc } = await sb.from('rrhh_asistencias_detalle')
        .select('fecha, estado, entrada, salida')
        .eq('empleado_id', empleadoId)
        .gte('fecha', desdeEsc).lte('fecha', hastaEsc);
      // Contar solo días con trabajo efectivo (excluye feriado no trabajado, ausente, licencia, vacaciones)
      diasTrabajadosInferidos = (detsEsc || []).filter(d => {
        if (['ausente','licencia','vacaciones'].includes(d.estado)) return false;
        if (d.estado === 'feriado' && !d.entrada && !d.salida) return false;
        // Cualquier otro estado con fichada o estado de trabajado cuenta
        return !!d.entrada || !!d.salida || ['puntual','tarde','falta_fichada','feriado'].includes(d.estado);
      }).length;
    }

    // Si Asistencias no está cerrado, no prorrateamos: usamos 30 días.
    // El fijo se pisa al abrir el mes y se recalcula al cierre.
    const dias_trabajados = inputs.dias_trabajados ?? (asistenciasCerradas ? diasTrabajadosInferidos : 30);
    // Mercadería: cuotas del mes desde la tabla nueva (respeta cuotas + estado).
    // BUG fix 19-jun-2026: usaba rrhh_retiro_mercaderia (singular vieja) que ya no se llena.
    let mercaderia_auto = 0;
    if (inputs.mercaderia == null) {
      const [y, m] = periodo.split('-').map(Number);
      const { data: _sum } = await sb.rpc('rrhh_sum_retiros_mes', {
        p_empleado_id: empleadoId, p_anio: y, p_mes: m
      });
      mercaderia_auto = Number(_sum || 0);
    }
    const mercaderia = inputs.mercaderia ?? mercaderia_auto;

    // ── Preservar ajuste manual + overrides_manuales existentes al recalcular ──
    // Si la fila ya tiene overrides marcados en JSONB, NO los sobreescribimos.
    // Ej: si admin editó la comisión a $480.334 manualmente, el recálculo
    // automático no la pisa hasta que el admin "limpie" el override.
    const { data: existingAjuste } = await sb.from('rrhh_liquidacion')
      .select('ajuste, ajuste_comentario, overrides_manuales, fijo, comision, viaticos, premio_monto, feriado_monto, mercaderia, tipo, ajuste_blanco')
      .eq('empleado_id', empleadoId)
      .eq('periodo', periodo + '-01')
      .limit(1);
    const tipoPrev = existingAjuste?.[0]?.tipo || null;
    // > 0 = ya se le aplicó el 💎 Doble Blanco (ítem 0018) a esta liquidación
    const ajusteBlancoPrev = Number(existingAjuste?.[0]?.ajuste_blanco || 0);
    const ajustePrev = Number(existingAjuste?.[0]?.ajuste || 0);
    const ajusteComentPrev = existingAjuste?.[0]?.ajuste_comentario || null;
    const overridesPrev = existingAjuste?.[0]?.overrides_manuales || {};
    const ajuste = inputs.ajuste ?? ajustePrev;
    // (3-sep) Pagos de extras aprobados por JP para este período → columna Extras (efectivo)
    let extrasPagoAprob = 0;
    try {
      const { data: _ep } = await sb.rpc('rrhh_extras_pago_mes', { p_emp: empleadoId, p_periodo: periodo + '-01' });
      extrasPagoAprob = Number(_ep || 0);
    } catch(_) {}
    const extras = (inputs.extras ?? 0) + extrasPagoAprob;
    const otros_rem = inputs.otros_remunerativos ?? 0;
    const uniforme_ok = inputs.uniforme_ok ?? true;
    const fuera_convenio = !!emp.fuera_convenio;
    // (1-oct-2026) Claudia: categoría 'directora' → sin descuentos ni antig/pres no rem (ver calcularReciboCCT)
    const directora = String(emp.categoria?.codigo || '') === 'directora';
    const fraccionNR = (configEmp.fraccion_no_rem != null) ? Number(configEmp.fraccion_no_rem)
                     : (configEmp.jornada_parcial ? 0.5 : null);   // media jornada: no rem al 50 % (estudio)

    // ── JORNADA PARCIAL (art. 92 ter LCT) — caso franquera Escasany ──
    // (1-oct-2026, JP) MEDIA JORNADA FIJA, igual que el estudio: básico a 16/30
    // (en septiembre 15 + 1 Día del Gremio) y sumas no rem al 50 %. Antes se
    // prorrateaba por horas de turnos (jun 50 %, jul 32 %, ago 41 %, sep 33 %)
    // y por eso la proforma se corría del recibo del estudio todos los meses.
    // Verificado al centavo contra sep-2026. El pactado por encima de esta base
    // lo completa el solver 0018 (segunda liquidación).
    const JORNADA_PARCIAL_DIAS_RECIBO = 16;
    let dias_recibo = dias_trabajados;
    if (configEmp.jornada_parcial) {
      dias_recibo = JORNADA_PARCIAL_DIAS_RECIBO;
      console.log(`[liquidarEmpleada:92ter] emp=${empleadoId}: media jornada fija → ${dias_recibo}/30 días de recibo`);
    }

    // ── RECIBO BLANCO (CCT) ──
    const recibo = salaryEngine.calcularReciboCCT({
      basico_escala: Number(emp.categoria.sueldo_basico),
      fecha_ingreso: emp.fecha_ingreso,
      periodo,
      dias_trabajados: dias_recibo,
      obra_social_codigo: emp.obra_social_codigo || '',
      suma_fija_nr: Number(paritaria.suma_fija_nr),
      recompos_nr: Number(paritaria.recompos_nr),
      fuera_convenio, directora,
      otros_remunerativos: otros_rem,
      fraccion_no_rem_override: fraccionNR,
    });

    // ── TOPE GANANCIAS 4ta: si emp.calcular_tope_ganancias=true, forzar el recibo neto
    //    al tope mensual (lo que no se pasa de Ganancias) y prorratear los componentes
    //    del recibo al nuevo bruto. La diferencia (fijo + viaticos + extras + comision +
    //    premio - tope) va por efectivo (negro).
    // (1-oct-2026) El forzado del recibo al tope queda detrás de `forzar_recibo_al_tope`:
    // para Claudia/JP la proforma tiene que ser igual a la del estudio; el tope se
    // informa (banner + detalle) y el básico lo ajusta el estudio.
    if (emp.calcular_tope_ganancias && emp.forzar_recibo_al_tope) {
      try {
        const { data: topeData, error: eTope } = await sb.rpc('rrhh_calcular_tope_ganancias', {
          p_empleado_id: empleadoId,
          p_periodo: periodo + '-01',
        });
        if (eTope) {
          console.warn(`Tope ganancias falló para emp=${empleadoId}: ${eTope.message}`);
        } else if (topeData && Number(topeData.neto_tope_mensual) > 0) {
          const netoTope = Number(topeData.neto_tope_mensual);
          const brutoTope = Number(topeData.bruto_tope_mensual);
          const brutoActual = Number(recibo.totales.bruto || 0);
          if (brutoActual > 0 && Math.abs(brutoActual - brutoTope) > 1) {
            // Ajustar proporcional: factor = brutoTope / brutoActual
            const f = brutoTope / brutoActual;
            for (const c of recibo.conceptos) {
              c.importe = Number(c.importe || 0) * f;
            }
            const t = recibo.totales;
            t.basico       = Number(t.basico||0)       * f;
            t.dia_gremio   = Number(t.dia_gremio||0)   * f;
            t.antiguedad   = Number(t.antiguedad||0)   * f;
            t.presentismo  = Number(t.presentismo||0)  * f;
            t.sumafija_nr  = Number(t.sumafija_nr||0)  * f;
            t.ant_nr       = Number(t.ant_nr||0)       * f;
            t.pres_nr      = Number(t.pres_nr||0)      * f;
            t.recompos_nr  = Number(t.recompos_nr||0)  * f;
            t.otros_rem    = Number(t.otros_rem||0)    * f;
            t.jubilacion   = Number(t.jubilacion||0)   * f;
            t.ley19032     = Number(t.ley19032||0)     * f;
            t.obra_social  = Number(t.obra_social||0)  * f;
            t.sec          = Number(t.sec||0)          * f;
            t.faecys       = Number(t.faecys||0)       * f;
            t.total_rem    = Number(t.total_rem||0)    * f;
            t.total_nr     = Number(t.total_nr||0)     * f;
            t.total_descuentos = Number(t.total_descuentos||0) * f;
            t.bruto = brutoTope;
            t.neto  = netoTope;
            console.info(`Tope ganancias aplicado emp=${empleadoId}: neto $${netoTope.toLocaleString('es-AR')}`);
          } else if (brutoActual === 0) {
            // Caso fuera_convenio con basico=0: el calc CCT dio todo 0. Forzar valores.
            const t = recibo.totales;
            t.basico = brutoTope;  // aprox: poner el bruto como básico
            t.bruto = brutoTope;
            // Estimar descuentos jubilatorios típicos (~21% del bruto)
            const descAprox = brutoTope - netoTope;
            t.jubilacion = descAprox * 0.55;
            t.ley19032   = descAprox * 0.15;
            t.obra_social = descAprox * 0.30;
            t.total_descuentos = descAprox;
            t.total_rem = brutoTope;
            t.neto = netoTope;
            console.info(`Tope ganancias forzado (basico era 0) emp=${empleadoId}: neto $${netoTope.toLocaleString('es-AR')}`);
          }
        }
      } catch (e) {
        console.warn(`Excepción tope ganancias emp=${empleadoId}:`, e);
      }
    }

    // ── NEGRO ──
    const puntos_mes = await calcularPuntosMes(empleadoId, periodo);
    // Tolerancia de errores: override por colaboradora si existe (Escasany=2), si no, el del local
    const maxErroresEmp = (configEmp.max_errores_premio_override != null && configEmp.max_errores_premio_override !== undefined)
      ? Number(configEmp.max_errores_premio_override)
      : Number(cfgLocal.umbral_premio);
    // ─── Denominador del prorrateo ───
    // - 'mes_30' (default): siempre /30 → colaboradoras que trabajan mes completo
    // - 'dias_local' (Escasany franquera): /promedio dias_trabajados de vendedoras del local
    //   en el mismo periodo. Así si vendedora normal trabajó 26 días y Escasany 8, ratio = 8/26.
    let dias_referencia = 30;
    if (configEmp.dias_prorrateo_modo === 'dias_local') {
      const { data: otrasLiqs } = await sb.from('rrhh_liquidacion')
        .select('dias_trabajados, empleado_id, rrhh_empleados!inner(local, apellido)')
        .eq('periodo', periodo + '-01')
        .eq('rrhh_empleados.local', emp.local)
        .neq('empleado_id', empleadoId);
      const diasNormales = (otrasLiqs || [])
        .filter(l => Number(l.dias_trabajados || 0) > 0)
        .map(l => Number(l.dias_trabajados));
      if (diasNormales.length > 0) {
        const promedio = diasNormales.reduce((a, b) => a + b, 0) / diasNormales.length;
        dias_referencia = Math.max(1, Math.ceil(promedio));
      } else {
        // Fallback: si no hay otras liquidaciones todavía (primer cálculo del mes),
        // asumimos 26 como referencia común de un mes laboral.
        dias_referencia = 26;
      }
    }
    const ratio = dias_trabajados / dias_referencia;

    let cobraPremio = uniforme_ok && (puntos_mes <= maxErroresEmp);
    // Premio: si está en modo 'dias_local', se prorratea proporcional. En modo 'mes_30' va full.
    const premioBase = Number(configEmp.premio_fichadas_uniforme);
    let premio = cobraPremio
      ? (configEmp.dias_prorrateo_modo === 'dias_local' ? premioBase * ratio : premioBase)
      : 0;

    // Comisión: depende de la config de la empleada.
    //  - Flag comision_dia_por_venta=true (Escasany): SUMA de ventas de los DÍAS
    //    que fichó × tasa × fraccion → solo comisiona sobre las ventas reales
    //    de los días que efectivamente estuvo presente.
    //  - Resto (default): ventas_TOTAL_mes × tasa × fraccion × ratio
    //    (÷ activas si el local usa modo dividido_activos)
    const ventasLocal = await cargarVentasLocalMes(emp.local, periodo);
    const tasaLocal = Number(cfgLocal.tasa_comision);
    let comision = 0;
    let comision_base = 0;
    let comisionDetalleDias = null; // guardado en overrides para tooltip
    if (configEmp.comision_dia_por_venta === true) {
      // Días efectivamente trabajados (presente / puntual / tarde — no franco/ausente/vac/lic)
      const py = periodo.split('-')[0], pm = periodo.split('-')[1];
      const desdeFecha = `${py}-${pm}-01`;
      const hastaFecha = `${py}-${pm}-${String(diasDelMes(periodo)).padStart(2,'0')}`;
      const { data: detAsis } = await sb.from('rrhh_asistencias_detalle')
        .select('fecha, estado, entrada, salida')
        .eq('empleado_id', empleadoId)
        .gte('fecha', desdeFecha).lte('fecha', hastaFecha);
      // (1-oct-2026, regla JP) "Si le faltó una fichada es un error de ella, pero si tiene
      // una significa que ese día fue a trabajar, así que comisiona": un día con
      // falta_fichada y al menos UNA marca (entrada o salida) cuenta como trabajado.
      const trabajados = new Set(
        (detAsis || [])
          .filter(d => {
            const est = (d.estado || '').toLowerCase();
            if (['presente','puntual','tarde'].includes(est)) return true;
            return est === 'falta_fichada' && !!(d.entrada || d.salida);
          })
          .map(d => d.fecha)
      );
      // Ventas diarias del local en esos días
      let sumaVentas = 0;
      const detArr = [];
      if (trabajados.size > 0) {
        const { data: vRows } = await sb.from('ventas_diarias')
          .select('fecha, efectivo, tarjeta, qr, vales, online, fc_oficina, transferencia, cc')
          .eq('local', emp.local)
          .in('fecha', Array.from(trabajados));
        (vRows || []).forEach(v => {
          const total = Number(v.efectivo||0) + Number(v.tarjeta||0) + Number(v.qr||0) + Number(v.vales||0)
                      + Number(v.online||0) + Number(v.fc_oficina||0) + Number(v.transferencia||0) + Number(v.cc||0);
          detArr.push({ fecha: v.fecha, monto: total });
          sumaVentas += total;
        });
      }
      detArr.sort((a,b)=>a.fecha.localeCompare(b.fecha));
      comision_base = sumaVentas * tasaLocal;
      comision = comision_base * Number(configEmp.fraccion_comision);
      comisionDetalleDias = { modo: 'dias_local', dias: detArr, sumaVentas, tasa: tasaLocal, fraccion: Number(configEmp.fraccion_comision) };
    } else {
      // Modo mes_30 (vendedoras normales)
      comision_base = ventasLocal * tasaLocal;
      if (cfgLocal.modo_reparto === 'dividido_activos') {
        const activas = await contarActivasLocal(emp.local, periodo + '-01');
        if (activas > 0) comision_base = comision_base / activas;
      }
      comision = comision_base * Number(configEmp.fraccion_comision) * ratio;
    }

    // Fijo:
    //  - colaboradoras en mes_30 (vendedoras normales): se prorratea por dias_trabajados/30.
    //    Si trabajó todo el mes: ratio=1 → cobra full. Con ausencias sin goce: baja.
    //  - colaboradoras en dias_local (Escasany franquera): cobra el fijo COMPLETO siempre,
    //    porque su fijo ya está calibrado al perfil de "trabaja pocos días al mes".
    const fijo = (configEmp.dias_prorrateo_modo === 'dias_local')
      ? Number(configEmp.fijo)
      : Number(configEmp.fijo) * (dias_trabajados / 30);

    // Viáticos: prorrateados sobre dias_referencia (mismo criterio que comisión).
    const viaticos_full = Number(configEmp.viaticos);
    let viaticos = viaticos_full * ratio;

    // Plus por feriado trabajado: solo en locales en shoppings (Alcorta/Unicenter).
    // Se cuentan los feriados del mes donde el local NO cierra Y la colaboradora efectivamente
    // estuvo disponible (no de vacaciones / licencia / ausente). Esto evita pagarle plus
    // a alguien que estaba de vacaciones cuando el local trabajó el feriado.
    const [py, pm] = periodo.split('-').map(Number);
    const desdeFer = `${periodo}-01`;
    const hastaFer = `${py}-${String(pm).padStart(2,'0')}-${String(diasDelMes(periodo)).padStart(2,'0')}`;
    const fers = (_cache.feriados && _cache.periodo === periodo)
      ? _cache.feriados
      : (await sb.from('rrhh_feriados')
          .select('fecha, cierra_oficina, cierra_shoppings')
          .gte('fecha', desdeFer).lte('fecha', hastaFer)).data || [];
    const { data: detalleEmp } = await sb.from('rrhh_asistencias_detalle')
      .select('fecha, estado').eq('empleado_id', empleadoId)
      .gte('fecha', desdeFer).lte('fecha', hastaFer);
    const estadoNoTrabajado = new Set(['vacaciones', 'licencia', 'ausente']);
    const noDisponiblePorFecha = new Set(
      (detalleEmp || [])
        .filter(d => estadoNoTrabajado.has(d.estado))
        .map(d => d.fecha)
    );
    let feriado_dias = 0;
    (fers || []).forEach(f => {
      const localTrabaja = (emp.local === 'oficina') ? !f.cierra_oficina : !f.cierra_shoppings;
      if (!localTrabaja) return;
      if (noDisponiblePorFecha.has(f.fecha)) return;
      feriado_dias += 1;
    });

    // (3-ago) Viáticos: descontar los días de VACACIONES del mes. Las vacaciones
    // no restan dias_trabajados (el fijo es pago), pero el viático es por
    // viajar al local — de vacaciones no se viaja. Caso Benitez jul-2026.
    const _vacDiasMes = (detalleEmp || []).filter(d => d.estado === 'vacaciones').length;
    // (1-oct-2026, JP — caso Verón sep-2026) Lo mismo vale para la LICENCIA con goce: el
    // sueldo se paga, pero esos días no viajó. La licencia SIN goce ya está descontada en
    // dias_trabajados, por eso acá se restan solo las pagas.
    const _noViajaDias = _vacDiasMes + Number(_dnpDet.licPagas || 0);
    if (_noViajaDias > 0 && viaticos > 0) {
      viaticos = viaticos_full * Math.max(0, dias_trabajados - _noViajaDias) / 30;
    }
    const feriado_por_dia = Number(cfgLocal.feriado_por_dia || 0);
    // Multiplicador especial: para Escasany x2 porque al ser franquera el feriado le pesa más
    // (1-oct-2026) 0 es un valor válido = "no cobra plus de feriado" (Claudia y JP en Oficina).
    const feriadoMul = (configEmp.feriado_multiplicador != null) ? Number(configEmp.feriado_multiplicador) : 1.0;
    let feriado_monto = feriado_dias * feriado_por_dia * feriadoMul;

    // Guard (asistenciasCerradas ya se calculó al inicio de liquidarEmpleada)
    if (!asistenciasCerradas) {
      premio = 0;
      cobraPremio = false;
      viaticos = 0;
      feriado_dias = 0;
      feriado_monto = 0;
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  EARLY RETURN: modo "🔒 Cierre Asistencias" (Fase 2C)
    //  Solo actualiza premio / viáticos / feriado + recalcula total_negro
    //  y efectivo usando los valores actuales de DB de los demás campos
    //  (fijo, comisión, extras, mercadería, ajustes, etc. NO se tocan).
    // ═══════════════════════════════════════════════════════════════════════
    if (inputs.soloAsistencias) {
      const { data: existSA } = await sb.from('rrhh_liquidacion')
        .select('id, fijo, comision, extras, vacaciones_pago, mercaderia, ajuste, recibo_neto, prestamo_interes, overrides_manuales')
        .eq('empleado_id', empleadoId).eq('periodo', periodo + '-01').limit(1);
      if (!existSA?.[0]) {
        return { skipped: true, motivo: 'Sin liq previa — no hay qué actualizar en modo soloAsistencias' };
      }
      const liqSA = existSA[0];
      const overSA = liqSA.overrides_manuales || {};
      const premioF   = (overSA.premio_monto?.new  != null) ? Number(overSA.premio_monto.new)  : premio;
      const viaticosF = (overSA.viaticos?.new      != null) ? Number(overSA.viaticos.new)      : viaticos;
      const feriadoF  = (overSA.feriado_monto?.new != null) ? Number(overSA.feriado_monto.new) : feriado_monto;
      // Recalcular total_negro con VALORES ACTUALES DE DB para lo demás
      const totalNegroSA = Number(liqSA.fijo||0) + Number(liqSA.comision||0)
        + premioF + viaticosF + feriadoF
        + Number(liqSA.extras||0) + Number(liqSA.vacaciones_pago||0);
      const efectivoSA = Math.max(0, totalNegroSA
        - Number(liqSA.recibo_neto||0)
        - Number(liqSA.mercaderia||0)
        - Number(liqSA.ajuste||0)
        - Number(liqSA.prestamo_interes||0));
      // 🚨 (1-oct-2026) Por RPC y NO con update directo: las encargadas solo tienen SELECT
      // sobre rrhh_liquidacion y el update se bloqueaba por RLS EN SILENCIO (0 filas, sin
      // error). Por eso, cuando cerraba la encargada, no se cargaban premio/viáticos/feriado
      // (Alcorta y Unicenter, sep-2026). La RPC valida quién llama y acota los importes a la
      // configuración. Si falla, AHORA tira error (queda en r.errores y cerrarMes lo avisa).
      const { error: eSA } = await sb.rpc('rrhh_liq_cargar_asistencias', {
        p_liq: liqSA.id, p_premio_cobra: !!cobraPremio, p_premio: premioF, p_viaticos: viaticosF,
        p_feriado_dias: feriado_dias, p_feriado: feriadoF, p_puntos: puntos_mes,
        // (1-oct-2026) también los DÍAS: la RPC re-prorratea fijo y comisión (ausencias,
        // licencias sin goce). Así todo lo que depende de Asistencias se carga al cerrar.
        p_dias: dias_trabajados,
      });
      if (eSA) throw new Error('No se pudo cargar premio/viáticos/feriado: ' + eSA.message);
      return {
        liquidacion_id: liqSA.id,
        soloAsistencias: true,
        totales: { premio: premioF, viaticos: viaticosF, feriado: feriadoF, total_negro: totalNegroSA, efectivo: efectivoSA },
        puntos_mes, cobraPremio,
      };
    }

    // ── Pago de vacaciones imputado a este mes ──
    // Suma los importe_pagado de movs con estado='pagada' cuyo periodo_liquidacion sea este mes
    let vacacionesPago = 0;
    try {
      // (4-ago) Vía RPC SECURITY DEFINER: el SELECT directo devolvía vacío
      // intermitentemente en el navegador (caso Bianchi julio, 2 veces).
      const { data: vpVal, error: vpErr } = await sb.rpc('rrhh_vacaciones_pago_mes', {
        p_empleado_id: empleadoId, p_periodo: periodo + '-01' });
      if (vpErr) console.warn('[liquidarEmpleada:vacPago] error RPC:', vpErr);
      vacacionesPago = Number(vpVal || 0);
    } catch (e) { console.warn('[liquidarEmpleada:vacPago]', e); }

    const total_negro_esperado = fijo + comision + premio + viaticos + extras + feriado_monto + vacacionesPago;

    // ── EARLY RETURN: modo "⚡ Importes" — solo actualizar campos negros sin tocar recibo ──
    // Requiere que la liquidación YA exista (para reaprovechar recibo_neto). Si no existe,
    // sale con error para que el admin corra Recalcular/Proforma primero.
    if (inputs.soloImportes) {
      const { data: existSolo } = await sb.from('rrhh_liquidacion')
        .select('id, recibo_neto, ajuste, overrides_manuales, prestamo_capital, prestamo_interes')
        .eq('empleado_id', empleadoId).eq('periodo', periodo + '-01').limit(1);
      if (!existSolo?.[0]) {
        throw new Error('Sin liquidación previa — corré Recalcular o Definitivo primero, después podés usar ⚡ Importes para refrescar.');
      }
      const liqExist = existSolo[0];
      const reciboNetoExist = Number(liqExist.recibo_neto || 0);
      const ajusteExist = Number(liqExist.ajuste || 0);

      // Cuotas de préstamo del mes (capital + interés) — pueden cambiar
      const { data: cuotasSolo } = await sb.from('rrhh_prestamo_cuota')
        .select('monto_capital, monto_interes, estado, prestamo_id, prestamo:rrhh_prestamo!inner(empleado_id, estado)')
        .eq('mes_descuento', periodo + '-01').neq('estado', 'cancelada');
      const cuotasSoloEmp = (cuotasSolo || []).filter(c => c.prestamo?.empleado_id === empleadoId && c.prestamo?.estado === 'activo');
      const prestCapSolo = cuotasSoloEmp.reduce((a, c) => a + Number(c.monto_capital || 0), 0);
      const prestIntSolo = cuotasSoloEmp.reduce((a, c) => a + Number(c.monto_interes || 0), 0);

      // Aplicar overrides_manuales preservados
      const overridesSolo = liqExist.overrides_manuales || {};
      const fijoFinal     = (overridesSolo.fijo?.new      != null) ? Number(overridesSolo.fijo.new)         : fijo;
      const comFinal      = (overridesSolo.comision?.new  != null) ? Number(overridesSolo.comision.new)     : comision;
      const premFinal     = (overridesSolo.premio_monto?.new != null) ? Number(overridesSolo.premio_monto.new) : premio;
      const viatFinal     = (overridesSolo.viaticos?.new  != null) ? Number(overridesSolo.viaticos.new)     : viaticos;
      const fersFinal     = (overridesSolo.feriado_monto?.new != null) ? Number(overridesSolo.feriado_monto.new) : feriado_monto;
      const totalNegroFin = fijoFinal + comFinal + premFinal + viatFinal + extras + fersFinal + vacacionesPago;
      const efectivoSolo = Math.max(0, totalNegroFin - reciboNetoExist - mercaderia - ajusteExist - prestIntSolo);

      await sb.from('rrhh_liquidacion').update({
        dias_trabajados, mercaderia,
        fijo: fijoFinal, comision: comFinal, premio_cobra: cobraPremio, premio_monto: premFinal,
        viaticos: viatFinal, extras, feriado_dias, feriado_monto: fersFinal,
        vacaciones_pago: vacacionesPago,
        total_negro: totalNegroFin,
        efectivo: efectivoSolo,
        prestamo_capital: prestCapSolo, prestamo_interes: prestIntSolo,
        puntos_mes,
        calculado_at: new Date().toISOString(),
      }).eq('id', liqExist.id);

      return {
        liquidacion_id: liqExist.id,
        soloImportes: true,
        totales_negro: { fijo: fijoFinal, comision: comFinal, premio: premFinal, viaticos: viatFinal, extras, total_negro_esperado: totalNegroFin, efectivo: efectivoSolo, ajuste_blanco: 0 },
        puntos_mes, cobraPremio,
      };
    }

    // Modo de liquidación: cct_negro (default) vs doble_blanco (recibo ajustado: Contreras/Escasany)
    // En doble_blanco el estudio re-liquida con el básico ajustado para que el neto del único
    // recibo coincida con el Total esperado. Recalculamos el recibo con el básico inverso.
    let ajuste_blanco = 0;
    let efectivo = 0;
    let reciboFinal = recibo;

    // ── NETO OBJETIVO FIJO POR PERÍODO (4-ago — JP y Claudia, julio) ──
    // Si la config trae recibo_neto_objetivo para ESTE período, el recibo se
    // completa con el ítem 'Comisiones 0018' (solver) hasta ese neto exacto.
    // El desglose del PDF queda consistente con el neto pactado/alineado.
    // El resto del total sigue yendo por efectivo como siempre.
    if (configEmp.modo_liquidacion !== 'doble_blanco'
        && Number(configEmp.recibo_neto_objetivo || 0) > 0
        && String(configEmp.recibo_neto_objetivo_periodo || '').slice(0, 7) === periodo) {
      const _objetivoFijo = Number(configEmp.recibo_neto_objetivo);
      const _comisionObj = salaryEngine.calcularComisionVentaParaNeto({
        neto_objetivo: _objetivoFijo,
        neto_recibo_base: recibo.totales.neto,
        obra_social_codigo: emp.obra_social_codigo || '',
        fuera_convenio,
      });
      if (_comisionObj > 0) {
        reciboFinal = salaryEngine.calcularReciboCCT({
          basico_escala: Number(emp.categoria.sueldo_basico),
          fecha_ingreso: emp.fecha_ingreso,
          periodo, dias_trabajados: dias_recibo,
          obra_social_codigo: emp.obra_social_codigo || '',
          suma_fija_nr: Number(paritaria.suma_fija_nr),
          recompos_nr: Number(paritaria.recompos_nr),
          fuera_convenio, directora,
          otros_remunerativos: (otros_rem || 0) + _comisionObj,
          fraccion_no_rem_override: fraccionNR,
          otros_rem_concepto: { codigo: '0018', nombre: 'Comisiones', unidades_pct: dias_recibo },
        });
        ajuste_blanco = Number(_comisionObj.toFixed(2));
        console.log(`[liquidarEmpleada:objetivo] emp=${empleadoId}: neto base ${recibo.totales.neto} → objetivo ${_objetivoFijo} (0018 bruto ${ajuste_blanco})`);
      }
    }
    // Cálculo provisorio del efectivo para cct_negro. En doble_blanco se recalcula
    // todo más abajo (después de tener prestamo_interes para descontarlo del recibo).
    if (configEmp.modo_liquidacion !== 'doble_blanco') {
      efectivo = Math.max(0, total_negro_esperado - reciboFinal.totales.neto - mercaderia - ajuste);
    }
    // Usar reciboFinal (con básico ajustado si doble_blanco/objetivo, sino el original)

        // ── Cuotas de préstamo del mes (capital sale del banco, interés del efectivo) ──
    // NOTA: NO filtramos por estado='pendiente'. Si la liquidación se regenera
    // después de aplicar las cuotas, queremos seguir descontándolas — el
    // mes_descuento es único por préstamo, así que no hay doble descuento.
    const { data: cuotasPendientes } = await sb.from('rrhh_prestamo_cuota')
      .select('id, monto_capital, monto_interes, estado, prestamo_id, prestamo:rrhh_prestamo!inner(empleado_id, estado)')
      .eq('mes_descuento', periodo + '-01')
      .neq('estado', 'cancelada');
    const cuotasEmp = (cuotasPendientes || []).filter(
      c => c.prestamo?.empleado_id === empleadoId && c.prestamo?.estado === 'activo'
    );
    const prestamo_capital = cuotasEmp.reduce((a, c) => a + Number(c.monto_capital || 0), 0);
    const prestamo_interes = cuotasEmp.reduce((a, c) => a + Number(c.monto_interes || 0), 0);
    // Reparto correcto:
    //   - CAPITAL del préstamo → se descuenta de la TRANSFERENCIA BANCARIA (el recibo legal
    //     sigue diciendo "neto $X", pero a la colaboradora le acreditamos $X − capital).
    //     No afecta al cálculo de efectivo.
    //   - INTERÉS → se descuenta del EFECTIVO (no figura en el recibo blanco).
    // (1-oct-2026, regla JP) En doble blanco la PRIMERA liquidación (proforma) es el
    // recibo puro, igual al del estudio. El ítem 0018 Comisiones (solver) va recién
    // en la SEGUNDA: botón 💎 Doble Blanco o el definitivo, con los sueldos cerrados.
    //   · Una vez aplicado (ajuste_blanco > 0), los recálculos posteriores (⚡, auto-refresh,
    //     cierre) lo MANTIENEN: si no, abrir la grilla borraba el 0018 sin avisar.
    //   · Volver a generar la PROFORMA sí lo saca (vuelve al recibo del estudio).
    const conComision0018 = (configEmp.modo_liquidacion === 'doble_blanco')
      && (!!inputs.soloDobleBlanco || inputs.tipo === 'definitivo'
          || (inputs.tipo !== 'proforma' && ajusteBlancoPrev > 0));
    if (!conComision0018) {
      efectivo = Math.max(0, total_negro_esperado - reciboFinal.totales.neto - mercaderia - ajuste - prestamo_interes);
    } else {
      // ── doble_blanco V2 (junio 2026) ────────────────────────────────────
      // Básico CCT escala pura + concepto 'Comisiones' código 0018 calculado vía
      // solver inverso para que neto_recibo = Total Adorno COMPLETO (sin restar nada).
      // Mercadería + ajuste + intereses se descuentan después en la columna 'A acreditar
      // banco' (junto con préstamo capital), no del recibo. Así el recibo refleja el
      // verdadero total cobrado por la colaboradora (legal: ARCA / LSD ve el total).
      //
      // CRUCIAL: aplicar overrides_manuales ANTES de calcular el neto_objetivo, sino
      // el solver apunta al total automático (sin la comisión manual de Escasany, p.ej.)
      // y deja efectivo > 0.
      const fijoFinal      = (overridesPrev.fijo?.new      != null) ? Number(overridesPrev.fijo.new)      : fijo;
      const comisionFinal  = (overridesPrev.comision?.new  != null) ? Number(overridesPrev.comision.new)  : comision;
      const premioFinal    = (overridesPrev.premio_monto?.new != null) ? Number(overridesPrev.premio_monto.new) : premio;
      const viaticosFinal  = (overridesPrev.viaticos?.new  != null) ? Number(overridesPrev.viaticos.new)  : viaticos;
      const feriadoFinal   = (overridesPrev.feriado_monto?.new != null) ? Number(overridesPrev.feriado_monto.new) : feriado_monto;
      // (3-sep, regla JP) El PAGO DE VACACIONES no entra al recibo doble
      // blanco: se paga en efectivo, fuera del recibo. El solver apunta al
      // total SIN vacaciones y el efectivo queda = vacaciones pagadas.
      const totalNegroReal = fijoFinal + comisionFinal + premioFinal + viaticosFinal + extras + feriadoFinal;
      const neto_objetivo_db = totalNegroReal;
      const comisionVentaBruta = salaryEngine.calcularComisionVentaParaNeto({
        neto_objetivo: neto_objetivo_db,
        neto_recibo_base: recibo.totales.neto,
        obra_social_codigo: emp.obra_social_codigo || '',
        fuera_convenio,
      });
      // Recalcular recibo agregando la comisión venta como otros_remunerativos
      // (suma al total_rem, no lleva antigüedad ni presentismo) pero imprimiéndolo
      // como concepto 'Comisiones' código 0018 (como hace el estudio contable).
      reciboFinal = salaryEngine.calcularReciboCCT({
        basico_escala: Number(emp.categoria.sueldo_basico),
        fecha_ingreso: emp.fecha_ingreso,
        periodo, dias_trabajados: dias_recibo,
        obra_social_codigo: emp.obra_social_codigo || '',
        suma_fija_nr: Number(paritaria.suma_fija_nr),
        recompos_nr: Number(paritaria.recompos_nr),
        fuera_convenio, directora,
        otros_remunerativos: (otros_rem || 0) + comisionVentaBruta,
        fraccion_no_rem_override: fraccionNR,
        otros_rem_concepto: {
          codigo: '0018',
          nombre: 'Comisiones',
          unidades_pct: dias_recibo,
        },
      });
      efectivo = vacacionesPago;   // doble blanco: solo las vacaciones pagadas van por efectivo
      // ajuste_blanco ahora = bruto del ítem 'Comisiones 0018' agregado por solver
      // (cambio de significado vs v1 que era delta del básico, mismo campo en DB).
      ajuste_blanco = Number(comisionVentaBruta.toFixed(2));
    }

    // ── Aplicar overrides_manuales: preservar campos editados manualmente ──
    // Si admin editó algún campo a mano, NO lo pisamos con el cálculo automático.
    // Mantenemos también el JSONB overrides_manuales tal cual.
    const camposOverridables = ['fijo','comision','viaticos','premio_monto','feriado_monto','mercaderia','extras'];
    const valoresOverride = {};
    camposOverridables.forEach(k => {
      if (overridesPrev[k]) {
        valoresOverride[k] = Number(overridesPrev[k].new);
      }
    });

    // ── UPSERT en rrhh_liquidacion ──
    const t = reciboFinal.totales;
    const filaLiq = {
      empleado_id: empleadoId, periodo: periodo + '-01', local: emp.local,
      estado: 'borrador',
      dias_trabajados, mercaderia, ajuste, uniforme_ok,
      puntos_mes, observaciones: inputs.observaciones || null,
      prestamo_capital, prestamo_interes,
      modo_liquidacion: configEmp.modo_liquidacion || 'cct_negro',
      // recibo
      recibo_basico: t.basico, recibo_dia_gremio: t.dia_gremio || 0, recibo_antiguedad: t.antiguedad, recibo_presentismo: t.presentismo,
      recibo_sumafija_nr: t.sumafija_nr, recibo_antig_nr: t.ant_nr, recibo_pres_nr: t.pres_nr,
      recibo_recompos_nr: t.recompos_nr, recibo_otros_rem: t.otros_rem,
      recibo_jubilacion: t.jubilacion, recibo_ley19032: t.ley19032,
      recibo_obra_social: t.obra_social, recibo_sec: t.sec, recibo_faecys: t.faecys,
      recibo_total_rem: t.total_rem, recibo_total_nr: t.total_nr,
      recibo_bruto: t.bruto, recibo_descuentos: t.total_descuentos, recibo_neto: t.neto,
      // negro
      fijo, comision, premio_cobra: cobraPremio, premio_monto: premio,
      viaticos, extras, feriado_dias, feriado_monto,
      vacaciones_pago: vacacionesPago,   // (3-sep) se persiste: en doble blanco es el efectivo
      ajuste_comentario: ajusteComentPrev,
      total_negro: total_negro_esperado,
      efectivo, ajuste_blanco,
      calculado_at: new Date().toISOString(),
      overrides_manuales: overridesPrev,
      tipo: inputs.tipo || tipoPrev || 'proforma',
    };

    // Snapshot/timestamps según tipo
    if (inputs.tipo === 'proforma') {
      filaLiq.proforma_generada_at = new Date().toISOString();
      filaLiq.proforma_snapshot = {
        fijo, comision, viaticos,
        premio_monto: premio,
        feriado_monto, ajuste,
        recibo_neto: t.neto,
        recibo_bruto: t.bruto,
        recibo_total_rem: t.total_rem,
        total_negro: total_negro_esperado,
        efectivo,
        descuento_especial: inputs.descuento_especial || null,
        paritaria_id: paritaria?.id || null,
        snapshot_at: new Date().toISOString(),
      };
      if (inputs.descuento_especial) {
        filaLiq.descuentos_especiales = inputs.descuento_especial;
      }
    } else if (inputs.tipo === 'definitivo') {
      filaLiq.definitivo_generado_at = new Date().toISOString();
    }

    // Aplicar los overrides al filaLiq pisando los campos automáticos
    Object.keys(valoresOverride).forEach(k => {
      // Mapeo de claves del filaLiq: igual (fijo, comision, viaticos, mercaderia, feriado_monto)
      // premio_monto es campo directo en filaLiq
      filaLiq[k] = valoresOverride[k];
    });

    // Recalcular total_negro respetando overrides
    filaLiq.total_negro = (filaLiq.fijo || 0) + (filaLiq.comision || 0) + (filaLiq.premio_monto || 0)
                       + (filaLiq.viaticos || 0) + (filaLiq.extras || 0) + (filaLiq.feriado_monto || 0)
                       + Number(filaLiq.vacaciones_pago || 0);   // (1-oct) sin esto el trigger total_consistente sumaba las vacaciones 2 veces al efectivo
    // Recalcular efectivo: subtotal - mercaderia - intereses - ajuste
    // EXCEPTO en doble_blanco donde efectivo = SOLO el pago de vacaciones
    // (3-sep, regla JP: las vacaciones pagadas no entran al recibo doble blanco).
    if (conComision0018) {
      filaLiq.efectivo = Number(filaLiq.vacaciones_pago || 0);
    } else {
      const subtotalEfMan = Math.max(0, (filaLiq.total_negro || 0) - (filaLiq.recibo_neto || 0));
      filaLiq.efectivo = Math.max(0, subtotalEfMan - (filaLiq.mercaderia || 0) - (prestamo_interes || 0) - (filaLiq.ajuste || 0));
    }

    // Upsert por (empleado_id, periodo)
    const { data: existing } = await sb.from('rrhh_liquidacion')
      .select('id').eq('empleado_id', empleadoId).eq('periodo', periodo + '-01').limit(1);
    let liqId;
    if (existing?.[0]) {
      liqId = existing[0].id;
      const { error } = await sb.from('rrhh_liquidacion').update(filaLiq).eq('id', liqId);
      if (error) throw new Error('Error update liquidación: ' + error.message);
      // Borrar conceptos viejos antes de re-insertar
      await sb.from('rrhh_liquidacion_concepto').delete().eq('liquidacion_id', liqId);
    } else {
      const { data: ins, error } = await sb.from('rrhh_liquidacion').insert(filaLiq).select('id').single();
      if (error) throw new Error('Error insert liquidación: ' + error.message);
      liqId = ins.id;
    }

    // NOTA: Las cuotas se marcan como 'aplicada' al CERRAR el mes
    // (función liqCerrarMes), NO al calcular/regenerar la liquidación.
    // Mientras el mes esté abierto, las cuotas quedan 'pendiente' aunque
    // se haya recalculado la liquidación N veces. Esto evita doble descuento
    // y permite re-cálculo libre antes del cierre formal.
    // Sólo seteamos liquidacion_id en las cuotas para trazabilidad (en pendiente):
    if (cuotasEmp.length > 0) {
      const cuotaIds = cuotasEmp.map(c => c.id);
      await sb.from('rrhh_prestamo_cuota')
        .update({ liquidacion_id: liqId })
        .in('id', cuotaIds);
    }

    // Conceptos
    const conceptos = reciboFinal.conceptos.map(c => ({
      liquidacion_id: liqId,
      codigo: c.codigo, nombre: c.nombre,
      base: c.base, porcentaje: c.porcentaje, importe: c.importe,
      remunerativo: c.remunerativo, es_descuento: c.es_descuento, orden: c.orden,
    }));
    if (conceptos.length) {
      const { error } = await sb.from('rrhh_liquidacion_concepto').insert(conceptos);
      if (error) throw new Error('Error insert conceptos: ' + error.message);
    }

            return { liquidacion_id: liqId, recibo: reciboFinal, totales_negro: { fijo, comision, premio, viaticos, extras, total_negro_esperado, ajuste_blanco, efectivo }, puntos_mes, cobraPremio };
  }

  /**
   * Liquida todas las colaboradoras activas del módulo en un local para un período.
   * Devuelve { ok: [...], errores: [{empleado, error}] }
   */
  async function liquidarMes(local, periodo, opts = {}) {
    // opts puede ser: { tipo: 'proforma'|'definitivo', descuentosEspeciales: {empId: {dias_extra, motivo}}, inputsPorEmpleado: {empId: {...}} }
    // Backwards-compat: si opts es {empId: {...}} (formato viejo), tratarlo como inputsPorEmpleado
    // (31-jul) tipo ya NO defaultea a 'definitivo': si no viene explícito
    // (botones Banco → Proforma/Definitivo), se preserva el de la fila o
    // arranca en 'proforma'. Así el mes nuevo no nace "✓ definitivo".
    const tipo = opts.tipo || null;
    const descuentosEspeciales = opts.descuentosEspeciales || {};
    const inputsPorEmpleado = opts.inputsPorEmpleado || (Object.keys(opts).some(k => /^\d+$/.test(k)) ? opts : {});

    // (26-sep) La escala (y el no remunerativo) se resuelven ANTES de la precarga:
    // si hay que traerla de FAECYS, la paritaria cacheada tiene que ser la nueva.
    await verificarEscalaDelMes(periodo, tipo);

    // ── PRECARGA: datos del mes que son IGUALES para todas las colaboradoras ──
    // Se cargan UNA vez antes del for-loop y se pasan en `opts._cache`
    // a liquidarEmpleada, evitando que cada colaboradora los vuelva a pedir.
    const [py, pm] = periodo.split('-').map(Number);
    const desdeFer = `${periodo}-01`;
    const hastaFer = `${py}-${String(pm).padStart(2,'0')}-${String(diasDelMes(periodo)).padStart(2,'0')}`;
    const [paritariaCache, cfgLocalCache, feriadosCache] = await Promise.all([
      cargarParitaria(periodo),
      cargarConfigLocal(local, periodo),
      sb.from('rrhh_feriados').select('fecha, cierra_oficina, cierra_shoppings')
        .gte('fecha', desdeFer).lte('fecha', hastaFer).then(r => r.data || []),
    ]);
    const cache = { paritaria: paritariaCache, cfgLocal: cfgLocalCache, feriados: feriadosCache, local, periodo };

    const periodoFull = periodo + '-01';
    const { data: configs } = await sb.from('rrhh_sueldo_empleada_config')
      .select('empleado_id, rrhh_empleados!inner(id, apellido, nombre, local, estado)')
      .lte('vigente_desde', periodoFull)
      .eq('activa_en_modulo', true);

    const colaboradoras = (configs || [])
      .filter(c => c.rrhh_empleados?.local === local && c.rrhh_empleados?.estado === 'activo')
      .map(c => c.rrhh_empleados);
    const uniq = {};
    colaboradoras.forEach(e => { uniq[e.id] = e; });
    let lista = Object.values(uniq);
    // Filtro opcional por nombre (cuando el admin tiene el filtro de búsqueda activo)
    const _filtroNom = (opts.filtroNombre || '').toString().toLowerCase().trim();
    if (_filtroNom) {
      lista = lista.filter(e => {
        const txt = ((e.apellido||'') + ' ' + (e.nombre||'') + ' ' + (e.nombre_completo||'')).toLowerCase();
        return txt.includes(_filtroNom);
      });
    }
    // ── Excluir colaboradoras cuyas liquidaciones estén cerradas (estado=firmada) ──
    // El admin tiene que reabrir manualmente (click en 🔒) antes de poder recalcular.
    // Esto protege contra pisar valores ajustados al estudio o cualquier corrección manual.
    const _idsDelLote = lista.map(e => e.id);
    const _firmadas = new Set();
    if (_idsDelLote.length > 0) {
      try {
        const { data: _liqsCheck } = await sb.from('rrhh_liquidacion')
          .select('empleado_id, estado')
          .eq('local', local)
          .eq('periodo', periodo + '-01')
          .in('estado', ['firmada', 'revisada', 'anulada'])
          .in('empleado_id', _idsDelLote);
        (_liqsCheck || []).forEach(r => _firmadas.add(r.empleado_id));
      } catch (_) {}
    }
    if (_firmadas.size > 0) {
      const _nombresFirm = lista.filter(e => _firmadas.has(e.id))
        .map(e => `${e.apellido}, ${e.nombre}`).join('\n  • ');
      const _continuar = confirm(`⚠️ ${_firmadas.size} liquidación(es) están CERRADAS (revisada/firmada/anulada):\n\n  • ${_nombresFirm}\n\nNO se van a procesar. Reabrí esas liquidaciones (click en 🔒) si querés que entren en el recálculo.\n\n¿Continuar con las abiertas?`);
      if (!_continuar) return { ok: [], errores: [] };
      lista = lista.filter(e => !_firmadas.has(e.id));
    }

    const ok = [], errores = [];

    // ── Procesar colaboradoras en paralelo con concurrencia limitada ──
    // Antes era for-await en serie (cada colaboradora esperaba la anterior).
    // Ahora corremos hasta CONCURRENCY simultáneas → 5-10x más rápido.
    const CONCURRENCY = 5;
    const queue = lista.slice();
    async function worker() {
      while (queue.length > 0) {
        const e = queue.shift();
        if (!e) return;
        try {
          // 🚨 (1-oct-2026) Las banderas del botón NUNCA llegaban a liquidarEmpleada: ⚡, 💎 y
          // el cierre de Asistencias hacían todos un recálculo completo. Mientras el doble
          // blanco metía el 0018 siempre, no se notaba; con la regla "0018 solo con 💎 o
          // definitivo", el 💎 dejaba el recibo puro (Contreras/Escasany, sep-2026). Se pasan
          // soloDobleBlanco (para que el 💎 haga lo suyo y saltee al resto) y soloAsistencias
          // (para que el cierre use la RPC que sí pueden ejecutar las encargadas).
          // soloImportes NO se pasa a propósito: ⚡ y el auto-refresh siguen haciendo el
          // recálculo completo que hicieron siempre.
          const empInputs = { ...(inputsPorEmpleado[e.id] || {}), tipo, _cache: cache,
            soloDobleBlanco: !!opts.soloDobleBlanco, soloAsistencias: !!opts.soloAsistencias, silent: !!opts.silent };
          if (descuentosEspeciales[e.id]) {
            empInputs.descuento_especial = descuentosEspeciales[e.id];
          }
          const r = await liquidarEmpleada(e.id, periodo, empInputs);
          if (r?.skipped) {
            // colaboradora fuera del scope del botón usado — ni ok ni error
          } else {
            ok.push({ empleado: e, resultado: r });
          }
        } catch (err) {
          errores.push({ empleado: e, error: err.message });
        }
      }
    }
    await Promise.all(Array.from({ length: Math.min(CONCURRENCY, lista.length) }, worker));
    return { ok, errores };
  }

  return { liquidarEmpleada, liquidarMes, calcularPuntosMes };
})();
