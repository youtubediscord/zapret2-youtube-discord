@echo off
chcp 65001 >nul 2>&1
setlocal EnableDelayedExpansion

:: ===== ВСЕ ПУТИ ОТНОСИТЕЛЬНО РАСПОЛОЖЕНИЯ BAT-ФАЙЛА =====
set "BASE_DIR=%~dp0"
if "%BASE_DIR:~-1%"=="\" set "BASE_DIR=%BASE_DIR:~0,-1%"

set "PRESETS_DIR=%BASE_DIR%\presets"
set "WINWS2_EXE=%BASE_DIR%\exe\winws2.exe"
set "ACTIVE_PRESET=%BASE_DIR%\preset-active.txt"
set "STATE_FILE=%BASE_DIR%\current_preset.txt"
set "RUN_BAT=%BASE_DIR%\utils\zapret2-run.bat"
set "TASK_NAME=Zapret2"
set "VERSION=1.2.0"

:: Внешние команды
if "%~1"=="stop" (
    call :do_stop_all
    exit /b
)

:: Проверка прав администратора
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [!] Требуются права администратора. Перезапуск...
    powershell -NoProfile -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

:: Проверка что exe существует
if not exist "%WINWS2_EXE%" (
    call :PrintRed "[X] winws2.exe не найден: %WINWS2_EXE%"
    pause
    exit /b 1
)

title Zapret2 Console v%VERSION%

:: ========== ГЛАВНОЕ МЕНЮ ==========
:menu
cls
call :load_current_preset
call :get_task_status
call :get_process_status

echo.
echo   ZAPRET2 CONSOLE v%VERSION%
echo   ════════════════════════════════════════════
echo.
echo   Текущий пресет:  !CURRENT_PRESET_NAME!
echo   Автозапуск:      !TASK_STATUS_TEXT!
echo   Процесс winws2:  !PROCESS_STATUS_TEXT!
echo.
echo   ── ПРЕСЕТЫ ──────────────────────────────────
echo      1. Выбрать пресет
echo.
echo   ── АВТОЗАПУСК ───────────────────────────────
echo      2. Установить автозапуск
echo      3. Удалить автозапуск
echo      4. Статус
echo.
echo   ── ЗАПУСК ───────────────────────────────────
echo      5. Запустить winws2
echo      6. Остановить winws2
echo      7. Перезапустить winws2
echo.
echo   ── ИНСТРУМЕНТЫ ──────────────────────────────
echo      8. Диагностика
echo      9. Тестирование пресетов
echo     10. Очистить кэш Discord
echo     11. Включить TCP timestamps
echo.
echo   ════════════════════════════════════════════
echo   ── ССЫЛКИ ──────────────────────────────────
echo     12. TG: VPN Discord YouTube
echo     13. TG: Bypass Block
echo     14. TG Bot: @zapretvpns_bot
echo   ════════════════════════════════════════════
echo      0. Выход
echo.

set "menu_choice="
set /p "menu_choice=   Выберите (0-14): "

if "%menu_choice%"=="1" goto preset_select
if "%menu_choice%"=="2" goto task_install
if "%menu_choice%"=="3" goto task_remove
if "%menu_choice%"=="4" goto task_status
if "%menu_choice%"=="5" goto direct_start
if "%menu_choice%"=="6" goto direct_stop
if "%menu_choice%"=="7" goto direct_restart
if "%menu_choice%"=="8" goto diagnostics
if "%menu_choice%"=="9" goto run_tests
if "%menu_choice%"=="10" goto discord_cache
if "%menu_choice%"=="11" goto tcp_timestamps
if "%menu_choice%"=="12" (start "" "tg://resolve?domain=vpndiscordyooutube" & goto menu)
if "%menu_choice%"=="13" (start "" "tg://resolve?domain=bypassblock" & goto menu)
if "%menu_choice%"=="14" (start "" "tg://resolve?domain=zapretvpns_bot" & goto menu)
if "%menu_choice%"=="0" exit /b
goto menu


:: ========== ВЫБОР ПРЕСЕТА ==========
:preset_select
cls
echo.
echo   ВЫБОР ПРЕСЕТА
echo   ════════════════════════════════════════════
echo.

set "count=0"
for %%F in ("%PRESETS_DIR%\*.txt") do (
    set "fname=%%~nF"
    if not "!fname:~0,1!"=="_" (
        set /a count+=1
        set "preset[!count!]=%%~nF"
        set "preset_path[!count!]=%%~fF"

        set "marker=  "
        if defined CURRENT_PRESET_NAME (
            if "!fname!"=="!CURRENT_PRESET_NAME!" set "marker=► "
        )

        if !count! lss 10 (
            echo   !marker! !count!. %%~nF
        ) else (
            echo   !marker!!count!. %%~nF
        )
    )
)

if "!count!"=="0" (
    call :PrintRed "  Пресеты не найдены в %PRESETS_DIR%"
    pause
    goto menu
)

echo.
echo   ────────────────────────────────────────────
echo      0. Назад
echo.
set "choice="
set /p "choice=   Выберите пресет (1-%count%): "

if "%choice%"=="0" goto menu
if "%choice%"=="" goto menu

set "valid=0"
for /l %%i in (1,1,%count%) do (
    if "!choice!"=="%%i" set "valid=1"
)

if "!valid!"=="0" (
    call :PrintRed "  Неверный выбор"
    timeout /t 2 /nobreak >nul
    goto preset_select
)

set "SELECTED_NAME=!preset[%choice%]!"
set "SELECTED_PATH=!preset_path[%choice%]!"

copy /Y "!SELECTED_PATH!" "%ACTIVE_PRESET%" >nul
if %errorlevel% neq 0 (
    call :PrintRed "  Ошибка копирования пресета!"
    pause
    goto menu
)
echo !SELECTED_NAME!>"%STATE_FILE%"

echo.
call :PrintGreen "  Пресет '!SELECTED_NAME!' выбран"

:: Спросить о перезапуске если winws2 запущен
call :get_process_status
if "!PROCESS_RUNNING!"=="1" (
    echo.
    set "restart_choice="
    set /p "restart_choice=   Перезапустить winws2 с новым пресетом? (Y/N, по умолчанию Y): "
    if "!restart_choice!"=="" set "restart_choice=Y"
    if /i "!restart_choice!"=="Y" (
        call :do_stop_process
        call :do_start_process
    )
)

pause
goto menu


:: ========== УСТАНОВКА АВТОЗАПУСКА (Task Scheduler) ==========
:task_install
cls
echo.
echo   УСТАНОВКА АВТОЗАПУСКА
echo   ════════════════════════════════════════════
echo.

if not exist "%ACTIVE_PRESET%" (
    call :PrintRed "  Сначала выберите пресет (пункт 1)!"
    pause
    goto menu
)

call :load_current_preset
echo   Пресет: !CURRENT_PRESET_NAME!
echo.

:: Удалить старую задачу если есть
schtasks /Query /TN "%TASK_NAME%" >nul 2>&1
if !errorlevel!==0 (
    call :PrintYellow "  Удаляю старую задачу..."
    schtasks /Delete /TN "%TASK_NAME%" /F >nul 2>&1
)

:: Включить TCP timestamps
call :do_tcp_enable

:: Создать задачу: при входе пользователя, с наивысшими правами
echo   Создаю задачу автозапуска...
schtasks /Create /TN "%TASK_NAME%" /TR "\"%RUN_BAT%\"" /SC ONLOGON /RL HIGHEST /F >nul 2>&1
if !errorlevel! neq 0 (
    call :PrintRed "  Ошибка создания задачи!"
    call :PrintYellow "  Пробую альтернативный метод..."
    :: Альтернатива: через XML для большего контроля
    call :create_task_xml
    schtasks /Create /TN "%TASK_NAME%" /XML "%BASE_DIR%\zapret2-task.xml" /F >nul 2>&1
    if !errorlevel! neq 0 (
        call :PrintRed "  Не удалось создать задачу!"
        pause
        goto menu
    )
)

echo.
call :get_task_status
if "!TASK_EXISTS!"=="1" (
    call :PrintGreen "  Автозапуск '%TASK_NAME%' установлен"
    call :PrintGreen "  Запуск при входе пользователя с правами администратора"
    call :PrintGreen "  Пресет: !CURRENT_PRESET_NAME!"
) else (
    call :PrintRed "  Не удалось создать задачу"
)

:: Запустить сейчас если не запущен
call :get_process_status
if "!PROCESS_RUNNING!"=="0" (
    echo.
    set "start_now="
    set /p "start_now=   Запустить winws2 сейчас? (Y/N, по умолчанию Y): "
    if "!start_now!"=="" set "start_now=Y"
    if /i "!start_now!"=="Y" (
        call :do_start_process
    )
)

pause
goto menu


:: ========== УДАЛЕНИЕ АВТОЗАПУСКА ==========
:task_remove
cls
echo.
echo   УДАЛЕНИЕ АВТОЗАПУСКА
echo   ════════════════════════════════════════════
echo.

:: Удалить задачу
schtasks /Query /TN "%TASK_NAME%" >nul 2>&1
if !errorlevel!==0 (
    schtasks /Delete /TN "%TASK_NAME%" /F >nul 2>&1
    call :PrintGreen "  Задача '%TASK_NAME%' удалена"
) else (
    echo   Задача '%TASK_NAME%' не найдена
)

:: Остановить процесс
call :get_process_status
if "!PROCESS_RUNNING!"=="1" (
    echo   Останавливаю winws2.exe...
    taskkill /F /IM winws2.exe >nul 2>&1
    call :PrintGreen "  winws2.exe остановлен"
)

:: Очистить WinDivert
call :cleanup_windivert

:: Удалить XML если есть
if exist "%BASE_DIR%\zapret2-task.xml" del /f /q "%BASE_DIR%\zapret2-task.xml" >nul 2>&1

echo.
pause
goto menu


:: ========== СТАТУС ==========
:task_status
cls
echo.
echo   СТАТУС
echo   ════════════════════════════════════════════
echo.

:: Задача
call :get_task_status
if "!TASK_EXISTS!"=="1" (
    call :PrintGreen "  Автозапуск '%TASK_NAME%' — установлен"
    :: Показать детали
    schtasks /Query /TN "%TASK_NAME%" /V /FO LIST 2>nul | findstr /I "Status Last.Run Next.Run" 2>nul
) else (
    call :PrintRed "  Автозапуск '%TASK_NAME%' — не установлен"
)
echo.

:: Текущий пресет
call :load_current_preset
echo   Текущий пресет: !CURRENT_PRESET_NAME!
echo.

:: WinDivert
if not exist "%BASE_DIR%\exe\*.sys" (
    call :PrintRed "  WinDivert .sys драйвер НЕ найден в exe\"
) else (
    call :PrintGreen "  WinDivert .sys драйвер найден"
)
echo.

:: Процесс
tasklist /FI "IMAGENAME eq winws2.exe" 2>nul | find /I "winws2.exe" >nul
if !errorlevel!==0 (
    call :PrintGreen "  Процесс winws2.exe ЗАПУЩЕН"
    for /f "tokens=2" %%P in ('tasklist /FI "IMAGENAME eq winws2.exe" /NH 2^>nul ^| find /I "winws2.exe"') do (
        echo   PID: %%P
    )
) else (
    call :PrintRed "  Процесс winws2.exe НЕ запущен"
)

echo.
pause
goto menu


:: ========== ПРЯМОЙ ЗАПУСК ==========
:direct_start
cls
echo.
if not exist "%ACTIVE_PRESET%" (
    call :PrintRed "  Сначала выберите пресет (пункт 1)!"
    pause
    goto menu
)

call :get_process_status
if "!PROCESS_RUNNING!"=="1" (
    call :PrintYellow "  winws2 уже запущен"
    pause
    goto menu
)

call :do_tcp_enable
call :do_start_process

echo.
pause
goto menu

:direct_stop
cls
echo.
call :do_stop_process
echo.
pause
goto menu

:direct_restart
cls
echo.
if not exist "%ACTIVE_PRESET%" (
    call :PrintRed "  Сначала выберите пресет (пункт 1)!"
    pause
    goto menu
)
call :do_stop_process
timeout /t 1 /nobreak >nul
call :do_start_process
echo.
pause
goto menu


:: ========== ДИАГНОСТИКА ==========
:diagnostics
cls
echo.
echo   ДИАГНОСТИКА
echo   ════════════════════════════════════════════
echo.

:: 1. Base Filtering Engine
sc query BFE | findstr /I "RUNNING" >nul
if !errorlevel!==0 (
    call :PrintGreen "  Base Filtering Engine — OK"
) else (
    call :PrintRed "  [X] Base Filtering Engine не запущен!"
)

:: 2. TCP timestamps
netsh interface tcp show global | findstr /i "timestamps" | findstr /i "enabled" >nul
if !errorlevel!==0 (
    call :PrintGreen "  TCP timestamps — включены"
) else (
    call :PrintYellow "  [?] TCP timestamps отключены (пункт 11)"
)

:: 3. Прокси
set "proxyEnabled=0"
for /f "tokens=2*" %%A in ('reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyEnable 2^>nul ^| findstr /i "ProxyEnable"') do (
    if "%%B"=="0x1" set "proxyEnabled=1"
)
if !proxyEnabled!==1 (
    for /f "tokens=2*" %%A in ('reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyServer 2^>nul ^| findstr /i "ProxyServer"') do (
        call :PrintYellow "  [?] Системный прокси: %%B"
    )
) else (
    call :PrintGreen "  Системный прокси — отключён"
)

:: 4. Adguard
tasklist /FI "IMAGENAME eq AdguardSvc.exe" 2>nul | find /I "AdguardSvc.exe" >nul
if !errorlevel!==0 (
    call :PrintRed "  [X] Adguard — может мешать Discord"
) else (
    call :PrintGreen "  Adguard — не обнаружен"
)

:: 5. Killer Network
sc query 2>nul | findstr /I "Killer" >nul
if !errorlevel!==0 (
    call :PrintRed "  [X] Killer Network — конфликтует с zapret"
) else (
    call :PrintGreen "  Killer Network — не обнаружен"
)

:: 6. Intel Connectivity
sc query 2>nul | findstr /I "Intel" | findstr /I "Connectivity" >nul
if !errorlevel!==0 (
    call :PrintRed "  [X] Intel Connectivity — конфликтует с zapret"
) else (
    call :PrintGreen "  Intel Connectivity — не обнаружен"
)

:: 7. Check Point
set "cpFound=0"
sc query 2>nul | findstr /I "TracSrvWrapper" >nul && set "cpFound=1"
sc query 2>nul | findstr /I "EPWD" >nul && set "cpFound=1"
if !cpFound!==1 (
    call :PrintRed "  [X] Check Point — конфликтует с zapret"
) else (
    call :PrintGreen "  Check Point — не обнаружен"
)

:: 8. SmartByte
sc query 2>nul | findstr /I "SmartByte" >nul
if !errorlevel!==0 (
    call :PrintRed "  [X] SmartByte — конфликтует с zapret"
) else (
    call :PrintGreen "  SmartByte — не обнаружен"
)

:: 9. VPN
sc query 2>nul | findstr /I "VPN" >nul
if !errorlevel!==0 (
    call :PrintYellow "  [?] VPN-сервисы обнаружены — могут конфликтовать"
) else (
    call :PrintGreen "  VPN — не обнаружены"
)

:: 10. WinDivert
if not exist "%BASE_DIR%\exe\*.sys" (
    call :PrintRed "  [X] WinDivert .sys не найден"
) else (
    call :PrintGreen "  WinDivert .sys — найден"
)

:: 11. Конфликтующие обходы
set "conflicts="
for %%s in (GoodbyeDPI zapret discordfix_zapret winws1) do (
    sc query "%%s" >nul 2>&1
    if !errorlevel!==0 set "conflicts=!conflicts! %%s"
)
if defined conflicts (
    call :PrintRed "  [X] Конфликтующие сервисы:!conflicts!"
    echo.
    set "fix_choice="
    set /p "fix_choice=   Удалить конфликтующие сервисы? (Y/N): "
    if /i "!fix_choice!"=="Y" (
        for %%s in (!conflicts!) do (
            net stop "%%s" >nul 2>&1
            sc delete "%%s" >nul 2>&1
        )
        call :cleanup_windivert
        call :PrintGreen "  Удалены"
    )
) else (
    call :PrintGreen "  Конфликтующие сервисы — нет"
)

:: 12. WinDivert без winws
tasklist /FI "IMAGENAME eq winws2.exe" 2>nul | find /I "winws2.exe" >nul
set "winws_run=!errorlevel!"
sc query "WinDivert" 2>nul | findstr /I "RUNNING STOP_PENDING" >nul
set "wd_run=!errorlevel!"
if !winws_run! neq 0 if !wd_run!==0 (
    call :PrintYellow "  [?] WinDivert без winws2 — очищаю..."
    call :cleanup_windivert
)

:: 13. DNS
set "dohfound=0"
for /f "delims=" %%a in ('powershell -NoProfile -Command "try { (Get-ChildItem -Recurse -Path 'HKLM:System\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters\' -ErrorAction Stop | Get-ItemProperty | Where-Object { $_.DohFlags -gt 0 } | Measure-Object).Count } catch { 0 }" 2^>nul') do (
    if %%a gtr 0 set "dohfound=1"
)
if !dohfound!==1 (
    call :PrintGreen "  Secure DNS (DoH) — настроен"
) else (
    call :PrintYellow "  [?] Secure DNS не настроен — рекомендуется"
)

:: 14. Hosts
set "hostsFile=%SystemRoot%\System32\drivers\etc\hosts"
if exist "%hostsFile%" (
    set "yt_hosts=0"
    findstr /I "youtube.com" "%hostsFile%" >nul 2>&1 && set "yt_hosts=1"
    findstr /I "youtu.be" "%hostsFile%" >nul 2>&1 && set "yt_hosts=1"
    if !yt_hosts!==1 (
        call :PrintYellow "  [?] Hosts: есть записи YouTube"
    ) else (
        call :PrintGreen "  Hosts — чист"
    )
)

:: 15. Пресет
if exist "%ACTIVE_PRESET%" (
    call :PrintGreen "  Активный пресет — выбран"
) else (
    call :PrintYellow "  [?] Активный пресет не выбран"
)

echo.
echo   ════════════════════════════════════════════
pause
goto menu


:: ========== ОЧИСТКА КЭША DISCORD ==========
:discord_cache
cls
echo.
echo   ОЧИСТКА КЭША DISCORD
echo   ════════════════════════════════════════════
echo.

tasklist /FI "IMAGENAME eq Discord.exe" 2>nul | findstr /I "Discord.exe" >nul
if !errorlevel!==0 (
    echo   Закрываю Discord...
    taskkill /IM Discord.exe /F >nul 2>&1
    timeout /t 2 /nobreak >nul
    call :PrintGreen "  Discord закрыт"
)

set "discordDir=%appdata%\discord"
if not exist "%discordDir%" (
    call :PrintYellow "  Папка Discord не найдена"
    pause
    goto menu
)

set "cleared=0"
for %%d in ("Cache" "Code Cache" "GPUCache") do (
    set "dirPath=%discordDir%\%%~d"
    if exist "!dirPath!" (
        rd /s /q "!dirPath!" >nul 2>&1
        if !errorlevel!==0 (
            call :PrintGreen "  Удалено: %%~d"
            set "cleared=1"
        ) else (
            call :PrintRed "  Ошибка: %%~d"
        )
    )
)

if "!cleared!"=="0" (echo   Кэш уже чист) else (call :PrintGreen "  Кэш Discord очищен")

echo.
pause
goto menu


:: ========== ТЕСТИРОВАНИЕ ПРЕСЕТОВ ==========
:run_tests
cls
echo.
echo   ТЕСТИРОВАНИЕ ПРЕСЕТОВ
echo   ════════════════════════════════════════════
echo.

call :get_process_status
if "!PROCESS_RUNNING!"=="1" (
    call :PrintYellow "  winws2 запущен — будет остановлен на время тестов"
)

echo   Запускаю тесты в PowerShell...
echo.
start "" powershell -NoProfile -ExecutionPolicy Bypass -File "%BASE_DIR%\utils\test-presets.ps1"
pause
goto menu


:: ========== TCP TIMESTAMPS ==========
:tcp_timestamps
cls
echo.
call :do_tcp_enable
echo.
pause
goto menu


:: ══════════════════════════════════════════════
:: ═════════  ВНУТРЕННИЕ ФУНКЦИИ  ═══════════════
:: ══════════════════════════════════════════════

:load_current_preset
if exist "%STATE_FILE%" (
    set /p CURRENT_PRESET_NAME=<"%STATE_FILE%"
) else (
    set "CURRENT_PRESET_NAME=не выбран"
)
exit /b

:get_task_status
set "TASK_EXISTS=0"
set "TASK_STATUS_TEXT=не установлен"
schtasks /Query /TN "%TASK_NAME%" >nul 2>&1
if !errorlevel!==0 (
    set "TASK_EXISTS=1"
    set "TASK_STATUS_TEXT=установлен (при входе)"
)
exit /b

:get_process_status
set "PROCESS_RUNNING=0"
set "PROCESS_STATUS_TEXT=ОСТАНОВЛЕН"
tasklist /FI "IMAGENAME eq winws2.exe" 2>nul | find /I "winws2.exe" >nul
if !errorlevel!==0 (
    set "PROCESS_RUNNING=1"
    set "PROCESS_STATUS_TEXT=ЗАПУЩЕН"
)
exit /b

:do_start_process
echo   Запускаю winws2...
start "" /D "%BASE_DIR%" /MIN "%WINWS2_EXE%" @"%ACTIVE_PRESET%"
timeout /t 2 /nobreak >nul
tasklist /FI "IMAGENAME eq winws2.exe" 2>nul | find /I "winws2.exe" >nul
if !errorlevel! neq 0 (
    call :PrintRed "  [X] winws2 не удалось запустить!"
    call :PrintYellow "  Запуск напрямую для диагностики..."
    echo.
    cd /d "%BASE_DIR%"
    "%WINWS2_EXE%" @"%ACTIVE_PRESET%"
) else (
    call :PrintGreen "  winws2 запущен"
)
exit /b

:do_stop_process
tasklist /FI "IMAGENAME eq winws2.exe" 2>nul | find /I "winws2.exe" >nul
if !errorlevel!==0 (
    echo   Останавливаю winws2...
    taskkill /F /IM winws2.exe >nul 2>&1
    timeout /t 2 /nobreak >nul
    call :PrintGreen "  winws2 остановлен"
) else (
    echo   winws2 не запущен
)
exit /b

:do_stop_all
call :do_stop_process
exit /b

:do_tcp_enable
netsh interface tcp show global | findstr /i "timestamps" | findstr /i "enabled" >nul
if !errorlevel!==0 (
    call :PrintGreen "  TCP timestamps уже включены"
) else (
    echo   Включаю TCP timestamps...
    netsh interface tcp set global timestamps=enabled >nul 2>&1
    if !errorlevel!==0 (
        call :PrintGreen "  TCP timestamps включены"
    ) else (
        call :PrintRed "  [X] Не удалось включить TCP timestamps"
    )
)
exit /b

:cleanup_windivert
sc query "WinDivert" >nul 2>&1
if !errorlevel!==0 (
    net stop "WinDivert" >nul 2>&1
    sc delete "WinDivert" >nul 2>&1
)
net stop "WinDivert14" >nul 2>&1
sc delete "WinDivert14" >nul 2>&1
exit /b

:: Создать XML для задачи (альтернативный метод)
:create_task_xml
(
echo ^<?xml version="1.0" encoding="UTF-16"?^>
echo ^<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task"^>
echo   ^<Triggers^>
echo     ^<LogonTrigger^>
echo       ^<Enabled^>true^</Enabled^>
echo     ^</LogonTrigger^>
echo   ^</Triggers^>
echo   ^<Principals^>
echo     ^<Principal^>
echo       ^<RunLevel^>HighestAvailable^</RunLevel^>
echo     ^</Principal^>
echo   ^</Principals^>
echo   ^<Settings^>
echo     ^<MultipleInstancesPolicy^>IgnoreNew^</MultipleInstancesPolicy^>
echo     ^<DisallowStartIfOnBatteries^>false^</DisallowStartIfOnBatteries^>
echo     ^<StopIfGoingOnBatteries^>false^</StopIfGoingOnBatteries^>
echo     ^<ExecutionTimeLimit^>PT0S^</ExecutionTimeLimit^>
echo     ^<AllowStartOnDemand^>true^</AllowStartOnDemand^>
echo     ^<AllowHardTerminate^>true^</AllowHardTerminate^>
echo   ^</Settings^>
echo   ^<Actions^>
echo     ^<Exec^>
echo       ^<Command^>"%RUN_BAT%"^</Command^>
echo       ^<WorkingDirectory^>%BASE_DIR%^</WorkingDirectory^>
echo     ^</Exec^>
echo   ^</Actions^>
echo ^</Task^>
) > "%BASE_DIR%\zapret2-task.xml"
exit /b

:PrintGreen
powershell -NoProfile -Command "Write-Host '%~1' -ForegroundColor Green"
exit /b

:PrintRed
powershell -NoProfile -Command "Write-Host '%~1' -ForegroundColor Red"
exit /b

:PrintYellow
powershell -NoProfile -Command "Write-Host '%~1' -ForegroundColor Yellow"
exit /b
