@echo off
cd /d "%~dp0"
set LOG=install_log.txt
echo %date% %time% Starting... > %LOG%

where powershell >> %LOG% 2>&1
if errorlevel 1 (echo PowerShell not found >> %LOG% & type %LOG% & pause & exit /b 1)

echo Checking environment... > %LOG%
powershell -ExecutionPolicy Bypass -File "setup.ps1" -DryRun >> %LOG% 2>&1
if errorlevel 1 (type %LOG% & pause & exit /b 1)

echo Environment OK. Press Enter to install...
pause >nul

powershell -ExecutionPolicy Bypass -File "setup.ps1"
pause
