@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "PS_SCRIPT=%SCRIPT_DIR%Stress-PC.ps1"

if not exist "%PS_SCRIPT%" (
  echo ERROR: Could not find "%PS_SCRIPT%"
  pause
  exit /b 1
)

echo Running stress test (default profile)...
echo This may make the PC slow/unresponsive temporarily.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" -DurationSeconds 180 -CpuWorkers 4 -MemoryGB 4 -EnableDiskIO
set "EXIT_CODE=%ERRORLEVEL%"
echo.

if "%EXIT_CODE%"=="0" (
  echo Stress test finished.
) else (
  echo Stress test ended with exit code %EXIT_CODE%.
)

echo.
pause
exit /b %EXIT_CODE%
