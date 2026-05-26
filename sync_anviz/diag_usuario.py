"""
═══════════════════════════════════════════════════════════════════════
 diag_usuario.py — Diagnosticar el estado de un usuario en rrhh_usuarios
 USO:
   python diag_usuario.py juanpsimonelli@gmail.com
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

if len(sys.argv) != 2:
    sys.exit("Uso: python diag_usuario.py <email>")

email_target = sys.argv[1]

if not SUPA_KEY:
    sys.exit("❌ Falta SUPABASE_SERVICE_KEY en .env")

H = {
    "apikey": SUPA_KEY,
    "Authorization": f"Bearer {SUPA_KEY}",
    "Content-Type": "application/json",
}

print(f"🔍 Diagnóstico para {email_target}\n")

# 1) Buscar en auth.users
req = urlrequest.Request(f"{SUPA_URL}/auth/v1/admin/users?per_page=200", headers=H)
with urlrequest.urlopen(req, timeout=15) as resp:
    data = json.loads(resp.read())
users = data.get('users', data) if isinstance(data, dict) else data
auth_user = next((u for u in users if (u.get('email') or '').lower() == email_target.lower()), None)

if not auth_user:
    print(f"❌ No existe en auth.users")
    sys.exit(1)

uid = auth_user['id']
print(f"✓ AUTH.USERS")
print(f"   id:                 {uid}")
print(f"   email:              {auth_user.get('email')}")
print(f"   email_confirmed_at: {auth_user.get('email_confirmed_at')}")
print(f"   banned_until:       {auth_user.get('banned_until')}")
print(f"   last_sign_in_at:    {auth_user.get('last_sign_in_at')}")
print()

# 2) Buscar en rrhh_usuarios
req = urlrequest.Request(
    f"{SUPA_URL}/rest/v1/rrhh_usuarios?auth_user_id=eq.{uid}&select=*",
    headers=H,
)
with urlrequest.urlopen(req, timeout=15) as resp:
    rrhh = json.loads(resp.read())

print(f"✓ RRHH_USUARIOS ({len(rrhh)} fila/s)")
if not rrhh:
    print(f"   ❌ NO HAY FILA en rrhh_usuarios con auth_user_id={uid}")
    print(f"   👉 Hay que insertar la fila manualmente. SQL:")
    print(f"      INSERT INTO rrhh_usuarios (auth_user_id, email, rol, activo)")
    print(f"      VALUES ('{uid}', '{email_target}', 'admin', true);")
else:
    for u in rrhh:
        print(f"   id:             {u.get('id')}")
        print(f"   auth_user_id:   {u.get('auth_user_id')}")
        print(f"   email:          {u.get('email')}")
        print(f"   rol:            {u.get('rol')}")
        print(f"   local_gerencia: {u.get('local_gerencia')}")
        print(f"   empleado_id:    {u.get('empleado_id')}")
        print(f"   activo:         {u.get('activo')}")
        print(f"   last_login:     {u.get('last_login')}")

        if not u.get('activo'):
            print(f"\n   ⚠️ activo=false — por eso no podés entrar")
            print(f"   👉 Fix: UPDATE rrhh_usuarios SET activo=true WHERE id={u.get('id')};")

print()

# 3) Probar la query exacta que hace el frontend (con anon key, simulando RLS)
ANON_KEY = os.environ.get('SUPABASE_ANON_KEY')
print(f"✓ RLS test (con anon key, sin auth de usuario) — solo informativo")
print(f"   (El frontend usa el JWT del usuario logueado, esto no es 100% representativo)")
