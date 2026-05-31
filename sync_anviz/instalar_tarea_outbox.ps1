# ═══════════════════════════════════════════════════════════════════════
#  instalar_tarea_outbox.ps1
#
#  Crea (o reemplaza) la tarea programada de Windows que procesa el
#  outbox de emails cada hora.
#
#  IMPORTANTE: Usa wrapper VBScript para correr Python sin ventana visible
#  (porque python.exe de WindowsApps no tiene pythonw.exe).
#
#  Cómo correr (una sola vez):
#    PowerShell como ADMINISTRADOR (clic derecho → Ejecutar como administrador):
#      cd C:\CRM_Adorno\rrhh-adorno\sync_anviz
#      .\instalar_tarea_outbox.ps1
#
#  Para ver el estado de la tarea después:
#      Get-ScheduledTask -TaskName "RRHH_ProcesarEmailOutbox"
#  Para correr ahora manualmente (sin esperar al próximo trigger):
#      Start-ScheduledTask -TaskName "RRHH_ProcesarEmailOutbox"
#  Para eliminarla:
#      Unregister-ScheduledTask -TaskName "RRHH_ProcesarEmailOutbox" -Confirm:$false
# ═══════════════════════════════════════════════════════════════════════

$ErrorActionPreference = 'Stop'

$TaskName    = "RRHH_ProcesarEmailOutbox"
$WrapperVbs  = "C:\CRM_Adorno\rrhh-adorno\sync_anviz\wrapper_outbox.vbs"
$WorkDir     = "C:\CRM_Adorno\rrhh-adorno\sync_anviz"
$WScriptExe  = "C:\Windows\System32\wscript.exe"

# Verificar que el wrapper VBS existe
if (-not (Test-Path $WrapperVbs)) {
    Write-Host "ERROR: No se encontro $WrapperVbs" -ForegroundColor Red
    Write-Host "Asegurate de que wrapper_outbox.vbs este en la misma carpeta." -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $WScriptExe)) {
    Write-Host "ERROR: No se encontro wscript.exe en $WScriptExe" -ForegroundColor Red
    exit 1
}

Write-Host "Wrapper VBS:        $WrapperVbs" -ForegroundColor Green
Write-Host "WScript runtime:    $WScriptExe" -ForegroundColor Green
Write-Host "Directorio trabajo: $WorkDir" -ForegroundColor Green

# Eliminar tarea anterior si existe (idempotente)
$existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "Tarea anterior encontrada, eliminandola..." -ForegroundColor Yellow
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

# Definir la accion: correr wscript con el wrapper VBS (sin ventana visible)
$action = New-ScheduledTaskAction `
    -Execute $WScriptExe `
    -Argument "`"$WrapperVbs`"" `
    -WorkingDirectory $WorkDir

# Trigger: arrancar hoy a las 09:00, repetir cada 1 hora hasta las 22:00
$startTime = (Get-Date).Date.AddHours(9)  # hoy a las 09:00
$trigger = New-ScheduledTaskTrigger -Once -At $startTime `
    -RepetitionInterval (New-TimeSpan -Hours 1) `
    -RepetitionDuration (New-TimeSpan -Hours 13)  # de 09:00 a 22:00

# Settings: arrancar lo antes posible si la PC estaba apagada, timeout 10min
$settings = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 10) `
    -MultipleInstances IgnoreNew `
    -Hidden

# Correr con el usuario actual, sin login interactivo
$principal = New-ScheduledTaskPrincipal `
    -UserId "$env:USERDOMAIN\$env:USERNAME" `
    -LogonType Interactive `
    -RunLevel Limited

# Registrar la tarea
Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Principal $principal `
    -Description "Procesa el outbox de emails de RRHH Adorno (avisos Ganancias, recibos firma, etc.) cada 1 hora entre 09:00 y 22:00. Usa wrapper VBS para correr sin ventana visible." | Out-Null

Write-Host ""
Write-Host "Tarea creada con exito" -ForegroundColor Green
Write-Host "Nombre:      $TaskName"
Write-Host "Frecuencia:  cada 1 hora, de 09:00 a 22:00"
Write-Host "Comando:     $WScriptExe `"$WrapperVbs`""
Write-Host "Modo:        oculto (no abre ventana negra)" -ForegroundColor Cyan
Write-Host ""
Write-Host "Para ver el estado: Get-ScheduledTask -TaskName $TaskName" -ForegroundColor Cyan
Write-Host "Para correr ahora:  Start-ScheduledTask -TaskName $TaskName" -ForegroundColor Cyan
Write-Host "Para borrarla:      Unregister-ScheduledTask -TaskName $TaskName -Confirm:`$false" -ForegroundColor Cyan
