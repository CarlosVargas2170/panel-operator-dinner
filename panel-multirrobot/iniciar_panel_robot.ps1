$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
$Host.UI.RawUI.WindowTitle = 'PANEL ROBOT MULTIRROBOT - Elegir IP'

Write-Host ''
Write-Host '======================================================' -ForegroundColor Cyan
Write-Host '   PANEL ROBOT MULTIRROBOT - SELECCION DE IP' -ForegroundColor Cyan
Write-Host '======================================================' -ForegroundColor Cyan
Write-Host 'Este es tu panel local para cualquier robot compatible.'
Write-Host 'No utiliza FastAPI ni Uvicorn. Conserva el panel local original.'
Write-Host ''

function Validar-IPv4Local([string]$valor) {
    if ($valor -notmatch '^[0-9]{1,3}(\.[0-9]{1,3}){3}$') { return $null }
    $addr = $null
    if (-not [System.Net.IPAddress]::TryParse($valor, [ref]$addr)) { return $null }
    if ($addr.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) { return $null }
    $b = $addr.GetAddressBytes()
    $local = ($b[0] -eq 10) -or ($b[0] -eq 172 -and $b[1] -ge 16 -and $b[1] -le 31) -or `
             ($b[0] -eq 192 -and $b[1] -eq 168) -or ($b[0] -eq 100 -and $b[1] -ge 64 -and $b[1] -le 127)
    if (-not $local) { return $null }
    return $addr.ToString()
}

$seleccionada = $null
while ($null -eq $seleccionada) {
    $texto = Read-Host 'IP del robot (ej. 100.99.244.72 o 192.168.1.20)'
    if ([string]::IsNullOrWhiteSpace($texto)) {
        Write-Host '[ERROR] Debes indicar una IP. No hay ninguna IP por defecto.' -ForegroundColor Yellow
        continue
    }
    $seleccionada = Validar-IPv4Local $texto.Trim()
    if (-not $seleccionada) {
        Write-Host '[ERROR] IPv4 invalida. Se admite IP privada de LAN o Tailscale (100.64.0.0/10).' -ForegroundColor Yellow
    }
}
$env:PANEL_ROBOT_IP = $seleccionada
$env:PANEL_ROBOT_CONFIG_PROMPT = '1'
$env:PANEL_ROBOT_LIMITE_RPM = '30'  # Mantiene la misma limitacion del proyecto original.
Write-Host ''
Write-Host ('[OK] Robot elegido: ' + $seleccionada) -ForegroundColor Green
Write-Host 'Se aplicara a: movimiento :5000, Mini QR :5050, TTS :9000, camaras :8888/:8889.'
Write-Host 'IMPORTANTE: comprueba que realmente sea el robot esperado ANTES de tomar control.' -ForegroundColor Yellow
Write-Host ''

# Buscar Python ya instalado. No cambiar los otros proyectos Python de Windows.
function Encontrar-Python {
    $ejecutables = @()
    $cPython = Get-Command python -ErrorAction SilentlyContinue
    if ($cPython) { $ejecutables += ,@($cPython.Source) }
    $cPy = Get-Command py -ErrorAction SilentlyContinue
    if ($cPy) { $ejecutables += ,@($cPy.Source, '-3') }
    $ejecutables += ,@((Join-Path $env:LOCALAPPDATA 'Programs\Python\Python312\python.exe'))
    $ejecutables += ,@((Join-Path $env:ProgramFiles 'Python312\python.exe'))
    foreach ($cmd in $ejecutables) {
        try {
            $exe = $cmd[0]
            if (-not $exe -or -not (Test-Path -LiteralPath $exe)) { continue }
            $args = @()
            if ($cmd.Count -gt 1) { $args += $cmd[1..($cmd.Count-1)] }
            $args += '-c'
            $args += 'import sys; sys.exit(0 if sys.version_info >= (3,10) else 1)'
            & $exe @args *> $null
            if ($LASTEXITCODE -eq 0) { return ,$cmd }
        } catch { }
    }
    return $null
}

$python = Encontrar-Python
if (-not $python) {
    Write-Host '[AVISO] No se encontro Python 3.10+.' -ForegroundColor Yellow
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) { throw 'Instala Python 3.12 desde python.org y vuelve a ejecutar el BAT. Se recomienda marcar Add Python to PATH.' }
    $instalar = Read-Host 'Instalar automaticamente Python 3.12 con winget? (S/N)'
    if ($instalar.Trim().ToUpperInvariant() -ne 'S') { throw 'Python es necesario para ejecutar este panel.' }
    & $winget.Source install --id Python.Python.3.12 --exact --scope user --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) { throw 'La instalacion de Python no pudo completarse. Puedes instalar Python 3.12 manualmente.' }
    $python = Encontrar-Python
    if (-not $python) { throw 'Python se instalo, pero no se detecta en esta consola. Cierra la ventana, vuelve a abrir el BAT y prueba.' }
}

$pythonExe = $python[0]
$pythonArgs = @()
if ($python.Count -gt 1) { $pythonArgs = $python[1..($python.Count-1)] }
$venvPython = Join-Path $PSScriptRoot '.venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $venvPython)) {
    Write-Host '[1/3] Preparando Python para este proyecto...' -ForegroundColor Cyan
    & $pythonExe @pythonArgs -m venv '.venv'
    if ($LASTEXITCODE -ne 0) { throw 'No fue posible crear .venv. Comprueba que Python incluya venv.' }
}
& $venvPython -c "import importlib.util,sys; sys.exit(0 if importlib.util.find_spec('socketio') else 1)" | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host '[2/3] Instalando python-socketio (solo en este proyecto)...' -ForegroundColor Cyan
    $oldPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & $venvPython -m pip install --disable-pip-version-check 'python-socketio[client]>=5,<6'
        $pipExit = $LASTEXITCODE
    } finally { $ErrorActionPreference = $oldPreference }
    if ($pipExit -ne 0) { throw 'Fallo la instalacion de python-socketio. Comprueba la conexion a Internet.' }
} else {
    Write-Host '[2/3] Dependencias listas.' -ForegroundColor Green
}

# Los servicios pueden no existir en todos los robots; solo comprobar TCP y avisar.
Write-Host '[3/3] Verificando conectividad TCP (sin enviar movimiento)...' -ForegroundColor Cyan
foreach ($puerto in @(5000,5050,9000)) {
    $cliente = New-Object System.Net.Sockets.TcpClient
    try {
        $ar = $cliente.BeginConnect($seleccionada, $puerto, $null, $null)
        $ok = $ar.AsyncWaitHandle.WaitOne(1300)
        if ($ok) {
            try { $cliente.EndConnect($ar) } catch { $ok = $false }
        }
        if ($ok) {
            Write-Host ('  [OK] Puerto ' + $puerto) -ForegroundColor Green
        } else {
            Write-Host ('  [AVISO] Puerto ' + $puerto + ' no responde. La funcion asociada podria fallar.') -ForegroundColor Yellow
        }
    } finally {
        $cliente.Close()
    }
}
Write-Host ''
Write-Host ('Panel local: http://127.0.0.1:8765  |  Robot: ' + $seleccionada) -ForegroundColor Cyan
Write-Host 'TTS: si se solicita, introduce el token oficial (oculto). Halloween usa el catalogo original.'
Write-Host 'No cierres esta consola mientras uses el panel. Ctrl+C para detener.'
Write-Host ''
& $venvPython -u 'panel_robot_local.py' --habilitar-movimiento --inicio-desde-bat
if ($LASTEXITCODE -ne 0) { throw ('El servidor local termino con codigo ' + $LASTEXITCODE) }
