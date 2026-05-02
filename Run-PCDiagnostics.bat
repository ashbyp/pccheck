@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "PS_SCRIPT=%SCRIPT_DIR%scripts\Collect-PCDiagnostics.ps1"

if not exist "%PS_SCRIPT%" (
  echo ERROR: Could not find "%PS_SCRIPT%"
  pause
  exit /b 1
)

echo Running PC diagnostics...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" -Mode Quick -BurstDurationSeconds 30 -BurstIntervalSeconds 2
set "EXIT_CODE=%ERRORLEVEL%"
echo.

if "%EXIT_CODE%"=="0" (
  echo Diagnostics collection completed successfully.
) else (
  echo Diagnostics collection failed with exit code %EXIT_CODE%.
)

echo.
pause
exit /b %EXIT_CODE%
