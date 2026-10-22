@echo off
chcp 65001 >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Diagnosztika.ps1"
if errorlevel 1 (
  echo Hiba a diagnosztika soran.
)
pause
