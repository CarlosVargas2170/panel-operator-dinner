"""Nexus Mesero 06: backend web autenticado, utilizando APIs originales del robot.
Un proceso por robot: la exclusividad se almacena en memoria por seguridad.
No instala componentes en Windows ni realiza cambios en STM32.
"""
from __future__ import annotations

import asyncio
import base64
import hashlib
import hmac
import html
import json
import os
import re
import secrets
import threading
import time
from contextlib import asynccontextmanager
from pathlib import Path
from urllib.parse import parse_qs

import httpx
from fastapi import FastAPI, Request, HTTPException
from fastapi.responses import HTMLResponse, RedirectResponse, JSONResponse, Response

ROOT = Path(__file__).resolve().parent
USER = os.getenv('PANEL_USER', '').strip()
PASSWORD = os.getenv('PANEL_PASSWORD', '')
SESSION_SECRET = os.getenv('PANEL_SESSION_SECRET', '')
COOKIE_NAME = 'nexus_mesero06_session'
SESSION_SECONDS = 8 * 3600
COOKIE_SECURE = os.getenv('PANEL_COOKIE_SECURE', '1') != '0'
PUBLIC_URL = os.getenv('PANEL_PUBLIC_URL', '').rstrip('/')

# Requerir credenciales reales, sin valores por defecto publicados.
if not USER or len(PASSWORD) < 12 or len(SESSION_SECRET) < 32:
    raise RuntimeError('Faltan PANEL_USER, PANEL_PASSWORD (12+) o PANEL_SESSION_SECRET (32+) en el entorno.')

local_http = None
local_thread = None
robot_module = None
LEASE_SECONDS = 10.0
_lease_session = None
_lease_last = 0.0
_lease_lock = threading.RLock()
_login_attempts = {}
_login_lock = threading.Lock()


def encode64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode('ascii').rstrip('=')


def cookie_sign(payload: str) -> str:
    return encode64(hmac.new(SESSION_SECRET.encode(), payload.encode(), hashlib.sha256).digest())


def make_cookie() -> str:
    data = f'{int(time.time()) + SESSION_SECONDS}.{secrets.token_urlsafe(24)}'
    return data + '.' + cookie_sign(data)


def session_id(request: Request) -> str | None:
    raw = request.cookies.get(COOKIE_NAME, '')
    try:
        exp, nonce, sig = raw.split('.', 2)
        expiration = int(exp)
        if not (time.time() < expiration <= time.time() + SESSION_SECONDS) or len(nonce) > 100:
            return None
        payload = exp + '.' + nonce
        if hmac.compare_digest(cookie_sign(payload), sig):
            return raw
    except (TypeError, ValueError):
        pass
    return None


def csrf(sid: str) -> str:
    return cookie_sign('csrf:' + sid)


def origin_valid(request: Request) -> bool:
    origin = request.headers.get('origin', '').rstrip('/')
    if not origin:
        return False
    if PUBLIC_URL:
        return hmac.compare_digest(origin, PUBLIC_URL)
    # Desarrollo local; en producción configurar PANEL_PUBLIC_URL.
    return origin in {'http://' + request.headers.get('host',''),
                      'https://' + request.headers.get('host','')}


def post_authorized(request: Request, sid: str) -> bool:
    return origin_valid(request) and hmac.compare_digest(request.headers.get('x-robot-tts-token',''), csrf(sid))


def own_lease(sid: str, touch: bool = False) -> bool:
    global _lease_session, _lease_last
    with _lease_lock:
        valid = _lease_session == sid and (time.monotonic() - _lease_last) <= LEASE_SECONDS
        if valid and touch:
            _lease_last = time.monotonic()
        return valid


def release_lease(sid: str | None = None) -> None:
    global _lease_session, _lease_last
    with _lease_lock:
        if sid is not None and _lease_session != sid:
            return
        _lease_session = None
        _lease_last = 0.0
    if robot_module is not None:
        robot_module.DRIVE.stop()
        robot_module.DRIVE.release()


async def lease_watchdog():
    while True:
        await asyncio.sleep(0.4)
        with _lease_lock:
            expired = _lease_session is not None and (time.monotonic()-_lease_last)>LEASE_SECONDS
        if expired:
            release_lease()


@asynccontextmanager
async def lifespan(app: FastAPI):
    global robot_module, local_http, local_thread
    # El servicio HTTP original solo escucha en loopback. Nunca abrir el puerto 8765 a Internet.
    import http.server
    import robot_local_06
    from mesero06_drive_bridge import DriveBridge
    robot_module = robot_local_06
    robot_module.DRIVE.close()  # instancia inicial desactivada, sin movimiento
    active = os.getenv('MESERO06_ENABLE_DRIVE', '1') == '1'
    robot_module.DRIVE = DriveBridge(enabled=active)
    robot_module.DRIVE_ENABLED = active
    local_http = http.server.ThreadingHTTPServer(('127.0.0.1', 0), robot_module.Handler)
    robot_module.PORT = int(local_http.server_address[1])
    local_thread = threading.Thread(target=local_http.serve_forever, name='nexus-robot-loopback', daemon=True)
    local_thread.start()
    watchdog = asyncio.create_task(lease_watchdog())
    try:
        yield
    finally:
        watchdog.cancel()
        release_lease()
        local_http.shutdown()
        local_http.server_close()


app = FastAPI(title='Nexus Robotics · Mesero 06', docs_url=None, redoc_url=None, openapi_url=None, lifespan=lifespan)

@app.middleware('http')
async def protect(request: Request, call_next):
    path = request.url.path
    if path not in ('/login', '/healthz', '/favicon.ico') and not session_id(request):
        if request.method == 'GET' and not path.startswith('/api/'):
            return RedirectResponse('/login', status_code=303)
        return JSONResponse({'ok':False,'error':'Autenticación requerida'}, status_code=401)
    response = await call_next(request)
    response.headers['Cache-Control'] = 'no-store'
    response.headers['X-Content-Type-Options'] = 'nosniff'
    response.headers['Referrer-Policy'] = 'no-referrer'
    response.headers['X-Frame-Options'] = 'DENY'
    return response

LOGIN_PAGE = """<!doctype html><html lang='es'><head><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'>
<title>Acceso · Nexus Robotics</title><style>*{box-sizing:border-box}body{margin:0;min-height:100vh;display:grid;place-items:center;background:linear-gradient(140deg,#091421,#14273d);color:#edf6ff;font:15px system-ui,sans-serif;padding:20px}main{width:min(420px,100%);background:#142134;border:1px solid #40566e;border-radius:19px;padding:34px}h1{margin:0 0 6px;font-size:24px}p{color:#abbcd0;margin:0 0 24px}label{display:block;margin:15px 0 5px;font-size:12px}input{display:block;width:100%;background:#0a1728;color:white;border:1px solid #4d657e;padding:13px;border-radius:8px;font:inherit}button{width:100%;padding:14px;border:0;border-radius:9px;background:#3a89ec;color:white;font-size:15px;font-weight:750;margin-top:24px;cursor:pointer}.error{color:#ffb7b7;margin-top:12px}</style></head>
<body><main><h1>🤖 Nexus Robotics</h1><p>Panel de Operación · Mesero 06</p><form method='post' action='/login'><label for='u'>Usuario</label><input id='u' name='username' autocomplete='username' required><label for='p'>Contraseña</label><input id='p' name='password' type='password' autocomplete='current-password' required><button>Ingresar al panel</button></form>__ERROR__</main></body></html>"""


def login_screen(message: str = '', code: int = 200):
    return HTMLResponse(LOGIN_PAGE.replace('__ERROR__', '<p class="error">' + html.escape(message) + '</p>' if message else ''), status_code=code)

@app.get('/healthz')
def healthz():
    return {'ok': True, 'backend':'nexus-mesero06', 'robot_api':'configured'}

@app.get('/login')
def login_get(request: Request):
    if session_id(request): return RedirectResponse('/', status_code=303)
    return login_screen()

@app.post('/login')
async def login_post(request: Request):
    if request.headers.get('content-type','').split(';',1)[0].strip().lower() != 'application/x-www-form-urlencoded':
        return login_screen('Formato inválido', 415)
    if request.headers.get('origin') and not origin_valid(request):
        return login_screen('Origen no permitido', 403)
    raw = await request.body()
    if len(raw)>4096: return login_screen('Solicitud demasiado grande',413)
    data = parse_qs(raw.decode('utf8',errors='replace'))
    u = data.get('username',[''])[0]
    p = data.get('password',[''])[0]
    ip = request.client.host if request.client else 'unknown'
    now = time.monotonic()
    with _login_lock:
        events = [t for t in _login_attempts.get(ip,[]) if now-t < 900]
        if len(events)>=6:
            return login_screen('Demasiados intentos. Prueba más tarde.',429)
        correct = hmac.compare_digest(u.encode(), USER.encode()) & hmac.compare_digest(p.encode(), PASSWORD.encode())
        if not correct:
            events.append(now)
            _login_attempts[ip] = events
            return login_screen('Usuario o contraseña incorrectos.',401)
        _login_attempts.pop(ip,None)
    r=RedirectResponse('/',status_code=303)
    r.set_cookie(COOKIE_NAME,make_cookie(),max_age=SESSION_SECONDS,httponly=True,secure=COOKIE_SECURE,samesite='lax',path='/')
    return r

@app.post('/logout')
def logout(request: Request):
    sid=session_id(request)
    if not sid or not post_authorized(request,sid):
        return JSONResponse({'error':'Origen o sesión inválida'},status_code=403)
    release_lease(sid)
    r=RedirectResponse('/login',status_code=303)
    r.delete_cookie(COOKIE_NAME,path='/')
    return r

@app.get('/')
@app.get('/panel')
def panel(request: Request):
    sid=session_id(request)
    original=(ROOT/'ROBOT_LOCAL_06.html').read_text('utf8')
    page=original.replace('content="__LOCAL_TTS_TOKEN__"','content="'+csrf(sid)+'"',1)
    return HTMLResponse(page)

@app.get('/api/connection')
def connection(request: Request):
    state=robot_module.DRIVE.status() if robot_module else {'enabled':False,'connected':False}
    return {'ok':True, 'socketio_connected':state.get('connected',False),
            'stm32_connected':state.get('serial_connected',False),
            'robot_mode':state.get('robot_mode','DESCONOCIDO'),
            'tts_configured':bool(robot_module and robot_module.TTS_BEARER_TOKEN),
            'mini_url_configured':bool(os.getenv('MESERO06_MINI_URL'))}

# HLS: registrar rutas específicas ANTES del proxy genérico /api/{path}.
from render_hls_proxy import hls_router
app.include_router(hls_router)

# Restricción de rutas: todo lo demás es 404, no un proxy abierto hacia la red privada.
READ_ROUTES={
 'mini/offer/status','mini/merchants','mini/faces/diagnostic','mini/halloween',
 'mini/faces','mini/catalog/info','mini/products','mini/sales',
 'server/audio/catalog','github/catalog','local/status',
 'tts/diagnostic','tts/status','drive/status','drive/telemetry',
 'mini/status','mini/audio/status'
}
POST_ROUTES={
 'drive/claim','drive/release','drive/input','drive/stop','drive/query-mode','drive/cycle-mode',
 'mini/merchant/filter','mini/ui/product','mini/offer','mini/face/set',
 'mini/audio/play','mini/audio/stop','audio/stop-all','tts'
}

@app.api_route('/api/{path:path}', methods=['GET','POST'])
async def api_proxy(request: Request, path: str):
    global _lease_session,_lease_last
    sid=session_id(request)
    if not sid: return JSONResponse({'ok':False,'error':'Autenticación requerida'},status_code=401)
    if request.method=='GET':
        if path not in READ_ROUTES and not re.fullmatch(r'github/media/[A-Za-z0-9_-]{1,100}',path):
            return JSONResponse({'ok':False,'error':'Ruta no permitida'},status_code=404)
        if own_lease(sid) and path=='drive/status': own_lease(sid,touch=True)
    else:
        if path not in POST_ROUTES: return JSONResponse({'ok':False,'error':'Ruta no permitida'},status_code=404)
        if not post_authorized(request,sid):
            return JSONResponse({'ok':False,'error':'Origen o protección CSRF inválidos'},status_code=403)
        if path=='drive/claim':
            with _lease_lock:
                # Una sesión anterior caducada debe detenerse y liberarse ANTES de reclamar.
                expired = _lease_session is not None and (time.monotonic()-_lease_last) > LEASE_SECONDS
                if expired:
                    release_lease()
                if _lease_session is not None and _lease_session != sid:
                    return JSONResponse({'ok':False,'error':'Otro operador está utilizando el robot'},status_code=409)
                _lease_session,_lease_last=sid,time.monotonic()
        elif path.startswith('drive/') and path!='drive/stop':
            if not own_lease(sid,touch=True):
                return JSONResponse({'ok':False,'error':'Primero debes tomar control en esta sesión'},status_code=409)
        elif path not in ('audio/stop-all','mini/audio/stop'):
            # Los servicios multimedia no dependen de haber tomado los motores.
            # Se bloquean solamente si existe otra sesión de operación activa.
            with _lease_lock:
                if (_lease_session is not None and _lease_session != sid
                        and time.monotonic()-_lease_last <= LEASE_SECONDS):
                    return JSONResponse({'ok':False,'error':'Otro operador tiene el panel activo'},status_code=409)
        if path=='drive/ultra-toggle':
            return JSONResponse({'ok':False,'error':'El control de ultrasónicos requiere habilitación explícita en la instalación oficial'},status_code=403)
    body=await request.body() if request.method=='POST' else b''
    if len(body)>4096:
        return JSONResponse({'error':'Solicitud demasiado grande'},status_code=413)
    url=f'http://127.0.0.1:{robot_module.PORT}/api/{path}'
    if request.method=='GET' and request.url.query and path in {'server/audio/catalog','github/catalog'}:
        url+='?'+request.url.query
    headers={'Host':f'127.0.0.1:{robot_module.PORT}',
             'X-Robot-TTS-Token':robot_module.TOKEN,
             'Origin':f'http://127.0.0.1:{robot_module.PORT}',
             'Content-Type':'application/json'}
    try:
        timeout=140.0 if path=='tts' else 48.0 if path=='mini/face/set' else 15.0
        async with httpx.AsyncClient(timeout=timeout,trust_env=False) as client:
            inner=await client.request(request.method,url,content=body if request.method=='POST' else None,headers=headers)
        data=inner.content
        ctype=inner.headers.get('content-type','application/json').split(';',1)[0]
        if ctype not in ('application/json','audio/wav','audio/x-wav','audio/mpeg','audio/ogg','audio/mp4','application/octet-stream'):
            ctype='application/octet-stream'
        if path=='drive/claim' and inner.status_code>=400:
            release_lease(sid)
        if path=='drive/release' and inner.status_code<400:
            release_lease(sid)
        if path=='drive/status':
            try:
                j=json.loads(data)
                if isinstance(j,dict):
                    if not own_lease(sid):
                        j.update(owner=False,pending=False,movement_allowed=False)
                        j['block_reason']='Otra sesión controla el robot' if _lease_session else 'Pulsa Tomar control para solicitar el mando'
                    data=json.dumps(j,ensure_ascii=False).encode()
            except (ValueError,UnicodeDecodeError): pass
        return Response(content=data,status_code=inner.status_code,media_type=ctype)
    except (httpx.TimeoutException,httpx.TransportError):
        if path=='drive/claim': release_lease(sid)
        return JSONResponse({'ok':False,'error':'No se pudo contactar el servicio local del robot'},status_code=503)

