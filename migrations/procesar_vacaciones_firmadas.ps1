# ═══════════════════════════════════════════════════════════════════════
#  procesar_vacaciones_firmadas.ps1
#  Wrapper para ejecutar el procesador automáticamente.
#  Lo invoca la Tarea Programada de Windows.
# ═══════════════════════════════════════════════════════════════════════

# NOTA: NO usar ErrorActionPreference=Stop porque Python escribe warnings
# a stderr y eso hace que PowerShell aborte aunque sea solo un warning.
$ErrorActionPreference = "Continue"
# UTF-8 para que los emojis del Python se vean bien en el log
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$env:PYTHONIOENCODING = 'utf-8'

$script_dir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $script_dir

# Log file (uno por mes)
$log_dir = Join-Path $script_dir "logs"
if (!(Test-Path $log_dir)) { New-Item -ItemType Directory -Path $log_dir | Out-Null }
$log_file = Join-Path $log_dir "vacaciones-firmadas-$(Get-Date -Format yyyy-MM).log"

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Add-Content -Path $log_file -Value "`n========== $timestamp =========="

# Detectar python.exe (probar varias rutas comunes)
$python_paths = @(
    "py.exe",   # Windows Python launcher (preferido)
    "C:\Python313\python.exe",
    "C:\Python312\python.exe",
    "C:\Python311\python.exe",
    "C:\Python310\python.exe",
    "${env:LocalAppData}\Programs\Python\Python313\python.exe",
    "${env:LocalAppData}\Programs\Python\Python312\python.exe",
    "${env:LocalAppData}\Programs\Python\Python311\python.exe",
    "${env:LocalAppData}\Programs\Python\Python310\python.exe",
    "${env:LocalAppData}\Microsoft\WindowsApps\python.exe",
    "python.exe"
)
$python_exe = $null
foreach ($p in $python_paths) {
    if (Get-Command $p -ErrorAction SilentlyContinue) { $python_exe = $p; break }
}
if (-not $python_exe) {
    $err = "ERROR: No se encontró python.exe en las rutas conocidas"
    Add-Content -Path $log_file -Value $err
    Write-Error $err
    exit 1
}
Add-Content -Path $log_file -Value "Python encontrado: $python_exe"

# Ejecutar y capturar TODO el output (stdout + stderr) sin abortar por warnings
$output = & $python_exe .\10_procesar_vacaciones_firmadas.py --aplicar --marcar-leido 2>&1 | Out-String
$exit_code = $LASTEXITCODE
# Escribir log en UTF-8
Add-Content -Path $log_file -Value $output -Encoding UTF8
Add-Content -Path $log_file -Value "Exit code: $exit_code" -Encoding UTF8

if ($exit_code -ne 0) {
    Write-Error "El script Python terminó con exit code $exit_code. Ver log: $log_file"
    exit $exit_code
} else {
    Write-Host "OK - log en $log_file"
}
