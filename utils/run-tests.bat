@echo off
chcp 65001 >nul 2>&1
:: Запуск тестирования пресетов с обходом политики выполнения PowerShell
:: Можно запускать двойным кликом — права администратора будут запрошены автоматически

net.exe session >nul 2>&1
if %errorlevel% neq 0 (
    echo [!] Требуются права администратора. Перезапуск...
    powershell.exe -NoProfile -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0test-presets.ps1"
