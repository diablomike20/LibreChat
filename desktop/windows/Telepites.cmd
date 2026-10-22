@echo off
chcp 65001 >nul
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install.ps1"
if errorlevel 1 (
  echo.
  echo HIBA tortent. Masold ki a fent megjelent hibat az elemzeshez.
  pause
  exit /b 1
)
echo.
echo A telepites veget ert.
pause
