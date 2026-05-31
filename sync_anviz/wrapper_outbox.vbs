' ═══════════════════════════════════════════════════════════════════════
'  wrapper_outbox.vbs
'
'  Wrapper VBScript que ejecuta procesar_email_outbox.py sin ventana
'  visible (la ventana negra de Python).
'
'  Se invoca desde la tarea programada de Windows con:
'    wscript.exe "C:\CRM_Adorno\rrhh-adorno\sync_anviz\wrapper_outbox.vbs"
'
'  El "0" en WshShell.Run = SW_HIDE (ventana oculta).
'  El "False" = no esperar a que termine (la VBS sale enseguida).
' ═══════════════════════════════════════════════════════════════════════

Dim WshShell, sPython, sScript, sCommand
Set WshShell = CreateObject("WScript.Shell")

' Buscar python.exe — primero en instalaciones tipicas, despues PATH
Dim candidatos
candidatos = Array( _
    "C:\Users\Usuario\AppData\Local\Programs\Python\Python313\python.exe", _
    "C:\Users\Usuario\AppData\Local\Programs\Python\Python312\python.exe", _
    "C:\Users\Usuario\AppData\Local\Programs\Python\Python311\python.exe", _
    "C:\Users\Usuario\AppData\Local\Microsoft\WindowsApps\python.exe", _
    "C:\Python313\python.exe", _
    "C:\Python312\python.exe" _
)

Dim fso : Set fso = CreateObject("Scripting.FileSystemObject")
sPython = ""
Dim i
For i = 0 To UBound(candidatos)
    If fso.FileExists(candidatos(i)) Then
        sPython = candidatos(i)
        Exit For
    End If
Next

If sPython = "" Then
    sPython = "python.exe"   ' último fallback: PATH
End If

sScript = "C:\CRM_Adorno\rrhh-adorno\sync_anviz\procesar_email_outbox.py"
sCommand = """" & sPython & """ """ & sScript & """"

' Run con 0 = ventana oculta, True = esperar a que termine
' (esperamos para que el log de la tarea muestre el exit code real)
WshShell.Run sCommand, 0, True
