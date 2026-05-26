# ====================================================================
#  Instala una tarea programada de Windows que corre sync_anviz.py
#  el dia 1 de cada mes a las 7:00 AM
#
#  Uso (PowerShell como Admin):
#     cd C:\CRM_Adorno\rrhh-adorno\sync_anviz\scheduler
#     .\install_task.ps1
#
#  Para desinstalar:
#     Unregister-ScheduledTask -TaskName "RRHH-Adorno-SyncAnviz" -Confirm:$false
# ====================================================================

$ErrorActionPreference = "Stop"
$TaskName     = "RRHH-Adorno-SyncAnviz"
$ScriptPath   = "C:\CRM_Adorno\rrhh-adorno\sync_anviz\sync_anviz.py"
$WorkingDir   = "C:\CRM_Adorno\rrhh-adorno\sync_anviz"
$LogDir       = "C:\CRM_Adorno\rrhh-adorno\sync_anviz\logs"

# Verificar que Python este en PATH
$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) {
    Write-Host "ERROR: Python no esta en PATH." -ForegroundColor Red
    Write-Host "Instalalo desde https://www.python.org/downloads/ (marcar 'Add Python to PATH')" -ForegroundColor Yellow
    exit 1
}
Write-Host "OK: Python encontrado en $($python.Source)" -ForegroundColor Green

if (-not (Test-Path $ScriptPath)) {
    Write-Host "ERROR: No se encuentra $ScriptPath" -ForegroundColor Red
    exit 1
}

# Crear carpeta de logs
if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory | Out-Null }

# Borrar tarea previa si existe
$prev = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($prev) {
    Write-Host "Eliminando tarea previa..."
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

# Definir trigger: dia 1 de cada mes, 7:00 AM
$trigger = New-ScheduledTaskTrigger -At "07:00" -Once -RepetitionInterval (New-TimeSpan -Days 1)
# Mejor: usar Monthly trigger via CIM (mas robusto)
$cls = Get-CimClass -ClassName MSFT_TaskMonthlyTrigger -Namespace Root/Microsoft/Windows/TaskScheduler
$trigger = New-CimInstance -CimClass $cls -ClientOnly
$trigger.DaysOfMonth = @(1)
$trigger.StartBoundary = (Get-Date -Hour 7 -Minute 0 -Second 0).ToString("yyyy-MM-ddTHH:mm:ss")
$trigger.MonthsOfYear = 4095   # Todos los meses (bitmask 12 bits)
$trigger.Enabled = $true

# Comando: python sync_anviz.py --periodo mes-anterior, con redireccion a log
$logFile = "$LogDir\sync_$(Get-Date -Format 'yyyyMM')_log.txt"
$argString = "`"$ScriptPath`" --periodo mes-anterior"
$action = New-ScheduledTaskAction -Execute "python" -Argument $argString -WorkingDirectory $WorkingDir

# Settings
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopIfGoingOnBatteries -AllowStartIfOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 2)

# Registrar (corre con usuario actual, no necesita guardar password)
Register-ScheduledTask -TaskName $TaskName `
    -Trigger $trigger `
    -Action $action `
    -Settings $settings `
    -Description "Sincroniza fichadas Anviz CrossChex Cloud al RRHH (dia 1 de cada mes 7AM)" `
    -RunLevel Highest

Write-Host ""
Write-Host "OK: Tarea programada '$TaskName' creada." -ForegroundColor Green
Write-Host "    Frecuencia: dia 1 de cada mes a las 7:00" -ForegroundColor Cyan
Write-Host "    Logs en: $LogDir" -ForegroundColor Cyan
Write-Host ""
Write-Host "Para correr a mano YA:" -ForegroundColor Yellow
Write-Host "    Start-ScheduledTask -TaskName '$TaskName'" -ForegroundColor White
Write-Host "    Get-ScheduledTaskInfo -TaskName '$TaskName'" -ForegroundColor White
