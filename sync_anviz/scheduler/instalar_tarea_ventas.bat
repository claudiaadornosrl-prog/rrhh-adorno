@echo off
echo Instalando tarea programada "RRHH_SyncVentas"...
echo.

schtasks /create ^
  /tn "RRHH_SyncVentas" ^
  /tr "python C:\CRM_Adorno\rrhh-adorno\sync_anviz\sync_ventas.py --aplicar" ^
  /sc hourly ^
  /mo 4 ^
  /ru "%USERDOMAIN%\%USERNAME%" ^
  /it ^
  /f

if %ERRORLEVEL% == 0 (
    echo.
    echo [OK] Tarea creada exitosamente.
    echo      Nombre:     RRHH_SyncVentas
    echo      Comando:    python ...\sync_anviz\sync_ventas.py --aplicar
    echo      Frecuencia: cada 4 horas
    echo      Usuario:    %USERDOMAIN%\%USERNAME%
    echo.
    echo Corre solo mientras la PC este encendida. Si G1 de la planilla
    echo todavia no esta en OK, el script saltea ese local y no escribe nada.
) else (
    echo.
    echo [ERROR] No se pudo crear la tarea. Ejecuta este .bat como Administrador.
)
echo.
pause
