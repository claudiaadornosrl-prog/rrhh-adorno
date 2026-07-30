// ═══════════════════════════════════════════════════════════════════════
//  RRHH Adorno · exportaciones.js
//  Export Galicia Office (XLSX para acreditar sueldos) y planilla blanca.
//  Extraído de index.html el 30-jul-2026 (modularización, Fase 2).
//  Se carga después del script principal; nada de esto corre al arrancar.
// ═══════════════════════════════════════════════════════════════════════

async function exportarGaliciaXLSX(local, periodo) {
  try {
    if (!window.XLSX) { toast('Falta SheetJS — recargá la página', 'error'); return; }

    // Cargar liquidaciones del período + datos de colaboradora (incluido cbu)
    let q = sb.from('rrhh_liquidacion')
      .select('id, periodo, recibo_neto, prestamo_capital, local, empleado:rrhh_empleados(id, apellido, nombre, nombre_completo, cuil, cbu)')
      .eq('periodo', periodo + '-01');
    if (local && local !== 'todos') q = q.eq('local', local);
    const { data: liqs, error } = await q;
    if (error) { toast('Error: ' + error.message, 'error'); return; }
    if (!liqs || liqs.length === 0) { toast('No hay liquidaciones para exportar', 'warning'); return; }

    // Armar filas
    const fmtNombre = (e) => {
      if (!e) return '';
      const ape = (e.apellido || '').toUpperCase();
      const nom = (e.nombre   || '').toUpperCase();
      return `${ape}, ${nom}`.trim();
    };
    // Fecha de acreditación: último día hábil del mes del período, ajustable en el portal si hace falta
    const [py, pm] = periodo.split('-').map(Number);
    const ultDia = new Date(py, pm, 0); // día 0 del mes siguiente = último día del mes
    const fechaAcred = `${String(ultDia.getDate()).padStart(2,'0')}/${String(ultDia.getMonth()+1).padStart(2,'0')}/${ultDia.getFullYear()}`;

    const filas = [];
    const sinCuenta = [];
    let totalImporte = 0;
    for (const l of liqs) {
      const e = l.empleado;
      if (!e) continue;
      const aAcreditar = (+l.recibo_neto || 0) - (+l.prestamo_capital || 0);
      if (aAcreditar <= 0) continue;
      if (!e.cbu) { sinCuenta.push(fmtNombre(e)); continue; }
      filas.push({
        'Nombre': fmtNombre(e),
        'NroCuenta | CBU': e.cbu,
        'Fecha de Acred.': fechaAcred,
        'Importe': Math.round(aAcreditar),
        'Estado': '',
        'Email': '',
        'Observaciones': '',
      });
      totalImporte += aAcreditar;
    }

    if (filas.length === 0) {
      toast('Ninguna colaboradora con CBU cargado y monto > 0', 'error');
      return;
    }

    // Avisar las que quedan afuera (sin CBU)
    if (sinCuenta.length > 0) {
      const lista = sinCuenta.join('\n  • ');
      if (!confirm(`⚠ ${sinCuenta.length} empleada(s) sin CBU/cuenta cargada quedan fuera del archivo:\n\n  • ${lista}\n\nCargalas en su legajo (campo CBU) o continuá igual.\n\n¿Generar el archivo con las ${filas.length} restantes?`)) return;
    }

    // Armar el workbook
    const wb = XLSX.utils.book_new();
    const ws = XLSX.utils.json_to_sheet(filas, {
      header: ['Nombre','NroCuenta | CBU','Fecha de Acred.','Importe','Estado','Email','Observaciones']
    });
    // Anchos de columna razonables
    ws['!cols'] = [
      { wch: 32 }, { wch: 22 }, { wch: 14 }, { wch: 14 },
      { wch: 12 }, { wch: 18 }, { wch: 30 },
    ];
    XLSX.utils.book_append_sheet(wb, ws, 'Pagos');

    // Nombre del archivo
    const localTxt = (local && local !== 'todos') ? local : 'Adorno';
    const fileName = `Pagos ${localTxt} ${periodo}.xlsx`;
    XLSX.writeFile(wb, fileName);

    toast(`✓ ${filas.length} pagos exportados — total ${'$' + Math.round(totalImporte).toLocaleString('es-AR')}`, 'success');
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
      const { data: pAct } = await sb.from('rrhh_prestamo')
        .select('id, empleado_id, estado, cuotas_totales, tasa_mensual')
        .in('empleado_id', empIds);
      const pById = {}; (pAct || []).forEach(p => { pById[p.id] = p; });
      const idsP = (pAct || []).map(p => p.id);
      if (idsP.length > 0) {
        const { data: cs } = await sb.from('rrhh_prestamo_cuota')
          .select('prestamo_id, monto_capital, mes_descuento')
          .eq('mes_descuento', periodo + '-01').in('prestamo_id', idsP);
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
