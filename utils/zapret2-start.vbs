'' zapret2-start.vbs -- hidden launcher for winws2 (Task Scheduler)
'' Launches winws2.exe without visible window in taskbar

Set WshShell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

'' System paths (independent of PATH variable)
sSys32 = WshShell.ExpandEnvironmentStrings("%SystemRoot%") & "\System32"

'' Project root directory (parent of utils\)
sUtilsDir = fso.GetParentFolderName(WScript.ScriptFullName)
sRootDir = fso.GetParentFolderName(sUtilsDir)

WshShell.CurrentDirectory = sRootDir

'' Clean WinDivert before launch (prevents certificate errors)
Dim services : services = Array("WinDivert", "WinDivert14", "Monkey", "Monkey14")
For Each svc In services
    WshShell.Run sSys32 & "\cmd.exe /c " & sSys32 & "\sc.exe query """ & svc & """ >nul 2>&1 && (" & sSys32 & "\net.exe stop """ & svc & """ >nul 2>&1 & " & sSys32 & "\sc.exe delete """ & svc & """ >nul 2>&1)", 0, True
Next

'' Enable TCP timestamps
WshShell.Run sSys32 & "\cmd.exe /c " & sSys32 & "\netsh.exe interface tcp set global timestamps=enabled >nul 2>&1", 0, True

'' Short pause after cleanup
WScript.Sleep 500

'' Launch winws2 hidden via cmd.exe (inherits elevation from Task Scheduler)
WshShell.Run sSys32 & "\cmd.exe /c cd /d """ & sRootDir & """ && ""exe\winws2.exe"" @""utils\preset-active.txt""", 0, False
