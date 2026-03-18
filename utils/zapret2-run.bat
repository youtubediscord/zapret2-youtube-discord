@echo off
:: Запуск winws2 с активным пресетом
:: Этот файл вызывается автозапуском (Task Scheduler) и service.bat
cd /d "%~dp0.."
exe\winws2.exe @preset-active.txt
