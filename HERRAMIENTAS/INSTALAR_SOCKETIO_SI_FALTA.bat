@echo off
setlocal
cd /d "%~dp0"
title Instalar Socket.IO - Mesero 06
color 0B
echo.
echo Esta herramienta se usa SOLO si el panel dice que falta Socket.IO.
echo No ejecuta el robot ni mueve los motores.
echo.
where python >nul 2>&1
if errorlevel 1 (
  echo ERROR: Python no esta instalado o no aparece en PATH.
  echo Instala Python para Windows y vuelve a comprobar python --version.
  pause
  exit /b 1
)
python -m pip install "python-socketio[client]"
if errorlevel 1 (
  echo ERROR al instalar Socket.IO. Copia el mensaje para diagnosticarlo.
  pause
  exit /b 1
)
python -c "import socketio; print('Socket.IO listo')"
echo.
echo Ya puedes volver a CENTRO_LOCAL_MESERO06 y abrir ABRIR_CONTROL_MESERO06.bat
pause
