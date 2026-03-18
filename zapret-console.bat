@echo off
chcp 65001 >nul 2>&1
:: Быстрый запуск — выбрать пресет и запустить winws2
:: Для полного управления (сервис, диагностика) используйте service.bat

setlocal EnableDelayedExpansion

set "BASE_DIR=%~dp0"
if "%BASE_DIR:~-1%"=="\" set "BASE_DIR=%BASE_DIR:~0,-1%"

set "PRESETS_DIR=%BASE_DIR%\presets"
set "WINWS2_EXE=%BASE_DIR%\exe\winws2.exe"
set "ACTIVE_PRESET=%BASE_DIR%\utils\preset-active.txt"
set "STATE_FILE=%BASE_DIR%\utils\current_preset.txt"

net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

title Zapret2 Quick Launch

:menu
cls
echo.
echo   ZAPRET2 QUICK LAUNCH
echo   ════════════════════════════════════════ 2>nul

if exist "%STATE_FILE%" (
    set /p CURRENT_PRESET=<"%STATE_FILE%"
    echo   Текущий: !CURRENT_PRESET! 2>nul
) else (
    set "CURRENT_PRESET="
    echo   Текущий: не выбран 2>nul
)

tasklist /FI "IMAGENAME eq winws2.exe" 2>nul | find /I "winws2.exe" >nul
if %errorlevel% equ 0 (echo   winws2: ЗАПУЩЕН 2>nul) else (echo   winws2: ОСТАНОВЛЕН 2>nul)

echo.

set "count=0"
for %%F in ("%PRESETS_DIR%\*.txt") do (
    set "fname=%%~nF"
    if not "!fname:~0,1!"=="_" (
        set /a count+=1
        set "preset[!count!]=%%~nF"
        set "preset_path[!count!]=%%~fF"
        set "m=  "
        if defined CURRENT_PRESET if "!fname!"=="!CURRENT_PRESET!" set "m=► "
        if !count! lss 10 (echo   !m! !count!. %%~nF 2>nul) else (echo   !m!!count!. %%~nF 2>nul)
    )
)

echo.
echo   [S] Стоп  [R] Рестарт  [M] service.bat  [Q] Выход 2>nul
echo   [T] TG Группа  [B] Bypass Block  [V] VPN Bot 2>nul
echo.
set "c="
set /p "c=  Выбор (1-%count%): " 2>nul

if /i "!c!"=="q" goto :eof
if /i "!c!"=="m" (start "" "%BASE_DIR%\service.bat" & goto :eof)
if /i "!c!"=="s" (taskkill /F /IM winws2.exe >nul 2>&1 & timeout /t 1 /nobreak >nul & goto menu)
if /i "!c!"=="t" (start "" "tg://resolve?domain=vpndiscordyooutube" & goto menu)
if /i "!c!"=="b" (start "" "tg://resolve?domain=bypassblock" & goto menu)
if /i "!c!"=="v" (start "" "tg://resolve?domain=zapretvpns_bot" & goto menu)
if /i "!c!"=="r" (
    taskkill /F /IM winws2.exe >nul 2>&1
    timeout /t 2 /nobreak >nul
    for %%s in (WinDivert WinDivert14 Monkey Monkey14) do (sc query "%%s" >nul 2>&1 && (net stop "%%s" >nul 2>&1 & sc delete "%%s" >nul 2>&1))
    if exist "%ACTIVE_PRESET%" (start "" /D "%BASE_DIR%" /MIN "%WINWS2_EXE%" @"%ACTIVE_PRESET%")
    timeout /t 2 /nobreak >nul
    goto menu
)

set "valid=0"
for /l %%i in (1,1,%count%) do (if "!c!"=="%%i" set "valid=1")
if "!valid!"=="0" goto menu

set "SEL_NAME=!preset[%c%]!"
set "SEL_PATH=!preset_path[%c%]!"

taskkill /F /IM winws2.exe >nul 2>&1
timeout /t 2 /nobreak >nul
sc query "WinDivert" >nul 2>&1 && (net stop "WinDivert" >nul 2>&1 & sc delete "WinDivert" >nul 2>&1)
net stop "WinDivert14" >nul 2>&1 & sc delete "WinDivert14" >nul 2>&1
copy /Y "!SEL_PATH!" "%ACTIVE_PRESET%" >nul
echo !SEL_NAME!>"%STATE_FILE%"
start "" /D "%BASE_DIR%" /MIN "%WINWS2_EXE%" @"%ACTIVE_PRESET%"
timeout /t 2 /nobreak >nul
goto menu
