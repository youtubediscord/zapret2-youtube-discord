@echo off
:: Запуск winws2 с активным пресетом
:: Этот файл вызывается для ручного запуска и отладки
:: Для автозапуска (Task Scheduler) используется zapret2-start.vbs
cd /d "%~dp0.."

:: Очистка WinDivert перед запуском (предотвращает ошибки сертификатов)
for %%s in (WinDivert WinDivert14 Monkey Monkey14) do (
    sc.exe query "%%s" >nul 2>&1 && (
        net.exe stop "%%s" >nul 2>&1
        sc.exe delete "%%s" >nul 2>&1
    )
)

:: Включаем TCP timestamps
netsh.exe interface tcp set global timestamps=enabled >nul 2>&1

:: Пауза после очистки
timeout.exe /t 1 /nobreak >nul

exe\winws2.exe @utils\preset-active.txt
