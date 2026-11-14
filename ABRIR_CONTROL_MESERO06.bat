@echo off
setlocal
cd /d "%~dp0"
title CONTROL MESERO 06
color 0A
echo.
echo  ======================================
echo         CONTROL MESERO 06
 echo  ======================================
echo.
echo  Comprueba que Tailscale este conectado.
echo  El robot debe estar despejado y con STOP fisico disponible.
echo.
where python >nul 2>&1
if errorlevel 1 (
  echo ERROR: No se encontro Python. Comprueba python --version.
  pause
  exit /b 1
)
python -c "import socketio" >nul 2>&1
if errorlevel 1 (
  echo ERROR: Falta la dependencia python-socketio.
  echo Ejecuta en CMD: python -m pip install "python-socketio[client]"
  pause
  exit /b 1
)
rem No sobrescribir otro servidor ni abrir el navegador de una version antigua.
python -c "import socket; s=socket.socket(); s.bind(('127.0.0.1',8765)); s.close()" >nul 2>&1
if errorlevel 1 (
  echo.
  echo ERROR: El puerto 8765 ya esta ocupado.
  echo Cierra el CMD anterior del Mesero 06 con Ctrl+C.
  echo No abras dos paneles a la vez. No se inicio esta version.
  pause
  exit /b 1
)
set "MESERO06_LIMITE_RPM=30"
echo.
echo  Escribe SI cuando el programa lo solicite.
echo  El movimiento no se activa hasta tomar control REAL en el panel.
echo  Velocidad inicial 20 RPM; puedes seleccionar hasta 30 dentro del panel.
echo.
python mesero06_local_v13.py --habilitar-movimiento
if errorlevel 1 (
  echo.
  echo El programa termino con un error o se cancelo la autorizacion.
)
pause
