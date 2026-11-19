@echo off
setlocal EnableExtensions
cd /d "%~dp0"
title PANEL ROBOT MULTIRROBOT - Elegir IP del robot
color 0A

echo.
echo ================================================
echo    PANEL ROBOT MULTIRROBOT - IP DE CADA ROBOT
 echo ================================================
echo.
echo  Este es tu panel local para cualquier robot compatible.
echo  Se solicitara la IP del robot en cada inicio.
echo  Tailscale o la red local deben estar conectados.
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0iniciar_panel_robot.ps1"
set "RESULTADO=%ERRORLEVEL%"
if not "%RESULTADO%"=="0" (
 echo.
 echo [AVISO] El inicio termino con error. Revisa los mensajes anteriores.
 pause
)
endlocal & exit /b %RESULTADO%
