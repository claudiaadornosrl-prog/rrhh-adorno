"""
generar_vapid_keys.py
─────────────────────
Genera un par de claves VAPID para Web Push Notifications.

Uso:
    pip install cryptography py-vapid
    python generar_vapid_keys.py

Imprime las claves en pantalla. Vos:
  1. Copiás la `VAPID_PUBLIC_KEY` y la pegás en index.html (constante VAPID_PUBLIC_KEY)
  2. Copiás la `VAPID_PRIVATE_KEY` y la pegás en los Secrets de la Edge Function
     (Supabase Dashboard → Project Settings → Edge Functions → Secrets)
  3. Definís también un VAPID_SUBJECT (un mailto: o URL del proyecto)

Importante: una sola vez. Una vez generadas, NUNCA las rotes salvo emergencia
de seguridad — si las rotás, todas las suscripciones existentes dejan de andar
y las empleadas tienen que volver a darle al botón de "Activar notificaciones".
"""

import base64
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives import serialization


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")


def main() -> None:
    private_key = ec.generate_private_key(ec.SECP256R1())
    public_key = private_key.public_key()

    # Privada en formato PEM (la guarda Supabase Edge Function)
    private_pem = private_key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    ).decode("ascii")

    # Privada como bytes raw (32 bytes), base64url — formato VAPID directo
    private_numbers = private_key.private_numbers()
    private_raw = private_numbers.private_value.to_bytes(32, "big")
    private_b64 = b64url(private_raw)

    # Pública en formato uncompressed point (65 bytes), base64url — esto es lo
    # que va al frontend (applicationServerKey).
    public_raw = public_key.public_bytes(
        encoding=serialization.Encoding.X962,
        format=serialization.PublicFormat.UncompressedPoint,
    )
    public_b64 = b64url(public_raw)

    print("═══════════════════════════════════════════════════════════")
    print("  VAPID KEYS GENERADAS")
    print("═══════════════════════════════════════════════════════════\n")
    print(">>> VAPID_PUBLIC_KEY (va al frontend, en index.html):")
    print(f"\n    {public_b64}\n")
    print(">>> VAPID_PRIVATE_KEY (va a Supabase Secrets, formato raw base64url):")
    print(f"\n    {private_b64}\n")
    print(">>> VAPID_SUBJECT (también va a Secrets, definí uno tipo):")
    print("\n    mailto:juanpsimonelli@gmail.com\n")
    print("═══════════════════════════════════════════════════════════")
    print("  PRIVATE_KEY en formato PEM (alternativo, por si la lib lo pide así):")
    print("═══════════════════════════════════════════════════════════\n")
    print(private_pem)


if __name__ == "__main__":
    main()
