import argparse
import asyncio
import ctypes
import json
import socket
import ssl
import struct
from ctypes import wintypes
from typing import Any, Dict, List, Optional, Tuple

import websockets
from bleak import BleakClient, BleakScanner
from websockets.exceptions import ConnectionClosed

SERVICE_UUID = "E20A3914-ECB4-40E4-BA35-5026E881D26E"
INPUT_CHARACTERISTIC_UUID = "01234567-89AB-CDEF-0123-456789ABCDEF"
CONTROL_CHARACTERISTIC_UUID = "89ABCDEF-0123-4567-89AB-CDEF01234567"

PACKET_MAGIC = 0x42
PACKET_VERSION = 0x01

EVENT_MOUSE_MOVE = 0x01
EVENT_MOUSE_BUTTON = 0x02
EVENT_MOUSE_SCROLL = 0x03
EVENT_KEYBOARD = 0x04
EVENT_TEXT = 0x05
EVENT_PING = 0x06
EVENT_CONSUMER = 0x07

DISCOVERY_MAGIC = "RPAD_DISCOVER_V1"
AUTH_PREFIX = "AUTH:"

BUTTON_LEFT = 0x01
BUTTON_RIGHT = 0x02
BUTTON_MIDDLE = 0x03

ACTION_UP = 0x00
ACTION_DOWN = 0x01
ACTION_TAP = 0x02

INPUT_MOUSE = 0
INPUT_KEYBOARD = 1

MOUSEEVENTF_MOVE = 0x0001
MOUSEEVENTF_LEFTDOWN = 0x0002
MOUSEEVENTF_LEFTUP = 0x0004
MOUSEEVENTF_RIGHTDOWN = 0x0008
MOUSEEVENTF_RIGHTUP = 0x0010
MOUSEEVENTF_MIDDLEDOWN = 0x0020
MOUSEEVENTF_MIDDLEUP = 0x0040
MOUSEEVENTF_WHEEL = 0x0800
MOUSEEVENTF_HWHEEL = 0x1000

KEYEVENTF_EXTENDEDKEY = 0x0001
KEYEVENTF_KEYUP = 0x0002
KEYEVENTF_UNICODE = 0x0004

WHEEL_DELTA = 120
ULONG_PTR = wintypes.WPARAM


class MOUSEINPUT(ctypes.Structure):
    _fields_ = [
        ("dx", wintypes.LONG),
        ("dy", wintypes.LONG),
        ("mouseData", wintypes.DWORD),
        ("dwFlags", wintypes.DWORD),
        ("time", wintypes.DWORD),
        ("dwExtraInfo", ULONG_PTR),
    ]


class KEYBDINPUT(ctypes.Structure):
    _fields_ = [
        ("wVk", wintypes.WORD),
        ("wScan", wintypes.WORD),
        ("dwFlags", wintypes.DWORD),
        ("time", wintypes.DWORD),
        ("dwExtraInfo", ULONG_PTR),
    ]


class _INPUTUNION(ctypes.Union):
    _fields_ = [("mi", MOUSEINPUT), ("ki", KEYBDINPUT)]


class INPUT(ctypes.Structure):
    _anonymous_ = ("union",)
    _fields_ = [("type", wintypes.DWORD), ("union", _INPUTUNION)]


user32 = ctypes.WinDLL("user32", use_last_error=True)


def send_input(input_event: INPUT) -> None:
    sent = user32.SendInput(1, ctypes.byref(input_event), ctypes.sizeof(INPUT))
    if sent != 1:
        raise ctypes.WinError(ctypes.get_last_error())


def send_mouse_move(dx: int, dy: int) -> None:
    event = INPUT(
        type=INPUT_MOUSE,
        mi=MOUSEINPUT(dx=dx, dy=dy, mouseData=0, dwFlags=MOUSEEVENTF_MOVE, time=0, dwExtraInfo=0),
    )
    send_input(event)


def send_mouse_button(button: int, action: int) -> None:
    button_flags: Dict[int, Dict[int, int]] = {
        BUTTON_LEFT: {ACTION_DOWN: MOUSEEVENTF_LEFTDOWN, ACTION_UP: MOUSEEVENTF_LEFTUP},
        BUTTON_RIGHT: {ACTION_DOWN: MOUSEEVENTF_RIGHTDOWN, ACTION_UP: MOUSEEVENTF_RIGHTUP},
        BUTTON_MIDDLE: {ACTION_DOWN: MOUSEEVENTF_MIDDLEDOWN, ACTION_UP: MOUSEEVENTF_MIDDLEUP},
    }

    if button not in button_flags:
        return

    if action == ACTION_TAP:
        send_mouse_button(button, ACTION_DOWN)
        send_mouse_button(button, ACTION_UP)
        return

    flag = button_flags[button].get(action)
    if flag is None:
        return

    event = INPUT(
        type=INPUT_MOUSE,
        mi=MOUSEINPUT(dx=0, dy=0, mouseData=0, dwFlags=flag, time=0, dwExtraInfo=0),
    )
    send_input(event)


def send_scroll(dx: int, dy: int) -> None:
    if dy != 0:
        vertical = INPUT(
            type=INPUT_MOUSE,
            mi=MOUSEINPUT(
                dx=0,
                dy=0,
                mouseData=dy * WHEEL_DELTA,
                dwFlags=MOUSEEVENTF_WHEEL,
                time=0,
                dwExtraInfo=0,
            ),
        )
        send_input(vertical)

    if dx != 0:
        horizontal = INPUT(
            type=INPUT_MOUSE,
            mi=MOUSEINPUT(
                dx=0,
                dy=0,
                mouseData=dx * WHEEL_DELTA,
                dwFlags=MOUSEEVENTF_HWHEEL,
                time=0,
                dwExtraInfo=0,
            ),
        )
        send_input(horizontal)


def hid_usage_to_vk(usage_id: int) -> Optional[Tuple[int, bool]]:
    if 0x04 <= usage_id <= 0x1D:
        return ord("A") + (usage_id - 0x04), False

    if 0x1E <= usage_id <= 0x26:
        return ord("1") + (usage_id - 0x1E), False

    if usage_id == 0x27:
        return ord("0"), False

    if 0x3A <= usage_id <= 0x45:
        return 0x70 + (usage_id - 0x3A), False

    mapping = {
        0x28: (0x0D, False),  # Enter
        0x29: (0x1B, False),  # Escape
        0x2A: (0x08, False),  # Backspace
        0x2B: (0x09, False),  # Tab
        0x2C: (0x20, False),  # Space
        0x2D: (0xBD, False),  # -
        0x2E: (0xBB, False),  # =
        0x2F: (0xDB, False),  # [
        0x30: (0xDD, False),  # ]
        0x31: (0xDC, False),  # \\
        0x33: (0xBA, False),  # ;
        0x34: (0xDE, False),  # '
        0x35: (0xC0, False),  # `
        0x36: (0xBC, False),  # ,
        0x37: (0xBE, False),  # .
        0x38: (0xBF, False),  # /
        0x39: (0x14, False),  # CapsLock
        0x46: (0x2C, True),   # PrintScreen
        0x47: (0x91, False),  # ScrollLock
        0x48: (0x13, False),  # Pause
        0x49: (0x2D, True),   # Insert
        0x4A: (0x24, True),   # Home
        0x4B: (0x21, True),   # PageUp
        0x4C: (0x2E, True),   # Delete
        0x4D: (0x23, True),   # End
        0x4E: (0x22, True),   # PageDown
        0x4F: (0x27, True),   # Right
        0x50: (0x25, True),   # Left
        0x51: (0x28, True),   # Down
        0x52: (0x26, True),   # Up
        0xE0: (0xA2, False),  # Left Ctrl
        0xE1: (0xA0, False),  # Left Shift
        0xE2: (0xA4, False),  # Left Alt
        0xE3: (0x5B, True),   # Left Win
        0xE4: (0xA3, True),   # Right Ctrl
        0xE5: (0xA1, False),  # Right Shift
        0xE6: (0xA5, True),   # Right Alt
        0xE7: (0x5C, True),   # Right Win
    }
    return mapping.get(usage_id)


def consumer_usage_to_vk(usage_id: int) -> Optional[Tuple[int, bool]]:
    mapping = {
        0x00B5: (0xB0, True),  # Media Next Track
        0x00B6: (0xB1, True),  # Media Prev Track
        0x00B7: (0xB2, True),  # Media Stop
        0x00CD: (0xB3, True),  # Media Play/Pause
        0x00E2: (0xAD, True),  # Volume Mute
        0x00E9: (0xAF, True),  # Volume Up
        0x00EA: (0xAE, True),  # Volume Down
    }
    return mapping.get(usage_id)


def send_virtual_key(vk_code: int, action: int, extended: bool = False) -> None:
    if action == ACTION_TAP:
        send_virtual_key(vk_code, ACTION_DOWN, extended)
        send_virtual_key(vk_code, ACTION_UP, extended)
        return

    flags = KEYEVENTF_EXTENDEDKEY if extended else 0
    if action == ACTION_UP:
        flags |= KEYEVENTF_KEYUP

    event = INPUT(
        type=INPUT_KEYBOARD,
        ki=KEYBDINPUT(wVk=vk_code, wScan=0, dwFlags=flags, time=0, dwExtraInfo=0),
    )
    send_input(event)


def send_unicode_text(text: str) -> None:
    for character in text:
        down = INPUT(
            type=INPUT_KEYBOARD,
            ki=KEYBDINPUT(wVk=0, wScan=ord(character), dwFlags=KEYEVENTF_UNICODE, time=0, dwExtraInfo=0),
        )
        up = INPUT(
            type=INPUT_KEYBOARD,
            ki=KEYBDINPUT(
                wVk=0,
                wScan=ord(character),
                dwFlags=KEYEVENTF_UNICODE | KEYEVENTF_KEYUP,
                time=0,
                dwExtraInfo=0,
            ),
        )
        send_input(down)
        send_input(up)


def dispatch_packet(packet: bytes) -> None:
    if len(packet) < 3:
        return

    magic, version, event_type = packet[0], packet[1], packet[2]
    payload = packet[3:]

    if magic != PACKET_MAGIC or version != PACKET_VERSION:
        return

    try:
        if event_type == EVENT_MOUSE_MOVE and len(payload) >= 4:
            dx, dy = struct.unpack_from("<hh", payload, 0)
            send_mouse_move(dx, dy)
        elif event_type == EVENT_MOUSE_BUTTON and len(payload) >= 2:
            button = payload[0]
            action = payload[1]
            send_mouse_button(button, action)
        elif event_type == EVENT_MOUSE_SCROLL and len(payload) >= 4:
            dx, dy = struct.unpack_from("<hh", payload, 0)
            send_scroll(dx, dy)
        elif event_type == EVENT_KEYBOARD and len(payload) >= 3:
            usage_id, action = struct.unpack_from("<HB", payload, 0)
            mapping = hid_usage_to_vk(usage_id)
            if mapping is not None:
                vk_code, extended = mapping
                send_virtual_key(vk_code, action, extended)
        elif event_type == EVENT_TEXT and len(payload) >= 1:
            text_len = payload[0]
            text_data = payload[1 : 1 + text_len]
            if text_data:
                send_unicode_text(text_data.decode("utf-8", errors="ignore"))
        elif event_type == EVENT_PING:
            return
        elif event_type == EVENT_CONSUMER and len(payload) >= 3:
            usage_id, action = struct.unpack_from("<HB", payload, 0)
            mapping = consumer_usage_to_vk(usage_id)
            if mapping is not None:
                vk_code, extended = mapping
                send_virtual_key(vk_code, action, extended)
    except Exception as exc:
        print(f"Input dispatch failed: {exc}")


def notification_handler(_: int, data: bytearray) -> None:
    dispatch_packet(bytes(data))


def get_local_ip_for_target(remote_host: str) -> str:
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as local_socket:
            local_socket.connect((remote_host, 1))
            return local_socket.getsockname()[0]
    except OSError:
        return "127.0.0.1"


def extract_device_uuids(device: Any, advertisement_data: Any = None) -> List[str]:
    if advertisement_data is not None:
        advertised_uuids = getattr(advertisement_data, "service_uuids", None) or []
        if advertised_uuids:
            return [str(uuid).lower() for uuid in advertised_uuids]

    metadata = getattr(device, "metadata", None)
    if isinstance(metadata, dict):
        metadata_uuids = metadata.get("uuids") or metadata.get("service_uuids") or []
        if metadata_uuids:
            return [str(uuid).lower() for uuid in metadata_uuids]

    fallback_uuids = getattr(device, "service_uuids", None) or []
    return [str(uuid).lower() for uuid in fallback_uuids]


def format_device_line(index: int, device: Any, advertisement_data: Any = None) -> str:
    name = device.name or "<no-name>"
    uuids = extract_device_uuids(device, advertisement_data)
    has_service = SERVICE_UUID.lower() in uuids
    marker = "*" if has_service else " "
    return f"[{index}] {marker} {name} | {device.address}"


async def scan_devices(scan_time: float):
    print(f"Scanning for BLE peripherals ({scan_time:.1f}s)...")
    try:
        discovered = await BleakScanner.discover(timeout=scan_time, return_adv=True)
    except TypeError:
        devices = await BleakScanner.discover(timeout=scan_time)
        unique_devices: Dict[str, Tuple[Any, Optional[Any]]] = {}
        for device in devices:
            unique_devices[device.address] = (device, None)
        return list(unique_devices.values())

    unique_devices: Dict[str, Tuple[Any, Optional[Any]]] = {}
    if isinstance(discovered, dict):
        for entry in discovered.values():
            if isinstance(entry, tuple) and len(entry) >= 2:
                device = entry[0]
                advertisement_data = entry[1]
            else:
                device = entry
                advertisement_data = None

            unique_devices[device.address] = (device, advertisement_data)
    else:
        for device in discovered:
            unique_devices[device.address] = (device, None)

    return list(unique_devices.values())


async def select_target_address(scan_time: float) -> Optional[str]:
    while True:
        devices = await scan_devices(scan_time)
        if not devices:
            print("No BLE devices found. Press Enter to scan again or q to quit.")
            if input("> ").strip().lower() == "q":
                return None
            continue

        print("\nFound devices (* = service UUID match):")
        for index, entry in enumerate(devices):
            device, advertisement_data = entry
            print(format_device_line(index, device, advertisement_data))

        print("\nSelect device index, paste address, r to rescan, q to quit")
        choice = input("> ").strip()

        if not choice:
            continue

        normalized = choice.lower()
        if normalized == "q":
            return None
        if normalized == "r":
            continue

        if choice.isdigit():
            selected_index = int(choice)
            if 0 <= selected_index < len(devices):
                return devices[selected_index][0].address
            print("Invalid index")
            continue

        return choice


async def connect_loop(target_address: str):
    while True:
        try:
            print(f"Connecting to BLE target {target_address}...")
            async with BleakClient(target_address, timeout=15.0) as client:
                print(f"BLE connected: {target_address}")
                await client.start_notify(INPUT_CHARACTERISTIC_UUID, notification_handler)
                try:
                    await client.write_gatt_char(
                        CONTROL_CHARACTERISTIC_UUID,
                        bytes([PACKET_MAGIC, PACKET_VERSION, EVENT_PING]),
                        response=False,
                    )
                except Exception:
                    pass

                while client.is_connected:
                    await asyncio.sleep(0.25)

        except Exception as exc:
            print(f"BLE connection error: {exc}")

        print("BLE disconnected. Reconnecting in 2 seconds...")
        await asyncio.sleep(2)


async def handle_wifi_client(websocket, auth_token: str):
    peer = websocket.remote_address
    print(f"Wi-Fi client connected: {peer}")

    try:
        auth_payload = await asyncio.wait_for(websocket.recv(), timeout=5.0)
        auth_text = auth_payload if isinstance(auth_payload, str) else auth_payload.decode("utf-8", errors="ignore")

        if not auth_text.startswith(AUTH_PREFIX):
            await websocket.send("AUTH_FAIL")
            await websocket.close(code=4003, reason="Missing auth token")
            print(f"Wi-Fi auth missing from {peer}")
            return

        incoming_token = auth_text[len(AUTH_PREFIX) :]
        if incoming_token != auth_token:
            await websocket.send("AUTH_FAIL")
            await websocket.close(code=4003, reason="Invalid auth token")
            print(f"Wi-Fi auth failed for {peer}")
            return

        await websocket.send("AUTH_OK")

        async for message in websocket:
            if isinstance(message, str):
                packet = message.encode("utf-8", errors="ignore")
            else:
                packet = bytes(message)
            dispatch_packet(packet)
    except ConnectionClosed:
        pass
    except Exception as exc:
        print(f"Wi-Fi client error: {exc}")
    finally:
        print(f"Wi-Fi client disconnected: {peer}")


async def run_websocket_server(host: str, port: int, auth_token: str, ssl_context: Optional[ssl.SSLContext]):
    async def websocket_handler(websocket):
        await handle_wifi_client(websocket, auth_token)

    async with websockets.serve(websocket_handler, host, port, max_size=1024 * 1024, ssl=ssl_context):
        scheme = "wss" if ssl_context is not None else "ws"
        print(f"Wi-Fi WebSocket server listening on {scheme}://{host}:{port}")
        await asyncio.Future()


class DiscoveryProtocol(asyncio.DatagramProtocol):
    def __init__(self, websocket_port: int, use_tls: bool):
        self.websocket_port = websocket_port
        self.use_tls = use_tls
        self.transport = None

    def connection_made(self, transport):
        self.transport = transport

    def datagram_received(self, data: bytes, addr):
        incoming_text = data.decode("utf-8", errors="ignore").strip()
        if incoming_text != DISCOVERY_MAGIC:
            return

        local_ip = get_local_ip_for_target(addr[0])
        ws_scheme = "wss" if self.use_tls else "ws"
        payload = {
            "app": "BLERemotePad",
            "version": 1,
            "ws_url": f"{ws_scheme}://{local_ip}:{self.websocket_port}",
            "ws_port": self.websocket_port,
            "host": local_ip,
            "name": socket.gethostname(),
            "secure": self.use_tls,
        }

        if self.transport is not None:
            self.transport.sendto(json.dumps(payload).encode("utf-8"), addr)


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


async def run(args):
    tasks = []
    ssl_context = build_ssl_context(args)

    target_address = None
    if not args.wifi_only:
        target_address = args.address
        if target_address is None:
            target_address = await select_target_address(args.scan_time)

        if target_address is not None:
            tasks.append(asyncio.create_task(connect_loop(target_address)))
        elif args.no_wifi:
            print("No BLE target selected and Wi-Fi disabled. Exit.")
            return
        else:
            print("BLE target not selected. Running in Wi-Fi-only mode.")

    if not args.no_wifi:
        tasks.append(
            asyncio.create_task(
                run_websocket_server(args.wifi_host, args.wifi_port, args.wifi_token, ssl_context)
            )
        )

        if not args.no_discovery:
            tasks.append(
                asyncio.create_task(
                    run_discovery_server(
                        args.discovery_host,
                        args.discovery_port,
                        args.wifi_port,
                        ssl_context is not None,
                    )
                )
            )

    if not tasks:
        print("No transport enabled. Exit.")
        return

    done, pending = await asyncio.wait(tasks, return_when=asyncio.FIRST_EXCEPTION)

    for task in pending:
        task.cancel()

    for task in done:
        exception = task.exception()
        if exception is not None:
            raise exception


def parse_args():
    parser = argparse.ArgumentParser(
        description="Windows receiver for iPhone BLE and Wi-Fi mouse+keyboard packets.",
    )
    parser.add_argument(
        "--address",
        help="Manual BLE device address (skip interactive BLE scan).",
    )
    parser.add_argument(
        "--scan-time",
        type=float,
        default=5.0,
        help="BLE scan duration in seconds for each interactive scan (default: 5.0).",
    )
    parser.add_argument(
        "--wifi-host",
        default="0.0.0.0",
        help="Host interface for Wi-Fi WebSocket server (default: 0.0.0.0).",
    )
    parser.add_argument(
        "--wifi-port",
        type=int,
        default=8765,
        help="Port for Wi-Fi WebSocket server (default: 8765).",
    )
    parser.add_argument(
        "--wifi-token",
        default="remotepad-token",
        help="Required auth token for Wi-Fi WebSocket clients.",
    )
    parser.add_argument(
        "--tls-cert",
        help="Path to TLS certificate (PEM) for enabling wss.",
    )
    parser.add_argument(
        "--tls-key",
        help="Path to TLS private key (PEM) for enabling wss.",
    )
    parser.add_argument(
        "--wss-only",
        action="store_true",
        help="Require TLS for Wi-Fi transport (needs --tls-cert and --tls-key).",
    )
    parser.add_argument(
        "--discovery-host",
        default="0.0.0.0",
        help="Host interface for UDP auto-discovery responder (default: 0.0.0.0).",
    )
    parser.add_argument(
        "--discovery-port",
        type=int,
        default=8766,
        help="UDP port for discovery responder (default: 8766).",
    )
    parser.add_argument(
        "--no-wifi",
        action="store_true",
        help="Disable Wi-Fi WebSocket fallback server.",
    )
    parser.add_argument(
        "--no-discovery",
        action="store_true",
        help="Disable UDP discovery responder.",
    )
    parser.add_argument(
        "--wifi-only",
        action="store_true",
        help="Do not start BLE flow, run only Wi-Fi WebSocket receiver.",
    )
    return parser.parse_args()


def build_ssl_context(args) -> Optional[ssl.SSLContext]:
    if not (args.wss_only or args.tls_cert or args.tls_key):
        return None

    if not args.tls_cert or not args.tls_key:
        raise ValueError("TLS mode requires both --tls-cert and --tls-key")

    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(certfile=args.tls_cert, keyfile=args.tls_key)
    return context


if __name__ == "__main__":
    try:
        asyncio.run(run(parse_args()))
    except ValueError as exc:
        print(f"Configuration error: {exc}")
    except KeyboardInterrupt:
        print("Stopped by user")
