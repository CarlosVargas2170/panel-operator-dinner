"""Biblioteca multimedia aprobada del repositorio de origen.

Sincroniza *solo* nombres de audio de GitHub main. No ejecuta JS de GitHub,
no mueve motores, no modifica Flutter ni descarga audios al robot.
"""
import hashlib
import json
import mimetypes
import re
import threading
import time
import urllib.request
import urllib.parse
from pathlib import Path

ROOT = Path(__file__).resolve().parent
CATALOG_FILE = ROOT / 'github_audio_catalog.json'
CACHE = ROOT / 'audio_original'
TREE_URL = 'https://api.github.com/repos/CarlosVargas2170/control-remote-robot-mesero/git/trees/main?recursive=1'
RAW_ROOT = 'https://raw.githubusercontent.com/CarlosVargas2170/control-remote-robot-mesero/main/'
MAX_MEDIA_BYTES = 16 * 1024 * 1024
MAX_TREE_BYTES = 2 * 1024 * 1024
MIN_REFRESH_SECONDS = 600
_LOCK = threading.RLock()
_LAST_CHECK = 0.0
_LAST_STATUS = 'Copia local cargada'


def valid_audio_path(path):
    if not isinstance(path,str) or not 6 <= len(path) <= 150:return False
    if not path.startswith('audio/') or '..' in path.split('/') or '\\' in path:return False
    if not re.fullmatch(r'audio/[a-zA-Z0-9_./ -]+', path):return False
    if any(p in ('','.','..') for p in path.split('/')):return False
    return Path(path).suffix.lower() in ('.mp3','.wav','.m4a','.ogg')


def clip_id(path):return 'gh_'+hashlib.sha1(path.encode('utf-8')).hexdigest()[:12]


def friendly_name(path):
    name=Path(path).stem.replace('_',' ').replace('-',' ')
    if Path(path).parent.name=='kiky':name='Kíky · '+name
    return name[:100]


def _read():
    data=json.loads(CATALOG_FILE.read_text('utf-8'))
    items=[x for x in data.get('items',[]) if isinstance(x,dict) and valid_audio_path(x.get('path')) and x.get('id')==clip_id(x['path'])]
    return items


def catalog(refresh=False):
    global _LAST_STATUS
    if refresh:
        sync_catalog()
    with _LOCK:
        rows=_read()
        for r in rows:
            r['local']=(CACHE / r['path'].removeprefix('audio/')).is_file()
        return {'ok':True,'repository':'CarlosVargas2170/control-remote-robot-mesero',
                'branch':'main','items':rows,'count':len(rows), 'sync':_LAST_STATUS,
                'note':'GitHub solo actualiza el catálogo. Los archivos no se instalan en el robot automáticamente.'}


def sync_catalog():
    global _LAST_CHECK,_LAST_STATUS
    with _LOCK:
        if time.monotonic()-_LAST_CHECK < MIN_REFRESH_SECONDS:return
        _LAST_CHECK=time.monotonic()
        try:
            req=urllib.request.Request(TREE_URL,headers={
                'User-Agent':'PanelRobot-catalog-reader/1.0', 'Accept':'application/vnd.github+json'})
            with urllib.request.urlopen(req, timeout=8) as response:
                body=response.read(MAX_TREE_BYTES+1)
            if len(body)>MAX_TREE_BYTES:raise ValueError('Inventario demasiado grande')
            data=json.loads(body)
            if data.get('truncated') is True:raise ValueError('Inventario remoto incompleto')
            paths=sorted({r.get('path') for r in data.get('tree',[]) if r.get('type')=='blob'
                          and valid_audio_path(r.get('path'))})
            if not paths:raise ValueError('El inventario remoto llegó vacío; se conserva la copia local')
            old={r['path']:r for r in _read()}
            rows=[]
            for path in paths[:350]:
                r=old.get(path,{'id':clip_id(path),'path':path,'name':friendly_name(path),'emoji':'🎵'})
                rows.append({k:v for k,v in r.items() if k in ('id','path','name','emoji','bytes')})
            p=CATALOG_FILE.with_name('github_audio_catalog.next.json')
            p.write_text(json.dumps({'repository':'CarlosVargas2170/control-remote-robot-mesero',
                   'branch':'main','source':'GitHub main metadata','items':rows},ensure_ascii=False,indent=2),'utf-8')
            p.replace(CATALOG_FILE)
            _LAST_STATUS='Catálogo actualizado desde GitHub main'
        except Exception as ex:
            _LAST_STATUS=f'Sin actualización remota ({type(ex).__name__}); se conserva la copia local'


def find_clip(item_id):
    with _LOCK:
        return next((r for r in _read() if r['id']==item_id),None)


def local_media(item_id):
    row=find_clip(item_id)
    if not row:return None
    path=CACHE / row['path'].removeprefix('audio/')
    # All paths are confined to the cache root.
    if not path.resolve().is_relative_to(CACHE.resolve()):return None
    if not path.is_file():
        url=RAW_ROOT+urllib.parse.quote(row['path'],safe='/')
        req=urllib.request.Request(url,headers={'User-Agent':'PanelRobot-media-preview/1.0'})
        with urllib.request.urlopen(req,timeout=14) as response:
            data=response.read(MAX_MEDIA_BYTES+1)
        if len(data)>MAX_MEDIA_BYTES:raise ValueError('Audio demasiado grande')
        if not data:raise ValueError('No llegó el audio de GitHub')
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    if path.stat().st_size>MAX_MEDIA_BYTES:raise ValueError('Audio demasiado grande')
    mime={'.wav':'audio/wav','.mp3':'audio/mpeg','.m4a':'audio/mp4','.ogg':'audio/ogg'}[path.suffix.lower()]
    return path,mime
