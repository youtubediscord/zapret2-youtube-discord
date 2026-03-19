'' zapret2-start.vbs -- skrytyj zapusk winws2 dlja avtozapuska (Task Scheduler)
'' Zapuskaet winws2.exe bez vidimogo okna v paneli zadach

Set WshShell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

'' Opredeljaem kornevuju direktoriju proekta (roditel utils\)
sUtilsDir = fso.GetParentFolderName(WScript.ScriptFullName)
sRootDir = fso.GetParentFolderName(sUtilsDir)

WshShell.CurrentDirectory = sRootDir

'' Ochistka WinDivert pered zapuskom (predotvrashchaet oshibki sertifikatov)
Dim services : services = Array("WinDivert", "WinDivert14", "Monkey", "Monkey14")
For Each svc In services
    WshShell.Run "cmd.exe /c sc.exe query """ & svc & """ >nul 2>&1 && (net.exe stop """ & svc & """ >nul 2>&1 & sc.exe delete """ & svc & """ >nul 2>&1)", 0, True
Next

'' Vkljuchaem TCP timestamps
WshShell.Run "cmd.exe /c netsh.exe interface tcp set global timestamps=enabled >nul 2>&1", 0, True

'' Nebol'shaja pauza posle ochistki
WScript.Sleep 500

'' Zapusk winws2 polnost'ju skryto (0 = Hidden, False = ne zhdat' zavershenija)
WshShell.Run """" & sRootDir & "\exe\winws2.exe"" @""" & sRootDir & "\utils\preset-active.txt""", 0, False
