# Important note
## กูทำเพราะกูอยากทำ ก็แค่นั้น ไม่มีเชี่ยไรเลย

## Webcam Mode (LAN / USB tethering network)

This project now includes a dedicated Webcam tab on iOS.

### What it does
- iPhone captures camera frames and streams to Windows over WebSocket.
- Windows receives frames and publishes a Virtual Camera device that Zoom/Meet/Discord can use.
- Works over normal LAN Wi-Fi or USB Personal Hotspot (USB network path).

### Windows setup
1. Install Python dependencies:
	- `pip install -r requirements.txt`
2. Start webcam receiver:
	- `python webcam_receiver.py --webcam-host 0.0.0.0 --webcam-port 8767 --webcam-token remotepad-token`
3. In your video app, select the virtual camera device created by `pyvirtualcam`.

### iOS setup
1. Open the new `Webcam` workspace tab.
2. Choose transport mode: `Wi-Fi` or `USB`.
3. Set URL to your Windows endpoint, for example:
	- `ws://192.168.1.100:8767`
   - USB mode commonly uses `ws://172.20.10.2:8767`
4. Set token to match Windows receiver token.
5. Choose camera: `Front` or `Back`.
6. Choose resolution and FPS.
7. If camera setup fails, try `Back` camera or `720p`.
8. `Enable microphone audio` default is OFF.
9. Tap `Start Webcam`.

### Screen Awake
- In Settings workspace, enable `Keep screen awake` to prevent iPhone display sleep while using controls/webcam.

### Notes
- iOS cannot expose native USB UVC directly; USB mode here means USB network tethering.
- Target latency under 200ms depends on LAN quality and host performance.
- 1080p30 is baseline; 1080p60 depends on device thermal/network headroom.