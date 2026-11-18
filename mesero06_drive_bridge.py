"""Cliente Socket.IO del controlador original del Mesero 06.

Solo puede ejecutarse detrás de un backend autenticado autorizado en Tailscale.
No modifica el robot; conserva STOP, watchdog, modo físico y verificación STM32.
"""
from __future__ import annotations

import os
import re
import threading
import time
from collections import deque

try:
    import socketio
except ImportError:
    socketio = None

ROBOT_URL = os.environ.get('MESERO06_SOCKET_URL', 'http://100.87.64.123:5000').rstrip('/')
SEND_HZ = 20.0
BROWSER_TIMEOUT = 0.28
INACTIVITY_RELEASE = 120.0
CLAIM_TIMEOUT = 12.0  # Permitir reintento si no responde el servidor de control
# Se conserva el rango existente del panel original (0..30 RPM) y el inicio a 20 RPM.
# Los limites finales de seguridad los siguen imponiendo el controlador y STM32.
MAX_TEST_SPEED = 30
KEYS = ('w', 'a', 's', 'd')
# Claves observadas en las tramas seriales reales. Son valores BRUTOS: no se
# asumen unidades, rango de seguridad ni significado de cada etiqueta US*.
TELEMETRY_FIELDS = frozenset((
    'DT','TXL','TKR','CNL','CNR','DIRL','DIRR',
    'AX','AY','AZ','GX','GY','GZ','USDF','USIF','USDT','USIT',
    'YAW','IMUACE','IMAGE'
))
TELEMETRY_PAIR = re.compile(r'\b([A-Z][A-Z0-9]{1,12})=(-?\d{1,12})(?=\s|$)')



class DriveBridge:
    def __init__(self, enabled=False):
        self.enabled = bool(enabled)
        # Esta capacidad se habilita exclusivamente en el backend autorizado y supervisado.
        self.supervised_remote = self.enabled and os.environ.get('MESERO06_REMOTE_SUPERVISADO') == '1'
        self.lock = threading.RLock()
        self.socket = None
        self._connect_guard = threading.Lock()
        self._monitor_attempt = 0.0
        self._telemetry_values = {}
        self._telemetry_tel_at = 0.0
        self._telemetry_imu_at = 0.0
        self._telemetry_last_sample_at = 0.0
        self._telemetry_history = deque(maxlen=160)
        self.connected = False
        self.owner = False
        self.pending = False
        self.claim_sent_at = 0.0
        self.remote_status = {}
        self.last_error = ''
        self.motion = {key: False for key in KEYS}
        self.video_fresh = False
        self.browser_active = False
        self.supervised_input = False
        self.speed = min(20, MAX_TEST_SPEED)
        self.last_browser_frame = 0.0
        self.sequence = 0
        self._quit = threading.Event()
        self._thread = None
        self._was_moving = False
        self._sent_stop_for_loss = False
        # Ultrasonicos: el estado es ULTIMA ORDEN, no un ACK fisico de STM32.
        self.ultra_last_command = 'UNKNOWN'
        self.ultra_off_until = 0.0
        self.ultra_rearm_pending = False
        self.ultra_error = ''
        self.ultra_next_poll = 0.0
        # La STM32 decide el modo. Nunca cambiarlo al tomar control ni al iniciar.
        self.mode_change_pending = False
        self.mode_before_change = None
        self.mode_change_error = ''
        if self.enabled:
            self._thread = threading.Thread(target=self._send_loop, daemon=True, name='mesero06-control-loop')
            self._thread.start()
            # Observador de solo lectura: conectar para recibir serial_log sin
            # solicitar ni asumir control del robot ni enviar comandos de motor.
            self._ensure_telemetry_observer()

    def _ensure_telemetry_observer(self):
        if not self.enabled or socketio is None:
            return
        with self.lock:
            now = time.monotonic()
            if self.connected or now - self._monitor_attempt < 7:
                return
            self._monitor_attempt = now
        threading.Thread(target=self._connect, daemon=True,
                         name='mesero06-telemetria-observador').start()

    def _ingest_serial_line(self, message):
        """Procesa exclusivamente tramas TEL/YAW, nunca interpreta una orden."""
        if isinstance(message, dict):
            message = message.get('line', '')
        if not isinstance(message, str) or len(message) > 1500:
            return
        has_tel = re.search(r'(?<![A-Z])TEL\s+', message) is not None
        has_imu = re.search(r'\bYAW=', message) is not None
        if not has_tel and not has_imu:
            return
        extracted = {}
        for key, raw in TELEMETRY_PAIR.findall(message):
            if key in TELEMETRY_FIELDS:
                try: extracted[key] = int(raw)
                except ValueError: pass
        if not extracted:
            return
        now = time.monotonic()
        with self.lock:
            self._telemetry_values.update(extracted)
            if has_tel:
                self._telemetry_tel_at = now
                # 4 valores US* en gráfico, muestreo ~3 Hz con buffer limitado.
                if now - self._telemetry_last_sample_at >= 0.3:
                    snapshot = {'t': now}
                    snapshot.update({key: self._telemetry_values.get(key)
                                     for key in ('USDF','USIF','USDT','USIT')})
                    self._telemetry_history.append(snapshot)
                    self._telemetry_last_sample_at = now
            if has_imu:
                self._telemetry_imu_at = now

    def telemetry(self):
        """Solo lectura, sin movimiento ni comandos seriales."""
        self._ensure_telemetry_observer()
        now = time.monotonic()
        with self.lock:
            age = now - self._telemetry_tel_at if self._telemetry_tel_at else None
            imu_age = now - self._telemetry_imu_at if self._telemetry_imu_at else None
            return {
                'ok': True, 'connected': bool(self.connected),
                'serial_connected': bool(self.remote_status.get('serial_connected')),
                'fresh': age is not None and age <= 3.0,
                'age_seconds': round(age, 1) if age is not None else None,
                'imu_age_seconds': round(imu_age, 1) if imu_age is not None else None,
                'values': dict(self._telemetry_values),
                'history': [dict(item, t=round(item['t']-now, 2))
                            for item in self._telemetry_history],
                'units_confirmed': False,
                'note': ('USDF/USIF/USDT/USIT son etiquetas originales de STM32. '
                         'Sin calibracion no son distancias certificadas ni un sistema anticolision.')
            }

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
                        if self.ultra_off_until:
                            self.ultra_rearm_pending = True
                            self.ultra_last_command = 'RECOVERY_PENDING'
                @sio.on('status')
                def on_status(data):
                    if isinstance(data, dict):
                        with self.lock:
                            self.remote_status = data
                            remote_ultra = data.get('ultra_commanded_state')
                            if remote_ultra in ('ON_REQUESTED', 'OFF_REQUESTED', 'RECOVERY_PENDING'):
                                self.ultra_last_command = remote_ultra
                                if remote_ultra == 'ON_REQUESTED':
                                    self.ultra_off_until = 0.0
                                    self.ultra_rearm_pending = False
                                elif remote_ultra == 'OFF_REQUESTED' and self.ultra_off_until <= 0:
                                    self.ultra_off_until = time.monotonic() + 60.0
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
                        self.last_error = (data or {}).get('reason', 'Comando serial denegado') if isinstance(data, dict) else 'Comando serial denegado'
                        self.ultra_error = self.last_error
                        self.ultra_rearm_pending = bool(self.ultra_off_until)
                        self.ultra_last_command = 'RECOVERY_PENDING' if self.ultra_rearm_pending else 'UNKNOWN'
                @sio.on('control_granted')
                def on_granted(*_):
                    with self.lock:
                        if self.pending:
                            self.owner = True
                            self.pending = False
                            self._reset_input()
                            if self.ultra_rearm_pending or self.ultra_last_command == 'UNKNOWN':
                                sio.emit('serial_command', {'command': 'ON ULTRA'})
                                self.ultra_last_command = 'ON_REQUESTED'
                                self.ultra_rearm_pending = False
                                self.ultra_off_until = 0.0
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
                def on_serial_log(data=None):
                    self._ingest_serial_line(data)
            client = self.socket
        try:
            # Una conexión única compartida por observación y control; evita
            # carreras si el operador pulsa Tomar control mientras conecta.
            with self._connect_guard:
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
        self.supervised_input = False
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
            self.claim_sent_at = time.monotonic()
            self.last_error = ''
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
                # Restaurar proteccion antes de abandonar el control.
                if self.ultra_off_until or self.ultra_rearm_pending:
                    client.emit('serial_command', {'command': 'ON ULTRA'})
                    with self.lock:
                        self.ultra_last_command = 'ON_REQUESTED'
                        self.ultra_off_until = 0.0
                        self.ultra_rearm_pending = False
                client.emit('release_control')
            except Exception:
                pass
        return {'ok': True, 'reason': 'Control liberado'}

    def toggle_ultra(self):
        """U: OFF durante 60s; U de nuevo: ON. Requiere watchdog del robot."""
        with self.lock:
            if not self.enabled or not self.connected or not self.owner or not self.socket:
                return {'ok': False, 'reason': 'Toma el control REAL del robot antes de usar U'}
            if not self.remote_status.get('serial_connected'):
                return {'ok': False, 'reason': 'STM32 sin enlace serial confirmado'}
            if self.remote_status.get('ultra_watchdog_supported') is not True:
                return {'ok': False, 'reason': 'Instala el watchdog de 60s en Python del robot antes de permitir OFF ULTRA'}
            if self.mode_change_pending:
                return {'ok': False, 'reason': 'Cambio de modo fisico pendiente'}
            if self.remote_status.get('robot_mode') != 'TELEDIRIGIDO':
                return {'ok': False, 'reason': 'Debes estar en modo TELEDIRIGIDO'}
            if any(self.motion.values()) or self._was_moving:
                return {'ok': False, 'reason': 'Deten el robot y suelta WASD antes de cambiar ultrasónicos'}
            if self.ultra_last_command in ('UNKNOWN', 'RECOVERY_PENDING'):
                # Primero garantizar ON cuando no hay estado confiable.
                return {'ok': False, 'reason': 'Estado no sincronizado: espera a que el robot publique ON solicitado'}
            turning_off = self.ultra_last_command != 'OFF_REQUESTED'
            command = 'OFF ULTRA' if turning_off else 'ON ULTRA'
            client = self.socket
            # Se actualiza el estado solicitado (no la confirmacion fisica).
            self.ultra_last_command = 'OFF_REQUESTED' if turning_off else 'ON_REQUESTED'
            self.ultra_off_until = time.monotonic() + 60.0 if turning_off else 0.0
            self.ultra_rearm_pending = False
            self.ultra_error = ''
        try:
            client.emit('serial_command', {'command': command})
            client.emit('status_request')
            return {'ok': True, 'reason': ('OFF ULTRA solicitado durante maximo 60 s' if turning_off else 'ON ULTRA solicitado'),
                    'ultra_command': command, 'physical_confirmed': False}
        except Exception as exc:
            with self.lock:
                self.ultra_error = 'Fallo de red al enviar '+ command + ': '+type(exc).__name__
                self.ultra_rearm_pending = turning_off
                self.ultra_last_command = 'RECOVERY_PENDING'
            return {'ok': False, 'reason': self.ultra_error}

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
            self.supervised_input = False
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
        supervised = self.supervised_remote and payload.get('supervised') is True
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
            self.supervised_input = supervised
            self.speed = min(MAX_TEST_SPEED, max(0, requested_speed))
            self.motion = {k: incoming[k] and focus and (video or supervised) for k in KEYS}
        return {'ok': True}

    def _send_loop(self):
        # El robot ya tiene su lazo de 20 Hz. Este bucle mantiene el estado completo,
        # siempre neutro si falta cámara/foco/heartbeat, sin soltar el control.
        while not self._quit.wait(1.0/SEND_HZ):
            with self.lock:
                fresh = time.monotonic() - self.last_browser_frame <= BROWSER_TIMEOUT
                mode_ok = self.remote_status.get('robot_mode') == 'TELEDIRIGIDO'
                can_move = self.owner and self.connected and bool(self.remote_status.get('serial_connected')) and not self.mode_change_pending and fresh and (self.video_fresh or self.supervised_input) and self.browser_active and mode_ok
                keys = dict(self.motion) if can_move else {k: False for k in KEYS}
                moving = any(keys.values())
                should_stop = self.owner and self.connected and self._was_moving and not moving and (not fresh or not (self.video_fresh or self.supervised_input)) and not self._sent_stop_for_loss
                self._was_moving = moving
                self._sent_stop_for_loss = not moving if should_stop else (False if moving else self._sent_stop_for_loss)
                stale_lease = self.owner and self.last_browser_frame and (time.monotonic()-self.last_browser_frame)>INACTIVITY_RELEASE
                self.sequence += 1
                seq = self.sequence
                speed = self.speed
                client = self.socket if self.owner and self.connected else None
            # Watchdog adicional del backend (el del robot es el primario).
            with self.lock:
                due = self.ultra_off_until > 0 and time.monotonic() >= self.ultra_off_until
                if due:
                    self.ultra_rearm_pending = True
                    self.ultra_last_command = 'RECOVERY_PENDING'
                needs_rearm = self.ultra_rearm_pending
                ultra_client = self.socket if self.connected and self.owner else None
                poll_status = self.ultra_off_until > 0 and time.monotonic() >= self.ultra_next_poll
                if poll_status: self.ultra_next_poll = time.monotonic()+1
            if (due or needs_rearm) and ultra_client is not None:
                try:
                    ultra_client.emit('serial_command', {'command': 'ON ULTRA'})
                    with self.lock:
                        self.ultra_off_until = 0.0
                        self.ultra_rearm_pending = False
                        self.ultra_last_command = 'ON_REQUESTED'
                except Exception:
                    with self.lock:
                        self.ultra_error = 'Reactivacion pendiente; sin entrega confirmada'
            elif poll_status and ultra_client is not None:
                try: ultra_client.emit('status_request')
                except Exception: pass
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
            # Una solicitud sin respuesta no puede dejar el botón gris para siempre.
            # Si el grant llega tarde, on_granted libera el control inmediatamente.
            if self.pending and self.claim_sent_at and time.monotonic()-self.claim_sent_at > CLAIM_TIMEOUT:
                self.pending = False
                self.claim_sent_at = 0.0
                self.last_error = 'No hubo respuesta a Tomar control en 12 s; puedes reintentar.'
            fresh = time.monotonic() - self.last_browser_frame <= BROWSER_TIMEOUT
            mode = self.remote_status.get('robot_mode', 'DESCONOCIDO')
            serial_ok = bool(self.remote_status.get('serial_connected'))
            video_ok = bool(fresh and self.video_fresh)
            supervised_ok = bool(fresh and self.supervised_input and self.supervised_remote)
            visual_or_supervisor_ok = video_ok or supervised_ok
            focus_ok = bool(fresh and self.browser_active)
            reasons = []
            if not self.enabled: reasons.append('Control físico no habilitado en el servidor')
            if self.enabled and not self.connected: reasons.append('Sin conexion Socket.IO al puerto 5000')
            if self.connected and not self.owner: reasons.append('Falta pulsar Tomar control REAL o fue denegado')
            if self.owner and not serial_ok: reasons.append('El STM32 no confirma enlace serial')
            if self.owner and self.mode_change_pending: reasons.append('Esperando confirmación del cambio de modo físico desde STM32')
            if self.owner and mode != 'TELEDIRIGIDO': reasons.append('Modo fisico no es TELEDIRIGIDO: ' + mode)
            if self.owner and not visual_or_supervisor_ok: reasons.append('Falta vídeo reciente o autorización de supervisión presencial')
            if self.owner and not focus_ok: reasons.append('Navegador sin foco o sin senales de teclas')
            movement_allowed = bool(self.owner and self.connected and not self.mode_change_pending and serial_ok and visual_or_supervisor_ok and focus_ok and mode=='TELEDIRIGIDO')
            return {
                'enabled': self.enabled, 'connected': self.connected, 'owner': self.owner,
                'pending': self.pending, 'robot_mode': mode,
                'mode_change_pending': self.mode_change_pending,
                'mode_change_error': self.mode_change_error,
                'serial_connected': serial_ok,
                'failsafe': self.remote_status.get('failsafe'),
                'video_fresh': video_ok,
                'supervised_remote_active': supervised_ok,
                'supervised_remote_enabled': self.supervised_remote,
                'browser_active': focus_ok,
                'movement_allowed': movement_allowed,
                'block_reason': '; '.join(reasons) if reasons else '',
                'speed_limit': MAX_TEST_SPEED, 'speed_selected': self.speed, 'error': self.last_error,
                'ultra_watchdog_supported': self.remote_status.get('ultra_watchdog_supported') is True,
                'ultra_commanded_state': self.ultra_last_command,
                'ultra_remaining_sec': max(0, int(self.ultra_off_until-time.monotonic()+0.99)) if self.ultra_off_until else 0,
                'ultra_physical_confirmed': False,
                'ultra_error': self.ultra_error,
                'note': 'La prueba real requiere supervision presencial y parada fisica disponible.',
            }

    def close(self):
        self.stop()
        self.release()
        self._quit.set()
        if self.socket and self.socket.connected:
            self.socket.disconnect()
