"""Pruebas offline: verifican autenticación y rutas, nunca mueven motores."""
import importlib
import os
from pathlib import Path

os.environ['PANEL_USER']='operador'
os.environ['PANEL_PASSWORD']='UnaClaveDePruebaMuyLarga123!'
os.environ['PANEL_SESSION_SECRET']='secreto-de-pruebas-largo-y-unico-no-produccion'
os.environ['PANEL_PUBLIC_URL']='https://testserver'
os.environ['MESERO06_ENABLE_DRIVE']='0'
os.environ['CAMERA_HLS_PROXY_ENABLED']='0'

from fastapi.testclient import TestClient


def test_login_and_private_panel():
    from nexus_panel_app import app
    with TestClient(app, base_url='https://testserver') as c:
        r=c.get('/',follow_redirects=False)
        assert r.status_code==303 and r.headers['location']=='/login'
        assert c.get('/api/drive/status').status_code==401
        assert c.post('/login',data={'username':'operador','password':'incorrecta'},headers={'origin':'https://testserver'}).status_code==401
        r=c.post('/login',data={'username':'operador','password':'UnaClaveDePruebaMuyLarga123!'},headers={'origin':'https://testserver'},follow_redirects=False)
        assert r.status_code==303
        assert r.cookies['nexus_mesero06_session']
        page=c.get('/')
        assert page.status_code==200
        assert 'nexus-supervised' in page.text
        assert 'const local=true;' in page.text
        assert 'content="__LOCAL_TTS_TOKEN__"' not in page.text
        assert c.get('/api/drive/status').status_code==200
        assert c.get('/api/mini/halloween').status_code==200
        assert c.get('/ver-hls').status_code==200
        assert c.post('/api/drive/claim',json={}).status_code==403  # CSRF
        assert c.get('/api/other/internals').status_code==404
        assert c.get('/api/v3/video/SERBOT06/index.m3u8').status_code in (403,503)


def test_csrf_and_no_unsafe_stop():
    from nexus_panel_app import app
    with TestClient(app,base_url='https://testserver') as c:
        c.post('/login',data={'username':'operador','password':'UnaClaveDePruebaMuyLarga123!'},headers={'origin':'https://testserver'})
        page=c.get('/')
        # HTMLParser would suffice; BeautifulSoup not needed on server, only in test.
        import re
        match=re.search(r'<meta content="([^"]+)" name="local-tts-token"',page.text)
        assert match
        token=match.group(1)
        bad=c.post('/api/drive/claim',json={},headers={'origin':'https://attacker.invalid','x-robot-tts-token':token})
        assert bad.status_code==403
        denied=c.post('/api/drive/claim',json={},headers={'origin':'https://testserver','x-robot-tts-token':token})
        assert denied.status_code==409  # control disabled in tests, never falsely successful
        stop=c.post('/api/drive/stop',json={},headers={'origin':'https://testserver','x-robot-tts-token':token})
        assert stop.status_code==200


def test_offline_resources_count():
    root=Path(__file__).resolve().parents[1]
    assert len([p for p in (root/'audio_original').rglob('*') if p.is_file()])==57
    import json
    data=json.loads((root/'halloween_catalogo_publico.json').read_text('utf8'))
    assert len(data['faces'])>=10
