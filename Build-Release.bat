@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "PS_SCRIPT=%SCRIPT_DIR%scripts\build-release.ps1"

if not exist "%PS_SCRIPT%" (
  echo ERROR: Could not find "%PS_SCRIPT%"
  pause
  exit /b 1
)

set "VERSION=0.1.0"
if not "%~1"=="" set "VERSION=%~1"

echo Building release package (version %VERSION%)...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" -Version "%VERSION%"
set "EXIT_CODE=%ERRORLEVEL%"
echo.

if "%EXIT_CODE%"=="0" (
  echo Release build completed successfully.
) else (
  echo Release build failed with exit code %EXIT_CODE%.
)

echo.
pause
exit /b %EXIT_CODE%
