# SnapmakerPrintTool
Snapmaker Print Tool

A Windows batch script to **upload, print, and monitor** your Snapmaker 3D printer via the Luban HTTP API. You can create three files to do all functions upload.bat, print.bat and monitor.bat.
Supports drag & drop, automatic printer discovery, keep‑alive for large files, smart plug control, and RTSP camera feed.

> Based on the original guide: [Snapmaker Forum – Automatic Start via Drag & Drop](https://forum.snapmaker.com/t/guide-automatic-start-via-drag-drop/29177)

---

## Features
- **Upload** – G‑code, NC, CNC, or firmware (`.bin`) files
- **Print** – automatic start after upload (optional monitoring)
- **Monitor** – real‑time progress, remaining time, and interactive controls
- **Drag & drop** – just drop a file onto the script
- **Automatic homing** – configurable (`always`, `auto`, `prompt`, `no`)
- **Keep‑alive** – prevents timeouts for large files (>15 MB)
- **Kasa Smart Plug** – auto power on/off printer
- **VLC RTSP camera** – launch live view while monitoring
- **Audio alerts** – beep on print completion (customizable)
- **Clean shutdown** – removes temporary files and orphaned processes

---

## Requirements
| Requirement | Details |
|-------------|---------|
| **OS** | Windows 7 / 8 / 10 / 11 |
| **curl.exe** | Built‑in on Windows 10/11 – if missing, install from [curl.se](https://curl.se/) |
| **PowerShell** | Included with Windows |
| **Snapmaker printer** | Firmware with HTTP API (Luban 4.x+) |
| **VLC (optional)** | For RTSP camera – [videolan.org](https://www.videolan.org/vlc/) |
| **hs100.exe (optional)** | For Kasa smart plug – [frogedude/hs100](https://github.com/frogedude/hs100) |

---

## Installation
1. Download `SnapmakerPrintTool.bat` to any folder.
2. *(Optional)* For Kasa support: place `hs100.exe` in the same folder, a `hs100\` subfolder, or add it to your `PATH`.
3. *(Optional)* For VLC camera: install VLC media player (standard location).

No registry changes or administrator rights are required.

---

## Configuration
Open the script in a text editor (Notepad, VS Code, etc.).  
All user settings are at the top, clearly marked as `USER CONFIGURATION`.

| Variable | Description | Default |
|----------|-------------|---------|
| `MODE` | `print` (upload+print+monitor), `upload` (only upload), `monitor` (only monitor current print) | `upload` |
| `USE_LUBAN` | `yes` = read IP/token from `%APPDATA%\snapmaker-luban\machine.json`, `no` = use hardcoded `IP`/`TOKEN` | `yes` |
| `IP` / `TOKEN` | Used only if `USE_LUBAN=no` or Luban config missing | `ip` / `token` |
| `HOMING_MODE` | `always`, `auto` (home if not homed), `prompt`, `no` | `auto` |
| `LIMIT` | File size (bytes) above which keep‑alive is enabled | `15728640` (15 MB) |
| `KEEPALIVE` | Seconds between keep‑alive requests | `2` |
| `TIMEOUT` | Seconds to wait after success before closing (`0` = wait for key) | `3` |
| `TIMEOUT_FAIL` | Seconds to wait after failure before exiting | `5` |
| `MONITOR` | `yes`/`no` – show interactive monitor after starting print | `yes` |
| `SOUND` | `yes`/`no` – play beep on print completion | `yes` |
| `SOUND_METHOD` | `default` (Windows system beep) or `powershell` (880 Hz, 300 ms) | `default` |
| `SOUND_COUNT` | Number of beeps (1–10) | `1` |
| `VLC` | `yes`/`no` – launch VLC with RTSP camera on monitor start | `no` |
| `CAMERA_RTSP` | RTSP URL for your Snapmaker camera | `rtsp://...` |
| `KASA` | `yes`/`no` – enable Kasa smart plug control | `no` |
| `KASA_IP` | IP address of the smart plug | `192.168.1.100` |
| `KASA_AUTO_POWER_ON` | `yes` = turn plug on before upload/print | `yes` |
| `KASA_AUTO_POWER_OFF` | `yes` = turn plug off after print completion | `yes` |

> **Tip:** If you use Luban, leave `USE_LUBAN=yes`. The script automatically finds your printer’s IP and token from `machine.json`.

---

## Usage:
### Drag & Drop (recommended)
1. Configure the script (set `MODE`, homing, etc.).
2. Drag any supported file (`.gcode`, `.nc`, `.cnc`, `.bin`) and drop it onto `SnapmakerPrintTool.bat`.
3. The script will:
   - Check printer status
   - Home if needed (according to `HOMING_MODE`)
   - Upload the file
   - If `MODE=print` – start printing and optionally monitor
   - If `MODE=upload` – upload only

### Double‑click / Command line
Run without a file – you will be prompted to drag one.
cmd
SnapmakerPrintTool.bat "C:\path\to\your\file.gcode"
