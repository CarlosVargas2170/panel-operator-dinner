"""Puente TTS local de prueba para Robot Mesero 06.

Conecta de forma restringida TTS, audio, ventas y GIFs reales de mini_app_qr.
El movimiento conserva el puente oficial separado. Limite por defecto: 5 RPM;
solo el iniciador especifico permite hasta 30 RPM con confirmacion.
Todas las ordenes POST necesitan credencial local y origen comprobado.
"""
import http.server
import getpass
import atexit
import os
import json
import secrets
import sys
import time
import urllib.error
import urllib.request
import urllib.parse
import re
import webbrowser
from pathlib import Path
import mesero06_repo_media as repo_media

HOST = '127.0.0.1'
PORT = 8765
ROBOT_TTS = 'http://100.87.64.123:9000'
ROBOT_MINI = 'http://100.87.64.123:5050'
PAGE = Path(__file__).with_name('mesero06_panel_glass_v13.html')
CAMERAS_PAGE = Path(__file__).with_name('mesero06_camaras_2.html')
TOKEN = secrets.token_urlsafe(32)
LAST_SEND = [0.0]
# La IP Tailscale privada no debe pasar por proxies del sistema (Windows/empresa).
DIRECT_TAILSCALE = urllib.request.build_opener(urllib.request.ProxyHandler({}))
# La credencial es del servicio de voz, no del robot/SSH, y nunca se entrega al navegador.
# Se introduce en la terminal o se recibe de la variable de entorno del proceso.
TTS_BEARER_TOKEN = os.environ.get('MESERO06_TTS_TOKEN', '').strip()
from mesero06_drive_bridge import DriveBridge, MAX_TEST_SPEED
DRIVE_ENABLED = '--habilitar-movimiento' in sys.argv
DRIVE = DriveBridge(enabled=DRIVE_ENABLED)
atexit.register(DRIVE.close)

# Solo audios conocidos del inventario local; nunca se admite una URL arbitraria del navegador.
MINI_FACE_CATALOG = {
    'normal': 'normal', 'happy': 'happy', 'angry': 'angry', 'cry': 'cry',
    'love': 'love', 'money': 'money', 'sad': 'sad', 'sleep': 'sleep',
    'confused': 'confused', 'six-seven': 'six-seven', 'aura': 'aura',
    'kiss': 'kiss', 'nexus': 'nexus',
}
# Identificadores encontrados en face_halloween_src.html, NO confirmados en Flutter.
# La UI solo los ofrece como PRUEBA; se confirma por respuesta /attract/set.
HALLOWEEN_CANDIDATES = frozenset({'pumpkin','ghost','scared','witch','sinister','alien'})
MINI_FACE_LOCK = __import__('threading').Lock()
MINI_AUDIO_CATALOG = {'sixseven': 'audio/six-seven.wav', 'dance': 'audio/dance_to_sell.wav', 'pedro': 'audio/pedro_pedro.mp3', 'tokio': 'audio/reto_tokio.mp3', 'miaumiau': 'audio/miau_miau.mp3', 'siren': 'audio/alert_siren.mp3', 'saludo': 'audio/hello.wav', 'gracias': 'audio/thanks_shopping.wav', 'pregunta': 'audio/question_coffe.wav', 'orden': 'audio/there_is_an_order.wav', 'atencion': 'audio/attention_with_service.wav', 'presentacion': 'audio/presentacion.wav', 'bandeja': 'audio/collect_tray.wav', 'comprar': 'audio/purchase_buy.wav', 'gasosa': 'audio/buy_gaseosa.wav', 'brownie': 'audio/Hola_deseas_un_Brown.wav', 'helado': 'audio/Hola_deseas_un_Cremo.wav', 'jingle': 'audio/eco-combo-kiky.wav', 'postre': 'audio/want_postre.wav', 'fahh': 'audio/fahh.mp3', 'bocina': 'audio/bocina_car.mp3', 'lujisadito': 'audio/lujisadito.mp3', 'eco_lena': 'audio/eco-combo-lena-kiky.wav'}
# Correspondencias sugeridas por el inventario del robot; la existencia y el texto exacto
# deben verificarse en la primera prueba. Siempre showOverlay=False.
MINI_AUDIO_CATALOG.update({
    'boton_pago': 'audio/select_button_to_pay.wav',
    'aqui_tienes': 'audio/Aqui_tienes_Que_lo_d.wav',
    'atencion_permiso': 'audio/attention_excuse_me.wav',
})
MINI_AUDIO_LOCK = __import__('threading').Lock()
MINI_AUDIO_STATE = {'busy': False, 'asset': None, 'job': 0, 'result': 'Sin reproducciones'}
MINI_LAST_SEND = [0.0]
# Ruta adicional del servicio TTS únicamente si el administrador la confirma.
# No se inventa un endpoint de parada en el puerto 9000.
TTS_STOP_PATH = os.environ.get('MESERO06_TTS_STOP_PATH', '').strip()
TTS_STOP_ALLOWED = {'/synthesize/stop', '/tts/stop', '/audio/stop', '/playback/stop', '/synthesize/cancel'}

def mini_request(path, data=None, timeout=8, max_bytes=32768):
    raw = json.dumps(data, ensure_ascii=False).encode('utf-8') if data is not None else None
    req = urllib.request.Request(ROBOT_MINI + path, data=raw, method='POST' if data is not None else 'GET',
        headers={'Content-Type':'application/json','Accept':'application/json'})
    with DIRECT_TAILSCALE.open(req, timeout=timeout) as response:
        return response.status, response.read(max_bytes)

# Descubrimiento de comercios: IDs que reporta Flutter, nunca nombres inventados.
# Los filtros solo se aplican con confirmación y sin pagos en curso.
MERCHANT_SWITCH_LOCK = __import__('threading').Lock()

def get_available_merchants():
    code, raw = mini_request('/config', timeout=7, max_bytes=65536)
    config = json.loads(raw)
    if code != 200 or not isinstance(config, dict):
        raise ValueError('Configuración Flutter inválida')
    public = config.get('data', config)
    if not isinstance(public, dict):
        raise ValueError('Configuración Flutter inesperada')
    ids = set()
    for x in public.get('merchantIds', []) or []:
        if type(x) is int and 0 < x < 1000000000:
            ids.add(x)
    if type(public.get('merchantId')) is int and public['merchantId'] > 0:
        ids.add(public['merchantId'])
    names = {}
    try:
        status, body = mini_request('/products', timeout=9, max_bytes=1200000)
        data = json.loads(body)
        if status == 200 and isinstance(data, dict):
            catalog = data.get('data')
            def walk(node, depth=0):
                if depth > 10 or node is None:
                    return
                if isinstance(node, list):
                    for item in node[:2000]:
                        walk(item, depth + 1)
                elif isinstance(node, dict):
                    k = node.get('merchantId', node.get('merchant_id'))
                    # Solo identificar nodos que realmente contienen un merchantId.
                    if type(k) is int and 0 < k < 1000000000:
                        ids.add(k)
                        title = next((node.get(t) for t in ('merchantName','commerceName','businessName','storeName','nameMerchant') if isinstance(node.get(t),str) and node[t].strip()), None)
                        if title:
                            names[k] = title.strip()[:70]
                    # Algunos catálogos agrupan por clave ID bajo merchants.
                    for field, value in list(node.items())[:300]:
                        if field in ('merchants','comercios') and isinstance(value,dict):
                            for key, obj in list(value.items())[:250]:
                                if str(key).isdigit() and isinstance(obj,dict):
                                    number = int(key)
                                    if 0 < number < 1000000000:
                                        ids.add(number)
                                        nm = next((obj.get(t) for t in ('merchantName','commerceName','name','title') if isinstance(obj.get(t),str) and obj[t].strip()), None)
                                        if nm: names[number]=nm.strip()[:70]
                        if isinstance(value,(dict,list)):
                            walk(value,depth+1)
            walk(catalog)
    except (urllib.error.URLError, TimeoutError, OSError, ValueError, TypeError, json.JSONDecodeError):
        # Flutter puede tener la caché vacía mientras carga; en ese caso queda la lista de /config.
        pass
    return [{'id':i,'name':names.get(i,'Comercio #'+str(i))} for i in sorted(ids)][:100]


def face_inventory():
    static=[{'id':x,'name':x.replace('-',' ').title(),'emoji':'🎭','collection':'base'} for x in MINI_FACE_CATALOG]
    try:
        status, body = mini_request('/attract/list', timeout=5, max_bytes=131072)
        data=json.loads(body)
        if status != 200 or not isinstance(data,dict) or data.get('success') is not True:
            return static, 'base'
        incoming = data.get('gifs',data.get('faces',data.get('items',data.get('data',[]))))
        if isinstance(incoming,dict): incoming=incoming.get('gifs',incoming.get('items',[]))
        if not isinstance(incoming,list): return static,'base'
        result=[];seen=set()
        import re
        for row in incoming[:200]:
            if isinstance(row,str):
                row={'id':row}
            if not isinstance(row,dict): continue
            name=row.get('id',row.get('gif',row.get('name')))
            if not isinstance(name,str) or not re.fullmatch(r'[a-zA-Z0-9][a-zA-Z0-9_-]{0,54}',name): continue
            if name in seen: continue
            seen.add(name)
            label=row.get('label',row.get('name',name))
            if not isinstance(label,str):label=name
            emoji=row.get('emoji','🎭')
            if not isinstance(emoji,str) or len(emoji)>8:emoji='🎭'
            group=row.get('collection',row.get('group','base'))
            if group not in ('base','navidad','halloween'):group='base'
            # Clasificación visual: únicamente para IDs enumerados realmente por Flutter.
            if group=='base' and name.lower() in ('pumpkin','ghost','scared','witch','sinister','alien','zombie'):
                group='halloween'
            result.append({'id':name,'name':label[:64],'emoji':emoji,'collection':group})
        return result, 'flutter'
    except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError, OSError, ValueError, TypeError, json.JSONDecodeError):
        return static,'base'

def mini_audio_worker(asset, job):
    try:
        status, body = mini_request('/audio/play', {'asset': asset, 'volume': 1.0, 'force': False, 'showOverlay': False}, timeout=600)
        data = json.loads(body)
        result = 'Finalizado' if status == 200 and data.get('played') is True else 'Omitido por la aplicación (cooldown o error)'
    except Exception as exc:
        result = 'Error de reproducción: ' + type(exc).__name__
    with MINI_AUDIO_LOCK:
        if MINI_AUDIO_STATE['job'] == job:
            MINI_AUDIO_STATE.update(busy=False, asset=None, result=result)




# Acciones oficiales de mini_app_qr: sin cambiar el comercio ni tocar la lógica de pagos.
# El servidor Flutter espera hasta que termina el audio; usar un hilo para no bloquear el panel.
MINI_OFFER_PATHS = {
    'coffee': '/greet/audio?asset=audio/question_coffe.wav&showOverlay=false',  # Carrusel + cafe sin overlay
    'commerce': '/greet/audio?asset=audio/purchase_buy.wav&showOverlay=false',  # Carrusel + invitacion, sin overlay
    'delivered': '/audio/play',  # Audio coffee, sin overlay; no cambia pantalla
}

def mini_offer_worker(path, job):
    try:
        data = {'asset': 'audio/here_is_coffee.wav', 'showOverlay': False} if path == '/audio/play' else {}
        status, body = mini_request(path, data, timeout=600)
        info = json.loads(body)
        played = info.get('audio', info.get('played'))
        if status == 200 and info.get('success') is True:
            result = 'Oferta procesada por Flutter' if played is True else 'Pantalla actualizada, audio omitido por cooldown o no confirmado'
        else:
            result = 'Flutter no confirmó la oferta'
    except Exception as exc:
        result = 'Error al ofrecer: ' + type(exc).__name__
    with MINI_AUDIO_LOCK:
        if MINI_AUDIO_STATE['job'] == job:
            MINI_AUDIO_STATE.update(busy=False, asset=None, result=result)


def get_remote(path, method='GET', payload=None, timeout=12, max_bytes=32768, drain=False):
    raw = json.dumps(payload, ensure_ascii=False).encode('utf-8') if payload is not None else None
    req = urllib.request.Request(
        ROBOT_TTS + path,
        data=raw,
        method=method,
        headers={
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            **({'Authorization': 'Bearer ' + TTS_BEARER_TOKEN} if TTS_BEARER_TOKEN and path not in ('/health', '/openapi.json') else {}),
        },
    )
    with DIRECT_TAILSCALE.open(req, timeout=timeout) as r:
        if drain:
            # /synthesize/play devuelve PCM por streaming: cortar a 32 KB puede
            # dejar la reproducción incompleta y el backend marcado como ocupado.
            # Consumir el stream entero (sin almacenarlo ni reproducirlo en PC).
            total = 0
            while True:
                chunk = r.read(65536)
                if not chunk:
                    break
                total += len(chunk)
                if total > 16 * 1024 * 1024:
                    raise ValueError('El stream TTS excedió el límite esperado')
            return r.status, b''
        return r.status, r.read(max_bytes)


def discover_tts_stop_path():
    """Solo rutas POST explícitas en el OpenAPI del servicio TTS; sin conjeturas."""
    if TTS_STOP_PATH:
        return TTS_STOP_PATH if TTS_STOP_PATH in TTS_STOP_ALLOWED else None
    try:
        code, data = get_remote('/openapi.json', timeout=3, max_bytes=300000)
        if code != 200:
            return None
        paths = json.loads(data).get('paths', {})
        if not isinstance(paths, dict):
            return None
        for candidate in ('/synthesize/stop', '/tts/stop', '/audio/stop', '/playback/stop', '/synthesize/cancel'):
            entry = paths.get(candidate)
            if isinstance(entry, dict) and 'post' in entry:
                return candidate
    except (OSError, urllib.error.URLError, TimeoutError, ValueError, TypeError, json.JSONDecodeError):
        pass
    return None


def stop_all_robot_audio():
    """Detiene mini_app_qr y, si está documentado, TTS. No afecta los motores ni cámaras."""
    with MINI_AUDIO_LOCK:
        MINI_AUDIO_STATE['job'] += 1  # invalidar respuestas tardías de los workers
        MINI_AUDIO_STATE.update(busy=False, asset=None, result='Parada de audio solicitada')
        MINI_LAST_SEND[0] = 0.0       # nueva orden permitida tras STOP
    mini_result = {'ok': False, 'detail': 'No se confirmó la detención de audio en Flutter'}
    try:
        code, body = mini_request('/audio/stop', data={}, timeout=7)
        info = json.loads(body)
        mini_result = {'ok': code == 200 and info.get('success') is True,
                       'detail': 'Flutter confirmó STOP' if code == 200 and info.get('success') is True
                                 else 'Flutter no confirmó STOP'}
    except (OSError, urllib.error.URLError, TimeoutError, ValueError, TypeError, json.JSONDecodeError):
        mini_result['detail'] = 'No se pudo contactar /audio/stop de Flutter'
    tts_result = {'ok': False, 'supported': False, 'detail': 'TTS remoto sin endpoint de parada confirmado'}
    if TTS_BEARER_TOKEN:
        route = discover_tts_stop_path()
        if route:
            tts_result['supported'] = True
            try:
                code, _ = get_remote(route, method='POST', payload={}, timeout=7)
                tts_result['ok'] = 200 <= code < 300
                tts_result['detail'] = ('TTS confirmó parada' if tts_result['ok']
                                        else 'TTS rechazó parada')
                if tts_result['ok']:
                    LAST_SEND[0] = 0.0
            except (OSError, urllib.error.URLError, TimeoutError, ValueError):
                tts_result['detail'] = 'TTS no respondió a su endpoint de parada'
    return {'ok': mini_result['ok'] or tts_result['ok'], 'mini': mini_result, 'tts': tts_result,
            'detail': 'Audio local detenido por el navegador; ver detalles de mini_app_qr y TTS'}


class Handler(http.server.BaseHTTPRequestHandler):
    server_version = 'Mesero06-Local-TTS/1.3'

    def log_message(self, format_string, *args):
        # Do not log message content from TTS.
        if self.path.startswith('/api/tts'):
            return
        print('[local]', self.address_string(), self.command, self.path)

    def headers_json(self, status):
        self.send_response(status)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('X-Frame-Options', 'DENY')
        self.send_header('Referrer-Policy', 'no-referrer')
        self.end_headers()

    def reply(self, status, data):
        self.headers_json(status)
        self.wfile.write(json.dumps(data, ensure_ascii=False).encode('utf-8'))

    def do_GET(self):
        path = urllib.parse.urlsplit(self.path).path
        if self.headers.get('Host') not in (f'{HOST}:{PORT}', f'localhost:{PORT}'):
            return self.reply(403, {'error': 'Host local no permitido'})
        if path in ('/', '/index.html', '/mesero06_panel_glass_v13.html', '/panel', '/panel/'):
            if not PAGE.is_file():
                return self.reply(404, {'error': 'Archivo HTML no encontrado junto al script.'})
            html = PAGE.read_text('utf-8').replace('content="__LOCAL_TTS_TOKEN__"', f'content="{TOKEN}"')
            body = html.encode('utf-8')
            self.send_response(200)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.send_header('Content-Length', str(len(body)))
            self.send_header('Cache-Control', 'no-store')
            self.send_header('X-Frame-Options', 'DENY')
            self.send_header('Referrer-Policy', 'no-referrer')
            self.end_headers()
            self.wfile.write(body)
        elif path in ('/camaras', '/camaras/'):
            if not CAMERAS_PAGE.is_file():
                return self.reply(404, {'error': 'Visor de dos cámaras no encontrado'})
            body = CAMERAS_PAGE.read_bytes()
            self.send_response(200)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.send_header('Content-Length', str(len(body)))
            self.send_header('Cache-Control', 'no-store')
            self.send_header('X-Frame-Options', 'DENY')
            self.send_header('Referrer-Policy', 'no-referrer')
            self.end_headers()
            self.wfile.write(body)
        elif path == '/api/mini/offer/status':
            # Estado de la ultima accion multimedia; no accede a pagos ni movimiento.
            with MINI_AUDIO_LOCK:
                info = {'ok': True, 'busy': bool(MINI_AUDIO_STATE['busy']),
                        'result': str(MINI_AUDIO_STATE['result'])[:180],
                        'action': str(MINI_AUDIO_STATE['asset'] or '')[:40]}
            return self.reply(200, info)
        elif path == '/api/mini/merchants':
            try:
                items=get_available_merchants()
                return self.reply(200, {'ok':True,'merchants':items,'readOnly':True})
            except (urllib.error.HTTPError,urllib.error.URLError,TimeoutError,OSError,ValueError,TypeError,json.JSONDecodeError):
                return self.reply(502,{'ok':False,'error':'No se pudieron consultar los comercios activos en Flutter'})
        elif path == '/api/mini/faces/diagnostic':
            try:
                code, body = mini_request('/attract/list', timeout=5, max_bytes=131072)
                info = json.loads(body)
                valid = code == 200 and isinstance(info, dict) and info.get('success') is True
                self.reply(200, {'ok': True, 'apiAvailable': valid,
                                 'message': 'Inventario de caras disponible' if valid else
                                            'Flutter no confirmó /attract/list. Debe implementarlo el desarrollador.'})
            except (OSError, urllib.error.URLError, TimeoutError, ValueError, TypeError, json.JSONDecodeError):
                self.reply(200, {'ok': True, 'apiAvailable': False,
                                 'message': 'Mesero 06 no expone un inventario compatible en /attract/list.'})
        elif path == '/api/mini/faces':
            faces, source = face_inventory()
            return self.reply(200, {'ok':True,'source':source,'faces':faces,'supportsAutoDiscovery':source=='flutter'})
        elif path == '/api/mini/catalog/info':
            # Consulta SOLO lectura. No devuelve URL base, claves ni tokens de Flutter.
            try:
                code, body = mini_request('/config', timeout=7, max_bytes=32768)
                data = json.loads(body)
                if code != 200 or not isinstance(data, dict):
                    return self.reply(502, {'ok': False, 'error': 'No se pudo leer la configuración de Flutter'})
                public = data.get('data', data)
                if not isinstance(public, dict):
                    return self.reply(502, {'ok': False, 'error': 'Configuración de Flutter inesperada'})
                ids = public.get('merchantIds') or ([] if public.get('merchantId') is None else [public.get('merchantId')])
                if not isinstance(ids, list):
                    ids = []
                ids = [x for x in ids if isinstance(x, int) and not isinstance(x, bool)][:50]
                product_id = public.get('productId')
                return self.reply(200, {'ok': True, 'merchantIds': ids,
                    'productId': product_id if isinstance(product_id, int) and not isinstance(product_id, bool) else None})
            except (OSError, urllib.error.URLError, TimeoutError, ValueError, TypeError, json.JSONDecodeError):
                return self.reply(502, {'ok': False, 'error': 'No se pudo consultar la configuración activa'})
        elif path == '/api/mini/products':
            # Solo lectura del catalogo activo. No modifica comercios, productos ni pantalla Flutter.
            try:
                status, body = mini_request('/products', timeout=8, max_bytes=1200000)
                data = json.loads(body)
                if status != 200 or not isinstance(data, dict) or data.get('success') is not True:
                    return self.reply(502, {'ok': False, 'error': 'Flutter no confirmo el catalogo'})
                return self.reply(200, {'ok': True, 'cacheLoaded': data.get('cacheLoaded'), 'data': data.get('data'), 'readOnly': True})
            except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, OSError):
                return self.reply(502, {'ok': False, 'error': 'No se pudo leer productos desde mini_app_qr'})
            except (json.JSONDecodeError, ValueError):
                return self.reply(502, {'ok': False, 'error': 'Catalogo demasiado grande o respuesta invalida'})
        elif path == '/api/mini/sales':
            # Lectura exclusiva de la sesión en RAM de mini_app_qr.
            # No llama endpoints que cambien pagos ni reseteen contadores.
            try:
                status, body = mini_request('/payment/polling-status', timeout=5)
                if len(body)>262144:
                    return self.reply(502, {'ok': False, 'error': 'Respuesta de ventas demasiado grande'})
                info = json.loads(body)
                if status != 200 or info.get('success') is not True or not isinstance(info.get('counter'), dict):
                    return self.reply(502, {'ok': False, 'error': 'mini_app_qr no confirmó la consulta de ventas'})
                self.reply(200, {'ok': True, 'counter': info['counter'],
                                 'phase': info.get('phase'), 'isPolling': info.get('isPolling'),
                                 'source': 'mini_app_qr', 'readOnly': True})
            except (OSError, urllib.error.URLError, TimeoutError, ValueError, TypeError, json.JSONDecodeError) as exc:
                return self.reply(502, {'ok': False, 'error': 'Ventas no disponibles por Tailscale: ' + type(exc).__name__})
        elif path == '/api/github/catalog':
            # Catalogo en memoria local / sincronizacion de metadatos SOLO audio.
            refresh = urllib.parse.parse_qs(urllib.parse.urlsplit(self.path).query).get('refresh',['0'])[0]=='1'
            try:
                self.reply(200, repo_media.catalog(refresh=refresh))
            except Exception as exc:
                self.reply(502, {'ok':False,'error':'No se pudo abrir el catálogo original: '+type(exc).__name__})
        elif path.startswith('/api/github/media/'):
            # Previsualizacion local; no toca parlantes del robot ni motores.
            item_id=path.rsplit('/',1)[-1]
            try:
                media=repo_media.local_media(item_id)
                if not media:
                    return self.reply(404,{'error':'Audio fuera del catálogo verificado'})
                file_path,mime=media
                self.send_response(200)
                self.send_header('Content-Type',mime)
                self.send_header('Content-Length',str(file_path.stat().st_size))
                self.send_header('X-Content-Type-Options','nosniff')
                self.send_header('X-Frame-Options','DENY')
                self.send_header('Cache-Control','private, max-age=120')
                self.end_headers()
                with file_path.open('rb') as stream:
                    while True:
                        chunk=stream.read(65536)
                        if not chunk: break
                        self.wfile.write(chunk)
            except (OSError,urllib.error.URLError,ValueError,TimeoutError) as exc:
                self.reply(502,{'error':'No disponible en copia local o GitHub: '+type(exc).__name__})
        elif path == '/favicon.ico':
            self.send_response(204)
            self.send_header('Cache-Control', 'no-store')
            self.end_headers()
        elif path == '/api/local/status':
            self.reply(200, {'ok': True, 'detail': 'Servidor local listo', 'pagina': f'http://{HOST}:{PORT}/', 'movimiento': 'piloto supervisado' if DRIVE_ENABLED else 'desactivado'})
        elif path == '/api/tts/diagnostic':
            checks = {}
            for label, resource in [('health', '/health'), ('voices', '/voices'), ('openapi', '/openapi.json')]:
                try:
                    code, _ = get_remote(resource, timeout=6)
                    checks[label] = {'http_status': code, 'ok': 200 <= code < 300}
                except urllib.error.HTTPError as exc:
                    checks[label] = {'http_status': exc.code, 'ok': False}
                except (urllib.error.URLError, TimeoutError, OSError) as exc:
                    checks[label] = {'ok': False, 'error': type(exc).__name__}
            self.reply(200, {
                'authorization_configured': bool(TTS_BEARER_TOKEN),
                'checks': checks,
                'proxy': 'no se utiliza proxy para la IP de Tailscale',
                'audio_enviado': False,
                'movimiento': 'piloto supervisado' if DRIVE_ENABLED else 'desactivado',
                'nota': ('Existe un token TTS cargado; GET /voices ayuda a comprobar su validez. '
                         if TTS_BEARER_TOKEN else 'Falta el token oficial TTS para consultar voces y reproducir.')
                         + ' GET no garantiza permiso para POST /synthesize/play.'
            })
        elif path == '/api/tts/status':
            try:
                status, body = get_remote('/health', timeout=6)
                self.reply(200 if status == 200 else 502, {'ok': status == 200, 'service': 'TTS Mesero 06', 'health': body[:600].decode('utf-8', 'replace')})
            except urllib.error.HTTPError as exc:
                self.reply(502, {'ok': False, 'error': f'El servicio TTS rechazó /health con HTTP {exc.code}'})
            except (urllib.error.URLError, TimeoutError, OSError) as exc:
                self.reply(502, {'ok': False, 'error': type(exc).__name__ + ': no se pudo conectar al TTS mediante Tailscale'})
        elif path == '/api/drive/status':
            self.reply(200, DRIVE.status())
        elif path == '/api/mini/status':
            try:
                status, body = mini_request('/attract/current', timeout=7)
                info = json.loads(body)
                self.reply(200, {'connected': status == 200 and info.get('success') is True,
                                 'gif': info.get('gif'), 'audio_catalog_count': len(MINI_AUDIO_CATALOG),
                                 'movement': 'disabled', 'audio_automatic': False})
            except Exception as exc:
                self.reply(502, {'connected': False, 'error': 'mini_app_qr no responde: ' + type(exc).__name__})
        elif path == '/api/mini/audio/status':
            with MINI_AUDIO_LOCK:
                self.reply(200, dict(MINI_AUDIO_STATE))
        else:
            self.reply(404, {'error': 'Ruta no encontrada', 'ruta_solicitada': path, 'abrir_panel': f'http://{HOST}:{PORT}/'})

    def do_POST(self):
        if self.headers.get('Host') not in (f'{HOST}:{PORT}', f'localhost:{PORT}'):
            return self.reply(403, {'error': 'Host local no permitido'})
        if self.path in ('/api/drive/claim', '/api/drive/release', '/api/drive/input', '/api/drive/stop', '/api/drive/query-mode', '/api/drive/cycle-mode'):
            if self.headers.get('Origin') not in {f'http://{HOST}:{PORT}', f'http://localhost:{PORT}'}:
                return self.reply(403, {'error': 'Origen no permitido'})
            if self.headers.get('X-Robot-TTS-Token') != TOKEN:
                return self.reply(403, {'error': 'Credencial local inválida'})
            if self.headers.get_content_type() != 'application/json':
                return self.reply(415, {'error': 'Se requiere JSON'})
            try:
                size = int(self.headers.get('Content-Length', '0'))
                if size <= 0 or size > 1000:
                    return self.reply(413, {'error': 'Solicitud inválida'})
                data = json.loads(self.rfile.read(size))
            except (ValueError, TypeError, json.JSONDecodeError):
                return self.reply(400, {'error': 'JSON inválido'})
            action = self.path.rsplit('/', 1)[-1]
            if action == 'claim':
                result = DRIVE.claim()
            elif action == 'release':
                result = DRIVE.release()
            elif action == 'stop':
                result = DRIVE.stop()
            elif action == 'query-mode':
                result = DRIVE.query_mode()
            elif action == 'cycle-mode':
                result = DRIVE.cycle_mode()
            else:
                result = DRIVE.input(data)
            return self.reply(200 if result.get('ok') else 409, result)
        if self.path == '/api/mini/merchant/filter':
            # El cambio aplica un filtro temporal en mini_app_qr; no cambia pagos, motores ni la configuración de Tailscale.
            if self.headers.get('Origin') not in {f'http://{HOST}:{PORT}', f'http://localhost:{PORT}'}:
                return self.reply(403, {'error':'Origen no permitido'})
            if self.headers.get('X-Robot-TTS-Token') != TOKEN:
                return self.reply(403, {'error':'Credencial local inválida'})
            if self.headers.get_content_type() != 'application/json':
                return self.reply(415, {'error':'Se requiere JSON'})
            try:
                size=int(self.headers.get('Content-Length','0'))
                if not 1<=size<=120:
                    return self.reply(413,{'error':'Solicitud demasiado grande'})
                data=json.loads(self.rfile.read(size))
                if not isinstance(data,dict) or set(data)!={'merchantId'}:
                    return self.reply(400,{'error':'Se requiere merchantId, o null para Todos'})
                mid=data.get('merchantId')
                if mid is not None and (type(mid) is not int or not 0<mid<1000000000):
                    return self.reply(400,{'error':'Identificador de comercio inválido'})
                with MERCHANT_SWITCH_LOCK:
                    ps,praw=mini_request('/payment/polling-status',timeout=5)
                    pay=json.loads(praw)
                    if ps!=200 or pay.get('success') is not True or pay.get('isPolling') is not False or pay.get('phase') not in (None,'idle'):
                        return self.reply(409,{'error':'Hay un pago/pedido activo o no se pudo confirmar el estado. No se cambia el comercio.'})
                    available=get_available_merchants()
                    ids=[x['id'] for x in available]
                    if not ids:
                        return self.reply(409,{'error':'No se conocen los IDs de comercios instalados en Flutter.'})
                    if mid is not None and mid not in ids:
                        return self.reply(400,{'error':'El comercio elegido no existe en el catálogo actual de Flutter.'})
                    if mid is None:
                        # Advertido en pantalla: esto restablece la configuración temporal de filtros de productos.
                        payload={'reset':True,'reload':True}
                    else:
                        payload={'filterMode':'whitelist','merchants':{str(i):{'enabled':i==mid} for i in ids},'reload':True}
                    status, body=mini_request('/products/filter',payload,timeout=12,max_bytes=65536)
                    reply=json.loads(body)
                    if status!=200 or reply.get('success') is not True:
                        return self.reply(502,{'error':'Flutter no confirmó el filtro de comercios.'})
                    return self.reply(200,{'ok':True,'merchantId':mid,'detail':'Filtro aceptado por Flutter','reloadRequested':True})
            except urllib.error.HTTPError as exc:
                return self.reply(502,{'error':'Flutter rechazó el filtro HTTP '+str(exc.code)})
            except (urllib.error.URLError,OSError,TimeoutError,ValueError,TypeError,json.JSONDecodeError):
                return self.reply(502,{'error':'No se pudo cambiar el filtro de comercios por Tailscale'})
        if self.path == '/api/mini/ui/product':
            # Solo imagen de producto: POST /product ya existe en Flutter.
            # Sin audio, pago, motor ni cambio del comercio seleccionado.
            if self.headers.get('Origin') not in {f'http://{HOST}:{PORT}', f'http://localhost:{PORT}'}:
                return self.reply(403, {'error': 'Origen no permitido'})
            if self.headers.get('X-Robot-TTS-Token') != TOKEN:
                return self.reply(403, {'error': 'Credencial local inválida'})
            if self.headers.get_content_type() != 'application/json':
                return self.reply(415, {'error': 'Se requiere JSON'})
            try:
                size = int(self.headers.get('Content-Length', '0'))
                if not 1 <= size <= 150:
                    return self.reply(413, {'error': 'Solicitud inválida'})
                data = json.loads(self.rfile.read(size))
                if not isinstance(data, dict) or data:
                    return self.reply(400, {'error': 'Se esperaba un objeto JSON vacío'})
                status, body = mini_request('/product', {}, timeout=8)
                info = json.loads(body)
                if status != 200 or info.get('success') is not True:
                    return self.reply(502, {'error': 'Flutter no confirmó mostrar el producto'})
                return self.reply(200, {'ok': True, 'detail': 'Pantalla de producto solicitada sin audio'})
            except (ValueError, TypeError, json.JSONDecodeError):
                return self.reply(400, {'error': 'JSON inválido'})
            except (OSError, urllib.error.URLError, TimeoutError):
                return self.reply(502, {'error': 'No se pudo contactar mini_app_qr'})
        if self.path == '/api/mini/offer':
            # Solo permite tres acciones predefinidas; no convierte la ruta en proxy HTTP abierto.
            allowed_origins = {f'http://{HOST}:{PORT}', f'http://localhost:{PORT}'}
            if self.headers.get('Origin') not in allowed_origins:
                return self.reply(403, {'error': 'Origen no permitido'})
            if self.headers.get('X-Robot-TTS-Token') != TOKEN:
                return self.reply(403, {'error': 'Credencial local inválida'})
            if self.headers.get_content_type() != 'application/json':
                return self.reply(415, {'error': 'Se requiere JSON'})
            try:
                size = int(self.headers.get('Content-Length', '0'))
                if not 1 <= size <= 100:
                    return self.reply(413, {'error': 'Solicitud inválida'})
                data = json.loads(self.rfile.read(size))
                kind = data.get('kind') if isinstance(data, dict) else None
                path = MINI_OFFER_PATHS.get(kind) if isinstance(kind, str) else None
                if not path:
                    return self.reply(400, {'error': 'Oferta no permitida'})
                with MINI_AUDIO_LOCK:
                    if MINI_AUDIO_STATE['busy']:
                        return self.reply(409, {'error': 'Otro audio está en proceso. Detén el sonido o espera.'})
                    if time.monotonic() - MINI_LAST_SEND[0] < 5:
                        return self.reply(429, {'error': 'Espera 5 segundos entre audios'})
                    MINI_LAST_SEND[0] = time.monotonic()
                    MINI_AUDIO_STATE['job'] += 1
                    job = MINI_AUDIO_STATE['job']
                    MINI_AUDIO_STATE.update(busy=True, asset=kind, result='Oferta enviada; esperando a Flutter')
                __import__('threading').Thread(target=mini_offer_worker, args=(path, job), daemon=True).start()
                return self.reply(202, {'ok': True, 'accepted': True, 'kind': kind,
                                        'detail': 'Enviada a mini_app_qr; esperar reproducción. No se ha cobrado.'})
            except (ValueError, TypeError, json.JSONDecodeError):
                return self.reply(400, {'error': 'JSON inválido'})
        if self.path == '/api/mini/face/set':
            # El navegador solo puede solicitar IDs base, inventariados o seis IDs originales Halloween.
            # La confirmación de Flutter determina si realmente existe; nunca rutas o URL.
            allowed_origins = {f'http://{HOST}:{PORT}', f'http://localhost:{PORT}'}
            if self.headers.get('Origin') not in allowed_origins:
                return self.reply(403, {'error': 'Origen no permitido'})
            if self.headers.get('X-Robot-TTS-Token') != TOKEN:
                return self.reply(403, {'error': 'Credencial local inválida'})
            if self.headers.get_content_type() != 'application/json':
                return self.reply(415, {'error': 'Se requiere JSON'})
            try:
                size = int(self.headers.get('Content-Length', '0'))
                if not 1 <= size <= 160:
                    return self.reply(413, {'error': 'Solicitud inválida'})
                data = json.loads(self.rfile.read(size))
                if not isinstance(data, dict):
                    return self.reply(400, {'error': 'JSON inválido'})
                face_id = data.get('id')
                gif_name = MINI_FACE_CATALOG.get(face_id) if isinstance(face_id, str) else None
                # Solo estos seis IDs exactos admiten prueba directa. Se envían a
                # /attract/set sin asumir que están instalados ni aceptar rutas arbitrarias.
                if not gif_name and isinstance(face_id, str) and face_id in HALLOWEEN_CANDIDATES:
                    gif_name = face_id
                if not gif_name and isinstance(face_id,str):
                    discovered, source=face_inventory()
                    if source == 'flutter' and any(row['id']==face_id for row in discovered):
                        gif_name=face_id
                if not gif_name:
                    return self.reply(400, {'error': 'Carita no registrada en el catálogo ni en los seis IDs originales'})
                # Serializar cambios para que peticiones simultáneas no lleguen fuera de orden.
                with MINI_FACE_LOCK:
                    status, body = mini_request('/attract/set', {'gif': gif_name}, timeout=7)
                info = json.loads(body)
                if status != 200 or info.get('success') is not True or info.get('gif') != gif_name:
                    return self.reply(502, {'error': 'Flutter no confirmó el cambio de GIF'})
                return self.reply(200, {'ok': True, 'gif': gif_name, 'assetPath': info.get('assetPath')})
            except urllib.error.HTTPError as exc:
                return self.reply(502, {'error': 'mini_app_qr respondió HTTP ' + str(exc.code)})
            except (OSError, urllib.error.URLError, TimeoutError) as exc:
                return self.reply(502, {'error': 'No se pudo conectar al robot: ' + type(exc).__name__})
            except (ValueError, TypeError, json.JSONDecodeError):
                return self.reply(502, {'error': 'Respuesta inválida de mini_app_qr'})
        if self.path == '/api/audio/stop-all':
            # Parada multimedia prioritaria: nunca se bloquea por MINI_AUDIO_STATE.busy.
            if self.headers.get('Origin') not in {f'http://{HOST}:{PORT}', f'http://localhost:{PORT}'}:
                return self.reply(403, {'error': 'Origen no permitido'})
            if self.headers.get('X-Robot-TTS-Token') != TOKEN:
                return self.reply(403, {'error': 'Credencial local inválida'})
            if self.headers.get_content_type() != 'application/json':
                return self.reply(415, {'error': 'Se requiere JSON'})
            try:
                size = int(self.headers.get('Content-Length', '0'))
                if not 1 <= size <= 100:
                    return self.reply(413, {'error': 'Solicitud inválida'})
                args = json.loads(self.rfile.read(size))
                if args != {}:
                    return self.reply(400, {'error': 'No se aceptan parámetros'})
            except (ValueError, TypeError, json.JSONDecodeError):
                return self.reply(400, {'error': 'JSON inválido'})
            return self.reply(200, stop_all_robot_audio())
        if self.path in ('/api/mini/audio/play', '/api/mini/audio/stop'):
            # Mismo origen y CSRF del puente local; endpoint remoto nunca expuesto al navegador.
            allowed_origins = {f'http://{HOST}:{PORT}', f'http://localhost:{PORT}'}
            if self.headers.get('Origin') not in allowed_origins:
                return self.reply(403, {'error': 'Origen no permitido'})
            if self.headers.get('X-Robot-TTS-Token') != TOKEN:
                return self.reply(403, {'error': 'Credencial local inválida'})
            if self.headers.get_content_type() != 'application/json':
                return self.reply(415, {'error': 'Se requiere JSON'})
            try:
                length = int(self.headers.get('Content-Length', '0'))
                if not 1 <= length <= 2000:
                    return self.reply(413, {'error': 'Solicitud demasiado grande'})
                args = json.loads(self.rfile.read(length))
                if not isinstance(args, dict):
                    return self.reply(400, {'error': 'Datos inválidos'})
                if self.path == '/api/mini/audio/play':
                    clip_id = args.get('id')
                    asset = MINI_AUDIO_CATALOG.get(clip_id) if isinstance(clip_id,str) else None
                    # GitHub source is an *audio filename catalog*, not proof that Flutter
                    # has the matching asset installed. Only the exact allowlisted path
                    # from the public repository may be requested, never browser paths.
                    if not asset and isinstance(clip_id,str):
                        row=repo_media.find_clip(clip_id)
                        if row:asset=row['path']
                    if not asset:
                        return self.reply(400, {'error': 'Audio no autorizado en el catálogo local'})
                    with MINI_AUDIO_LOCK:
                        if MINI_AUDIO_STATE['busy']:
                            return self.reply(409, {'error': 'Ya hay un audio en proceso. Detén la reproducción anterior.'})
                        if time.monotonic()-MINI_LAST_SEND[0] < 5:
                            return self.reply(429, {'error': 'Espera 5 segundos entre audios'})
                        MINI_LAST_SEND[0]=time.monotonic()
                        MINI_AUDIO_STATE['job'] += 1
                        job=MINI_AUDIO_STATE['job']
                        MINI_AUDIO_STATE.update(busy=True, asset=clip_id, result='Orden recibida; pendiente del robot')
                    __import__('threading').Thread(target=mini_audio_worker, args=(asset,job),daemon=True).start()
                    return self.reply(202, {'ok': True, 'accepted': True, 'detail': 'Solicitud enviada en segundo plano. Puede tardar; verificar altavoz.'})
                else:
                    result = stop_all_robot_audio()
                    return self.reply(200, result)
            except urllib.error.HTTPError as exc:
                return self.reply(502, {'error': 'mini_app_qr respondió HTTP ' + str(exc.code)})
            except (OSError, urllib.error.URLError, TimeoutError) as exc:
                return self.reply(502, {'error': 'No se pudo conectar mini_app_qr: ' + type(exc).__name__})
            except (ValueError, TypeError, json.JSONDecodeError):
                return self.reply(400, {'error': 'JSON inválido'})
        if self.path != '/api/tts':
            return self.reply(404, {'error': 'Ruta no encontrada'})
        allowed_origins = {f'http://{HOST}:{PORT}', f'http://localhost:{PORT}'}
        if self.headers.get('Origin') not in allowed_origins:
            return self.reply(403, {'error': 'Origen no permitido'})
        if self.headers.get('X-Robot-TTS-Token') != TOKEN:
            return self.reply(403, {'error': 'Token local invalido'})
        if self.headers.get_content_type() != 'application/json':
            return self.reply(415, {'error': 'Formato requerido: application/json'})
        if not TTS_BEARER_TOKEN:
            return self.reply(412, {'error': 'Falta autenticar el servicio TTS. Introduce el token oficial en la terminal al iniciar el servidor; nunca en el HTML.'})
        try:
            size = int(self.headers.get('Content-Length', '0'))
            if size <= 0 or size > 4096:
                return self.reply(413, {'error': 'Mensaje demasiado grande'})
            data = json.loads(self.rfile.read(size))
            if not isinstance(data, dict):
                return self.reply(400, {'error': 'Solicitud invalida'})
            phrase = data.get('text', '')
            if not isinstance(phrase, str) or not (1 <= len(phrase.strip()) <= 280):
                return self.reply(400, {'error': 'Texto requerido (1 a 280 caracteres)'})
            if data.get('speaker_id', 'default') != 'default' or data.get('language', 'es') != 'es':
                return self.reply(400, {'error': 'Solo se permite voz default en español durante la prueba'})
            if time.monotonic() - LAST_SEND[0] < 3:
                return self.reply(429, {'error': 'Espera 3 segundos entre mensajes'})
            LAST_SEND[0] = time.monotonic()
            result, _ = get_remote('/synthesize/play', method='POST', payload={
                'text': phrase.strip(), 'speaker_id': 'default', 'language': 'es'
            }, timeout=120, drain=True)
            if 200 <= result < 300:
                return self.reply(200, {'ok': True, 'detail': 'TTS aceptó el mensaje. Comprueba el altavoz del robot.'})
            return self.reply(502, {'error': 'TTS no confirmó la reproducción'})
        except urllib.error.HTTPError as exc:
            return self.reply(502, {
                'error': f'El servicio del robot rechazó la reproducción (HTTP {exc.code}).',
                'pista': ('Comprueba /api/tts/diagnostic. HTTP 401 indica token inválido; '
                          'HTTP 403 puede indicar ausencia de autorización. '
                          'No compartas contraseñas ni tokens.')
            })
        except (urllib.error.URLError, TimeoutError, OSError):
            return self.reply(502, {'error': 'No se pudo contactar el servicio TTS desde esta computadora'})
        except (ValueError, TypeError, json.JSONDecodeError):
            return self.reply(400, {'error': 'Datos JSON inválidos'})


if __name__ == '__main__':
    if not PAGE.is_file():
        print('ERROR: mesero06_panel_glass_v13.html debe estar junto a este archivo.')
        sys.exit(1)
    if DRIVE_ENABLED:
        print('\nATENCION: ESTA SESION PERMITE CONTROLAR FISICAMENTE AL ROBOT.')
        print('Solo en zona despejada, con una persona junto al robot y STOP fisico accesible.')
        print(f'Velocidad seleccionada inicial: 20 RPM. Limite: {MAX_TEST_SPEED} RPM (solo si el operador autoriza movimiento).')
        try:
            respuesta = input('¿Confirmas que estas en condiciones de probar el control real? Escribe SI: ')
        except (KeyboardInterrupt, EOFError):
            respuesta = ''
        if respuesta.strip().upper() != 'SI':
            print('Control real NO activado. No se iniciara el servidor.')
            sys.exit(2)
    if not TTS_BEARER_TOKEN and sys.stdin.isatty():
        try:
            TTS_BEARER_TOKEN = getpass.getpass('Token OFICIAL TTS (opcional, Enter para omitir): ').strip()
        except (KeyboardInterrupt, EOFError):
            TTS_BEARER_TOKEN = ''
    print('\nMESERO 06 V13 · CENTRO LOCAL · ' + ('PRUEBA REAL SUPERVISADA' if DRIVE_ENABLED else 'MOVIMIENTO DESACTIVADO'))
    print('Credencial TTS cargada:', 'SI (oculta)' if TTS_BEARER_TOKEN else 'NO (solo lectura)')
    print('Se abrira el panel en: http://127.0.0.1:8765/')
    print('Control fisico autorizado en este inicio:' , 'SI' if DRIVE_ENABLED else 'NO')
    print('Limite de velocidad del puente:', MAX_TEST_SPEED, 'RPM')
    print('Pulsa Comprobar TTS; solo se reproducira audio al pulsar Enviar.')
    print('Cierra este servidor con Ctrl+C. No lo publiques en Internet.\n')
    try:
        with http.server.ThreadingHTTPServer((HOST, PORT), Handler) as server:
            try:
                webbrowser.open(f'http://{HOST}:{PORT}/')
            except Exception:
                pass  # Se puede abrir manualmente en el navegador.
            server.serve_forever()
    except KeyboardInterrupt:
        print('\nServidor detenido.')
    except OSError as exc:
        print(f'ERROR al iniciar el servidor en el puerto {PORT}: {exc}')
        print('Quizas ya existe otra ventana ejecutando este mismo servidor. Cierra esa ventana con Ctrl+C.')
        sys.exit(1)
