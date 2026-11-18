'''Puente HLS HTTPS del Robot Mesero 06.

Reutiliza la lógica de la otra consola de flota del usuario (main.py):
lista blanca de streams, reescritura de manifiestos HLS y retransmisión segura de segmentos.
No toca comandos de movimiento ni requiere modificar el servidor DVR.
Reproducción exclusivamente por solicitud del visitante (no precarga).
'''
from __future__ import annotations

import os
import re
import logging
from urllib.parse import quote, unquote, urljoin, urlsplit

import httpx
from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import HTMLResponse, Response, StreamingResponse

hls_router = APIRouter()
log = logging.getLogger('robot06.hls')
ALLOWED_STREAMS = frozenset({'SERBOT06'})
RESOURCE_RE = re.compile(r'^[A-Za-z0-9._~/-]{1,480}$')
ALLOWED_EXT = frozenset({'.m3u8', '.ts', '.m4s', '.mp4', '.aac', '.mp3', '.vtt', '.key'})
MEDIA_TYPES = {'.ts': 'video/mp2t', '.m4s': 'video/iso.segment',
    '.mp4': 'video/mp4', '.aac': 'audio/aac', '.mp3': 'audio/mpeg',
    '.vtt': 'text/vtt', '.key': 'application/octet-stream'}
QUERY_RE = re.compile(r'^[A-Za-z0-9_%+.,:=&-]*$')


def video_enabled() -> bool:
    return os.getenv('CAMERA_HLS_PROXY_ENABLED', '0').strip().lower() in ('1','true','on','yes')


def base_url() -> str:
    # Dominio que ya utiliza el panel de flota para Flussonic/DVR.
    base = os.getenv('CAMERA_HLS_BASE_URL', 'http://dvr.nexarobotics.org').strip().rstrip('/')
    p = urlsplit(base)
    if p.scheme not in ('http','https') or not p.hostname or p.username or p.password or p.path not in ('','/') or p.query or p.fragment:
        raise HTTPException(503, 'Configura CAMERA_HLS_BASE_URL con la dirección base HTTP(S) del DVR')
    return base


def safe_resource(path: str) -> str:
    decoded = unquote(path)
    if (not RESOURCE_RE.fullmatch(decoded) or
        any(x in ('','.','..') for x in decoded.split('/')) or
        '.' + decoded.rsplit('.',1)[-1].lower() not in ALLOWED_EXT):
        raise HTTPException(404,'Recurso HLS no permitido')
    return decoded


def proxy_link(uri: str, origin: str, stream: str, path: str) -> str:
    remote = urljoin(f'{origin}/{stream}/{path}',uri)
    p = urlsplit(remote)
    base = urlsplit(origin)
    if p.scheme != base.scheme or p.netloc != base.netloc or not p.path.startswith('/'+stream+'/') or p.fragment:
        raise ValueError('Manifiesto con referencia externa no permitida')
    relative = safe_resource(p.path[len(stream)+2:])
    if len(p.query)>512 or not QUERY_RE.fullmatch(p.query):
        raise ValueError('Parámetros HLS no admitidos')
    return '/api/v3/video/'+stream+'/'+quote(relative,safe='/._~-')+('?' + p.query if p.query else '')


def rewrite_manifest(content: str, origin: str, stream: str, path: str) -> str:
    lines=[]
    for line in content.splitlines():
        if not line or (line.lstrip().startswith('#') and 'URI="' not in line):
            lines.append(line)
        elif line.startswith('#'):
            lines.append(re.sub(r'URI="([^"]+)"',
                lambda m: 'URI="'+proxy_link(m.group(1),origin,stream,path)+'"',line))
        else:
            lines.append(proxy_link(line.strip(),origin,stream,path))
    return '\n'.join(lines)+'\n'


@hls_router.get('/api/v3/video/{stream}/{resource_path:path}')
async def hls_resource(stream: str,resource_path: str,request: Request):
    if not video_enabled():
        raise HTTPException(503,'Vídeo deshabilitado por configuración')
    if stream not in ALLOWED_STREAMS:
        raise HTTPException(404,'Stream no autorizado')
    resource=safe_resource(resource_path)
    query=request.url.query
    if len(query)>512 or not QUERY_RE.fullmatch(query):
        raise HTTPException(400,'Parámetros HLS no admitidos')
    origin=base_url()
    remote=f'{origin}/{stream}/'+quote(resource,safe='/._~-')
    if query: remote+='?'+query
    suffix='.'+resource.rsplit('.',1)[-1].lower()
    headers={'Accept':'application/vnd.apple.mpegurl,video/*,*/*'}
    requested_range=request.headers.get('range','')
    if requested_range:
        if not re.fullmatch(r'bytes=\d{0,12}-\d{0,12}',requested_range):
            raise HTTPException(416,'Rango de vídeo inválido')
        headers['Range']=requested_range
    client=httpx.AsyncClient(timeout=httpx.Timeout(15.0,connect=5.0),
                             follow_redirects=False,trust_env=False)
    try:
        upstream=await client.send(client.build_request('GET',remote,headers=headers),stream=True)
    except httpx.HTTPError:
        await client.aclose()
        raise HTTPException(502,'Render no puede conectar con el servidor DVR') from None
    if upstream.status_code not in (200,206):
        status=upstream.status_code
        await upstream.aclose()
        await client.aclose()
        raise HTTPException(502,f'El DVR respondió HTTP {status}')
    if suffix=='.m3u8':
        try:
            body=await upstream.aread()
            if len(body)>800_000 or not body.lstrip().startswith(b'#EXTM3U'):
                raise ValueError('Respuesta no es lista HLS')
            manifest=rewrite_manifest(body.decode('utf-8'),origin,stream,resource)
        except (ValueError,UnicodeError,HTTPException):
            raise HTTPException(502,'Manifiesto HLS inválido o con recursos externos') from None
        finally:
            await upstream.aclose()
            await client.aclose()
        return Response(manifest,media_type='application/vnd.apple.mpegurl',
            headers={'Cache-Control':'no-store','X-Content-Type-Options':'nosniff'})

    async def content():
        try:
            sent=0
            async for chunk in upstream.aiter_bytes(chunk_size=65536):
                sent+=len(chunk)
                if sent>24_000_000:
                    log.warning('Segmento de vídeo demasiado grande: %s',stream)
                    break
                yield chunk
        finally:
            await upstream.aclose()
            await client.aclose()
    public_headers={'Cache-Control':'no-store','X-Content-Type-Options':'nosniff'}
    for key in ('content-range','accept-ranges'):
        if upstream.headers.get(key):
            public_headers[key.title()]=upstream.headers[key]
    return StreamingResponse(content(),status_code=upstream.status_code,
                             media_type=MEDIA_TYPES.get(suffix,'application/octet-stream'),
                             headers=public_headers)


VIEWER='''<!doctype html><html lang="es"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>HLS · Mesero 06</title>
<script defer src="https://cdn.jsdelivr.net/npm/hls.js@1.6.0/dist/hls.min.js"></script>
<style>
:root{color-scheme:dark;font-family:system-ui,Segoe UI,sans-serif}
*{box-sizing:border-box}body{margin:0;background:#0b1118;color:#e7ecf2;padding:20px}
main{max-width:1100px;margin:auto}header{display:flex;justify-content:space-between;align-items:center;gap:12px;flex-wrap:wrap;margin-bottom:14px}
h1{font-size:22px;margin:0}small{color:#98aabd}button,a{font:700 14px system-ui;border:1px solid #546173;border-radius:10px;padding:11px 17px;color:#fff;background:#265da3;cursor:pointer;text-decoration:none}
button:disabled{opacity:.45;cursor:not-allowed}#stop{background:#5d3034}a{background:#242e3a}section{padding:15px;background:#17212b;border:1px solid #334350;border-radius:16px}
video{display:block;width:100%;max-height:77vh;aspect-ratio:16/9;object-fit:contain;background:black;border-radius:10px}
#status{font-size:13px;min-height:22px;color:#a9c4d5;margin:12px 2px 0}
</style></head><body><main><header><div><h1>📹 Cámara HLS · Mesero 06</h1>
<small>La reproducción comienza solo al pulsar Reproducir. No transmite mientras está detenida.</small></div>
<div style="display:flex;gap:8px;flex-wrap:wrap"><a href="/">Volver al panel</a><button id="play">▶ Reproducir</button><button id="stop" disabled>■ Detener</button></div>
</header><section><video id="video" controls playsinline preload="none"></video>
<p id="status" role="status">Cámara apagada · sin consumir vídeo.</p></section></main>
<script>
(()=>{const video=document.querySelector('#video'),play=document.querySelector('#play'),stop=document.querySelector('#stop'),status=document.querySelector('#status');
const source='/api/v3/video/SERBOT06/index.m3u8';let hls=null,started=false;
function say(text){status.textContent=text}
function cleanup(){if(hls){hls.destroy();hls=null}video.pause();video.removeAttribute('src');video.load();started=false;play.disabled=false;stop.disabled=true}
stop.addEventListener('click',()=>{cleanup();say('Cámara detenida · sin descargar segmentos HLS.')});
play.addEventListener('click',()=>{if(started)return;started=true;play.disabled=true;stop.disabled=false;say('Conectando al DVR por HTTPS del panel…');
if(video.canPlayType('application/vnd.apple.mpegurl')){video.src=source;video.play().catch(()=>say('Pulsa ▶ en el reproductor para iniciar.'));return;}
if(!window.Hls||!Hls.isSupported()){cleanup();say('Este navegador no dispone de reproducción HLS.');return;}
hls=new Hls({enableWorker:true,maxBufferLength:15,backBufferLength:10});
hls.on(Hls.Events.ERROR,(_event,data)=>{if(data.fatal){const code=data.response?.code||'';cleanup();say('No se pudo abrir el HLS'+(code?' (HTTP '+code+')':'')+'. Verifica que Render alcance el DVR.');}});
hls.attachMedia(video);hls.on(Hls.Events.MEDIA_ATTACHED,()=>hls.loadSource(source));
hls.on(Hls.Events.MANIFEST_PARSED,()=>{video.play().catch(()=>say('Pulsa ▶ en el reproductor.'));say('HLS conectado.');});
});
video.addEventListener('error',()=>{if(started){cleanup();say('Error de reproducción. Comprueba el stream SERBOT06.')}});
window.addEventListener('pagehide',cleanup);
})();
</script></body></html>'''

@hls_router.get('/ver-hls')
def viewer():
    # Panel público: visor sin video precargado y sin endpoints de control físico.
    return HTMLResponse(VIEWER,headers={'Cache-Control':'no-store',
        'X-Content-Type-Options':'nosniff','Referrer-Policy':'no-referrer',
        'Content-Security-Policy':"default-src 'self'; script-src 'self' 'unsafe-inline' https://cdn.jsdelivr.net; style-src 'self' 'unsafe-inline'; media-src 'self'; connect-src 'self'; frame-src 'none'; object-src 'none'; base-uri 'none'"})
