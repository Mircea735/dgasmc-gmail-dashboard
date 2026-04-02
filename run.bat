@echo off
cd /d "%~dp0"
echo.
echo  DGASMC Email Dashboard
echo  ─────────────────────────────
echo  http://localhost:8080
echo.
timeout /t 1 /nobreak >nul
start "" "http://localhost:8080"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0server.ps1"
