"""
═══════════════════════════════════════════════════════════════════════
 validar_turnos.py — Verificar que todos los turnos tengan hora_inicio
 cargada con el buffer de 15 min (formato X:45) para que el cruce
 de fichadas funcione correctamente.

 También chequea templates y turnos generados de abril+mayo.

 USO:
   python validar_turnos.py
═══════════════════════════════════════════════════════════════════════
"""
import sys
if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    except Exception:
        pass

import os, json
from pathlib import Path
from urllib import request as urlrequest
from collections import Counter, defaultdict

try:
    from dotenv import load_dotenv
    load_dotenv(Path(__file__).parent / '.env')
except ImportError:
    pass

SUPA_URL = os.environ.get('SUPABASE_URL', 'https://kwwiykssrpabncpqtmwi.supabase.co')
SUPA_KEY = os.environ.get('SUPABASE_SERVICE_KEY')

if not SUPA_KEY:
    sys.exit("❌ Falta SUPABASE_SERVICE_KEY en .env")

H = {
    "apikey": SUPA_KEY,
    "Authorization": f"Bearer {SUPA_KEY}",
    "Content-Type": "application/json",
}

def fetch(path):
    url = f"{SUPA_URL}/rest/v1/{path}"
    req = urlrequest.Request(url, headers={**H, "Range-Unit": "items"})
    with urlrequest.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read())

print("🔍 Validando turnos en la DB...\n")

# ═══════════════════════════════════════════════════════════════════════
# 1) Templates
# ═══════════════════════════════════════════════════════════════════════
print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print("1) TEMPLATES (rrhh_templates_turno)")
print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
tpls = fetch("rrhh_templates_turno?activo=eq.true&order=local,codigo")
print(f"{'Local':<12} {'Código':<18} {'Inicio':<10} {'Fin':<10} {'¿Buffer?':<10}")
print("─" * 70)
issues_tpl = []
for t in tpls:
    hi = (t.get('hora_inicio') or '')[:5]
    hf = (t.get('hora_fin') or '')[:5]
    ok = hi.endswith(':45')
    flag = "✓ ok" if ok else "⚠ FIX!"
    if not ok: issues_tpl.append((t['local'], t['codigo'], hi))
    print(f"{t.get('local',''):<12} {t.get('codigo',''):<18} {hi:<10} {hf:<10} {flag}")
print()

# ═══════════════════════════════════════════════════════════════════════
# 2) Tolerancias por local
# ═══════════════════════════════════════════════════════════════════════
print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print("2) TOLERANCIAS (rrhh_config_tolerancias)")
print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
tols = fetch("rrhh_config_tolerancias?order=local")
print(f"{'Local':<12} {'Buffer':<8} {'Tol.Tarde':<12} {'Tol.Temp':<10} {'MaxErr':<8} {'UmbralMensual':<15}")
print("─" * 75)
for t in tols:
    print(f"{t.get('local',''):<12} {t.get('buffer_entrada',''):<8} {t.get('minutos_tarde',''):<12} {t.get('minutos_temprano',''):<10} {t.get('max_errores_premio',''):<8} {t.get('umbral_mensual_tardanzas','')}")
print()

# ═══════════════════════════════════════════════════════════════════════
# 3) Turnos generados (abril + mayo 2026)
# ═══════════════════════════════════════════════════════════════════════
print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print("3) TURNOS GENERADOS (abril+mayo 2026)")
print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
turnos = fetch("rrhh_turnos?fecha=gte.2026-04-01&fecha=lte.2026-05-31&select=id,empleado_id,fecha,hora_inicio,hora_fin,es_franco,tipo&limit=2000")
print(f"Total: {len(turnos)} turnos\n")

# Agrupar por hora_inicio
por_inicio = Counter()
issues_turnos = []
for t in turnos:
    hi = (t.get('hora_inicio') or '')[:5]
    if not hi or t.get('es_franco'): continue
    por_inicio[hi] += 1
    if not hi.endswith(':45') and not hi.endswith(':30'):
        issues_turnos.append((t['empleado_id'], t['fecha'], hi))

print("Distribución por hora_inicio:")
for hi, cnt in sorted(por_inicio.items()):
    buffer_ok = "✓" if hi.endswith(':45') or hi.endswith(':30') else "⚠"
    print(f"   {buffer_ok} {hi}  →  {cnt} turnos")
print()

# ═══════════════════════════════════════════════════════════════════════
# 4) Resumen
# ═══════════════════════════════════════════════════════════════════════
print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print("RESUMEN")
print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
if not issues_tpl and not issues_turnos:
    print("✅ Todo OK — todos los turnos están cargados con buffer (X:45)")
else:
    if issues_tpl:
        print(f"\n⚠ {len(issues_tpl)} templates sin buffer (no terminan en :45):")
        for local, cod, hi in issues_tpl:
            print(f"   - {local}/{cod}: hora_inicio={hi}")
    if issues_turnos:
        print(f"\n⚠ {len(issues_turnos)} turnos individuales sin buffer:")
        # Mostrar solo primeros 10
        for emp, fecha, hi in issues_turnos[:10]:
            print(f"   - emp={emp} fecha={fecha} hora_inicio={hi}")
        if len(issues_turnos) > 10:
            print(f"   ... y {len(issues_turnos)-10} más")
