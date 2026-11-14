"""Conector local experimental para el controlador oficial del Mesero 06.

No cambia archivos del robot. Movimiento real DESHABILITADO salvo que el
operador arranque el puente con --habilitar-movimiento y confirme en consola.
No debe desplegarse en Internet ni en un servidor remoto.
"""
from __future__ import annotations

import os
import threading
import time

try:
    import socketio
except ImportError:
    socketio = None

ROBOT_URL = 'http://100.87.64.123:5000'
SEND_HZ = 20.0
BROWSER_TIMEOUT = 0.28
INACTIVITY_RELEASE = 120.0
# El inicio normal conserva un limite de 5 RPM. Solo el BAT exclusivo de
# prueba supervisada a 30 RPM cambia esta variable antes de iniciar Python.
MAX_TEST_SPEED = 30 if os.environ.get('MESERO06_LIMITE_RPM') == '30' else 5
KEYS = ('w', 'a', 's', 'd')


class DriveBridge:
    def __init__(self, enabled=False):
        self.enabled = bool(enabled)
        self.lock = threading.RLock()
        self.socket = None
        self.connected = False
        self.owner = False
        self.pending = False
        self.remote_status = {}
        self.last_error = ''
        self.motion = {key: False for key in KEYS}
        self.video_fresh = False
        self.browser_active = False
        self.speed = min(20, MAX_TEST_SPEED)
        self.last_browser_frame = 0.0
        self.sequence = 0
        self._quit = threading.Event()
        self._thread = None
        self._was_moving = False
        self._sent_stop_for_loss = False
        # La STM32 decide el modo. Nunca cambiarlo al tomar control ni al iniciar.
        self.mode_change_pending = False
        self.mode_before_change = None
        self.mode_change_error = ''
        if self.enabled:
            self._thread = threading.Thread(target=self._send_loop, daemon=True, name='mesero06-control-loop')
            self._thread.start()

    def _connect(self):
        if not self.enabled or socketio is None:
            return False
        with self.lock:
            if self.socket is not None and self.connected:
                return True
            if self.socket is None:
                sio = socketio.Client(reconnection=True, reconnection_attempts=3,
                                       reconnection_delay=1, logger=False, engineio_logger=False)
                self.socket = sio
                @sio.on('connect')
                def on_connect():
                    with self.lock:
                        self.connected = True
                        # Nunca recuperar el control automáticamente al reconectar.
                        self.owner = False
                        self.pending = False
                        self.mode_change_pending = False
                        self.mode_before_change = None
                        self._reset_input()
                    sio.emit('status_request')
                @sio.on('disconnect')
                def on_disconnect():
                    with self.lock:
                        self.connected = False
                        self.owner = False
                        self.pending = False
                        self.mode_change_pending = False
                        self.mode_before_change = None
                        self._reset_input()
                @sio.on('status')
                def on_status(data):
                    if isinstance(data, dict):
                        with self.lock:
                            self.remote_status = data
                            # Reanudar la autorización únicamente cuando la STM32
                            # comunique un modo REAL diferente del anterior.
                            new_mode = data.get('robot_mode')
                            if (self.mode_change_pending and new_mode in
                                    ('AUTONOMO', 'MANDO RC', 'TELEDIRIGIDO') and
                                    new_mode != self.mode_before_change):
                                self.mode_change_pending = False
                                self.mode_before_change = None
                                self.mode_change_error = ''
                                self._reset_input()
                @sio.on('mode_denied')
                def on_mode_denied(data=None):
                    with self.lock:
                        self.mode_change_error = (data or {}).get('reason', 'Cambio de modo denegado') if isinstance(data, dict) else 'Cambio de modo denegado'
                        self.mode_change_pending = False
                        # Requerir nueva toma de control para salir de una transición fallida.
                        self._reset_input()
                @sio.on('serial_command_denied')
                def on_serial_command_denied(data=None):
                    with self.lock:
                        self.last_error = (data or {}).get('reason', 'Consulta MODE? denegada') if isinstance(data, dict) else 'Consulta MODE? denegada'
                @sio.on('control_granted')
                def on_granted(*_):
                    with self.lock:
                        if self.pending:
                            self.owner = True
                            self.pending = False
                            self._reset_input()
                        else:
                            # Si ya no existía una solicitud vigente, liberar inmediatamente.
                            sio.emit('release_control')
                @sio.on('control_denied')
                def on_denied(data=None):
                    with self.lock:
                        self.pending = False
                        self.owner = False
                        self._reset_input()
                        self.last_error = (data or {}).get('reason', 'Control denegado') if isinstance(data, dict) else 'Control denegado'
                @sio.on('serial_log')
                def on_serial_log(*_):
                    pass
            client = self.socket
        try:
            if not client.connected:
                client.connect(ROBOT_URL, transports=['websocket'], wait_timeout=4)
            return bool(client.connected)
        except Exception as exc:
            with self.lock:
                self.last_error = 'No se pudo enlazar a Tailscale: ' + type(exc).__name__
            return False

    def _reset_input(self):
        self.motion = {key: False for key in KEYS}
        self.video_fresh = False
        self.browser_active = False
        self.last_browser_frame = 0.0
        self._was_moving = False
        self._sent_stop_for_loss = False

    def claim(self):
        if not self.enabled:
            return {'ok': False, 'reason': 'Modo real no habilitado al iniciar el servidor'}
        if not self._connect():
            return {'ok': False, 'reason': self.last_error or 'Controlador sin conexión'}
        with self.lock:
            if self.owner:
                return {'ok': True, 'pending': False, 'reason': 'Ya tienes el control'}
            if self.pending:
                return {'ok': True, 'pending': True, 'reason': 'Esperando confirmación'}
            self.pending = True
            self._reset_input()
        try:
            self.socket.emit('claim_control')
            return {'ok': True, 'pending': True, 'reason': 'Solicitando control al robot'}
        except Exception as exc:
            with self.lock:
                self.pending = False
            return {'ok': False, 'reason': type(exc).__name__}

    def release(self):
        with self.lock:
            was_owner = self.owner or self.pending
            self.owner = False
            self.pending = False
            self.mode_change_pending = False
            self.mode_before_change = None
            self.mode_change_error = ''
            self._reset_input()
            client = self.socket
        if was_owner and client is not None and client.connected:
            try:
                client.emit('emergency_stop')
                client.emit('release_control')
            except Exception:
                pass
        return {'ok': True, 'reason': 'Control liberado'}

    def query_mode(self):
        """Consulta solo lectura del modo real de la STM32 (no cambia nada)."""
        with self.lock:
            if not self.enabled or not self.connected or not self.owner or not self.socket:
                return {'ok': False, 'reason': 'Primero toma el control real en este panel'}
            client = self.socket
        try:
            client.emit('serial_command', {'command': 'MODE?'})
            return {'ok': True, 'reason': 'Consulta MODE? enviada al STM32. Espera el estado real.'}
        except Exception as exc:
            return {'ok': False, 'reason': 'No se pudo consultar MODE?: ' + type(exc).__name__}

    def cycle_mode(self):
        """Un solo ciclo de modo. La autoridad y STOP/rampa son del servidor oficial."""
        with self.lock:
            if not self.enabled or not self.connected or not self.owner or not self.socket:
                return {'ok': False, 'reason': 'Primero toma el control real en este panel'}
            if not self.remote_status.get('serial_connected'):
                return {'ok': False, 'reason': 'Sin confirmación de enlace con STM32'}
            current = self.remote_status.get('robot_mode')
            if current not in ('AUTONOMO', 'MANDO RC', 'TELEDIRIGIDO'):
                return {'ok': False, 'reason': 'Modo desconocido: pulsa Consultar modo físico antes de cambiar'}
            if self.mode_change_pending:
                return {'ok': False, 'reason': 'Cambio anterior pendiente de confirmación de STM32'}
            self.mode_change_pending = True
            self.mode_before_change = current
            self.mode_change_error = ''
            self._reset_input()  # Cero movimiento y se exige otra vez video/foco.
            client = self.socket
        try:
            # El evento oficial aplica STOP y espera la rampa antes de MODE NEXT.
            client.emit('cycle_mode')
            return {'ok': True, 'reason': 'Cambio solicitado desde ' + current + '. Esperando confirmación del STM32; ningún movimiento automático.'}
        except Exception as exc:
            with self.lock:
                self.mode_change_error = 'Error al solicitar cambio de modo'
                # Mantener bloqueo hasta liberar control para no autorizar modo incierto.
            return {'ok': False, 'reason': 'No se pudo cambiar el modo: ' + type(exc).__name__}

    def stop(self):
        with self.lock:
            self.motion = {k: False for k in KEYS}
            self.video_fresh = False
            self.browser_active = False
            self.last_browser_frame = 0.0
            self._was_moving = False
            self._sent_stop_for_loss = True
            client = self.socket if self.owner else None
        if client is not None and client.connected:
            try:
                client.emit('emergency_stop')
            except Exception:
                pass
        return {'ok': True, 'reason': 'STOP solicitado'}

    def input(self, payload):
        if not isinstance(payload, dict):
            return {'ok': False, 'reason': 'Formato no válido'}
        incoming = payload.get('keys')
        if not isinstance(incoming, dict) or any(not isinstance(incoming.get(k), bool) for k in KEYS):
            return {'ok': False, 'reason': 'Teclas no válidas'}
        if any(k not in KEYS for k in incoming):
            return {'ok': False, 'reason': 'Tecla no permitida'}
        focus = payload.get('focus') is True
        # El cliente solo declara video fresco si pudo medir fotogramas reales del elemento <video>.
        video = payload.get('video') is True
        try:
            frame_age = float(payload.get('frame_age_ms', 1e9))
            requested_speed = int(payload.get('speed', MAX_TEST_SPEED))
        except (TypeError, ValueError):
            return {'ok': False, 'reason': 'Velocidad o cámara inválida'}
        if not 0 <= frame_age <= 900:
            video = False
        with self.lock:
            if not self.enabled or not self.owner:
                return {'ok': False, 'reason': 'No tienes control real activo'}
            if self.mode_change_pending:
                return {'ok': False, 'reason': 'Cambio de modo físico pendiente de confirmación'}
            self.last_browser_frame = time.monotonic()
            self.browser_active = focus
            self.video_fresh = video
            self.speed = min(MAX_TEST_SPEED, max(0, requested_speed))
            self.motion = {k: incoming[k] and focus and video for k in KEYS}
        return {'ok': True}

    def _send_loop(self):
        # El robot ya tiene su lazo de 20 Hz. Este bucle mantiene el estado completo,
        # siempre neutro si falta cámara/foco/heartbeat, sin soltar el control.
        while not self._quit.wait(1.0/SEND_HZ):
            with self.lock:
                fresh = time.monotonic() - self.last_browser_frame <= BROWSER_TIMEOUT
                mode_ok = self.remote_status.get('robot_mode') == 'TELEDIRIGIDO'
                can_move = self.owner and self.connected and not self.mode_change_pending and fresh and self.video_fresh and self.browser_active and mode_ok
                keys = dict(self.motion) if can_move else {k: False for k in KEYS}
                moving = any(keys.values())
                should_stop = self.owner and self.connected and self._was_moving and not moving and (not fresh or not self.video_fresh) and not self._sent_stop_for_loss
                self._was_moving = moving
                self._sent_stop_for_loss = not moving if should_stop else (False if moving else self._sent_stop_for_loss)
                stale_lease = self.owner and self.last_browser_frame and (time.monotonic()-self.last_browser_frame)>INACTIVITY_RELEASE
                self.sequence += 1
                seq = self.sequence
                speed = self.speed
                client = self.socket if self.owner and self.connected else None
            if stale_lease:
                self.release()
                continue
            if client is None:
                continue
            try:
                if should_stop:
                    client.emit('emergency_stop')
                client.emit('control_input', {'keys': keys, 'speed': speed, 'sequence': seq})
            except Exception:
                with self.lock:
                    self.last_error = 'No se pudo enviar una orden al robot'

    def status(self):
        with self.lock:
            fresh = time.monotonic() - self.last_browser_frame <= BROWSER_TIMEOUT
            mode = self.remote_status.get('robot_mode', 'DESCONOCIDO')
            serial_ok = bool(self.remote_status.get('serial_connected'))
            video_ok = bool(fresh and self.video_fresh)
            focus_ok = bool(fresh and self.browser_active)
            reasons = []
            if not self.enabled: reasons.append('Inicio sin control fisico: abre ABRIR_CONTROL_MESERO06.bat y escribe SI')
            if self.enabled and not self.connected: reasons.append('Sin conexion Socket.IO al puerto 5000')
            if self.connected and not self.owner: reasons.append('Falta pulsar Tomar control REAL o fue denegado')
            if self.owner and not serial_ok: reasons.append('El STM32 no confirma enlace serial')
            if self.owner and self.mode_change_pending: reasons.append('Esperando confirmación del cambio de modo físico desde STM32')
            if self.owner and mode != 'TELEDIRIGIDO': reasons.append('Modo fisico no es TELEDIRIGIDO: ' + mode)
            if self.owner and not video_ok: reasons.append('Camara WebRTC nativa sin fotogramas recientes')
            if self.owner and not focus_ok: reasons.append('Navegador sin foco o sin senales de teclas')
            movement_allowed = bool(self.owner and self.connected and not self.mode_change_pending and serial_ok and video_ok and focus_ok and mode=='TELEDIRIGIDO')
            return {
                'enabled': self.enabled, 'connected': self.connected, 'owner': self.owner,
                'pending': self.pending, 'robot_mode': mode,
                'mode_change_pending': self.mode_change_pending,
                'mode_change_error': self.mode_change_error,
                'serial_connected': serial_ok,
                'failsafe': self.remote_status.get('failsafe'),
                'video_fresh': video_ok,
                'browser_active': focus_ok,
                'movement_allowed': movement_allowed,
                'block_reason': '; '.join(reasons) if reasons else '',
                'speed_limit': MAX_TEST_SPEED, 'speed_selected': self.speed, 'error': self.last_error,
                'note': 'La prueba real requiere supervision presencial y parada fisica disponible.',
            }

    def close(self):
        self.stop()
        self.release()
        self._quit.set()
        if self.socket and self.socket.connected:
            self.socket.disconnect()
