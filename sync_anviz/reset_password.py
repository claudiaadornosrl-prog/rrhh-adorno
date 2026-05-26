"""
═══════════════════════════════════════════════════════════════════════
 reset_password.py — Resetear contraseña de un usuario en Supabase Auth
 usando el SERVICE KEY del .env (sin email de recuperación).

 USO:
   python reset_password.py juanpsimonelli@gmail.com teo92
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

try:
    from dotenv import load_dotenv
    load_dotenv(Path(__file__).parent / '.env')
except ImportError:
    pass

SUPA_URL = os.environ.get('SUPABASE_URL', 'https://kwwiykssrpabncpqtmwi.supabase.co')
SUPA_KEY = os.environ.get('SUPABASE_SERVICE_KEY')

if len(sys.argv) != 3:
    sys.exit("Uso: python reset_password.py <email> <nueva_password>")

email_target = sys.argv[1]
new_pass     = sys.argv[2]

if not SUPA_KEY:
    sys.exit("❌ Falta SUPABASE_SERVICE_KEY en .env")
if len(new_pass) < 6:
    sys.exit(f"❌ Supabase exige password de al menos 6 caracteres. '{new_pass}' tiene {len(new_pass)}.")

H = {
    "apikey": SUPA_KEY,
    "Authorization": f"Bearer {SUPA_KEY}",
    "Content-Type": "application/json",
}

# 1) Buscar usuario por email
req = urlrequest.Request(f"{SUPA_URL}/auth/v1/admin/users?per_page=200", headers=H)
with urlrequest.urlopen(req, timeout=15) as resp:
    data = json.loads(resp.read())

users = data.get('users', data) if isinstance(data, dict) else data
target = next((u for u in users if (u.get('email') or '').lower() == email_target.lower()), None)
if not target:
    print(f"❌ No se encontró {email_target}")
    print("Emails encontrados:")
    for u in users:
        print(f"   {u.get('email')} → {u.get('id')}")
    sys.exit(1)

uid = target['id']
print(f"✓ Usuario: {email_target} → {uid}")

# 2) Resetear password
body = json.dumps({"password": new_pass}).encode('utf-8')
req = urlrequest.Request(f"{SUPA_URL}/auth/v1/admin/users/{uid}", data=body, headers=H, method='PUT')
try:
    with urlrequest.urlopen(req, timeout=15) as resp:
        result = json.loads(resp.read())
    print(f"✓ Contraseña reseteada exitosamente a '{new_pass}'")
    print(f"   Email confirmed: {result.get('email_confirmed_at') is not None}")
    print(f"\n👉 Entrá ahora con:")
    print(f"   Email:    {email_target}")
    print(f"   Password: {new_pass}")
except Exception as e:
    print(f"❌ Error al actualizar: {e}")
    if hasattr(e, 'read'):
        print(f"   Respuesta: {e.read().decode()}")
    sys.exit(1)
