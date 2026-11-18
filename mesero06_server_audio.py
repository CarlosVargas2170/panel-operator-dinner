"""Audios autorizados por el panel original: solo lectura del catálogo.

El catálogo remoto se lee exclusivamente desde una URL completa de GET /api/panel
facilitada por el operador, sin inventar parámetros ni almacenar credenciales.
El backend remoto decide qué botones existen; este módulo solamente admite
assets de audio de la lista de botones que ya devolvió ese backend.

Dos audios observados en HAR real se conservan como copia de emergencia, incluso
si el servidor remoto todavía no está configurado. Nada se instala en Flutter.
"""
import getpass
import hashlib
import ipaddress
import json
import os
import re
import socket
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

# Fuentes observadas en HAR proporcionado por el operador, no enlaces inventados.
OBSERVED_AUDIO = (
    ('🎂 FELIZ CUMPLEAÑOS', 'https://res.cloudinary.com/zrwcfuqw/video/upload/v1793049851/robotics/audios/feliz_cumpleanos_pq4e-e1fbea6a.wav'),
    ('🎵 APACHE APACHE', 'https://res.cloudinary.com/zrwcfuqw/video/upload/v1794765165/robotics/audios/apache_apache_bwyf-0ff9a415.mp3'),
)
_LOCK = threading.RLock()
# Catálogo real: se configura fuera de GitHub mediante variables del PC.
# Si no hay credencial válida, conservamos los dos clips verificados del HAR.
_URL = os.environ.get('MESERO06_PANEL_URL', 'https://backend.dinner.nexarobotics.org/api/panel?robot=mesero-6').strip()
_AUTH_HEADER = os.environ.get('MESERO06_PANEL_AUTH_HEADER', '').strip()
_AUTH_VALUE = os.environ.get('MESERO06_PANEL_TOKEN', '').strip()
if not (_URL and _AUTH_HEADER and _AUTH_VALUE and re.fullmatch(r'[A-Za-z0-9-]{1,60}', _AUTH_HEADER)
        and len(_AUTH_VALUE) <= 2048 and '\r' not in _AUTH_VALUE and '\n' not in _AUTH_VALUE):
    _URL = _AUTH_HEADER = _AUTH_VALUE = ''
_LIVE = None
_LAST_CHECK = 0.0
_STATUS = 'Dos archivos observados en HAR; sincronización automática no configurada'
_MIN_REFRESH_SECONDS = 120
_MAX_CATALOG_BYTES = 1024 * 1024
_AUDIO_FORMATS = ('.wav', '.mp3', '.ogg', '.m4a')


def valid_audio_source(source):
    if not isinstance(source, str) or not 1 <= len(source) <= 550:
        return False
    if source.startswith('audio/'):
        return (not any(part in ('', '.', '..') for part in source.split('/'))
                and re.fullmatch(r'audio/[a-zA-Z0-9_./ -]+', source) is not None
                and source.lower().endswith(_AUDIO_FORMATS))
    try:
        url = urllib.parse.urlsplit(source)
    except ValueError:
        return False
    return (url.scheme == 'https' and url.netloc == 'res.cloudinary.com'
            and url.username is None and not url.query and not url.fragment
            and url.path.startswith('/zrwcfuqw/video/upload/')
            and '/robotics/audios/' in url.path
            and url.path.lower().endswith(_AUDIO_FORMATS))


def _id(source):
    # El nombre subido por Cloudinary permanece estable aunque cambie /v123/.
    key = source
    if source.startswith('https:'):
        key = re.sub(r'/v\d+/', '/', urllib.parse.urlsplit(source).path)
    return 'sv_' + hashlib.sha256(key.encode('utf-8')).hexdigest()[:16]


def _new_item(source, label, category, observed=False):
    if not valid_audio_source(source):
        return None
    label = label if isinstance(label, str) else ''
    category = category if isinstance(category, str) else ''
    return {
        'id': _id(source), 'asset': source,
        'name': (label.strip() or urllib.parse.unquote(source.split('/')[-1]))[:110],
        'category': (category.strip() or 'Audios del servidor')[:75],
        'icon': '🎵', 'fromServer': True,
        'observedInHar': observed, 'defaultVolume': 1.0, 'force': False,
        'displayText': '',
    }


def _observed():
    return [_new_item(url, title, 'Servidor · archivos identificados', True)
            for title, url in OBSERVED_AUDIO]


def _secure_catalog_url(url):
    """URL exacta conocida del catálogo, sin cookies/token en el enlace."""
    if not isinstance(url, str) or len(url) > 2000:
        raise ValueError('URL demasiado larga o inválida')
    try:
        p = urllib.parse.urlsplit(url)
        host = (p.hostname or '').lower()
    except ValueError as exc:
        raise ValueError('URL inválida') from exc
    if (p.scheme != 'https' or not host or p.username or p.password
            or p.fragment or p.port not in (None, 443)
            or not (p.path == '/api/panel' or p.path.startswith('/api/panel/'))):
        raise ValueError('Se requiere la URL HTTPS real de GET /api/panel, sin credenciales')
    if any(k.lower() in ('token', 'apikey', 'api_key', 'key', 'authorization', 'password')
           for k, v in urllib.parse.parse_qsl(p.query)):
        raise ValueError('No pongas credenciales en la URL')
    if host == 'localhost' or host.endswith('.local') or host.endswith('.localhost'):
        raise ValueError('El backend debe usar un dominio público HTTPS')
    # Evitar que la PC haga peticiones HTTP hacia Tailscale, localhost o red interna.
    try:
        infos = socket.getaddrinfo(host, 443, type=socket.SOCK_STREAM)
        if not infos or not all(ipaddress.ip_address(t[4][0]).is_global for t in infos):
            raise ValueError('La URL apunta a una IP privada')
    except socket.gaierror as exc:
        raise ValueError('No se pudo resolver el servidor remoto') from exc
    return url


def configure_interactive():
    """Opción de inicio en BAT secundario. Token únicamente en la memoria del proceso."""
    print('\n=== CATÁLOGO DE AUDIOS DEL SERVIDOR ORIGINAL ===')
    print('Pega la URL completa obtenida de Network > GET /api/panel.')
    print('No pegues aquí una contraseña ni una URL con tokens.')
    try:
        url = input('URL GET /api/panel (Enter: usar dos audios conocidos): ').strip()
        if not url:
            print('Sin API externa; se usarán los dos audios observados.');return
        url = _secure_catalog_url(url)
        print('Si la solicitud exige autenticación, revisa Network > Headers.')
        print('Ejemplos de nombre de cabecera: Authorization o X-Panel-Token.')
        hdr = input('Nombre exacto de la cabecera (Enter si no requiere): ').strip()
        val = ''
        if hdr:
            if not re.fullmatch(r'[A-Za-z0-9-]{1,60}', hdr):
                raise ValueError('Nombre de cabecera no válido')
            val = getpass.getpass('Valor completo de la cabecera, oculto (no se guarda): ').strip()
            if not 1 <= len(val) <= 2048 or '\r' in val or '\n' in val:
                raise ValueError('Valor de cabecera no válido')
        with _LOCK:
            global _URL, _AUTH_HEADER, _AUTH_VALUE, _LAST_CHECK
            _URL, _AUTH_HEADER, _AUTH_VALUE = url, hdr, val
            _LAST_CHECK = 0.0
        print('Configuración temporal aplicada. Sin archivos de contraseñas.\n')
    except (KeyboardInterrupt, EOFError):
        print('\nSe mantiene el catálogo conocido sin sincronización.')
    except ValueError as exc:
        print('No se configuró la sincronización:', str(exc))


def _extract_items(response):
    if not isinstance(response, dict):
        raise ValueError('El catálogo no es un objeto JSON')
    root = response.get('data', response)
    if not isinstance(root, dict) or not isinstance(root.get('sections'), list):
        raise ValueError('Falta data.sections en GET /api/panel')
    items = {}
    for section in root['sections'][:200]:
        if not isinstance(section, dict):
            continue
        category = section.get('title') or 'Audios del servidor'
        for button in (section.get('buttons') or [])[:300]:
            if not isinstance(button, dict):
                continue
            if button.get('action') not in ('quick_play', 'greet_with_audio'):
                continue
            audio = button.get('audio')
            if not isinstance(audio, dict):
                continue
            source = audio.get('url') or audio.get('file_path') or ''
            label = button.get('label') or audio.get('display_text') or ''
            item = _new_item(source, label, category)
            if item:
                vol = audio.get('default_volume')
                if isinstance(vol, (int, float)) and not isinstance(vol, bool) and 0 <= vol <= 1:
                    item['defaultVolume'] = float(vol)
                item['force'] = button.get('force') is True
                display_text = audio.get('display_text')
                if isinstance(display_text, str):
                    item['displayText'] = display_text[:180]
                items[item['id']] = item
    return list(items.values())[:350]


def refresh(force=False):
    global _LAST_CHECK, _STATUS, _LIVE
    with _LOCK:
        if not _URL:
            return
        if not force and (time.monotonic() - _LAST_CHECK < _MIN_REFRESH_SECONDS):
            return
        _LAST_CHECK = time.monotonic()
        url, hdr, val = _URL, _AUTH_HEADER, _AUTH_VALUE
    try:
        url = _secure_catalog_url(url)
        headers = {'Accept': 'application/json', 'User-Agent': 'Mesero06-audio-catalog/1.0'}
        if hdr:
            headers[hdr] = val
        req = urllib.request.Request(url, headers=headers, method='GET')
        # No aceptar redirects: el token nunca debe viajar a un host inesperado.
        class NoRedirect(urllib.request.HTTPRedirectHandler):
            def redirect_request(self, req, fp, code, msg, headers, newurl):
                return None
        opener = urllib.request.build_opener(NoRedirect)
        with opener.open(req, timeout=12) as response:
            data = response.read(_MAX_CATALOG_BYTES + 1)
        if len(data) > _MAX_CATALOG_BYTES:
            raise ValueError('Catálogo excesivamente grande')
        items = _extract_items(json.loads(data.decode('utf-8')))
        with _LOCK:
            # La respuesta GET /api/panel autorizada es la fuente de verdad.
            _LIVE = items
            _STATUS = f'Catálogo del servidor consultado: {len(items)} audios autorizados'
    except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, OSError,
            ValueError, TypeError, UnicodeDecodeError, json.JSONDecodeError):
        with _LOCK:
            _STATUS = 'Error al consultar GET /api/panel; se mantiene la última copia disponible'


def catalog(refresh_remote=False):
    refresh(force=refresh_remote)
    with _LOCK:
        items = list(_LIVE) if _LIVE is not None else _observed()
        return {
            'ok': True, 'items': items, 'count': len(items),
            'automatic': bool(_URL), 'configured': bool(_URL),
            'source': 'backend' if _LIVE is not None else 'har_observado',
            'status': _STATUS,
            'note': 'Las URL son assets de Cloudinary. No se modificó Flutter ni se instalaron archivos en el robot.',
        }


def find_clip(item_id):
    if not isinstance(item_id, str) or not re.fullmatch(r'sv_[0-9a-f]{16}', item_id):
        return None
    with _LOCK:
        items = _LIVE if _LIVE is not None else _observed()
        return next((item for item in items if item['id'] == item_id), None)
