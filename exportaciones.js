// ═══════════════════════════════════════════════════════════════════════
//  RRHH Adorno · exportaciones.js
//  Export Galicia Office (XLSX para acreditar sueldos) y planilla blanca.
//  Extraído de index.html el 30-jul-2026 (modularización, Fase 2).
//  Se carga después del script principal; nada de esto corre al arrancar.
// ═══════════════════════════════════════════════════════════════════════

async function exportarGaliciaXLSX(local, periodo) {
  // (31-jul) Formato EXACTO del template del banco Galicia (GO → Haberes →
  // Acreditaciones): hoja "Template Liquidaciones" con columnas
  // Cuenta (texto, 14 dígitos con ceros a la izquierda — NO es el CBU, se
  // guarda en rrhh_empleados.cuenta_galicia) · Nombre (APELLIDO, NOMBRE) ·
  // Importe (número, 2 decimales) · Concepto ("01" = haberes).
  try {
    if (!window.XLSX) { toast('Falta SheetJS — recargá la página', 'error'); return; }

    let q = sb.from('rrhh_liquidacion')
      .select('id, periodo, recibo_neto, prestamo_capital, local, empleado:rrhh_empleados(id, apellido, nombre, nombre_completo, cuil, cuenta_galicia)')
      .eq('periodo', periodo + '-01');
    if (local && local !== 'todos') q = q.eq('local', local);
    const { data: liqs, error } = await q;
    if (error) { toast('Error: ' + error.message, 'error'); return; }
    if (!liqs || liqs.length === 0) { toast('No hay liquidaciones para exportar', 'warning'); return; }

    const fmtNombre = (e) => {
      if (!e) return '';
      return `${(e.apellido || '').toUpperCase()}, ${(e.nombre || '').toUpperCase()}`.trim();
    };

    const filas = [];
    const sinCuenta = [];
    let totalImporte = 0;
    for (const l of liqs.sort((a,b) => (a.empleado?.apellido||'').localeCompare(b.empleado?.apellido||''))) {
      const e = l.empleado;
      if (!e) continue;
      const aAcreditar = (+l.recibo_neto || 0) - (+l.prestamo_capital || 0);
      if (aAcreditar <= 0) continue;
      if (!e.cuenta_galicia) { sinCuenta.push(fmtNombre(e)); continue; }
      const impRedondo = Math.ceil(aAcreditar);  // sin centavos, siempre p/arriba
      filas.push([
        String(e.cuenta_galicia).padStart(14, '0'),
        fmtNombre(e),
        impRedondo,
        '01',
      ]);
      totalImporte += impRedondo;
    }

    if (filas.length === 0) {
      toast('Ninguna colaboradora con cuenta Galicia cargada y monto > 0', 'error');
      return;
    }
    if (sinCuenta.length > 0) {
      const lista = sinCuenta.join('\n  • ');
      if (!confirm(`⚠ ${sinCuenta.length} empleada(s) sin cuenta Galicia cargada quedan fuera del archivo:\n\n  • ${lista}\n\n¿Generar el archivo con las ${filas.length} restantes?`)) return;
    }

    const wb = XLSX.utils.book_new();

    // Hoja 1: "Ayuda" — instrucciones del banco, copiadas del template oficial
    const AYUDA = [
      ['', 'Ayuda : Planilla Excel Liquidaciones', ''],
      ['', '1. Completar la hoja de este excel llamada "Template Liquidaciones" según las siguientes definiciones de campos', '.'],
      ['', '2. Guardar y Enviar por GO (Menú: Haberes/Acreditaciones/Archivos/Envío Archivo de Acreditaciones). ', ''],
      ['', '', ''],
      ['', '', ''],
      ['CUENTA', 'El campo cuenta debe contener 12 digitos sin guiones. La misma debe comenzar con 0 (si es Cuenta Corriente) ó 4 (si es Caja de Ahorro). Formato de Celda: NÚMERO - Posiciones Decimales: 0.', ''],
      ['', '', ''],
      ['NOMBRE', 'Debe introducirse en el siguiente orden: Apellido y Nombre.  Sin comas.  No hay limite de caracteres. Formato de Celda: TEXTO', ''],
      ['', '', ''],
      ['IMPORTE', 'El campo importe admite un máximo de 14 caracteres. Sin signo monetario. Con coma decimal, incluyendo dos decimales. Formato de Celda: NÚMERO - Posiciones Decimales: 2.', ''],
      ['', '', ''],
      ['CONCEPTO', 'Se deberá colocar el Código que figura en la "Tabla de Conceptos" de acuerdo con la descripción que se quiera mostrar para cada monto a acreditar.  El campo requiere un mínimo de 2 caracteres. Formato de Celda: TEXTO. CAMPO OPCIONAL. Por default aparecerá siempre el Código 01, significa Acreditamiento de Haberes.', ''],
      ['', '', ''],
      ['', '', ''],
      ['Tabla de Conceptos', '', ''],
      ['', '', ''],
      ['Código', 'Descripción', ''],
      ['01', 'ACREDITAMIENTO DE HABERES', ''],
      ['02', 'HORAS EXTRAS', ''],
      ['03', 'REINTEGRO POR VIATICOS', ''],
      ['04', 'SUELDO ANUAL COMPLEMENTARIO', ''],
      ['05', 'SUBSIDIO VACACIONAL', ''],
      ['06', 'GASTOS DE REPRESENTACION', ''],
      ['07', 'HONORARIOS DE PROFESIONALES', ''],
      ['08', 'ASIGNACION PERSONAL CONTRATADO', ''],
      ['09', 'ASIGNACION BECAS/PASANTIAS', ''],
      [10, 'PREMIO POR PRODUCTIVIDAD/CALIDAD', ''],
      [11, 'REEMBOLSO GASTOS', ''],
      [12, 'INDEMNIZACION/LIQUIDACION FINAL', ''],
    ];
    const wsAyuda = XLSX.utils.aoa_to_sheet(AYUDA);
    wsAyuda['!cols'] = [{ wch: 18 }, { wch: 110 }, { wch: 4 }];
    XLSX.utils.book_append_sheet(wb, wsAyuda, 'Ayuda');

    const ws = XLSX.utils.aoa_to_sheet([
      ['Cuenta', 'Nombre', 'Importe', 'Concepto'],
      ...filas,
    ]);
    // Cuenta y Concepto como TEXTO (preservar ceros a la izquierda)
    for (let r = 1; r <= filas.length; r++) {
      const cCta = ws['A' + (r + 1)]; if (cCta) cCta.t = 's';
      const cCon = ws['D' + (r + 1)]; if (cCon) cCon.t = 's';
      const cImp = ws['C' + (r + 1)]; if (cImp) { cImp.t = 'n'; cImp.z = '0'; }
    }
    ws['!cols'] = [{ wch: 16 }, { wch: 34 }, { wch: 14 }, { wch: 10 }];
    XLSX.utils.book_append_sheet(wb, ws, 'Template Liquidaciones');

    const localTxt = (local && local !== 'todos') ? local.toUpperCase() : 'TODOS';
    const [py, pm] = periodo.split('-');
    XLSX.writeFile(wb, `SUELDOS ${Number(pm)}-${py} - ${localTxt}.xls`, { bookType: 'biff8' });

    toast(`✓ ${filas.length} acreditaciones — total ${'$' + Math.round(totalImporte).toLocaleString('es-AR')}`, 'success');
  } catch(e) {
    console.error(e);
    toast('Error al exportar: ' + e.message, 'error');
  }
}

// ─────────────────────────────────────────────────────────────────────
// Exportar planilla blanca del mes desde Liquidaciones
// (Recibo − Préstamos − Adelantos = A acreditar)
// ─────────────────────────────────────────────────────────────────────
async function exportarPlanillaBlancaLiq(local, periodo) {
  if (session.rol !== 'admin') { toast('Solo admin', 'error'); return; }
  try {
    if (!window.XLSX) { toast('Falta SheetJS — recargá la página', 'error'); return; }

    // 1) Liquidaciones del período
    let q = sb.from('rrhh_liquidacion')
      .select('id, periodo, local, recibo_neto, empleado_id, empleado:rrhh_empleados(id, apellido, nombre, nombre_completo, cuil, cbu, local)')
      .eq('periodo', periodo + '-01');
    if (local && local !== 'todos') q = q.eq('local', local);
    const { data: liqs, error } = await q;
    if (error) { toast('Error: ' + error.message, 'error'); return; }
    if (!liqs || liqs.length === 0) { toast('No hay liquidaciones para exportar', 'warning'); return; }

    // 2) Separar Adelantos (1 cuota tasa 0) vs Préstamos largos
    const empIds = [...new Set(liqs.map(l => l.empleado_id))];
    const adelMap = {}, presMap = {};
    if (empIds.length > 0) {
      // (31-jul) SOLO préstamos ACTIVOS y cuotas NO canceladas — igual que la
      // grilla. Sin estos filtros el Excel sumaba cuotas de préstamos
      // refinanciados/cancelados (Bianchi +$657.500, Noguera +$214.286).
      const { data: pAct } = await sb.from('rrhh_prestamo')
        .select('id, empleado_id, estado, cuotas_totales, tasa_mensual')
        .in('empleado_id', empIds).eq('estado', 'activo');
      const pById = {}; (pAct || []).forEach(p => { pById[p.id] = p; });
      const idsP = (pAct || []).map(p => p.id);
      if (idsP.length > 0) {
        const { data: cs } = await sb.from('rrhh_prestamo_cuota')
          .select('prestamo_id, monto_capital, mes_descuento')
          .eq('mes_descuento', periodo + '-01').neq('estado', 'cancelada').in('prestamo_id', idsP);
        (cs || []).forEach(c => {
          const pr = pById[c.prestamo_id]; if (!pr) return;
          const cap = Number(c.monto_capital || 0);
          const esAdel = pr.cuotas_totales === 1 && Number(pr.tasa_mensual||0) === 0;
          if (esAdel) adelMap[pr.empleado_id] = (adelMap[pr.empleado_id]||0) + cap;
          else        presMap[pr.empleado_id] = (presMap[pr.empleado_id]||0) + cap;
        });
      }
    }

    // 3) Armar filas
    const filas = [];
    let tRecibo=0, tPres=0, tAdel=0, tAcred=0;
    liqs.sort((a,b) => (a.local||'').localeCompare(b.local||'') || (a.empleado?.apellido||'').localeCompare(b.empleado?.apellido||''))
        .forEach(l => {
      const e = l.empleado; if (!e) return;
      const recibo = +l.recibo_neto || 0;
      const pres = presMap[l.empleado_id] || 0;
      const adel = adelMap[l.empleado_id] || 0;
      const acred = Math.max(0, recibo - pres - adel);
      filas.push({
        'Empleada':      e.nombre_completo || '',
        'Local':         e.local || l.local || '',
        'CUIL':          e.cuil || '',
        'CBU':           e.cbu || '',
        'Recibo neto':   Math.round(recibo),
        'Préstamos':     Math.round(pres),
        'Adelantos':     Math.round(adel),
        'A acreditar':   Math.round(acred),
      });
      tRecibo += recibo; tPres += pres; tAdel += adel; tAcred += acred;
    });

    // Fila de totales
    filas.push({
      'Empleada': 'TOTAL', 'Local': '', 'CUIL': '', 'CBU': '',
      'Recibo neto': Math.round(tRecibo),
      'Préstamos':   Math.round(tPres),
      'Adelantos':   Math.round(tAdel),
      'A acreditar': Math.round(tAcred),
    });

    const wb = XLSX.utils.book_new();
    const ws = XLSX.utils.json_to_sheet(filas, {
      header: ['Empleada','Local','CUIL','CBU','Recibo neto','Préstamos','Adelantos','A acreditar']
    });
    ws['!cols'] = [{wch:32},{wch:12},{wch:14},{wch:24},{wch:14},{wch:14},{wch:14},{wch:14}];
    XLSX.utils.book_append_sheet(wb, ws, 'Planilla blanca');

    const localTxt = (local && local !== 'todos') ? local : 'Adorno';
    XLSX.writeFile(wb, `Planilla blanca ${localTxt} ${periodo}.xlsx`);
    toast(`✓ ${filas.length-1} filas — A acreditar total ${'$' + Math.round(tAcred).toLocaleString('es-AR')}`, 'success');
  } catch (e) {
    console.error(e);
    toast('Error al exportar: ' + e.message, 'error');
  }
}


// ═══════════════════════════════════════════════════════════════════════
//  Libro Sueldos Digital (LSD) — TXT para ARCA
//  Extraído de index.html el 30-jul-2026 (Fase 2 · módulo 5).
// ═══════════════════════════════════════════════════════════════════════

const LSD_CUIT_EMPLEADOR = '30709673110';  // Claudia Adorno SRL — sin guiones

// Helpers de padding LSD
const _lsdPadN = (v, n) => String(v == null ? 0 : v).replace(/\D/g,'').padStart(n, '0').slice(-n);
const _lsdPadA = (v, n) => (String(v || '').padEnd(n, ' ')).slice(0, n);
// Importes: 15 dígitos sin punto, últimos 2 son centavos. Ej: $1.500.250,75 → '000000150025075'
const _lsdPadIm = (v) => {
  const cents = Math.round(Math.abs(Number(v || 0)) * 100);
  return String(cents).padStart(15, '0').slice(-15);
};
// Fecha AAAAMMDD desde string ISO o Date
const _lsdFechaAAAAMMDD = (d) => {
  if (!d) return '00000000';
  const dt = (d instanceof Date) ? d : new Date(d + (String(d).length === 10 ? 'T12:00:00' : ''));
  if (isNaN(dt)) return '00000000';
  return dt.getFullYear() + String(dt.getMonth()+1).padStart(2,'0') + String(dt.getDate()).padStart(2,'0');
};

async function generarLSDTxtAuto(periodo, localFilter) {
  // Genera UN solo archivo con TODOS los colaboradores (sin separar por jurisdicción).
  // Razón: Adorno SRL tiene solo Buenos Aires declarada en Simplificación Registral
  // → ARCA rechaza cargar liquidaciones para otras jurisdicciones (ej: CABA).
  // Cada colaborador mantiene su código de localidad individual dentro del registro 04.
  if (session.rol !== 'admin') { toast('Solo admin', 'error'); return; }
  await generarLSDTxt(periodo, null, 1);
}

// Versión del generador LSD — incluida en el nombre del archivo para fácil verificación.
// Bumpear este string en cada cambio funcional del generador.
const LSD_GENERATOR_VERSION = 'v49';

async function generarLSDTxt(periodo, jurisdiccionFiltro, nroLiquidacion) {
  if (session.rol !== 'admin') { toast('Solo admin', 'error'); return; }
  try {
    const periodoFull = periodo + '-01';
    const periodoAAMM = periodo.replace('-','');  // AAAAMM

    // 1) Liquidaciones del período + colaboradores + conceptos
    //    EXCLUYE monotributistas (no van al LSD ARCA — son terceras, facturan)
    let { data: liqs, error } = await sb.from('rrhh_liquidacion')
      .select('*, empleado:rrhh_empleados(*), conceptos:rrhh_liquidacion_concepto(*)')
      .eq('periodo', periodoFull)
      .order('empleado(apellido)');
    if (error) { toast('Error: ' + error.message, 'error'); return; }
    if (!liqs || liqs.length === 0) { toast('No hay liquidaciones para ese período', 'warning'); return; }
    // Filtrar fuera a monotributistas
    liqs = liqs.filter(l => !l.empleado?.monotributista);

    // 1b) Filtrar por jurisdicción si corresponde
    if (jurisdiccionFiltro) {
      liqs = liqs.filter(l => (l.empleado?.jurisdiccion || 'NACION') === jurisdiccionFiltro);
      if (liqs.length === 0) {
        toast('No hay colaboradores con jurisdicción ' + jurisdiccionFiltro + ' en este período', 'warning');
        return;
      }
    }

    // 2) Conceptos: usamos los códigos INTERNOS directamente (como MEMOSOFT).
    //    ARCA no acepta los códigos AFIP genéricos — cada empleador carga sus propios
    //    códigos en la sección "Conceptos" de LSD y solo esos pueden usarse en el TXT.

    // 3) Fecha de pago = último día hábil del mes (simplificación: último día calendario)
    const [py, pm] = periodo.split('-').map(Number);
    const ultDia = new Date(py, pm, 0);  // día 0 del mes siguiente = último del mes
    const fechaPagoAAAAMMDD = _lsdFechaAAAAMMDD(ultDia);
    const fechaRubricaAAAAMMDD = fechaPagoAAAAMMDD;  // misma fecha por ahora

    const lineas = [];

    // ─── Registro 01: cabecera ───
    const nroLiq = Number(nroLiquidacion) || 1;
    const reg01 = ''
      + '01'                                       // tipo (2)
      + _lsdPadN(LSD_CUIT_EMPLEADOR, 11)           // CUIT (11)
      + 'SJ'                                       // identificación envío (2)
      + _lsdPadN(periodoAAMM, 6)                   // período (6)
      + 'M'                                        // tipo liquidación (1) mensual
      + _lsdPadN(nroLiq, 5)                        // número liquidación (5)
      + '30'                                       // días base (2)
      + _lsdPadN(liqs.length, 6);                  // cantidad trabajadores (6)
    lineas.push(reg01);

    let empleadosOK = 0, empleadosErr = [];

    // ─── Por cada empleado: 02 + N×03 + 04 ───
    for (const l of liqs) {
      const emp = l.empleado;
      if (!emp) { empleadosErr.push('liq ' + l.id + ' sin empleado'); continue; }
      const cuil = String(emp.cuil || '').replace(/[^\d]/g, '').padStart(11, '0');
      if (cuil === '00000000000') { empleadosErr.push(emp.nombre_completo + ' sin CUIL'); continue; }

      // ── Registro 02 (formato real del estudio MEMOSOFT) ──
      // Legajo right-aligned con 0s, dependencia vacía, CBU vacío, forma_pago=1, fecha rúbrica vacía.
      const legajoField = String(emp.legajo || emp.id || '').padStart(10, '0').slice(-10);
      const reg02 = ''
        + '02'                                                   // tipo (2)
        + cuil                                                   // CUIL (11)
        + legajoField                                            // legajo (10) right-aligned con 0
        + _lsdPadA('', 50)                                       // dependencia revista (50) vacía
        + _lsdPadA('', 22)                                       // CBU (22) vacío
        + _lsdPadN(30, 3)                                        // días tope (3)
        + fechaPagoAAAAMMDD                                      // fecha pago (8)
        + _lsdPadA('', 8)                                        // fecha rúbrica (8) vacía
        + '1';                                                   // forma pago (1) = efectivo (como MEMOSOFT)
      lineas.push(reg02);

      // ── Registros 03: conceptos ──
      const conceptos = (l.conceptos || []).sort((a,b) => (a.orden||0) - (b.orden||0));
      // OSECAC usa códigos NR distintos a no-OSECAC para que las bases AFIP se calculen bien.
      // OSECAC : 0490 (suma), 0492 (ant), 0493 (pres), 0496 (recompos) — todos imputan a OS
      // no-OSECAC: 0491 (suma), 0494 (ant), 0495 (pres), 0497 (recompos) — NO imputan a OS
      const _osEmp = (emp.obra_social_codigo || '').toLowerCase();
      const _esOsecac = _osEmp === 'osecac';
      const _codeSwap = (cod) => {
        if (_esOsecac) {
          // Convertir códigos no-OSECAC → OSECAC
          if (cod === '0491') return '0490';
          if (cod === '0494') return '0492';
          if (cod === '0495') return '0493';
          if (cod === '0497') return '0496';
        } else {
          // Convertir códigos OSECAC → no-OSECAC
          if (cod === '0490') return '0491';
          if (cod === '0492') return '0494';
          if (cod === '0493') return '0495';
          if (cod === '0496') return '0497';
        }
        return cod;
      };
      for (const c of conceptos) {
        let codInterno = String(c.codigo || '').trim();
        if (!codInterno) continue;  // skip conceptos sin código
        codInterno = _codeSwap(codInterno);
        // Padding-LEFT con espacios (formato que usa el estudio en TXT real)
        const codField = codInterno.padStart(10, ' ').slice(-10);
        const reg03 = ''
          + '03'                                       // tipo (2)
          + cuil                                       // CUIL (11)
          + codField                                   // código concepto interno (10) — padding-left con espacios
          + _lsdPadN(Math.round(Number(c.unidades||0) * 100), 5)  // cantidad (3.2)
          + ' '                                        // unidad de medida (1)
          + _lsdPadIm(c.importe)                       // importe (15) sin punto
          + (c.es_descuento ? 'D' : 'C')               // D/C (1)
          + '      ';                                  // período ajuste retroactivo (6) vacío
        lineas.push(reg03);
      }

      // ── Registro 04: datos para F.931 ──
      const conyuge = emp.conyuge_a_cargo ? '1' : '0';
      const hijos = emp.hijos_a_cargo || 0;
      const enCCT = emp.fuera_convenio ? '0' : '1';
      // Remuneración bruta = bruto del recibo CCT (rem + NR). NO total_negro.
      // Si usamos total_negro las bases imponibles pueden quedar mayores → ARCA rechaza.
      // Bases imponibles 1-10: AFIP define qué entra en cada base.
      // Simplificación: bases 1-4 (SIPA, INSSJyP, OS, FSR) = bruto remunerativo del mes;
      //                 bases 5-9 = bruto total (rem + NR);
      //                 base 10 = 0 (no aplica régimen diferencial para comercio).
      // Si MEMOSOFT calcula diferente, lo ajustamos cuando comparemos.
      // Calcular bases imponibles a partir de los CONCEPTOS (registro 03).
      let baseRem = 0, baseNR_total = 0;
      for (const c of conceptos) {
        if (c.es_descuento) continue;
        const imp = Number(c.importe) || 0;
        if (c.remunerativo) baseRem += imp;
        else baseNR_total += imp;
      }
      const baseTotal = baseRem + baseNR_total;
      // PATRÓN DEL ESTUDIO (validado contra TXT abril 2026):
      //   - Base 1, 2, 3, 5 = baseRem SIEMPRE (incluso OSECAC)
      //   - Base 4, 8 (LRT) = baseTotal si OSECAC; baseRem si no
      //   - Base 9 = baseTotal SIEMPRE
      //   - Rem.Bruta = baseTotal SIEMPRE
      const base3 = baseRem;
      const baseLRT = _esOsecac ? baseTotal : baseRem;
      // Base 1-3, 5 (SIPA, PAMI, OS, FNE) = remunerativo
      // Base 4, 8 (LRT/ART) = remunerativo + NR (sobre rem total)
      // Base 9 (contribución empleador) = bruto total
      // Base 6, 7, 10 = 0

      // Código localidad real per colaborador (01 CABA, 02 BsAs)
      const locCodigo = String(emp.localidad_codigo || '02').padStart(2, '0').slice(-2);

      const reg04 = ''
        + '04'                                         // tipo (2)
        + cuil                                         // CUIL (11)
        + conyuge                                      // marca cónyuge (1)
        + _lsdPadN(hijos, 2)                           // cantidad hijos (2)
        + enCCT                                        // marca CCT (1)
        + '1'                                          // marca SCVO (1) — todos cubiertos
        + '0'                                          // marca reducción (1)
        + '1'                                          // código tipo empleador (1) — 1 = privado
        + '0'                                          // tipo operación (1)
        + _lsdPadA(emp.situacion_revista_default || '1', 2)  // situación revista (2)
        + _lsdPadA(emp.condicion_codigo || '1', 2)     // código condición (2)
        + _lsdPadA(emp.actividad_codigo || '049', 3).slice(-3)  // código actividad (3) — últimos 3
        + _lsdPadA(emp.modalidad_contrato_codigo || '008', 3)  // modalidad (3)
        + _lsdPadA(emp.siniestrado_codigo || '0', 2)   // siniestrado (2)
        + locCodigo                                    // código localidad (2) — 01 CABA, 02 BsAs
        + _lsdPadA(emp.situacion_revista_default || '1', 2)  // situación revista 1 (2)
        + _lsdPadN(1, 2)                               // día inicio revista 1 (2) — día 1
        + '  '                                         // situación revista 2 (2) vacía
        + '00'                                         // día inicio revista 2
        + '  '                                         // situación revista 3
        + '00'                                         // día inicio revista 3
        + _lsdPadN(l.dias_trabajados || 30, 2)         // días trabajados (2)
        + _lsdPadN(0, 3)                               // horas trabajadas (3)
        + _lsdPadN(0, 5)                               // % aporte adicional SS (5)
        + _lsdPadN(0, 5)                               // % contribución diferencial (5)
        + _lsdPadA(emp.os_codigo_afip || '126205', 6) // código obra social (6) — código REAL per empleada
        + _lsdPadN(0, 2)                               // adherentes OS (2)
        + _lsdPadIm(0)                                 // aporte adicional OS (15)
        + _lsdPadIm(0)                                 // contribución adicional OS (15)
        + _lsdPadIm(0)                                 // base diferencial aporte OS+FSR (15)
        + _lsdPadIm(0)                                 // base diferencial contrib OS+FSR (15)
        + _lsdPadIm(0)                                 // base diferencial LRT (15)
        + _lsdPadIm(0)                                 // remuneración maternidad (15)
        + _lsdPadIm(baseTotal)                         // remuneración bruta (15) — ARCA determina = baseTotal
        + _lsdPadIm(baseRem)                           // base imponible 1 (SIPA jub) — sobre rem
        + _lsdPadIm(baseRem)                           // base imponible 2 (PAMI) — sobre rem
        + _lsdPadIm(base3)                             // base imponible 3 (OS) — dinámica: baseTotal si OSECAC, baseRem si no
        + _lsdPadIm(baseLRT)                           // base imponible 4 (LRT aporte) — baseRem + 0492 + 0493
        + _lsdPadIm(baseRem)                           // base imponible 5 (FNE) — sobre rem
        + _lsdPadIm(0)                                 // base imponible 6
        + _lsdPadIm(0)                                 // base imponible 7
        + _lsdPadIm(baseLRT)                           // base imponible 8 (LRT contrib emp) — baseRem + 0492 + 0493
        + _lsdPadIm(baseTotal)                         // base imponible 9 (contrib total) — sobre bruto
        + _lsdPadIm(0)                                 // base diferencial aporte SS (15)
        + _lsdPadIm(0)                                 // base diferencial contrib SS (15)
        + _lsdPadIm(0)                                 // base imponible 10
        + _lsdPadIm(0);                                // importe a detraer Ley 26473 (15)
      lineas.push(reg04);
      empleadosOK++;
    }

    // Descargar
    const txt = lineas.join('\r\n');
    const blob = new Blob([txt], { type: 'text/plain;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = 'LSD_Adorno_' + (jurisdiccionFiltro || 'TODOS') + '_' + periodoAAMM + '_' + LSD_GENERATOR_VERSION + '.txt';
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);

    // Loggear en rrhh_lsd_export_log (si la tabla existe, sino skip)
    try {
      await sb.from('rrhh_lsd_export_log').insert({
        periodo: periodoFull,
        tipo: 'AFIP_LSD' + (jurisdiccionFiltro ? '_' + jurisdiccionFiltro : ''),
        empleados_count: empleadosOK, lineas_count: lineas.length,
        errores: empleadosErr.length ? empleadosErr.join(' · ') : null
      });
    } catch (_) {}

    let msg = '✓ LSD generado: ' + empleadosOK + ' colaboradores · ' + lineas.length + ' líneas';
    if (empleadosErr.length) msg += ' · ⚠ ' + empleadosErr.length + ' con errores';
    toast(msg, empleadosErr.length ? 'error' : 'success');
    if (empleadosErr.length) console.warn('LSD errores:', empleadosErr);
  } catch (e) {
    console.error(e);
    toast('Error generando LSD: ' + e.message, 'error');
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  SALARY WORKFLOW — Orquesta el cálculo y guardado de liquidaciones
//  Usa salaryEngine.calcularReciboCCT por debajo, suma el negro/ajuste blanco,
//  y vuelca a rrhh_liquidacion + rrhh_liquidacion_concepto.
// ═══════════════════════════════════════════════════════════════════════
