# Hermes Voice — Open-Source Voice AI Agent for Windows

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Platform: Windows](https://img.shields.io/badge/platform-Windows-blue.svg)]()

Real-time voice AI assistant with particle effects UI. Speak naturally, interrupt anytime, and let the AI control your desktop.

## Demo

Speak → whisper transcribes → LLM replies → TTS speaks → particle UI animates.

## Features

- **Real-time voice conversation** — VAD detects speech, auto-transcribes, auto-replies
- **Interruptible** — speak anytime to stop the AI mid-response
- **Particle effects UI** — visual feedback that pulses when you speak  
- **Agent tools** — open apps, adjust volume, take screenshots, run commands
- **Desktop control** — AI can click and type via MCP protocol
- **Cross-platform deploy** — Windows/macOS/Linux one-click install
- **Offline-capable** — pre-download models, work behind firewalls
- **Zero C: drive** — everything installs to D: or your chosen path

## Architecture

```
Browser (particle UI + mic)                 Python Server
     |        WebSocket audio                |
     | ---------------------------------->   |  VAD detection
     |                                       |  faster-whisper (STT)
     |                                       |  DeepSeek/OpenAI (LLM)
     |  <----------------------------------  |  edge-tts (TTS)
     |    text reply + mp3 audio             |
     |                                       |  Agent tools:
     |                                       |  - open apps
     |                                       |  - volume control
     |                                       |  - screenshots
     |                                       |  - terminal commands
     |                                       |  - mouse/keyboard (MCP)
```

## Quick Start

### Windows (one-click)

1. Double-click `一键安装.bat`
2. Enter your DeepSeek API key when prompted
3. Done — desktop shortcut created

### macOS / Linux

```bash
chmod +x setup.sh
./setup.sh
```

### Manual

```bash
# Install Hermes CLI first
# Then:
pip install -r files/requirements.txt
python files/voice_server.py
# Open http://127.0.0.1:8282
```

## Parameters

| Flag | Description |
|------|-------------|
| `-SkipVoice` | Skip voice assistant (CLI + WebUI only) |
| `-SkipWebUI` | Skip WebUI |
| `-DryRun` | Environment check only |
| `-Yes` | Auto-accept all defaults |

## Requirements

- Python 3.11+
- Git
- DeepSeek API key ([get one](https://platform.deepseek.com))
- ~3GB disk (pip packages + Whisper model)

## Project Structure

```
HermesVoice_Setup/
├── 一键安装.bat           # Windows launcher
├── setup.ps1              # PowerShell deployment
├── setup.sh               # Bash deployment (macOS/Linux)
├── files/
│   ├── voice_server.py    # Main voice AI server
│   ├── voice_particles_v2.html  # Particle UI
│   ├── windows_desktop_mcp.py   # Desktop control MCP
│   ├── config_template.yaml     # Config template
│   └── requirements.txt  # Python deps
└── README.md
```

## Why I Built This

I'm a sysadmin who wanted to explore AI. Instead of just using AI tools, I built one end-to-end — from voice recognition to LLM agent to desktop control to one-click deployment. This project is my portfolio piece for transitioning from traditional ops to AI engineering.

## License

MIT — use it, modify it, ship it.
