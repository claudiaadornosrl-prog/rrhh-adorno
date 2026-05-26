# ====================================================================
#  Prueba rápida de las 4 cuentas Anviz CrossChex Cloud
#  Pide token + baja 3 fichadas de los últimos 7 días de cada cuenta
#  Uso:
#     cd C:\CRM_Adorno\rrhh-adorno\sync_anviz
#     .\probar_anviz.ps1
# ====================================================================

# Permitir warnings sin fallar
$ErrorActionPreference = "Continue"

# Verificar deps
$pythonOk = Get-Command python -ErrorAction SilentlyContinue
if (-not $pythonOk) {
    Write-Host "ERROR: Python no esta en PATH" -ForegroundColor Red
    exit 1
}

Write-Host "Instalando dependencias..." -ForegroundColor Cyan
# Redirigir stderr a $null para evitar que warnings de pip rompan el script
pip install requests python-dotenv supabase --quiet 2>$null
Write-Host "OK" -ForegroundColor Green

$cuentas = @(
    @{ Nombre = "Oficina (Don Torcuato)";   Key = "7708294b5678c1ff2f24651850625893"; Secret = "28b61ff805b7105a8cd98ff424dbff41" }
    @{ Nombre = "Unicenter (Martinez)";     Key = "09320728bb09539cf9ade1f0942c3ec2"; Secret = "3272907e6db7dbbb8d1c205be454ca50" }
    @{ Nombre = "Alcorta principal";        Key = "3b750207c1927a118451111dcff8166e"; Secret = "23933b43e804d5a377ad9d5fa2cf80ee" }
    @{ Nombre = "Alcorta backup";           Key = "53803f86c9d5e5d7c3208f8733727cc1"; Secret = "a3101febbe000abd22ad5f6f9e2d65cc" }
)

# Probar cada region — el panel de JP puede estar en us, eu, ap...
$regiones = @("us", "eu", "ap")

foreach ($c in $cuentas) {
    Write-Host ""
    Write-Host "===================================================" -ForegroundColor Cyan
    Write-Host " $($c.Nombre)" -ForegroundColor Cyan
    Write-Host "===================================================" -ForegroundColor Cyan

    $exitoso = $false
    foreach ($r in $regiones) {
        Write-Host "  Probando region '$r'..." -NoNewline
        $output = python anviz_client.py --api-key $c.Key --api-secret $c.Secret --region $r --dias 7 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host " OK" -ForegroundColor Green
            $output | ForEach-Object { Write-Host "    $_" }
            $exitoso = $true
            break
        } else {
            Write-Host " falla" -ForegroundColor DarkGray
        }
    }
    if (-not $exitoso) {
        Write-Host "  ERROR: No funciono con ninguna region. Revisar credenciales o pedir activacion Developer Mode a Anviz." -ForegroundColor Red
        Write-Host "  Ultimo output:" -ForegroundColor DarkGray
        $output | Select-Object -Last 5 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
    }
}

Write-Host ""
Write-Host "Listo. Si alguna cuenta funciono, anota la region en el .env" -ForegroundColor Cyan
