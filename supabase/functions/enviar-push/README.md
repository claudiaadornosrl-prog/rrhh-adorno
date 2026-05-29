# enviar-push · Edge Function

Manda Web Push notifications a una empleada vía sus suscripciones registradas en `rrhh_push_subscriptions`.

## Setup (primera vez)

### 1. Generar VAPID keys

```powershell
cd C:\CRM_Adorno\rrhh-adorno\sync_anviz
pip install cryptography
python generar_vapid_keys.py
```

Te imprime 3 cosas:
- `VAPID_PUBLIC_KEY`
- `VAPID_PRIVATE_KEY`
- `VAPID_SUBJECT`

### 2. Pegar la pública en el frontend

En `rrhh-adorno/index.html`, buscar `VAPID_PUBLIC_KEY` (~línea 514) y reemplazar `'REEMPLAZAR_CON_VAPID_PUBLIC_KEY'` por la clave pública generada.

### 3. Configurar Secrets en Supabase

🌐 Supabase Dashboard → Project Settings → Edge Functions → Add new secret:

- `VAPID_PUBLIC_KEY` = (la pública)
- `VAPID_PRIVATE_KEY` = (la privada raw base64url)
- `VAPID_SUBJECT` = `mailto:juanpsimonelli@gmail.com`

(`SUPABASE_URL` y `SUPABASE_SERVICE_ROLE_KEY` ya están automáticos)

### 4. Deploy

🟨 PowerShell:

```powershell
cd C:\CRM_Adorno\rrhh-adorno
supabase functions deploy enviar-push --no-verify-jwt
```

> El `--no-verify-jwt` es opcional. Si lo dejás con JWT, hay que mandar el `apikey` header en cada invocación desde el cliente.

## Uso desde la app

```js
await sb.functions.invoke('enviar-push', {
  body: {
    empleado_id: 12,
    title: 'Vacaciones aprobadas ✓',
    body:  'Te aprobamos los días del 15/06 al 22/06.',
    url:   './#mis-vacaciones',
    tag:   'vacacion-43',  // si la empleada ya tenía una notif del mismo tag, se reemplaza
  }
});
```

## Test rápido sin frontend

🟨 PowerShell:

```powershell
$body = '{"empleado_id": 12, "title": "Test", "body": "Hola mundo"}'
$headers = @{
    "Authorization" = "Bearer $env:SUPA_ANON_KEY"
    "Content-Type"  = "application/json"
}
Invoke-RestMethod -Method Post `
    -Uri "https://kwwiykssrpabncpqtmwi.supabase.co/functions/v1/enviar-push" `
    -Headers $headers -Body $body
```

Response esperado:
```json
{"ok": true, "sent": 2, "total": 2, "dead": 0}
```
