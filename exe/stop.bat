@echo off

%SystemRoot%\System32\net.exe session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator privileges...
    echo Set UAC = CreateObject^("Shell.Application"^) > "%temp%\getadmin.vbs"
    echo UAC.ShellExecute "%~f0", "", "", "runas", 1 >> "%temp%\getadmin.vbs"
    %SystemRoot%\System32\cscript.exe //nologo "%temp%\getadmin.vbs"
    %SystemRoot%\System32\cmd.exe /c del "%temp%\getadmin.vbs"
    exit /b
)

%SystemRoot%\System32\taskkill.exe /F /IM winws.exe /T
%SystemRoot%\System32\taskkill.exe /F /IM winws2.exe /T
%SystemRoot%\System32\sc.exe stop Monkey
%SystemRoot%\System32\sc.exe delete Monkey
exit /b