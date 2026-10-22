async function renderLiquidaciones() {
  // Período por defecto (1-oct-2026, JP: "tiré un definitivo sobre octubre queriendo hacerlo
  // sobre septiembre"): mientras el mes ANTERIOR no esté cerrado en Sueldos (Cerrar mes) en
  // todos los locales, se abre en el mes anterior, que es el que se está liquidando. Recién
  // cuando está cerrado en los 3 pasa al mes actual.
  if (!liqState.periodo) {
    const hoy = new Date();
    const mesActual = `${hoy.getFullYear()}-${String(hoy.getMonth()+1).padStart(2,'0')}`;
    const ant = new Date(hoy.getFullYear(), hoy.getMonth() - 1, 1);
    const mesAnterior = `${ant.getFullYear()}-${String(ant.getMonth()+1).padStart(2,'0')}`;
    liqState.periodo = mesActual;
    try {
      const { data: cierres } = await sb.from('rrhh_meses_cerrados_sueldos')
        .select('local').eq('periodo', mesAnterior + '-01');
      const cerrados = new Set((cierres || []).map(c => c.local));
      const faltaCerrar = ['alcorta', 'unicenter', 'oficina'].some(l => !cerrados.has(l));
      if (faltaCerrar) liqState.periodo = mesAnterior;
    } catch (e) { console.warn('[renderLiquidaciones:periodoDefault]', e); }
  }
  const isAdmin     = session.rol === 'admin';
  const isGerente   = session.rol === 'gerente';
  const isDirectora = session.rol === 'directora';
  const soloBanco   = !!session.soloBanco;
  if (soloBanco) liqState.subTab = 'banco';
  // Directora ve TODOS los locales por default (no puede cambiar)
  if (!liqState.local) liqState.local = (isAdmin || isDirectora) ? 'todos' : (session.empleadoData?.local || 'alcorta');
  // (5-ago) La directora/soloBanco ahora SÍ puede filtrar por local
  const local = isGerente ? session.empleadoData.local : liqState.local;
  const periodo = liqState.periodo;

  // Cargar ventas del mes — mismo criterio que cargarVentasLocalMes:
  // fuente primaria = ventas_diarias (Dragonfish); fallback = rrhh_ventas_local_mes.
  let ventasMes = 0;
  let ventas3 = {};
  {
    const [_pyH, _pmH] = periodo.split('-').map(Number);
    const _desdeH = periodo + '-01';
    const _hastaHExcl = (_pmH === 12) ? `${_pyH+1}-01-01` : `${_pyH}-${String(_pmH+1).padStart(2,'0')}-01`;
    const _localesH = (local === 'todos') ? ['alcorta','unicenter','oficina'] : [local];
    for (const loc of _localesH) {
      let total = 0;
      try {
        const { data: dr } = await sb.from('ventas_diarias')
          .select('efectivo, tarjeta, qr, vales, online, fc_oficina, transferencia, cc')
          .eq('local', loc).gte('fecha', _desdeH).lt('fecha', _hastaHExcl);
        if (dr && dr.length > 0) {
          total = dr.reduce((s, v) => s
            + Number(v.efectivo||0) + Number(v.tarjeta||0) + Number(v.qr||0) + Number(v.vales||0)
            + Number(v.online||0)   + Number(v.fc_oficina||0) + Number(v.transferencia||0) + Number(v.cc||0), 0);
        }
      } catch (e) { console.warn('[header:ventas_diarias]', loc, e); }
      if (total === 0) {
        // Fallback histórico
        const { data: row } = await sb.from('rrhh_ventas_local_mes')
          .select('monto_ventas').eq('local', loc).eq('periodo', periodo + '-01').limit(1);
        total = Number(row?.[0]?.monto_ventas || 0);
      }
      if (local === 'todos') ventas3[loc] = total;
      else ventasMes = total;
    }
  }

  // Cargar liquidaciones del mes (un local o todos)
  let qLiq = sb.from('rrhh_liquidacion')
    .select('*, empleado:rrhh_empleados(apellido, nombre, nombre_completo, categoria:rrhh_categorias_cct(nombre))')
    .eq('periodo', periodo + '-01')
    .order('local').order('empleado(apellido)');
  if (local !== 'todos') qLiq = qLiq.eq('local', local);
  const { data: liqsRaw } = await qLiq;
  const liqsAll = liqsRaw || [];

  // ── FILTROS LOCALES (no recargan de Supabase) ──────────────────────
  const busqNorm = (liqState.busqueda || '').toLowerCase().trim();
  const categoriasPresentes = [...new Set(liqsAll.map(l => l.empleado?.categoria?.nombre).filter(Boolean))].sort();
  // Filtros que requieren recálculo (estado/categoría/alertas) — afectan métricas
  // El filtro de búsqueda por nombre NO está acá: se aplica en vivo al DOM por liqFiltrarBusquedaLocal()
  const liqs = liqsAll.filter(l => {
    if (liqState.estado && liqState.estado !== 'todos' && l.estado !== liqState.estado) return false;
    if (liqState.categoria && liqState.categoria !== 'todas' && l.empleado?.categoria?.nombre !== liqState.categoria) return false;
    if (liqState.soloAlertas && (l.puntos_mes || 0) <= 4) return false;
    return true;
  });

  // ── (28-sep, JP) Personal eventual pagado por caja (Nora) ──────────────
  // No tiene fila en rrhh_liquidacion: sale de los recibos de Tesorería con la
  // categoría "Pago Nora", repartidos por los días que cubren (mes) y la caja
  // que pagó (local). Una fila por local. Ya está pagado: suma al Total del
  // costo pero NO al Efectivo a pagar.
  let eventualesLiq = [];
  if (liqState.subTab === 'sueldo' && (!liqState.estado || liqState.estado === 'todos')
      && (!liqState.categoria || liqState.categoria === 'todas') && !liqState.soloAlertas) {
    try {
      const { data: evData, error: evErr } = await sb.rpc('rrhh_eventuales_liquidacion', { p_periodo: periodo + '-01' });
      if (evErr) console.warn('[eventuales]', evErr.message);
      eventualesLiq = (evData || []).filter(e => local === 'todos' || e.local === local);
    } catch (e) { console.warn('[eventuales]', e); }
  }
  window._liqEventuales = eventualesLiq;


  // ─── Revisión Ganancias: leer última corrida + auto-refresh si stale ──
  let gananciasRevisiones = [];
  if (isAdmin) {
    try { gananciasRevisiones = await obtenerRevisionGanancias(periodo); }
    catch (e) { console.warn('Ganancias revisión fail:', e); }
  }

  let periodos = [];
  // (31-jul) anclado al día 1: setMonth() sobre un día 29-31 desborda al mes
  // siguiente (jun 31 → 1-jul) y duplicaba meses en el selector a fin de mes.
  const _hoyP = new Date();
  for (let i = 0; i < 12; i++) {
    const d = new Date(_hoyP.getFullYear(), _hoyP.getMonth() - i, 1);
    periodos.push(`${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}`);
  }
  // Para directora: filtrar solo meses cerrados — early return si no hay ninguno
  // (los usuarios solo-Banco de administración SÍ ven el mes en curso)
  if (isDirectora && !soloBanco) {
    const { data: cerrados } = await sb.from('rrhh_meses_cerrados_sueldos')
      .select('periodo').order('periodo', { ascending: false });
    const setCerrados = new Set((cerrados || []).map(r => r.periodo.substring(0,7)));
    periodos = periodos.filter(p => setCerrados.has(p));
    if (periodos.length === 0) {
      const main = document.getElementById('main');
      if (main) main.innerHTML = `
        <div class="page-header"><h2>Liquidación del mes</h2></div>
        <div class="card" style="padding:60px;text-align:center;">
          <div style="font-size:56px;margin-bottom:14px;">📊</div>
          <h3 style="margin:0 0 8px;font-size:18px;">Todavía no hay meses cerrados</h3>
          <p style="color:var(--muted);font-size:14px;max-width:520px;margin:0 auto;">
            Cuando se cierre formalmente el primer mes vas a recibir una notificación
            y vas a poder ver el liquidador completo desde acá.
          </p>
        </div>
      `;
      return;  // undefined → renderPage NO pisa lo que ya pintamos
    }
    if (!setCerrados.has(liqState.periodo)) {
      liqState.periodo = periodos[0];
    }
  }
  const labelMes = (p) => {
    const [y,m] = p.split('-').map(Number);
    return new Date(y, m-1, 1).toLocaleDateString('es-AR', { month:'long', year:'numeric' });
  };

  const fmt = (n) => '$' + Number(n||0).toLocaleString('es-AR', { minimumFractionDigits: 0, maximumFractionDigits: 0 });

  // ─── Separar Adelantos (1 cuota tasa 0) vs Préstamos largos + intereses live ───
  // NOTA: leemos todas las cuotas del mes SIN filtrar por estado, así no
  // dependemos del campo l.prestamo_interes grabado (que puede quedar mal
  // si la liquidación se regeneró cuando las cuotas estaban 'aplicada').
  const empIdsLiq = [...new Set((liqs||[]).map(l => l.empleado_id))];
  const adelantosPorEmpLiq = {}, prestamosPorEmpLiq = {}, interesesPorEmpLiq = {};
  if (empIdsLiq.length > 0) {
    // BUG FIX: incluir activos + pagados + refinanciados (todo menos cancelados).
    // Si filtramos solo 'activo', los adelantos del mes que se acaba de cerrar
    // pasan a 'pagado' y la columna "Adelantos" queda vacía aunque el descuento
    // sí se hizo. El filtro por mes_descuento + estado cuota (abajo) es el correcto.
    const { data: pAct } = await sb.from('rrhh_prestamo')
      .select('id, empleado_id, estado, cuotas_totales, tasa_mensual')
      .in('empleado_id', empIdsLiq)
      .in('estado', ['activo','pagado']);
    const pMap = {};
    (pAct || []).forEach(p => { pMap[p.id] = p; });
    const idsP = (pAct || []).map(p => p.id);
    if (idsP.length > 0) {
      // Solo cuotas NO canceladas
      const { data: cs } = await sb.from('rrhh_prestamo_cuota')
        .select('prestamo_id, monto_capital, monto_interes, mes_descuento, estado')
        .eq('mes_descuento', periodo + '-01')
        .neq('estado', 'cancelada')
        .in('prestamo_id', idsP);
      (cs || []).forEach(c => {
        const pr = pMap[c.prestamo_id]; if (!pr) return;
        const cap = Number(c.monto_capital || 0);
        const intr = Number(c.monto_interes || 0);
        const esAdel = pr.cuotas_totales === 1 && Number(pr.tasa_mensual||0) === 0;
        if (esAdel) {
          adelantosPorEmpLiq[pr.empleado_id] = (adelantosPorEmpLiq[pr.empleado_id]||0) + cap;
        } else {
          prestamosPorEmpLiq[pr.empleado_id] = (prestamosPorEmpLiq[pr.empleado_id]||0) + cap;
          interesesPorEmpLiq[pr.empleado_id] = (interesesPorEmpLiq[pr.empleado_id]||0) + intr;
        }
      });
    }
  }

  // ─── Desglose de comisión para tooltip ───
  // Precalcula por cada empleada: ventas del local, tasa, activas, fracción, ratio → cálculo
  // Fórmula: ventas_local × tasa × (÷ activas si dividido_activos) × fraccion × ratio
  // Ratio = dias_trab / dias_ref (30 default, promedio del local si dias_local Escasany)
  const comisionDesglosePorEmp = {};
  if (empIdsLiq.length > 0) {
    try {
      const localesSet = new Set((liqs||[]).map(l => l.local).filter(Boolean));
      // 1) Ventas del mes por local
      const { data: ventasRows } = await sb.from('rrhh_ventas_local_mes')
        .select('local, monto_ventas')
        .eq('periodo', periodo + '-01')
        .in('local', Array.from(localesSet));
      const ventasPorLocal = {};
      (ventasRows || []).forEach(v => { ventasPorLocal[v.local] = Number(v.monto_ventas || 0); });
      // (3-ago) Fallback igual al motor: si el local no tiene fila manual,
      // sumar ventas_diarias del mes (Oficina mostraba $0 en el tooltip
      // aunque la comisión real se calculaba bien).
      {
        const [pyV, pmV] = periodo.split('-').map(Number);
        const desdeV = periodo + '-01';
        const hastaV = `${pyV}-${String(pmV).padStart(2,'0')}-${String(new Date(pyV, pmV, 0).getDate()).padStart(2,'0')}`;
        for (const loc of localesSet) {
          if (ventasPorLocal[loc]) continue;
          const { data: vdRows } = await sb.from('ventas_diarias')
            .select('efectivo, tarjeta, qr, vales, online, fc_oficina, transferencia, cc')
            .eq('local', loc).gte('fecha', desdeV).lte('fecha', hastaV);
          ventasPorLocal[loc] = (vdRows || []).reduce((t, v) =>
            t + Number(v.efectivo||0) + Number(v.tarjeta||0) + Number(v.qr||0) + Number(v.vales||0)
              + Number(v.online||0) + Number(v.fc_oficina||0) + Number(v.transferencia||0) + Number(v.cc||0), 0);
        }
      }
      // 2) Config por local (tasa, modo reparto)
      const { data: cfgLocalesRows } = await sb.from('rrhh_sueldo_local_config')
        .select('local, tasa_comision, modo_reparto')
        .in('local', Array.from(localesSet));
      const cfgLocalMap = {};
      (cfgLocalesRows || []).forEach(c => { cfgLocalMap[c.local] = c; });
      // 3) Config por colaboradora (fracción, modo prorrateo, flag día×venta)
      const { data: cfgEmpRows } = await sb.from('rrhh_sueldo_empleada_config')
        .select('empleado_id, fraccion_comision, dias_prorrateo_modo, comision_dia_por_venta')
        .in('empleado_id', empIdsLiq);
      const cfgEmpMap = {};
      (cfgEmpRows || []).forEach(c => { cfgEmpMap[c.empleado_id] = c; });
      // 4) Contar activas por local (solo si algún local tiene modo dividido_activos)
      const activasPorLocal = {};
      for (const loc of localesSet) {
        const cfg = cfgLocalMap[loc];
        if (cfg && cfg.modo_reparto === 'dividido_activos') {
          const { data: acts } = await sb.from('rrhh_sueldo_empleada_config')
            .select('empleado_id, rrhh_empleados!inner(local, estado)')
            .eq('rrhh_empleados.local', loc)
            .eq('rrhh_empleados.estado', 'activo')
            .gt('fraccion_comision', 0);
          activasPorLocal[loc] = (acts || []).length;
        }
      }
      // 5) Días promedio por local (para modo dias_local — Escasany)
      const promDiasPorLocal = {};
      const necesitaProm = (liqs||[]).some(l => {
        const c = cfgEmpMap[l.empleado_id];
        return c && c.dias_prorrateo_modo === 'dias_local';
      });
      if (necesitaProm) {
        for (const loc of localesSet) {
          const otras = (liqs||[])
            .filter(l => l.local === loc)
            .filter(l => {
              const c = cfgEmpMap[l.empleado_id];
              return !c || c.dias_prorrateo_modo !== 'dias_local';
            })
            .map(l => Number(l.dias_trabajados || 0))
            .filter(d => d > 0);
          if (otras.length > 0) {
            promDiasPorLocal[loc] = Math.max(1, Math.ceil(otras.reduce((a,b)=>a+b,0) / otras.length));
          } else {
            promDiasPorLocal[loc] = 26;
          }
        }
      }
      // 6) Para colaboradoras con flag comision_dia_por_venta (Escasany), cargar días fichados + ventas diarias
      const diasLocalEmpIds = (liqs||[])
        .filter(l => {
          const c = cfgEmpMap[l.empleado_id];
          return c && c.comision_dia_por_venta === true;
        })
        .map(l => l.empleado_id);
      const diasFichadosPorEmp = {}; // empleado_id → Set<fecha>
      const ventasDiariasPorLocal = {}; // local → { fecha → monto }
      if (diasLocalEmpIds.length > 0) {
        const [py, pm] = periodo.split('-').map(Number);
        const ultimoDia = new Date(py, pm, 0).getDate();
        const desdeF = `${periodo}-01`;
        const hastaF = `${periodo}-${String(ultimoDia).padStart(2,'0')}`;
        // Asistencias
        const { data: detAsis } = await sb.from('rrhh_asistencias_detalle')
          .select('empleado_id, fecha, estado')
          .in('empleado_id', diasLocalEmpIds)
          .gte('fecha', desdeF).lte('fecha', hastaF);
        (detAsis || []).forEach(d => {
          const est = (d.estado || '').toLowerCase();
          if (['presente','puntual','tarde'].includes(est)) {
            if (!diasFichadosPorEmp[d.empleado_id]) diasFichadosPorEmp[d.empleado_id] = new Set();
            diasFichadosPorEmp[d.empleado_id].add(d.fecha);
          }
        });
        // Ventas diarias por cada local que tiene una colaboradora dias_local
        const localesConFranquera = new Set(
          (liqs||[])
            .filter(l => diasLocalEmpIds.includes(l.empleado_id))
            .map(l => l.local)
        );
        for (const loc of localesConFranquera) {
          const { data: vRows } = await sb.from('ventas_diarias')
            .select('fecha, efectivo, tarjeta, qr, vales, online, fc_oficina, transferencia, cc')
            .eq('local', loc)
            .gte('fecha', desdeF).lte('fecha', hastaF);
          ventasDiariasPorLocal[loc] = {};
          (vRows || []).forEach(v => {
            const t = Number(v.efectivo||0) + Number(v.tarjeta||0) + Number(v.qr||0) + Number(v.vales||0)
                    + Number(v.online||0) + Number(v.fc_oficina||0) + Number(v.transferencia||0) + Number(v.cc||0);
            ventasDiariasPorLocal[loc][v.fecha] = t;
          });
        }
      }
      // 7) Calcular desglose por empleada
      (liqs||[]).forEach(l => {
        const cfgL = cfgLocalMap[l.local];
        const cfgE = cfgEmpMap[l.empleado_id];
        if (!cfgL || !cfgE) return;
        const ventasLocal = ventasPorLocal[l.local] || 0;
        const tasa = Number(cfgL.tasa_comision || 0);
        const fraccion = Number(cfgE.fraccion_comision || 0);
        const usaDiaXVenta = cfgE.comision_dia_por_venta === true;
        const modo = usaDiaXVenta ? 'dia_x_venta' : (cfgE.dias_prorrateo_modo || 'mes_30');
        const diasTrab = Number(l.dias_trabajados || 0);
        if (usaDiaXVenta) {
          // Suma día × venta
          const fichadas = diasFichadosPorEmp[l.empleado_id] || new Set();
          const ventasLoc = ventasDiariasPorLocal[l.local] || {};
          const detArr = Array.from(fichadas).sort().map(f => ({ fecha: f, monto: ventasLoc[f] || 0 }));
          const sumaVentas = detArr.reduce((s, d) => s + d.monto, 0);
          const comisionBase = sumaVentas * tasa;
          const comisionCalc = comisionBase * fraccion;
          comisionDesglosePorEmp[l.empleado_id] = {
            modo, tasa, fraccion, dias: detArr, sumaVentas, comisionBase, comisionCalc,
          };
        } else {
          // Modo mes_30 clásico
          const diasRef = 30;
          const ratio = diasRef > 0 ? diasTrab / diasRef : 0;
          let comisionBase = ventasLocal * tasa;
          let activas = null;
          if (cfgL.modo_reparto === 'dividido_activos') {
            activas = activasPorLocal[l.local] || null;
            if (activas && activas > 0) comisionBase = comisionBase / activas;
          }
          const comisionCalc = comisionBase * fraccion * ratio;
          comisionDesglosePorEmp[l.empleado_id] = {
            modo, ventasLocal, tasa, activas, fraccion, diasRef, diasTrab, ratio, comisionBase, comisionCalc,
          };
        }
      });
    } catch (e) {
      console.warn('[comisionDesglose] error:', e);
    }
  }

  // ═══ DESGLOSE DE VIÁTICOS (tooltip) — (1-oct-2026, JP) ═══
  // Mismos datos que usa liquidarEmpleada: viático completo de la config vigente, días pagos
  // (dias_trabajados), menos vacaciones y licencias CON goce (no viajó). Solo informa.
  const viaticosDesglosePorEmp = {};
  if (empIdsLiq.length > 0) {
    try {
      const [pyVi, pmVi] = periodo.split('-').map(Number);
      const desdeVi = periodo + '-01';
      const hastaVi = `${periodo}-${String(new Date(pyVi, pmVi, 0).getDate()).padStart(2, '0')}`;
      const [cfgV, detV, licV, certV, cierV] = await Promise.all([
        sb.from('rrhh_sueldo_empleada_config').select('empleado_id, viaticos, dias_prorrateo_modo, vigente_desde')
          .in('empleado_id', empIdsLiq).lte('vigente_desde', desdeVi).order('vigente_desde', { ascending: true }),
        sb.from('rrhh_asistencias_detalle').select('empleado_id, fecha, estado')
          .in('empleado_id', empIdsLiq).gte('fecha', desdeVi).lte('fecha', hastaVi).in('estado', ['vacaciones', 'licencia']),
        sb.from('rrhh_licencias').select('empleado_id, fecha_desde, fecha_hasta, paga')
          .in('empleado_id', empIdsLiq).lte('fecha_desde', hastaVi).gte('fecha_hasta', desdeVi),
        sb.from('rrhh_certificados_medicos').select('empleado_id, fecha_desde, fecha_hasta')
          .in('empleado_id', empIdsLiq).lte('fecha_desde', hastaVi).gte('fecha_hasta', desdeVi),
        sb.from('rrhh_meses_cerrados').select('local').eq('año', pyVi).eq('mes', pmVi),
      ]);
      const cfgVig = {};
      (cfgV.data || []).forEach(c => { cfgVig[c.empleado_id] = c; });      // la última (más reciente) gana
      const cerradoAsis = new Set((cierV.data || []).map(c => c.local));
      const ddmm = f => f.slice(8, 10) + '/' + f.slice(5, 7);
      (liqs || []).forEach(l => {
        const cfg = cfgVig[l.empleado_id];
        if (!cfg) return;
        const mios = (detV.data || []).filter(d => d.empleado_id === l.empleado_id);
        const vac = mios.filter(d => d.estado === 'vacaciones').map(d => d.fecha).sort();
        const licPagas = mios.filter(d => d.estado === 'licencia').map(d => d.fecha).sort().filter(f => {
          const li = (licV.data || []).find(x => x.empleado_id === l.empleado_id && x.fecha_desde <= f && x.fecha_hasta >= f);
          if (li) return !!li.paga;
          return (certV.data || []).some(x => x.empleado_id === l.empleado_id && x.fecha_desde <= f && x.fecha_hasta >= f);
        });
        viaticosDesglosePorEmp[l.empleado_id] = {
          completo: Number(cfg.viaticos || 0), modo: cfg.dias_prorrateo_modo || 'mes_30',
          diasPagos: Number(l.dias_trabajados || 0), vac: vac.map(ddmm), licPagas: licPagas.map(ddmm),
          asistenciasCerradas: cerradoAsis.has(l.local),
        };
      });
    } catch (e) {
      console.warn('[viaticosDesglose] error:', e);
    }
  }

  // ── SORT (click en header) — se hace AHORA porque algunos sorts usan préstamos/adelantos
  if (liqState.sortBy) {
    const dir = liqState.sortDir === 'desc' ? -1 : 1;
    // Cálculo local de esMesSAC (la variable global se define más abajo)
    const _mesN = parseInt(periodo.split('-')[1], 10);
    const esMesSAC = (_mesN === 6 || _mesN === 12);
    const getVal = (l) => {
      switch (liqState.sortBy) {
        case 'empleada':   return (l.empleado?.apellido || '').toLowerCase();
        case 'local':      return l.local || '';
        case 'dias':       return Number(l.dias_trabajados || 0);
        case 'puntos':     return Number(l.puntos_mes || 0);
        case 'total':      return Number(l.total_negro || 0);
        case 'recibo':     return Number(l.recibo_neto || 0) + (esMesSAC ? Number(l.sac_recibo_neto || 0) : 0);
        case 'banco':      return Number(l.recibo_neto || 0) + (esMesSAC ? Number(l.sac_recibo_neto || 0) : 0) - (prestamosPorEmpLiq[l.empleado_id] || 0) - (adelantosPorEmpLiq[l.empleado_id] || 0);
        case 'efectivo':   {
            const sac = sacPorEmp[l.empleado_id] || 0;
            const sacRec = esMesSAC ? Number(l.sac_recibo_neto || 0) : 0;
            const subtotal = Math.max(0, (+l.total_negro || 0) + sac - (+l.recibo_neto || 0) - sacRec);
            const intrLive = interesesPorEmpLiq[l.empleado_id] || 0;
            return Math.max(0, subtotal - Number(l.mercaderia || 0) - intrLive - Number(l.ajuste || 0));
          }
        case 'subtotal_efectivo': {
            const sac = sacPorEmp[l.empleado_id] || 0;
            const sacRec = esMesSAC ? Number(l.sac_recibo_neto || 0) : 0;
            return Math.max(0, (+l.total_negro || 0) + sac - (+l.recibo_neto || 0) - sacRec);
          }
        case 'cat':        return (l.empleado?.categoria?.nombre || '').toLowerCase();
        case 'antiguedad': return (l.empleado?.fecha_ingreso || '9999-12-31'); // más viejo = más antigüedad
        case 'bruto':      return Number(l.recibo_bruto || 0);
        case 'descuentos': return Number(l.recibo_descuentos || 0);
        case 'fijo':       return Number(l.fijo || 0);
        case 'comision':   return Number(l.comision || 0);
        case 'premios':    return l.premio_cobra ? Number(l.premio_monto || 0) : 0;
        case 'viaticos':   return Number(l.viaticos || 0);
        case 'feriado':    return Number(l.feriado_monto || 0);
        case 'sac':        return sacPorEmp[l.empleado_id] || 0;
        case 'extras':     return Number(l.extras || 0);
        case 'prestamos':  return prestamosPorEmpLiq[l.empleado_id] || 0;
        case 'adelantos':  return adelantosPorEmpLiq[l.empleado_id] || 0;
        case 'mercaderia': return Number(l.mercaderia || 0);
        case 'intereses':  return interesesPorEmpLiq[l.empleado_id] || 0;
        case 'ajustes':    return Number(l.ajuste || 0);
        default:           return 0;
      }
    };
    liqs.sort((a, b) => {
      const va = getVal(a), vb = getVal(b);
      if (va < vb) return -1 * dir;
      if (va > vb) return  1 * dir;
      return 0;
    });
  }

  // ─── SAC (aguinaldo): solo en junio y diciembre. Auto = mejor bruto del
  //     semestre (Fijo+Comisión+Premio+Viáticos+Extras = total_negro) / 12
  //     × meses trabajados del semestre. En Adorno el "total_negro" del sistema
  //     es el bruto real que cobra la colaboradora (blanco+negro conceptualmente).
  const mesNumero = parseInt(periodo.split('-')[1], 10);
  const esMesSAC = mesNumero === 6 || mesNumero === 12;
  const sacPorEmp = {};
  const sacDetallePorEmp = {}; // para tooltip: {mejorBruto, mesesT, mejorPeriodo}
  if (esMesSAC && empIdsLiq.length > 0) {
    const ay = periodo.split('-')[0];
    const semStart = mesNumero === 6 ? `${ay}-01-01` : `${ay}-07-01`;
    const semEnd   = mesNumero === 6 ? `${ay}-06-30` : `${ay}-12-31`;
    const { data: liqsSem } = await sb.from('rrhh_liquidacion')
      .select('empleado_id, total_negro, periodo')
      .in('empleado_id', empIdsLiq)
      .gte('periodo', semStart).lte('periodo', semEnd);
    const mejor = {}, mesesT = {}, detalle = {};
    (liqsSem || []).forEach(l => {
      const bruto = Number(l.total_negro || 0);
      if (!mejor[l.empleado_id] || bruto > mejor[l.empleado_id]) {
        mejor[l.empleado_id] = bruto;
        detalle[l.empleado_id] = { mejorBruto: bruto, mejorPeriodo: l.periodo };
      }
      mesesT[l.empleado_id] = (mesesT[l.empleado_id] || 0) + 1;
    });
    Object.entries(mejor).forEach(([eid, v]) => {
      const meses = Math.min(6, mesesT[eid] || 0);
      sacPorEmp[eid] = (v / 12) * meses;
      sacDetallePorEmp[eid] = { ...detalle[eid], mesesT: mesesT[eid] || 0, mesesUsados: meses };
    });
  }

  // ── Estado de cierre del mes en ASISTENCIAS (per local) ──
  // Si el local está cerrado, los puntos/faltas ya están consolidados.
  // Si NO está cerrado, los puntos pueden cambiar y la liquidación queda inconsistente.
  const periodoFull = periodo + '-01';
  const [_anioCierre, _mesCierre] = periodo.split('-').map(Number);
  const localesACheck = (local === 'todos') ? ['alcorta','unicenter','oficina'] : [local];
  const { data: cierresRows, error: _errCierres } = await sb.from('rrhh_meses_cerrados')
    .select('local, cerrado_por, cerrado_at')
    .eq('año', _anioCierre).eq('mes', _mesCierre)
    .in('local', localesACheck);
  if (_errCierres) console.warn('[cierresMes] error', _errCierres);
  const cierresMes = {};
  (cierresRows || []).forEach(c => { cierresMes[c.local] = c; });

  // Cierre de SUELDOS (rrhh_meses_cerrados_sueldos) — independiente del de asistencias.
  // Indica que la liquidación está congelada (recibos firmados/pagos hechos).
  const { data: cierresSueldosRows } = await sb.from('rrhh_meses_cerrados_sueldos')
    .select('local, cerrado_por, cerrado_at, periodo')
    .eq('periodo', periodoFull)
    .in('local', localesACheck);
  const cierresSueldos = {};
  (cierresSueldosRows || []).forEach(c => { cierresSueldos[c.local] = c; });

  let totalRecibo=0, totalNegro=0, totalEfectivo=0, totalBanco=0, totalPrestamoCap=0, totalAdelantos=0, totalSAC=0;
  (liqs||[]).forEach(l => {
    const adel = adelantosPorEmpLiq[l.empleado_id] || 0;
    const pres = prestamosPorEmpLiq[l.empleado_id] || 0;
    const sac  = sacPorEmp[l.empleado_id] || 0;
    totalRecibo    += +l.recibo_neto||0;
    totalNegro     += (+l.total_negro||0) + sac;
    totalEfectivo  += +l.efectivo||0;
    totalPrestamoCap += pres;
    totalAdelantos += adel;
    totalSAC       += sac;
    totalBanco     += (+l.recibo_neto||0) - pres - adel;
  });

  return `
    <div class="page-header">
      <h2>Liquidación del mes</h2>
      <div class="subtitle">Cálculo del recibo CCT + lo que cobra cada colaboradora según la fórmula de Adorno (fijo + comisión + premio + viáticos + extras).</div>
    </div>

    <!-- ══════ LÍNEA 1: Sub-tabs + Ventas + Guardar + Acciones + Kebab ══════ -->
    <!-- sticky: al scrollear la grilla no se pierden Proforma/Definitivo/⋮ -->
    <div class="cal-toolbar liq-toolbar-sticky" style="align-items:center;">
      <!-- Sub-tabs -->
      <div style="display:flex;gap:2px;">
        ${session.soloBanco ? '' : `<button onclick="liqSwitchSubTab('sueldo')" style="padding:8px 18px;border:none;background:transparent;font-size:14px;font-weight:${liqState.subTab==='sueldo'?'700':'500'};color:${liqState.subTab==='sueldo'?'var(--accent2)':'var(--muted)'};border-bottom:3px solid ${liqState.subTab==='sueldo'?'var(--accent2)':'transparent'};cursor:pointer;transition:all 0.15s;">💰 Sueldo</button>`}
        <button onclick="liqSwitchSubTab('banco')" style="padding:8px 18px;border:none;background:transparent;font-size:14px;font-weight:${liqState.subTab==='banco'?'700':'500'};color:${liqState.subTab==='banco'?'var(--accent2)':'var(--muted)'};border-bottom:3px solid ${liqState.subTab==='banco'?'var(--accent2)':'transparent'};cursor:pointer;transition:all 0.15s;">🏦 Banco</button>
      </div>
      <span id="liq-auto-refresh-indicator" style="align-self:center;margin-left:8px;"></span>
      <div style="margin-left:auto;display:flex;gap:8px;align-items:center;flex-wrap:wrap;">
        ${local === 'todos' ? `
          <div style="display:flex;gap:6px;font-size:12px;">
            ${['alcorta','unicenter','oficina'].map(loc => `
              <div style="background:#f3f4f6;border-radius:6px;padding:4px 8px;">
                <span style="color:var(--muted);">${LOCALES[loc]?.nombre || loc}:</span>
                <strong style="font-family:monospace;">$${Number(ventas3[loc]||0).toLocaleString('es-AR')}</strong>
              </div>`).join('')}
          </div>
        ` : `
          <label style="font-size:13px;color:var(--muted);">Ventas del mes:</label>
          <input type="number" id="liq-ventas" value="${ventasMes}" style="width:160px;text-align:right;font-family:monospace;" ${isAdmin?'':'disabled'}>
          ${isAdmin ? `<button class="btn small" onclick="liqGuardarVentas('${local}','${periodo}')">💾 Guardar</button>` : ''}
        `}
        ${(liqState.subTab === 'sueldo') ? `
          <!-- ════ BOTONES DE SUELDO (colores jerarquizados v204) ════ -->
          ${isAdmin ? `<button class="btn" style="background:white;color:#b91c1c;border:1px solid #fecaca;" onmouseover="this.style.background='#fef2f2'" onmouseout="this.style.background='white'" onclick="liqCerrarMes('${local}','${periodo}')" title="Cierra formalmente el mes una vez abonados los sueldos. Al cerrar, se generan automáticamente los borradores proforma del mes siguiente con los fijos actualizados.">🔒 Cerrar mes</button>` : ''}
        ` : `
          <!-- ════ BOTONES DE BANCO (colores jerarquizados v204) ════ -->
          ${isAdmin ? `<button class="btn" style="background:white;color:#92400e;border:1px solid #fcd34d;" onmouseover="this.style.background='#fef3c7'" onmouseout="this.style.background='white'" onclick="liqGenerarProforma('${local}','${periodo}')" title="Genera la liquidación PROFORMA (base para transferencia bancaria, antes del cierre del mes). Pregunta por descuentos especiales.">📋 Proforma</button>` : ''}
          ${isAdmin ? `<button class="btn primary" onclick="liqGenerarDefinitivo('${local}','${periodo}')" title="Genera la liquidación DEFINITIVA (re-aplica paritaria vigente, compara con proforma si existe, genera PDFs firmables).">✅ Definitivo</button>` : ''}
          ${isAdmin ? `<button class="btn" style="background:white;color:#6b21a8;border:1px solid #ddd6fe;" onmouseover="this.style.background='#f5f3ff'" onmouseout="this.style.background='white'" onclick="liqGenerarDobleBlanco('${local}','${periodo}')" title="Procesa SOLO colaboradoras en modo doble_blanco (Contreras, Escasany). Recalcula importes + recibo + solver inverso del ítem 0018 Comisiones.">💎 Doble Blanco</button>` : ''}
          ${(isAdmin || isGerente || soloBanco) ? `<button class="btn" onclick="descargarTodosRecibosCombinados('${local}','${periodo}')" title="Descargar PDF combinado con TODOS los recibos del mes — listo para imprimir y firmar">🖨️ Imprimir recibos</button>` : ''}
          ${(isAdmin || soloBanco) ? `
            <div class="liq-export-dd" style="position:relative;display:inline-block;">
              <button class="btn" onclick="liqToggleExportMenu(this, event)" title="Descargar archivos para el estudio contable">📤 Exportar ▾</button>
              <div id="liq-export-menu" style="display:none;position:absolute;top:calc(100% + 4px);right:0;background:white;border:1px solid var(--border);border-radius:8px;box-shadow:0 6px 18px rgba(0,0,0,0.12);min-width:220px;z-index:20;overflow:hidden;">
                <button class="liq-export-item" onclick="liqCloseExportMenu();exportarGaliciaXLSX('${local}','${periodo}')" style="width:100%;text-align:left;padding:10px 14px;border:none;background:transparent;cursor:pointer;font-size:13px;display:flex;align-items:center;gap:10px;" onmouseover="this.style.background='#f9fafb'" onmouseout="this.style.background='transparent'" title="Descargar .xlsx con formato Galicia Office para subir al portal">
                  <span style="font-size:15px;">📤</span> <span><strong>Galicia</strong><br><span style="font-size:11px;color:var(--muted);">.xlsx para Office Banking</span></span>
                </button>
                <button class="liq-export-item" onclick="liqCloseExportMenu();generarLSDTxtAuto('${periodo}','${local}')" style="width:100%;text-align:left;padding:10px 14px;border:none;background:transparent;cursor:pointer;font-size:13px;display:flex;align-items:center;gap:10px;border-top:1px solid var(--border);" onmouseover="this.style.background='#f9fafb'" onmouseout="this.style.background='transparent'" title="Libro de Sueldos Digital para ARCA (ex AFIP)">
                  <span style="font-size:15px;">📄</span> <span><strong>LSD ARCA</strong><br><span style="font-size:11px;color:var(--muted);">.txt Libro Sueldos Digital</span></span>
                </button>
                <button class="liq-export-item" onclick="liqCloseExportMenu();exportarPlanillaBlancaLiq('${local}','${periodo}')" style="width:100%;text-align:left;padding:10px 14px;border:none;background:transparent;cursor:pointer;font-size:13px;display:flex;align-items:center;gap:10px;border-top:1px solid var(--border);" onmouseover="this.style.background='#f9fafb'" onmouseout="this.style.background='transparent'" title="Excel solo con la parte blanca">
                  <span style="font-size:15px;">📋</span> <span><strong>Planilla blanca</strong><br><span style="font-size:11px;color:var(--muted);">.xlsx solo parte blanca</span></span>
                </button>
              </div>
            </div>
          ` : ''}
        `}

        <!-- ══════ KEBAB MENU ⋮ (utilidades ocasionales) ══════ -->
        ${isAdmin ? `
        <div class="liq-kebab-dd" style="position:relative;display:inline-block;">
          <button class="btn" onclick="liqToggleKebabMenu(this, event)" title="Más opciones" style="padding:6px 10px;font-size:16px;line-height:1;">⋮</button>
          <div id="liq-kebab-menu" style="display:none;position:absolute;top:calc(100% + 4px);right:0;background:white;border:1px solid var(--border);border-radius:8px;box-shadow:0 6px 18px rgba(0,0,0,0.12);min-width:200px;z-index:20;overflow:hidden;">
            <button class="liq-kebab-item" onclick="liqCloseKebabMenu();switchTab('liquidaciones')" style="width:100%;text-align:left;padding:10px 14px;border:none;background:transparent;cursor:pointer;font-size:13px;display:flex;align-items:center;gap:10px;" onmouseover="this.style.background='#f9fafb'" onmouseout="this.style.background='transparent'" title="Recargar desde la base de datos">
              <span style="font-size:15px;">🔄</span> <span>Refrescar</span>
            </button>
            <button class="liq-kebab-item" onclick="liqCloseKebabMenu();liqAbrirConfigCols()" style="width:100%;text-align:left;padding:10px 14px;border:none;background:transparent;cursor:pointer;font-size:13px;display:flex;align-items:center;gap:10px;border-top:1px solid var(--border);" onmouseover="this.style.background='#f9fafb'" onmouseout="this.style.background='transparent'" title="Mostrar/ocultar y reordenar columnas">
              <span style="font-size:15px;">⚙️</span> <span>Columnas</span>
            </button>
          </div>
        </div>
        ` : ''}
      </div>
    </div>

    <!-- ══════ LÍNEA 2: Mes + Local + Filtros + Contador ══════ -->
    <div class="cal-toolbar" style="margin-top:8px;padding:8px 12px;background:#f9fafb;border-radius:8px;font-size:13px;">
      <select onchange="liqState.periodo=this.value; switchTab('liquidaciones');" style="padding:5px 8px;font-weight:600;">
        ${periodos.map(p => `<option value="${p}" ${p===periodo?'selected':''}>${labelMes(p)}</option>`).join('')}
      </select>
      ${(isAdmin || session.soloBanco) ? `<select onchange="liqState.local=this.value; switchTab('liquidaciones');" style="padding:5px 8px;font-weight:600;">
        <option value="todos"     ${local==='todos'    ?'selected':''}>Todos los locales</option>
        <option value="alcorta"   ${local==='alcorta'  ?'selected':''}>Alcorta</option>
        <option value="unicenter" ${local==='unicenter'?'selected':''}>Unicenter</option>
        <option value="oficina"   ${local==='oficina'  ?'selected':''}>Oficina</option>
      </select>` : `<span class="emp-tag" style="background:#eef2ff;color:#4338ca;">${LOCALES[local]?.nombre || local}</span>`}
      <span style="width:1px;height:22px;background:var(--border);margin:0 4px;"></span>
      <input type="text" id="liq-busqueda" placeholder="🔍 Buscar por nombre…"
             value="${escapeHtml(liqState.busqueda || '')}"
             oninput="liqState.busqueda = this.value; liqFiltrarBusquedaLocal();"
             style="flex:0 0 220px;padding:6px 10px;border:1px solid var(--border);border-radius:6px;font-size:13px;">

      <label style="display:flex;align-items:center;gap:6px;color:var(--muted);">Estado:
        <select onchange="liqState.estado=this.value; switchTab('liquidaciones');" style="padding:5px 8px;">
          <option value="todos"    ${liqState.estado==='todos'?'selected':''}>Todos</option>
          <option value="borrador" ${liqState.estado==='borrador'?'selected':''}>Borrador</option>
          <option value="revisada" ${liqState.estado==='revisada'?'selected':''}>Revisada</option>
          <option value="firmada"  ${liqState.estado==='firmada'?'selected':''}>Firmada</option>
          <option value="anulada"  ${liqState.estado==='anulada'?'selected':''}>Anulada</option>
        </select>
      </label>

      ${categoriasPresentes.length > 0 ? `<label style="display:flex;align-items:center;gap:6px;color:var(--muted);">Categoría:
        <select onchange="liqState.categoria=this.value; switchTab('liquidaciones');" style="padding:5px 8px;max-width:240px;">
          <option value="todas" ${liqState.categoria==='todas'?'selected':''}>Todas</option>
          ${categoriasPresentes.map(c => `<option value="${escapeHtml(c)}" ${liqState.categoria===c?'selected':''}>${escapeHtml(c)}</option>`).join('')}
        </select>
      </label>` : ''}

      <div style="margin-left:auto;color:var(--muted);font-size:12px;display:flex;align-items:center;gap:8px;">
        <span>Mostrando <strong style="color:var(--text);">${liqs.length}</strong> de ${liqsAll.length}</span>
        ${(busqNorm || liqState.estado !== 'todos' || liqState.categoria !== 'todas' || liqState.soloAlertas)
          ? `<button class="btn small" onclick="liqLimpiarFiltros()" title="Limpiar todos los filtros">✕ Limpiar</button>`
          : ''}
      </div>
    </div>

    ${(liqs||[]).length === 0 ? (liqsAll.length === 0 ? `
      <div class="card"><div class="placeholder">
        <div class="icon">🧮</div>
        <h3>Aún no hay liquidaciones para este mes</h3>
        <p>Cargá las ventas del local del mes y dale "Generar mes" para calcular todas las liquidaciones.</p>
      </div></div>
    ` : `
      <div class="card"><div class="placeholder">
        <div class="icon">🔎</div>
        <h3>Ningún resultado coincide con los filtros</h3>
        <p>Probá limpiar la búsqueda, cambiar el estado o desmarcar "Solo con alertas".</p>
        <button class="btn primary" style="margin-top:10px;" onclick="liqLimpiarFiltros()">✕ Limpiar filtros</button>
      </div></div>
    `) : `
      <!-- BADGES de cierre del mes: ASISTENCIAS + SUELDOS por local -->
      ${(() => {
        const chip = (color, bg, border, icon, label, tip) =>
          `<span style="background:${bg};border:1px solid ${border};border-radius:4px;padding:2px 7px;font-size:11px;font-weight:600;color:${color};display:inline-flex;align-items:center;gap:3px;" title="${tip}">${icon} ${label}</span>`;
        const blocks = localesACheck.map(loc => {
          const nombre = LOCALES[loc]?.nombre || loc;
          const cA = cierresMes[loc];
          const cS = cierresSueldos[loc];

          const chipAsis = cA
            ? chip('#065f46','#dcfce7','#16a34a','✓',`Asistencias cerradas (${(cA.cerrado_at||'').split('T')[0]})`,
                `Asistencias cerradas por ${escapeHtml((cA.cerrado_por||'').split('@')[0])} — los puntos están consolidados`)
            : chip('#92400e','#fef3c7','#d97706','⏳','Asistencias abiertas',
                'El mes NO está cerrado en Asistencias — los puntos y faltas pueden cambiar');

          const chipSueldos = cS
            ? chip('#065f46','#dcfce7','#16a34a','✓',`Mes cerrado (${(cS.cerrado_at||'').split('T')[0]})`,
                `Sueldos cerrados por ${escapeHtml((cS.cerrado_por||'').split('@')[0])} — recibos firmados / pagos hechos`)
            : chip('#92400e','#fef3c7','#d97706','⏳','Mes abierto',
                'El mes NO está cerrado en Sueldos — la liquidación puede modificarse');

          const btnCerrar = (!cA && (isAdmin || isGerente))
            ? `<button class="btn small" style="margin-left:6px;" onclick="switchTab('asistencias')" title="Ir a Asistencias para cerrar el mes">Cerrar asistencias →</button>`
            : '';

          return `<div style="background:#f8fafc;border:1px solid #e2e8f0;border-radius:6px;padding:6px 10px;font-size:12px;display:flex;align-items:center;gap:8px;flex-wrap:wrap;">
            <strong style="color:#1e293b;">${escapeHtml(nombre)}:</strong>
            ${chipAsis}
            ${chipSueldos}
            ${btnCerrar}
          </div>`;
        }).join('');
        return `<div style="display:flex;gap:8px;margin-bottom:12px;flex-wrap:wrap;">${blocks}</div>`;
      })()}

      ${(() => {
        const alertas = (gananciasRevisiones || []).filter(g => g.revision && (g.revision.estado === 'al_borde' || g.revision.estado === 'excedido'));
        if (alertas.length === 0) return '';
        const hayExcedido = alertas.some(a => a.revision.estado === 'excedido');
        const bg = hayExcedido ? '#fef2f2' : '#fef9c3';
        const border = hayExcedido ? '#dc2626' : '#d97706';
        const icono = hayExcedido ? '🔴' : '🟡';
        const titulo = hayExcedido ? 'Tope Ganancias: hay colaboradoras excedidas' : 'Tope Ganancias: hay colaboradoras al borde';
        const lineas = alertas.map(a => {
          const r = a.revision;
          const lbl = r.estado === 'excedido' ? 'excedido' : 'al borde';
          const monto = '$' + Math.round(Math.abs(r.excedente)).toLocaleString('es-AR');
          return `<strong>${escapeHtml(a.nombre_completo.split(',')[0])}</strong>: ${monto} ${lbl}`;
        }).join(' · ');
        return `
          <div class="card" style="background:${bg};border-left:4px solid ${border};padding:12px 16px;margin-bottom:14px;display:flex;align-items:center;gap:12px;">
            <div style="font-size:22px;">${icono}</div>
            <div style="flex:1;font-size:13.5px;color:#1f2937;">
              <div style="font-weight:600;margin-bottom:2px;">${titulo}</div>
              <div>${lineas}</div>
            </div>
            <button class="btn" onclick="mostrarDetalleGanancias()" style="background:${border};color:white;border-color:${border};">Ver detalle</button>
          </div>
        `;
      })()}

      <!-- Scroll horizontal DOBLE (arriba + abajo) sincronizado con la tabla.
           #liq-scroll-main scrollea EN AMBOS EJES para que:
             - el thead sticky (top:0) se anchore ACÁ y quede fijo al bajar
             - la col Colaboradora sticky (left:0) se anchore ACÁ y quede fija al ir a la derecha
           El max-height se ajusta dinámicamente por JS (liqWireScrollDoble). -->
      <div class="card" style="padding:0;">
        <div id="liq-scroll-top" style="overflow-x:auto;overflow-y:hidden;height:14px;border-bottom:1px solid var(--border);">
          <div id="liq-scroll-top-inner" style="height:1px;"></div>
        </div>
      <div id="liq-scroll-main" style="overflow:auto;padding:14px;">
        ${(() => {
          // ── Definición de TODAS las columnas posibles del Liquidador ──
          // ─── Helper para renderizar celdas editables con override visual ───
          const renderEditableCell = (l, c, campo, valor, opts = {}) => {
            const ov = l.overrides_manuales && l.overrides_manuales[campo];
            const isOverride = !!ov;
            const bgBase = opts.bg || '';
            const bgOverride = isOverride ? 'background:#f3e8ff !important;border-left:3px solid #9333ea;' : (bgBase ? `background:${bgBase};` : '');
            const cursor = c.isAdmin ? 'cursor:pointer;' : '';
            const clickHandler = c.isAdmin ? `onclick="liqEditarCelda(${l.id}, '${campo}', '${opts.label || campo}', ${Number(valor || 0)})"` : '';
            const titleAttr = isOverride
              ? `title="✏️ Editado manualmente por ${ov.by} el ${new Date(ov.at).toLocaleString('es-AR')}. Anterior: $${Math.round(ov.old).toLocaleString('es-AR')}. Motivo: ${ov.motivo || '—'}. Click para volver a editar."`
              : (c.isAdmin ? 'title="Click para editar manualmente"' : '');
            const txtFmt = (valor != null && valor !== '') ? c.fmt(valor) : '—';
            const styleExtra = opts.styleExtra || '';
            return `<td style="padding:8px;font-family:monospace;${bgOverride}${cursor}${styleExtra}" ${clickHandler} ${titleAttr}>${isOverride ? '✏️ ' : ''}${txtFmt}</td>`;
          };

          const ALL_COLS = [
            { id:'empleada',  label:'Empleada',   sortKey:'empleada', thOpts:{align:'text-align:left'},
              tdRender:(l,c)=>{
                const mono = l.empleado?.monotributista
                  ? ' <span style="background:#f3e8ff;color:#7c3aed;font-size:10px;padding:2px 6px;border-radius:4px;margin-left:4px;font-weight:600;" title="Monotributista — factura por banco, NO va al LSD">🟣 MT</span>'
                  : '';
                return `<td style="padding:8px;text-align:left;font-weight:600;cursor:pointer;position:sticky;left:0;background:white;z-index:2;box-shadow:2px 0 4px -2px rgba(0,0,0,0.08);" onclick="liqHistoricoEmpleada(${l.empleado_id})" title="Ver últimos 12 meses">${c.escapeHtml(l.empleado?.apellido || '')} <span style="color:var(--muted);font-weight:400;">${c.escapeHtml((l.empleado?.nombre || '').split(' ')[0])}</span>${mono}</td>`;
              } },
            { id:'local',     label:'Local',      sortKey:'local', condition:c=>c.local==='todos', thOpts:{align:'text-align:left'},
              tdRender:(l,c)=>`<td style="padding:8px;text-align:left;font-size:11px;"><span class="emp-tag" style="background:#eef2ff;color:#4338ca;font-size:10px;">${c.escapeHtml(LOCALES[l.local]?.nombre || l.local)}</span></td>` },
            { id:'cat',       label:'Cat.',       sortKey:'cat',       thOpts:{align:'text-align:left'},
              tdRender:(l,c)=>`<td style="padding:8px;text-align:left;font-size:11px;color:var(--muted);">${c.escapeHtml(l.empleado?.categoria?.nombre || '')}</td>` },
            { id:'dias',      label:'Días',       sortKey:'dias',
              tdRender:(l,c)=>`<td style="padding:8px;">${l.dias_trabajados}</td>` },
            { id:'puntos',    label:'Pts',        sortKey:'puntos',
              tdRender:(l,c)=>`<td style="padding:8px;${(l.puntos_mes||0)>4 ? 'color:#dc2626;font-weight:600;' : ''}">${l.puntos_mes||0}</td>` },
            { id:'antiguedad', label:'Antig.',    sortKey:'antiguedad',
              tdRender:(l,c)=>{
                const fi = l.empleado?.fecha_ingreso;
                if (!fi) return `<td style="padding:8px;color:var(--muted);text-align:center;">—</td>`;
                // Calcular antigüedad al fin del período de la liq (no ahora mismo)
                const per = String(l.periodo || '').slice(0, 7);
                const refDate = per ? new Date(per + '-28T12:00:00') : new Date();
                const ing = new Date(fi + 'T12:00:00');
                let years  = refDate.getFullYear() - ing.getFullYear();
                let months = refDate.getMonth() - ing.getMonth();
                if (months < 0) { years -= 1; months += 12; }
                const txt = years > 0 ? `${years}a ${months}m` : `${months}m`;
                return `<td style="padding:8px;font-family:monospace;color:var(--muted);text-align:center;" title="Ingreso: ${fi}">${txt}</td>`;
              } },
            { id:'bruto',     label:'Bruto',      sortKey:'bruto', thOpts:{title:'Recibo bruto (remunerativo + no remunerativo) antes de descuentos de ley'},
              tdRender:(l,c)=>{
                const b = Number(l.recibo_bruto||0);
                return `<td style="padding:8px;font-family:monospace;${b===0?'color:var(--muted);':''}">${c.fmt(b)}</td>`;
              } },
            { id:'descuentos',label:'Descuentos', sortKey:'descuentos', thOpts:{title:'Descuentos de ley: Jubilación + Obra Social + Ley 19032 + SEC + Faecys'},
              tdRender:(l,c)=>{
                const d = Number(l.recibo_descuentos||0);
                return `<td style="padding:8px;font-family:monospace;color:${d>0?'#dc2626':'var(--muted)'};" title="Jub + OS + Ley 19032 + SEC + Faecys">${d>0?'−'+c.fmt(d):c.fmt(0)}</td>`;
              } },
            { id:'fijo',      label:'Fijo',       sortKey:'fijo',
              tdRender:(l,c)=>{
                const ov = l.overrides_manuales && l.overrides_manuales['fijo'];
                if (ov) {
                  const t = `✏️ Editado por ${ov.by} el ${new Date(ov.at).toLocaleString('es-AR')}. Anterior: $${Math.round(ov.old).toLocaleString('es-AR')}. ${ov.motivo||''}. Click para volver a editar.`.replace(/"/g,'&quot;');
                  return `<td style="padding:8px;font-family:monospace;background:#f3e8ff;border-left:3px solid #9333ea;${c.isAdmin?'cursor:pointer;':''}" ${c.isAdmin?`onclick="liqEditarCelda(${l.id}, 'fijo', 'Fijo', ${+l.fijo})"`:''} title="${t}">✏️ ${c.fmt(l.fijo)}</td>`;
                }
                const prorr = (l.dias_trabajados||30) < 30;
                const fijoFull = prorr && l.dias_trabajados > 0 ? (+l.fijo) * (30 / l.dias_trabajados) : 0;
                const titulo = prorr
                  ? `🚨 Prorrateado por ${30 - l.dias_trabajados} día(s) sin pago. Fórmula: $${Math.round(fijoFull).toLocaleString('es-AR')} × ${l.dias_trabajados}/30 = $${Math.round(+l.fijo).toLocaleString('es-AR')}`
                  : (c.isAdmin ? 'Click para editar manualmente' : '');
                const style = prorr ? 'background:#fef3c7;border-left:3px solid #f59e0b;cursor:help;' : (c.isAdmin?'cursor:pointer;':'');
                const click = (!prorr && c.isAdmin) ? `onclick="liqEditarCelda(${l.id}, 'fijo', 'Fijo', ${+l.fijo})"` : '';
                return `<td style="padding:8px;font-family:monospace;${style}" ${click} title="${titulo}">${c.fmt(l.fijo)}${prorr?' <sup style="color:#f59e0b;">⚠</sup>':''}</td>`;
              } },
            { id:'comision',  label:'Comisión',   sortKey:'comision',
              tdRender:(l,c)=>{
                const ov = l.overrides_manuales && l.overrides_manuales['comision'];
                const det = c.comisionDesglosePorEmpLiq && c.comisionDesglosePorEmpLiq[l.empleado_id];
                // Armar el desglose textual (usado como base del tooltip)
                let desglose = '';
                if (det) {
                  const pct = (det.tasa * 100).toFixed(3).replace(/\.?0+$/,'') + '%';
                  if (det.modo === 'dia_x_venta') {
                    // Escasany (acuerdo especial): día por día
                    desglose = `── Días trabajados (fichados) ──\n`;
                    (det.dias || []).forEach(d => {
                      const [y,m,dd] = d.fecha.split('-');
                      desglose += `  ${dd}/${m}: ${c.fmt(d.monto)}\n`;
                    });
                    desglose += `\nVentas totales (${(det.dias||[]).length} días): ${c.fmt(det.sumaVentas)}\n`
                             + `Porcentaje: ${pct}\n`
                             + `Fracción individual: ${det.fraccion}\n\n`
                             + `Cálculo: ${c.fmt(det.sumaVentas)} × ${pct} × ${det.fraccion}\n`
                             + `        = ${c.fmt(det.comisionCalc)}`;
                  } else {
                    // Vendedora normal (mes_30)
                    desglose = `Ventas del local (mes): ${c.fmt(det.ventasLocal)}\n`
                             + `Tasa del local: ${pct}\n`;
                    if (det.activas) desglose += `÷ ${det.activas} vendedoras activas\n`;
                    desglose += `Fracción individual: ${det.fraccion}\n`
                             + `Días trabajados: ${det.diasTrab} / ${det.diasRef}\n`
                             + `Ratio: ${det.ratio.toFixed(4)}\n\n`
                             + `Cálculo: ${c.fmt(det.ventasLocal)} × ${pct}`
                             + (det.activas ? ` ÷ ${det.activas}` : '')
                             + ` × ${det.fraccion} × ${det.ratio.toFixed(4)}\n`
                             + `        = ${c.fmt(det.comisionCalc)}`;
                  }
                }
                if (ov) {
                  const t = `✏️ Editado por ${ov.by} el ${new Date(ov.at).toLocaleString('es-AR')}. Anterior: $${Math.round(ov.old).toLocaleString('es-AR')}. ${ov.motivo||''}. Click para volver a editar.`;
                  const tipCompleto = desglose ? (t + '\n\n─── Desglose auto ───\n' + desglose) : t;
                  return `<td style="padding:8px;font-family:monospace;background:#f3e8ff;border-left:3px solid #9333ea;${c.isAdmin?'cursor:pointer;':''}" ${c.isAdmin?`onclick="liqEditarCelda(${l.id}, 'comision', 'Comisión', ${+l.comision})"`:''} title="${c.escapeHtml(tipCompleto)}">✏️ ${c.fmt(l.comision)}</td>`;
                }
                const prorr = (l.dias_trabajados||30) < 30 && (+l.comision) > 0;
                let titulo;
                if (desglose) {
                  titulo = `Comisión = Ventas × Tasa × Fracción × Ratio\n\n` + desglose;
                  if (prorr) titulo = `🚨 Prorrateado por ${30 - l.dias_trabajados} día(s) sin pago.\n\n` + titulo;
                  else if (c.isAdmin) titulo += `\n\n(Click para editar manualmente)`;
                } else {
                  titulo = prorr
                    ? `🚨 Prorrateado por ${30 - l.dias_trabajados} día(s) sin pago.`
                    : (c.isAdmin ? 'Click para editar manualmente' : '');
                }
                const style = prorr ? 'background:#fef3c7;border-left:3px solid #f59e0b;cursor:help;' : (c.isAdmin?'cursor:pointer;':'') + (desglose?'cursor:help;':'');
                const click = (!prorr && c.isAdmin) ? `onclick="liqEditarCelda(${l.id}, 'comision', 'Comisión', ${+l.comision})"` : '';
                return `<td style="padding:8px;font-family:monospace;${style}" ${click} title="${c.escapeHtml(titulo)}">${c.fmt(l.comision)}${prorr?' <sup style="color:#f59e0b;">⚠</sup>':''}</td>`;
              } },
            { id:'premios',   label:'Premios',    sortKey:'premios',
              tdRender:(l,c)=>{
                const ov = l.overrides_manuales && l.overrides_manuales['premio_monto'];
                if (ov) {
                  const t = `✏️ Editado por ${ov.by} el ${new Date(ov.at).toLocaleString('es-AR')}. Anterior: $${Math.round(ov.old).toLocaleString('es-AR')}. ${ov.motivo||''}. Click para volver a editar.`.replace(/"/g,'&quot;');
                  return `<td style="padding:8px;font-family:monospace;background:#f3e8ff;border-left:3px solid #9333ea;${c.isAdmin?'cursor:pointer;':''}" ${c.isAdmin?`onclick="liqEditarCelda(${l.id}, 'premio_monto', 'Premio', ${+l.premio_monto})"`:''} title="${t}">✏️ ${c.fmt(l.premio_monto)}</td>`;
                }
                const click = c.isAdmin ? `onclick="liqEditarCelda(${l.id}, 'premio_monto', 'Premio', ${+l.premio_monto})"` : '';
                const cursor = c.isAdmin ? 'cursor:pointer;' : '';
                return `<td style="padding:8px;font-family:monospace;color:${l.premio_cobra?'#059669':'#dc2626'};${cursor}" ${click} title="${l.uniforme_ok?'Uniforme OK':'Uniforme NO OK'}${c.isAdmin?'. Click para editar.':''}">${l.premio_cobra?c.fmt(l.premio_monto):c.fmt(0)}</td>`;
              } },
            { id:'viaticos',  label:'Viáticos',   sortKey:'viaticos',
              tdRender:(l,c)=>{
                const ov = l.overrides_manuales && l.overrides_manuales['viaticos'];
                if (ov) {
                  const t = `✏️ Editado por ${ov.by} el ${new Date(ov.at).toLocaleString('es-AR')}. Anterior: $${Math.round(ov.old).toLocaleString('es-AR')}. ${ov.motivo||''}. Click para volver a editar.`.replace(/"/g,'&quot;');
                  return `<td style="padding:8px;font-family:monospace;background:#f3e8ff;border-left:3px solid #9333ea;${c.isAdmin?'cursor:pointer;':''}" ${c.isAdmin?`onclick="liqEditarCelda(${l.id}, 'viaticos', 'Viáticos', ${+l.viaticos})"`:''} title="${t}">✏️ ${c.fmt(l.viaticos)}</td>`;
                }
                // (1-oct-2026, JP) Al pasar el mouse por un viático prorrateado, mostrar la cuenta.
                const dv = c.viaticosDesglosePorEmpLiq && c.viaticosDesglosePorEmpLiq[l.empleado_id];
                const prorr = dv ? ((+l.viaticos) > 0 && (+l.viaticos) < dv.completo - 0.5)
                                 : ((l.dias_trabajados||30) < 30 && (+l.viaticos) > 0);
                let titulo;
                if (dv && dv.completo > 0) {
                  const sinPago = Math.max(0, 30 - dv.diasPagos);
                  const noViaja = dv.vac.length + dv.licPagas.length;
                  if (!dv.asistenciasCerradas && !(+l.viaticos)) {
                    titulo = `Viático completo: ${c.fmt(dv.completo)}\n\nTodavía en $0: los viáticos se cargan al CERRAR Asistencias del mes.`;
                  } else if (dv.modo === 'dias_local') {
                    titulo = `Viático completo: ${c.fmt(dv.completo)}\n\nFranquera: proporcional a los días que trabajó (${dv.diasPagos}) sobre los días promedio que trabajaron las vendedoras del local.\n\n= ${c.fmt(l.viaticos)}`;
                  } else if (prorr) {
                    const viajo = Math.max(0, dv.diasPagos - noViaja);
                    titulo = `🚨 Viático prorrateado\nViático = completo × días que viajó ÷ 30\n\n`
                      + `Viático completo: ${c.fmt(dv.completo)}\n`
                      + `Días del mes: 30\n`
                      + (sinPago ? `− Sin pago (ausencias / licencia sin goce): ${sinPago}\n` : '')
                      + (dv.vac.length ? `− Vacaciones: ${dv.vac.length} (${dv.vac.join(', ')})\n` : '')
                      + (dv.licPagas.length ? `− Licencia con goce: ${dv.licPagas.length} (${dv.licPagas.join(', ')})\n` : '')
                      + `= Días que viajó: ${viajo}\n\n`
                      + `Cálculo: ${c.fmt(dv.completo)} × ${viajo} ÷ 30 = ${c.fmt(dv.completo * viajo / 30)}`;
                  } else {
                    titulo = `Viático completo: ${c.fmt(dv.completo)} (30 días, sin vacaciones ni licencias)`;
                  }
                  if (c.isAdmin) titulo += `\n\n(Click para editar manualmente)`;
                } else {
                  titulo = prorr
                    ? `🚨 Prorrateado por ${30 - l.dias_trabajados} día(s) sin pago.`
                    : (c.isAdmin ? 'Click para editar manualmente' : '');
                }
                const style = prorr ? 'background:#fef3c7;border-left:3px solid #f59e0b;cursor:help;' : (c.isAdmin?'cursor:pointer;':'');
                const click = c.isAdmin ? `onclick="liqEditarCelda(${l.id}, 'viaticos', 'Viáticos', ${+l.viaticos})"` : '';
                return `<td style="padding:8px;font-family:monospace;${style}" ${click} title="${c.escapeHtml(titulo)}">${c.fmt(l.viaticos)}${prorr?' <sup style="color:#f59e0b;">⚠</sup>':''}</td>`;
              } },
            { id:'feriado',   label:'Feriado',    sortKey:'feriado',
              tdRender:(l,c)=>{
                const ov = l.overrides_manuales && l.overrides_manuales['feriado_monto'];
                if (ov) {
                  const t = `✏️ Editado por ${ov.by} el ${new Date(ov.at).toLocaleString('es-AR')}. Anterior: $${Math.round(ov.old).toLocaleString('es-AR')}. ${ov.motivo||''}. Click para volver a editar.`.replace(/"/g,'&quot;');
                  return `<td style="padding:8px;font-family:monospace;background:#f3e8ff;border-left:3px solid #9333ea;${c.isAdmin?'cursor:pointer;':''}" ${c.isAdmin?`onclick="liqEditarCelda(${l.id}, 'feriado_monto', 'Feriado', ${+l.feriado_monto})"`:''} title="${t}">✏️ ${c.fmt(l.feriado_monto)}</td>`;
                }
                const click = c.isAdmin ? `onclick="liqEditarCelda(${l.id}, 'feriado_monto', 'Feriado', ${+l.feriado_monto})"` : '';
                const cursor = c.isAdmin ? 'cursor:pointer;' : '';
                return `<td style="padding:8px;font-family:monospace;${cursor}" ${click} title="${l.feriado_dias||0} feriado(s) × $${(l.feriado_monto && l.feriado_dias ? (+l.feriado_monto / +l.feriado_dias).toLocaleString('es-AR') : 0)}${c.isAdmin?'. Click para editar.':''}">${c.fmt(+l.feriado_monto || 0)}</td>`;
              } },
            { id:'sac',       label:'SAC',        sortKey:'sac',        condition:c=>c.esMesSAC, thOpts:{title:'SAC = mejor bruto del semestre / 12 × meses trabajados'},
              tdRender:(l,c)=>{
                const sac = c.sacPorEmpLiq[l.empleado_id] || 0;
                const det = c.sacDetallePorEmpLiq && c.sacDetallePorEmpLiq[l.empleado_id];
                let tip;
                if (sac > 0 && det) {
                  const mesTxt = (det.mejorPeriodo || '').substring(0, 7);
                  tip = `SAC = mejor bruto del semestre / 12 × meses trabajados\n\n`
                      + `Mejor bruto (${mesTxt}): $${c.fmt(det.mejorBruto)}\n`
                      + `  (fijo + comisión + premio + viáticos + extras)\n\n`
                      + `Meses en DB del semestre: ${det.mesesT}\n`
                      + `Meses usados (min 6): ${det.mesesUsados}\n\n`
                      + `Cálculo: $${c.fmt(det.mejorBruto)} / 12 × ${det.mesesUsados} = $${c.fmt(sac)}`;
                } else {
                  tip = 'Sin SAC (sin liquidaciones previas en el semestre)';
                }
                return `<td style="padding:8px;font-family:monospace;color:${sac>0?'#7c3aed':'var(--muted)'};cursor:${sac>0?'help':'default'};" title="${c.escapeHtml(tip)}">${sac>0?c.fmt(sac):'—'}</td>`;
              } },
            { id:'extras',    label:'Extras',     sortKey:'extras',
              tdRender:(l,c)=>{
                const ov = l.overrides_manuales && l.overrides_manuales['extras'];
                if (ov) {
                  const t = `✏️ Editado por ${ov.by} el ${new Date(ov.at).toLocaleString('es-AR')}. Anterior: $${Math.round(ov.old).toLocaleString('es-AR')}. ${ov.motivo||''}. Click para volver a editar.`.replace(/"/g,'&quot;');
                  return `<td style="padding:8px;font-family:monospace;background:#f3e8ff;border-left:3px solid #9333ea;${c.isAdmin?'cursor:pointer;':''}" ${c.isAdmin?`onclick="liqEditarCelda(${l.id}, 'extras', 'Extras', ${+l.extras})"`:''} title="${t}">✏️ ${c.fmt(l.extras)}</td>`;
                }
                const click = c.isAdmin ? `onclick="liqEditarCelda(${l.id}, 'extras', 'Extras', ${+l.extras})"` : '';
                const cursor = c.isAdmin ? 'cursor:pointer;' : '';
                // (3-ago) El pago de vacaciones se MUESTRA dentro de Extras con
                // nota al pasar el mouse (pedido JP). El click edita solo extras.
                const vacP = Number(l.vacaciones_pago || 0);
                const montoCelda = (+l.extras || 0) + vacP;
                let tipEx = c.isAdmin ? 'Click para editar manualmente (edita SOLO extras)' : '';
                if (vacP > 0) {
                  tipEx = `🌴 Incluye pago de vacaciones: $${Math.round(vacP).toLocaleString('es-AR')}\nExtras propiamente dichos: $${Math.round(+l.extras||0).toLocaleString('es-AR')}` + (c.isAdmin ? '\n\nClick edita SOLO los extras (el pago de vacaciones se gestiona desde Vacaciones).' : '');
                }
                const estiloVac = vacP > 0 ? 'background:#f0fdfa;border-left:3px solid #0d9488;' : '';
                return `<td style="padding:8px;font-family:monospace;${estiloVac}${cursor}" ${click} title="${c.escapeHtml(tipEx)}">${vacP>0?'🌴 ':''}${c.fmt(montoCelda)}</td>`;
              } },
            { id:'total',     label:'Total',      sortKey:'total', thOpts:{bg:'#eef2ff',title:'Fijo + Comisión + Premios + Viáticos + Feriado + Extras'},
              tdRender:(l,c)=>{ const sac = c.sacPorEmpLiq[l.empleado_id] || 0; return `<td style="padding:8px;font-family:monospace;background:#eef2ff;font-weight:600;">${c.fmt((+l.total_negro || 0) + sac)}</td>`; } },
            { id:'recibo',    label:'Recibo',     sortKey:'recibo', thOpts:{title:'Neto del recibo blanco (mensual + SAC en junio/diciembre). Ámbar P = proforma · Verde ✓ = definitivo · Verde ✍ = firmado y archivado. Click descarga el PDF firmable.'},
              tdRender:(l,c)=>{
                const sacRec = c.esMesSAC ? Number(l.sac_recibo_neto || 0) : 0;
                const total = Number(l.recibo_neto || 0) + sacRec;
                // ── Color según estado del recibo blanco ──
                // Verde = definitivo (recibo final, PDF firmable)
                // Ámbar = proforma o borrador (preview no definitivo)
                // Gris = todavía sin recibo (recibo_neto=0)
                // ── Etapas del circuito (jul 2026): el verde recién aparece
                //    cuando el PDF se emitió de verdad, no al calcular.
                //    gris = sin recibo · ámbar P = proforma · azul D = definitivo
                //    calculado (sin emitir) · verde ✓ = PDF generado/enviado ·
                //    verde ✍ = firmado y archivado.
                const esDefinitivo = (l.tipo === 'definitivo');
                const sinRecibo    = total === 0;
                const _firmado = !!l.pdf_firmado_at;
                const _badge = (color, txt, tit) => `<span style="background:${color};color:white;font-size:9px;padding:1px 5px;border-radius:3px;font-weight:600;margin-left:4px;vertical-align:middle;" title="${tit}">${txt}</span>`;
                // 3 estados (pedido JP 31-jul): P proforma · ✓ definitivo ·
                // ✍ firmado y archivado en OneDrive. Sin estados intermedios.
                let bg, badgeTx, tipBase;
                if (sinRecibo) {
                  bg = '#f3f4f6'; badgeTx = '';
                  tipBase = 'Sin recibo generado aún — ir a Banco → Proforma o Definitivo. ';
                } else if (_firmado) {
                  bg = '#dcfce7'; badgeTx = _badge('#10b981', '✍', 'Recibo firmado y archivado');
                  tipBase = 'Recibo FIRMADO y archivado en OneDrive. ';
                } else if (esDefinitivo) {
                  bg = '#dcfce7'; badgeTx = _badge('#10b981', '✓', 'Recibo definitivo');
                  tipBase = 'Recibo DEFINITIVO — listo para firmar. ';
                } else {
                  bg = '#fef3c7'; badgeTx = _badge('#f59e0b', 'P', 'Proforma — preview, generar Definitivo desde Banco');
                  tipBase = 'Recibo PROFORMA — preview, todavía no es el definitivo. ';
                }
                const tip = sacRec > 0
                  ? `${tipBase}\nRecibo blanco total = mensual + SAC:\n  Mensual: $${c.fmt(l.recibo_neto)}\n  SAC:     $${c.fmt(sacRec)}\n  ─────────\n  Total:   $${c.fmt(total)}\n\n(Click derecho = desglose)`
                  : `${tipBase}\nClick → ver PDF. Click derecho = desglose.`;
                const contenido = sinRecibo ? '— pendiente' : `${c.fmt(total)} 👁${badgeTx}`;
                return `<td style="padding:8px;font-family:monospace;background:${bg};font-weight:600;cursor:pointer;" onclick="verReciboPDF(${l.id})" title="${c.escapeHtml(tip)}" oncontextmenu="event.preventDefault();liqVerDetalle(${l.id});return false;">${contenido}</td>`;
              } },
            { id:'prestamos', label:'Préstamos',  sortKey:'prestamos',  thOpts:{title:'Capital de cuota de préstamo descontado del banco. Click para ver detalle.'},
              tdRender:(l,c)=>{ const pres = c.prestamosPorEmpLiq[l.empleado_id] || 0; return `<td style="padding:8px;font-family:monospace;cursor:${pres>0?'pointer':'default'};color:${pres>0?'#d97706':'var(--muted)'};" ${pres>0?`onclick="liqVerPrestamoEmp(${l.empleado_id})"`:''} title="${pres>0?'Capital del/los préstamo(s) descontado del banco — click para ver detalle':'Sin préstamo activo este mes'}">${pres>0?'−'+c.fmt(pres):c.fmt(0)}</td>`; } },
            { id:'adelantos', label:'Adelantos',  sortKey:'adelantos',  thOpts:{title:'Adelantos del mes (préstamos 1 cuota tasa 0%)'},
              tdRender:(l,c)=>{ const adel = c.adelantosPorEmpLiq[l.empleado_id] || 0; return `<td style="padding:8px;font-family:monospace;color:${adel>0?'#9333ea':'var(--muted)'};" title="${adel>0?'Adelanto del mes (préstamo 1 cuota tasa 0%)':'Sin adelanto este mes'}">${adel>0?'−'+c.fmt(adel):c.fmt(0)}</td>`; } },
            { id:'banco',     label:'Banco',      sortKey:'banco', thOpts:{bg:'#dcfce7',title:'Lo que efectivamente se transfiere por banco (Recibo mensual + SAC blanco − Préstamos − Adelantos)'},
              tdRender:(l,c)=>{
                const pres = c.prestamosPorEmpLiq[l.empleado_id] || 0;
                const adel = c.adelantosPorEmpLiq[l.empleado_id] || 0;
                const sacRec = c.esMesSAC ? Number(l.sac_recibo_neto || 0) : 0;
                const banco = (+l.recibo_neto || 0) + sacRec - pres - adel;
                const tip = sacRec > 0
                  ? `Banco = Recibo mensual + SAC blanco − Préstamos − Adelantos\n  Mensual: $${c.fmt(l.recibo_neto)}\n  + SAC:   $${c.fmt(sacRec)}\n  − Prést: $${c.fmt(pres)}\n  − Adel:  $${c.fmt(adel)}\n  ──────\n  Banco:   $${c.fmt(banco)}`
                  : 'Lo que efectivamente transferís a la cuenta de la colaboradora (Recibo − Préstamos − Adelantos)';
                return `<td style="padding:8px;font-family:monospace;background:#dcfce7;font-weight:600;" title="${c.escapeHtml(tip)}">${c.fmt(banco)}</td>`;
              } },
            { id:'subtotal_efectivo', label:'Subtotal', sortKey:'subtotal_efectivo', thOpts:{bg:'#ecfccb',title:'Subtotal del efectivo (Total − Recibo). En junio/diciembre resta también el SAC blanco. De acá se descuentan Mercadería, Intereses y Ajustes.'},
              tdRender:(l,c)=>{
                const sac = c.sacPorEmpLiq[l.empleado_id] || 0;
                const sacRec = c.esMesSAC ? Number(l.sac_recibo_neto || 0) : 0;
                const subtotal = Math.max(0, (+l.total_negro || 0) + sac - (+l.recibo_neto || 0) - sacRec);
                return `<td style="padding:8px;font-family:monospace;background:#ecfccb;font-weight:600;" title="Subtotal del efectivo = (Total + SAC) − (Recibo mensual + SAC blanco). Es la base sobre la que se aplican mercadería/intereses/ajustes.">${subtotal>0?c.fmt(subtotal):'—'}</td>`;
              } },
            { id:'mercaderia', label:'Mercadería', sortKey:'mercaderia',
              tdRender:(l,c)=>{
                const ov = l.overrides_manuales && l.overrides_manuales['mercaderia'];
                if (ov) {
                  const t = `✏️ Editado por ${ov.by} el ${new Date(ov.at).toLocaleString('es-AR')}. Anterior: $${Math.round(ov.old).toLocaleString('es-AR')}. ${ov.motivo||''}. Click para volver a editar.`.replace(/"/g,'&quot;');
                  return `<td style="padding:8px;font-family:monospace;background:#f3e8ff;border-left:3px solid #9333ea;${c.isAdmin?'cursor:pointer;':''}" ${c.isAdmin?`onclick="liqEditarCelda(${l.id}, 'mercaderia', 'Mercadería', ${+l.mercaderia})"`:''} title="${t}">✏️ ${c.fmt(l.mercaderia)}</td>`;
                }
                const click = c.isAdmin ? `onclick="liqEditarCelda(${l.id}, 'mercaderia', 'Mercadería', ${+l.mercaderia})"` : '';
                const cursor = c.isAdmin ? 'cursor:pointer;' : '';
                return `<td style="padding:8px;font-family:monospace;${cursor}" ${click} ${c.isAdmin?'title="Click para editar"':''}>${c.fmt(l.mercaderia)}</td>`;
              } },
            { id:'intereses', label:'Intereses',  sortKey:'intereses',  thOpts:{title:'Interés del/los préstamo(s) — se descuenta del Efectivo'},
              tdRender:(l,c)=>{ const intr = c.interesesPorEmpLiq[l.empleado_id] || 0; return `<td style="padding:8px;font-family:monospace;cursor:${intr>0?'pointer':'default'};color:${intr>0?'#d97706':'var(--muted)'};" ${intr>0?`onclick="liqVerPrestamoEmp(${l.empleado_id})"`:''} title="${intr>0?'Interés del préstamo — click para ver detalle del préstamo':'Sin interés este mes'}">${intr>0?'−'+c.fmt(intr):c.fmt(0)}</td>`; } },
            { id:'ajustes',   label:'Ajustes',    sortKey:'ajustes',    thOpts:{title:'Ajuste manual. Click para editar. Hover para ver comentario.'},
              tdRender:(l,c)=>`<td style="padding:8px;font-family:monospace;${c.isAdmin?'cursor:pointer;':''}" ${c.isAdmin?`onclick="liqEditarAjuste(${l.id}, ${l.empleado_id})"`:''} title="${l.ajuste_comentario ? c.escapeHtml(l.ajuste_comentario).replace(/"/g,'&quot;') : (c.isAdmin?'Click para cargar/editar ajuste':'Sin comentario')}">${c.fmt(l.ajuste)}${l.ajuste_comentario?' <span style=\"color:#9333ea;font-size:11px;\" title=\"Tiene comentario\">💬</span>':''}</td>` },
            { id:'efectivo',  label:'Efectivo',   sortKey:'efectivo', thOpts:{bg:'#fde2e8',title:'Efectivo neto = Subtotal − Mercadería − Intereses − Ajustes'},
              tdRender:(l,c)=>{
                // Modelo claro: parte del Subtotal efectivo (Total − Recibo) y restamos
                // mercadería, intereses (live) y ajustes. Así el cálculo siempre cuadra
                // con lo que vé el usuario en pantalla, independiente del DB.
                // En junio/diciembre (mes SAC) también hay que restar el SAC blanco del recibo,
                // igual que hace el Subtotal — sino el Efectivo aparece inflado por sac_recibo_neto.
                const sac = c.sacPorEmpLiq[l.empleado_id] || 0;
                const sacRec = c.esMesSAC ? Number(l.sac_recibo_neto || 0) : 0;
                const subtotal = Math.max(0, (+l.total_negro || 0) + sac - (+l.recibo_neto || 0) - sacRec);
                const mercaderia = Number(l.mercaderia || 0);
                const intrLive   = c.interesesPorEmpLiq[l.empleado_id] || 0;
                const ajuste     = Number(l.ajuste || 0);
                const ef = Math.max(0, subtotal - mercaderia - intrLive - ajuste);
                return `<td style="padding:8px;font-family:monospace;background:#fde2e8;font-weight:600;" title="Efectivo neto = Subtotal − Mercadería − Intereses − Ajustes${intrLive>0?' (interés descontado: $'+Math.round(intrLive).toLocaleString('es-AR')+')':''}">${ef>0?c.fmt(ef):'—'}</td>`;
              } },
            { id:'firma',     label:'Firma',
              tdRender:(l,c)=>{
                // Chip del sueldo mensual
                let chipMensual = '';
                if (l.pdf_firmado_at) {
                  const fecha = new Date(l.pdf_firmado_at).toLocaleDateString('es-AR');
                  chipMensual = `<span style="background:#d1fae5;color:#065f46;padding:2px 6px;border-radius:4px;font-size:10px;font-weight:600;" title="Recibo mensual firmado el ${fecha}">📄 ${fecha}</span>`;
                } else if (l.pdf_enviado_at) {
                  chipMensual = `<span style="background:#fef3c7;color:#92400e;padding:2px 6px;border-radius:4px;font-size:10px;font-weight:600;" title="Recibo mensual enviado para firmar">📄 ⏳</span>`;
                }
                // Chip del SAC (solo en junio/diciembre y si tiene SAC neto)
                let chipSAC = '';
                if (c.esMesSAC && Number(l.sac_recibo_neto || 0) > 0) {
                  if (l.sac_pdf_firmado_at) {
                    const fechaSac = new Date(l.sac_pdf_firmado_at).toLocaleDateString('es-AR');
                    chipSAC = `<span style="background:#d1fae5;color:#065f46;padding:2px 6px;border-radius:4px;font-size:10px;font-weight:600;" title="SAC firmado el ${fechaSac}">🎁 ${fechaSac}</span>`;
                  } else {
                    chipSAC = `<span style="background:#fef3c7;color:#92400e;padding:2px 6px;border-radius:4px;font-size:10px;font-weight:600;" title="SAC pendiente de firma">🎁 ⏳</span>`;
                  }
                }
                if (chipMensual || chipSAC) {
                  return `<td style="padding:8px;text-align:center;"><div style="display:flex;flex-direction:column;gap:3px;align-items:center;">${chipMensual}${chipSAC}</div></td>`;
                }
                // Fallback si el mes está cerrado a nivel local
                const mesCerr = c.cierresSueldosPorLocal && c.cierresSueldosPorLocal[l.local];
                if (mesCerr) {
                  return `<td style="padding:8px;text-align:center;"><span style="background:#e0e7ff;color:#3730a3;padding:2px 8px;border-radius:4px;font-size:11px;font-weight:600;" title="Mes cerrado el ${(mesCerr.cerrado_at||'').split('T')[0]} — falta que llegue el PDF firmado por la empleada">🗓️ Mes cerrado</span></td>`;
                }
                return `<td style="padding:8px;text-align:center;color:var(--muted);font-size:11px;">—</td>`;
              } },
            { id:'detalle',   label:'Acciones',
              tdRender:(l,c)=>{
                const firmado = l.pdf_firmado_at;
                const url = l.pdf_url_firmado || l.pdf_firmado_path || '';
                const esUrl = /^https?:\/\//i.test(url);
                const mesCerr = c.cierresSueldosPorLocal && c.cierresSueldosPorLocal[l.local];
                const fechaFirma = firmado ? new Date(firmado).toLocaleDateString('es-AR') : '';
                const btnFirmado = firmado
                  ? (esUrl
                      ? `<a class="btn small" href="${escapeHtml(url)}" target="_blank" rel="noopener" style="background:#d1fae5;color:#065f46;border-color:#86efac;text-decoration:none;" title="✓ Firmada el ${fechaFirma}. Click para abrir el archivo en OneDrive.">✓ Firmada</a>`
                      : `<button class="btn small" style="background:#d1fae5;color:#065f46;border-color:#86efac;cursor:default;" disabled title="✓ Firmada el ${fechaFirma}. Archivo antiguo — sin link directo.">✓ Firmada</button>`)
                  : (mesCerr
                      ? `<button class="btn small" style="background:#e0e7ff;color:#3730a3;border-color:#a5b4fc;" disabled title="Mes cerrado — el sistema espera que llegue el PDF firmado por la colaboradora por Gmail o que lo subas manualmente.">🗓️ Esperando firma</button>`
                      : `<button class="btn small" style="background:#fef3c7;color:#92400e;border-color:#fcd34d;" disabled title="No firmada — esperando que llegue el PDF firmado.">✗ No firmada</button>`);
                // Candado: cerrado si (mes cerrado a nivel local) O (liq en estado 'revisada'/'firmada'/'anulada')
                const estaCerrado = !!mesCerr || l.estado === 'firmada' || l.estado === 'revisada' || l.estado === 'anulada';
                const tipCandado = mesCerr
                  ? `🔒 Mes cerrado el ${(mesCerr.cerrado_at||'').split('T')[0]} por ${(mesCerr.cerrado_por||'').split('@')[0]}${c.isAdmin?' — para editar esta liq, primero reabrí el mes desde el botón 🔒 del header':''}`
                  : `🔒 Liquidación en estado "${l.estado}"${c.isAdmin?' — click para volver a borrador y editar':''}`;
                const btnCandado = estaCerrado
                  ? `<button class="btn small" style="background:#fee2e2;color:#991b1b;border-color:#fca5a5;cursor:${(c.isAdmin && !mesCerr)?'pointer':'default'};" ${(c.isAdmin && !mesCerr)?`onclick="liqReabrirEmpleado(${l.id})"`:''} title="${tipCandado}">🔒</button>`
                  : `<button class="btn small" style="background:#dcfce7;color:#166534;border-color:#86efac;cursor:default;" title="🔓 Abierta — se puede editar">🔓</button>`;
                // 📸 Resumen efímero: snapshot en memoria para generar la imagen
                // (solo admin — la imagen se dibuja en el navegador y NO se guarda)
                if (c.isAdmin) {
                  const _sacL   = c.sacPorEmpLiq[l.empleado_id] || 0;
                  const _sacRecL = c.esMesSAC ? Number(l.sac_recibo_neto || 0) : 0;
                  (window._liqResumenData = window._liqResumenData || {})[l.id] = {
                    nombre: `${l.empleado?.apellido || ''} ${(l.empleado?.nombre || '').split(' ')[0]}`.trim(),
                    periodo: String(l.periodo).slice(0, 10),
                    fijo: +l.fijo || 0, comision: +l.comision || 0,
                    premio: l.premio_cobra ? (+l.premio_monto || 0) : 0,
                    viaticos: +l.viaticos || 0, feriado: +l.feriado_monto || 0,
                    extras: (+l.extras || 0) + (+l.vacaciones_pago || 0),
                    sac_ef: _sacL, sac_rec: _sacRecL,
                    total: (+l.total_negro || 0) + _sacL,
                    recibo: (+l.recibo_neto || 0),
                    prestamos: c.prestamosPorEmpLiq[l.empleado_id] || 0,
                    adelantos: c.adelantosPorEmpLiq[l.empleado_id] || 0,
                    intereses: c.interesesPorEmpLiq[l.empleado_id] || 0,
                    mercaderia: +l.mercaderia || 0, ajuste: +l.ajuste || 0,
                  };
                }
                const btnImagen = c.isAdmin
                  ? `<button class="btn small" onclick="liqImagenResumen(${l.id})" title="📸 Generar imagen del resumen del sueldo (banco + efectivo) para mandarla por WhatsApp como foto con 'ver una vez'. La imagen se genera en tu compu y NO queda guardada en ningún lado.">📸</button>`
                  : '';
                return `<td style="padding:8px;white-space:nowrap;">
                  ${btnCandado}
                  ${btnFirmado}
                  ${c.isAdmin ? `<button class="btn small" onclick="liqEditar(${l.id})" title="Editar manualmente">✏️</button>` : ''}
                  ${btnImagen}
                </td>`;
              } },
          ];

          const ctxL = { fmt, escapeHtml, local, isAdmin, esMesSAC, adelantosPorEmpLiq, prestamosPorEmpLiq, interesesPorEmpLiq, sacPorEmpLiq: sacPorEmp, sacDetallePorEmpLiq: sacDetallePorEmp, comisionDesglosePorEmpLiq: comisionDesglosePorEmp, viaticosDesglosePorEmpLiq: viaticosDesglosePorEmp, cierresSueldosPorLocal: cierresSueldos };

          // Filtrar por condition (local==='todos', esMesSAC)
          // + Sub-tab Banco: mostrar columnas del recibo CCT (más info)
          // + Sub-tab Sueldo: ocultar Cat y Pts (JP no las quiere ahí)
          const BANCO_COLS = new Set([
            'empleada','cat','antiguedad','dias',
            'bruto','descuentos','recibo','sac',
            'prestamos','adelantos','banco','firma','detalle'
          ]);
          const OCULTAS_EN_SUELDO = new Set(['cat','puntos','antiguedad','bruto','descuentos']);
          const colsAvailable = ALL_COLS
            .filter(c => !c.condition || c.condition(ctxL))
            .filter(c => liqState.subTab !== 'banco' || BANCO_COLS.has(c.id))
            .filter(c => liqState.subTab !== 'sueldo' || !OCULTAS_EN_SUELDO.has(c.id));
          // Guardar lista de columnas disponibles para que el modal de config las muestre
          window._liqAvailableCols = colsAvailable.map(c => ({ id: c.id, label: c.label }));

          // Aplicar config del usuario (orden + visibilidad desde localStorage)
          const cfg = liqGetColsConfig();
          // Para la encargada, hay columnas críticas que NO pueden quedar ocultas
          // aunque su localStorage diga lo contrario (defienden el flujo de liquidación):
          //   empleada, dias, puntos, total, recibo, prestamos, adelantos, banco,
          //   intereses, efectivo, detalle.
          if (!isAdmin) {
            const CORE_GERENTE = ['empleada','dias','puntos','total','recibo','prestamos','adelantos','banco','subtotal_efectivo','mercaderia','intereses','ajustes','efectivo','detalle'];
            cfg.ocultas = (cfg.ocultas || []).filter(id => !CORE_GERENTE.includes(id));
          }
          const byId = Object.fromEntries(colsAvailable.map(c => [c.id, c]));
          const remaining = new Set(colsAvailable.map(c => c.id));
          const ordered = [];
          (cfg.orden || []).forEach(id => { if (byId[id] && remaining.has(id)) { ordered.push(byId[id]); remaining.delete(id); } });
          // Columnas no listadas en cfg.orden van al final en su orden original
          colsAvailable.forEach(c => { if (remaining.has(c.id)) ordered.push(c); });
          const cols = ordered.filter(c => !(cfg.ocultas || []).includes(c.id));

          // Render thead + tbody
          const arrow = (k) => liqState.sortBy === k
            ? `<span style="color:#4338ca;margin-left:3px;">${liqState.sortDir === 'asc' ? '↑' : '↓'}</span>`
            : '<span style="color:#cbd5e1;margin-left:3px;">↕</span>';
          const thHtml = cols.map(col => {
            const opts = col.thOpts || {};
            // Sticky vertical (siempre): headers pegados arriba al scrollear la grilla
            // Sticky horizontal (solo Empleada): columna nombre pegada a la izquierda
            const bgTh = opts.bg || '#f9fafb';
            const stickyVert = `position:sticky;top:0;`;
            const isEmpleada = (col.id === 'empleada');
            const zIndex = isEmpleada ? 5 : 3;   // esquina cruza dos stickies → mayor z
            const stickyEmp = isEmpleada ? 'left:0;box-shadow:2px 0 4px -2px rgba(0,0,0,0.08),0 2px 4px -2px rgba(0,0,0,0.08);' : 'box-shadow:0 2px 4px -2px rgba(0,0,0,0.08);';
            const style = `padding:8px;${opts.align || ''};background:${bgTh};${col.sortKey ? 'cursor:pointer;user-select:none;' : ''}${stickyVert}${stickyEmp}z-index:${zIndex};`;
            const onclick = col.sortKey ? `onclick="liqOrdenarPor('${col.sortKey}')"` : '';
            const title = opts.title ? `title="${opts.title}"` : '';
            return `<th style="${style}" ${onclick} ${title}>${col.label}${col.sortKey ? arrow(col.sortKey) : ''}</th>`;
          }).join('');
          const bodyHtml = (liqs||[]).map(l => {
            const nombreNorm = ((l.empleado?.apellido || '') + ' ' + (l.empleado?.nombre || '')).toLowerCase();
            return `<tr data-search="${escapeHtml(nombreNorm)}" style="border-top:1px solid var(--border);text-align:right;">${cols.map(col => col.tdRender(l, ctxL)).join('')}</tr>`;
          }).join('') + eventualesLiq.map((e, i) => liqEventualFila(e, i, cols, fmt)).join('');

          // ─── TFOOT con totales de columnas numéricas ───
          const sumCol = (sel) => (liqs || []).reduce((s, l) => s + (sel(l) || 0), 0);
          const totDias = sumCol(l => Number(l.dias_trabajados || 0)) + eventualesLiq.reduce((s, e) => s + Number(e.dias || 0), 0);
          const totPts  = sumCol(l => Number(l.puntos_mes || 0));
          const totTotal = sumCol(l => Number(l.total_negro || 0) + (sacPorEmp[l.empleado_id] || 0))
                         + eventualesLiq.reduce((s, e) => s + Number(e.importe || 0), 0);
          const totRecibo = sumCol(l => Number(l.recibo_neto || 0) + (esMesSAC ? Number(l.sac_recibo_neto || 0) : 0));
          const totBanco = sumCol(l => Number(l.recibo_neto || 0) + (esMesSAC ? Number(l.sac_recibo_neto || 0) : 0) - (prestamosPorEmpLiq[l.empleado_id] || 0) - (adelantosPorEmpLiq[l.empleado_id] || 0));
          const totMerc = sumCol(l => Number(l.mercaderia || 0));
          const totAdel = (liqs || []).reduce((s, l) => s + (adelantosPorEmpLiq[l.empleado_id] || 0), 0);
          const totPres = (liqs || []).reduce((s, l) => s + (prestamosPorEmpLiq[l.empleado_id] || 0), 0);
          const totInt = (liqs || []).reduce((s, l) => s + (interesesPorEmpLiq[l.empleado_id] || 0), 0);
          const totAjuste = sumCol(l => Number(l.ajuste || 0));
          const totEfect = sumCol(l => {
            const sac = sacPorEmp[l.empleado_id] || 0;
            const sacRec = esMesSAC ? Number(l.sac_recibo_neto || 0) : 0;
            const subtotal = Math.max(0, (+l.total_negro || 0) + sac - (+l.recibo_neto || 0) - sacRec);
            const merc = Number(l.mercaderia || 0);
            const intr = interesesPorEmpLiq[l.empleado_id] || 0;
            const aj = Number(l.ajuste || 0);
            return Math.max(0, subtotal - merc - intr - aj);
          });
          const totSubtotal = (liqs || []).reduce((s, l) => {
            const sac = sacPorEmp[l.empleado_id] || 0;
            const sacRec = esMesSAC ? Number(l.sac_recibo_neto || 0) : 0;
            return s + Math.max(0, (+l.total_negro || 0) + sac - (+l.recibo_neto || 0) - sacRec);
          }, 0);
          // Totales de las columnas de composición del sueldo
          const totFijo    = sumCol(l => Number(l.fijo || 0));
          const totCom     = sumCol(l => Number(l.comision || 0));
          const totPremio  = sumCol(l => (l.premio_cobra ? Number(l.premio_monto || 0) : 0));
          const totViat    = sumCol(l => Number(l.viaticos || 0));
          const totFeriado = sumCol(l => Number(l.feriado_monto || 0));
          const totSac     = (liqs || []).reduce((s, l) => s + (sacPorEmp[l.empleado_id] || 0), 0);
          const totExtras  = sumCol(l => Number(l.extras || 0));
          // Mapa por id-de-columna → contenido del td en el footer
          const totalsByCol = {
            empleada: `<strong>TOTAL (${(liqs||[]).length}${eventualesLiq.length ? ' + ' + eventualesLiq.length + ' eventual' : ''})</strong>`,
            dias: totDias,
            puntos: totPts,
            fijo:     fmt(totFijo),
            comision: fmt(totCom),
            premios:  fmt(totPremio),
            viaticos: fmt(totViat),
            feriado:  totFeriado > 0 ? fmt(totFeriado) : '—',
            sac:      totSac > 0 ? fmt(totSac) : '—',
            extras:   fmt(totExtras),
            total: fmt(totTotal),
            recibo: fmt(totRecibo),
            banco: fmt(totBanco),
            subtotal_efectivo: fmt(totSubtotal),
            mercaderia: fmt(totMerc),
            adelantos: totAdel > 0 ? '−' + fmt(totAdel) : '—',
            prestamos: totPres > 0 ? '−' + fmt(totPres) : '—',
            intereses: totInt > 0 ? '−' + fmt(totInt) : '—',
            ajustes: fmt(totAjuste),
            efectivo: fmt(totEfect),
          };
          const tfootHtml = cols.map(col => {
            const val = totalsByCol[col.id] !== undefined ? totalsByCol[col.id] : '';
            const align = col.id === 'empleada' ? 'left' : 'right';
            const sticky = col.id === 'empleada' ? 'position:sticky;left:0;z-index:3;box-shadow:2px 0 4px -2px rgba(0,0,0,0.08);' : '';
            return `<td style="padding:10px 8px;text-align:${align};font-weight:700;font-family:monospace;background:#f1f5f9;color:#1e293b;border-top:2px solid #94a3b8;${sticky}">${val}</td>`;
          }).join('');

          return `<table id="liq-tabla-main" style="width:100%;border-collapse:collapse;font-size:12.5px;">
            <thead><tr style="background:#f9fafb;text-align:right;">${thHtml}</tr></thead>
            <tbody>${bodyHtml}</tbody>
            <tfoot><tr>${tfootHtml}</tr></tfoot>
          </table>`;
        })()}
      </div>
      </div>
      <!-- fin card doble-scroll liquidador -->

      <details class="card" style="margin-top:14px;padding:10px 12px;background:#fef9c3;border-left:4px solid #eab308;font-size:12.5px;color:#854d0e;">
        <summary style="cursor:pointer;font-weight:600;list-style:none;">💡 Cómo se lee esta grilla</summary>
        <div style="margin-top:8px;"> el <strong>Total</strong> (azulado) es lo que debería cobrar la colaboradora (Fijo + Comisión + Premios + Viáticos + Extras + Feriado${esMesSAC ? ' + SAC' : ''}). <strong>Recibo</strong> es el neto del recibo blanco CCT. <strong>Banco</strong> (verde) es lo que efectivamente se transfiere por banco (Recibo − Préstamos − Adelantos). <strong>Subtotal</strong> (verde claro) es la base del efectivo (Total − Recibo); de ahí se descuentan Mercadería, Intereses y Ajustes para llegar al <strong>Efectivo</strong> (rojo) que va en mano. Para Contreras y Escasany (esquema 'todo en blanco') el sistema ajusta el básico del recibo para que el neto = Total esperado, así no hay negro.
        </div>
      </details>
    `}
  `;
}
