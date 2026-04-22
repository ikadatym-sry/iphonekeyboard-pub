import argparse
import asyncio
import json
import socket
import ssl
import struct
import time
from collections import deque
from dataclasses import dataclass
from typing import Any, Dict, Optional

import cv2
import numpy as np
import pyvirtualcam
import websockets
from websockets.exceptions import ConnectionClosed

DISCOVERY_MAGIC = "RPAD_DISCOVER_V1"
AUTH_PREFIX = "AUTH:"
FRAME_MAGIC = b"WCM1"


@dataclass
class StreamStats:
    frame_count: int = 0
    bytes_count: int = 0
    window_started_at: float = time.monotonic()

    def push(self, payload_size: int) -> Optional[Dict[str, float]]:
        self.frame_count += 1
        self.bytes_count += payload_size

        now = time.monotonic()
        elapsed = now - self.window_started_at
        if elapsed < 1.0:
            return None

        fps = self.frame_count / elapsed
        mbps = (self.bytes_count * 8.0 / 1_000_000.0) / elapsed

        self.frame_count = 0
        self.bytes_count = 0
        self.window_started_at = now

        return {"fps": fps, "mbps": mbps}


class DiscoveryProtocol(asyncio.DatagramProtocol):
    def __init__(self, websocket_port: int, use_tls: bool):
        self.websocket_port = websocket_port
        self.use_tls = use_tls
        self.transport: Optional[asyncio.DatagramTransport] = None

    def connection_made(self, transport: asyncio.BaseTransport):
        self.transport = transport  # type: ignore[assignment]

    def datagram_received(self, data: bytes, addr):
        incoming_text = data.decode("utf-8", errors="ignore").strip()
        if incoming_text != DISCOVERY_MAGIC:
            return

        local_ip = get_local_ip_for_target(addr[0])
        ws_scheme = "wss" if self.use_tls else "ws"
        payload = {
            "app": "BLERemotePad-Webcam",
            "version": 1,
            "ws_url": f"{ws_scheme}://{local_ip}:{self.websocket_port}",
            "ws_port": self.websocket_port,
            "host": local_ip,
            "name": socket.gethostname(),
            "secure": self.use_tls,
            "mode": "webcam",
        }

        if self.transport is not None:
            self.transport.sendto(json.dumps(payload).encode("utf-8"), addr)


class WebcamServer:
    def __init__(self, args: argparse.Namespace):
        self.args = args
        self.auth_token = args.webcam_token

        self.virtual_cam: Optional[pyvirtualcam.Camera] = None
        self.frame_queue: deque[np.ndarray] = deque(maxlen=2)
        self.sender_task: Optional[asyncio.Task[Any]] = None
        self.last_dimensions = (0, 0)

        self.stream_stats = StreamStats()
        self.peer_name = "-"

    async def run(self):
        ssl_context = build_ssl_context(self.args)

        tasks = [
            asyncio.create_task(self.run_websocket_server(ssl_context)),
            asyncio.create_task(
                run_discovery_server(
                    self.args.discovery_host,
                    self.args.discovery_port,
                    self.args.webcam_port,
                    ssl_context is not None,
                )
            ),
        ]

        done, pending = await asyncio.wait(tasks, return_when=asyncio.FIRST_EXCEPTION)

        for task in pending:
            task.cancel()

        for task in done:
            exc = task.exception()
            if exc is not None:
                raise exc

    async def run_websocket_server(self, ssl_context: Optional[ssl.SSLContext]):
        async def websocket_handler(websocket):
            await self.handle_client(websocket)

        async with websockets.serve(
            websocket_handler,
            self.args.webcam_host,
            self.args.webcam_port,
            max_size=8 * 1024 * 1024,
            ssl=ssl_context,
        ):
            scheme = "wss" if ssl_context else "ws"
            print(f"Webcam websocket listening on {scheme}://{self.args.webcam_host}:{self.args.webcam_port}")
            await asyncio.Future()

    async def handle_client(self, websocket):
        self.peer_name = str(websocket.remote_address)
        print(f"Webcam client connected: {self.peer_name}")

        try:
            auth_payload = await asyncio.wait_for(websocket.recv(), timeout=5.0)
            auth_text = auth_payload if isinstance(auth_payload, str) else auth_payload.decode("utf-8", errors="ignore")

            if not auth_text.startswith(AUTH_PREFIX):
                await websocket.send("AUTH_FAIL")
                await websocket.close(code=4003, reason="Missing auth token")
                print("Webcam auth missing")
                return

            incoming_token = auth_text[len(AUTH_PREFIX) :]
            if incoming_token != self.auth_token:
                await websocket.send("AUTH_FAIL")
                await websocket.close(code=4003, reason="Invalid auth token")
                print("Webcam auth failed")
                return

            await websocket.send("AUTH_OK")
            await self.ensure_sender_task()

            async for message in websocket:
                if isinstance(message, str):
                    continue

                frame = parse_frame_packet(bytes(message))
                if frame is None:
                    continue

                self.frame_queue.append(frame)
                stat = self.stream_stats.push(len(message))
                if stat is not None:
                    print(
                        f"[{self.peer_name}] RX {stat['fps']:.1f} fps, {stat['mbps']:.2f} Mbps, output {self.last_dimensions[0]}x{self.last_dimensions[1]}"
                    )
        except ConnectionClosed:
            pass
        except Exception as exc:
            print(f"Webcam client error: {exc}")
        finally:
            print(f"Webcam client disconnected: {self.peer_name}")

    async def ensure_sender_task(self):
        if self.sender_task is not None and not self.sender_task.done():
            return

        self.sender_task = asyncio.create_task(self.sender_loop())

    async def sender_loop(self):
        while True:
            if not self.frame_queue:
                await asyncio.sleep(0.001)
                continue

            frame = self.frame_queue.pop()
            self.frame_queue.clear()

            try:
                self.send_to_virtual_cam(frame)
            except Exception as exc:
                print(f"Virtual cam send error: {exc}")
                await asyncio.sleep(0.05)

    def send_to_virtual_cam(self, frame_bgr: np.ndarray):
        height, width = frame_bgr.shape[:2]
        self.last_dimensions = (width, height)

        if self.virtual_cam is None or self.virtual_cam.width != width or self.virtual_cam.height != height:
            self.recreate_virtual_cam(width, height)

        frame_rgb = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB)
        self.virtual_cam.send(frame_rgb)
        self.virtual_cam.sleep_until_next_frame()

    def recreate_virtual_cam(self, width: int, height: int):
        if self.virtual_cam is not None:
            self.virtual_cam.close()
            self.virtual_cam = None

        target_fps = max(1, int(self.args.virtual_cam_fps))
        self.virtual_cam = pyvirtualcam.Camera(width=width, height=height, fps=target_fps, print_fps=False)
        print(f"Virtual camera created: {self.virtual_cam.device} ({width}x{height}@{target_fps})")


async def run_discovery_server(host: str, discovery_port: int, websocket_port: int, use_tls: bool):
    loop = asyncio.get_running_loop()
    transport, _ = await loop.create_datagram_endpoint(
        lambda: DiscoveryProtocol(websocket_port, use_tls),
        local_addr=(host, discovery_port),
        allow_broadcast=True,
    )

    print(f"UDP discovery responder listening on {host}:{discovery_port}")

    try:
        await asyncio.Future()
    finally:
        transport.close()


def parse_frame_packet(packet: bytes) -> Optional[np.ndarray]:
    # Packet: magic(4) + width(2 LE) + height(2 LE) + fps(1) + mic(1) + timestamp_ms(4 LE) + jpeg
    if len(packet) < 14:
        return None

    if packet[0:4] != FRAME_MAGIC:
        return None

    width, height = struct.unpack_from("<HH", packet, 4)
    jpeg_payload = packet[14:]

    if width <= 0 or height <= 0 or not jpeg_payload:
        return None

    np_buffer = np.frombuffer(jpeg_payload, dtype=np.uint8)
    frame = cv2.imdecode(np_buffer, cv2.IMREAD_COLOR)
    return frame


def get_local_ip_for_target(remote_host: str) -> str:
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as local_socket:
            local_socket.connect((remote_host, 1))
            return local_socket.getsockname()[0]
    except OSError:
        return "127.0.0.1"


def build_ssl_context(args: argparse.Namespace) -> Optional[ssl.SSLContext]:
    if not (args.wss_only or args.tls_cert or args.tls_key):
        return None

    if not args.tls_cert or not args.tls_key:
        raise ValueError("TLS mode requires both --tls-cert and --tls-key")

    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(certfile=args.tls_cert, keyfile=args.tls_key)
    return context


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Windows webcam receiver with virtual camera output")
    parser.add_argument("--webcam-host", default="0.0.0.0", help="Host for webcam websocket server")
    parser.add_argument("--webcam-port", type=int, default=8767, help="Port for webcam websocket server")
    parser.add_argument("--webcam-token", default="remotepad-token", help="Webcam auth token")
    parser.add_argument("--virtual-cam-fps", type=int, default=30, help="Virtual camera FPS")

    parser.add_argument("--tls-cert", help="Path to TLS certificate (PEM) for enabling wss")
    parser.add_argument("--tls-key", help="Path to TLS private key (PEM) for enabling wss")
    parser.add_argument("--wss-only", action="store_true", help="Require TLS mode")

    parser.add_argument("--discovery-host", default="0.0.0.0", help="Host for UDP discovery responder")
    parser.add_argument("--discovery-port", type=int, default=8766, help="UDP discovery port")
    return parser.parse_args()


if __name__ == "__main__":
    try:
        asyncio.run(WebcamServer(parse_args()).run())
    except ValueError as exc:
        print(f"Configuration error: {exc}")
    except KeyboardInterrupt:
        print("Stopped by user")
