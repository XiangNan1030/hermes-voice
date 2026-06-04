# Hermes Voice — Open-Source Voice AI Agent

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Platform: Windows](https://img.shields.io/badge/platform-Windows-blue.svg)]()

**English** | [中文](#chinese)

Real-time voice AI assistant with particle effects UI. Speak naturally, interrupt anytime, and let the AI control your desktop.

## Features

- **Real-time voice** — VAD detects speech, auto-transcribes, auto-replies
- **Interruptible** — speak anytime to stop the AI mid-response
- **Particle effects UI** — visual feedback that pulses when you speak  
- **Agent tools** — open apps, adjust volume, take screenshots, run commands
- **Desktop control** — AI can click and type via MCP protocol
- **Cross-platform** — Windows/macOS/Linux one-click deploy
- **Offline-ready** — pre-download models, work behind firewalls
- **Zero C: drive** — everything installs to D: or your chosen path

## Quick Start

### Windows (one-click)

1. Double-click `一键安装.bat`
2. Enter DeepSeek API key when prompted
3. Done — desktop shortcut created

### Manual

```bash
pip install -r files/requirements.txt
python files/voice_server.py
# Open http://127.0.0.1:8282
```

## Architecture

```
Browser (particle UI + mic) → WebSocket audio → Python server
  → VAD → faster-whisper → DeepSeek LLM → edge-tts
  → reply text + mp3 audio → browser playback
  → Agent tools: open/volume/screenshot/terminal/click
```

## License

MIT

---

<h2 id="chinese">中文说明</h2>

## Hermes Voice — 开源语音 AI 助手

实时语音 AI 助手，带粒子特效界面。直接说话即可，随时打断，让 AI 帮你操控电脑。

## 功能特性

- **实时语音对话** — 语音活动检测自动触发，说完即识别
- **可打断** — AI 回复过程中随时插话打断
- **粒子特效** — 说话时粒子聚合并震动，静音时散成圆形
- **Agent 工具集** — 打开程序、调音量、截图、执行命令
- **桌面操控** — 通过 MCP 协议控制鼠标键盘
- **跨平台部署** — 支持 Windows/macOS/Linux 一键安装
- **离线可用** — 预先下载模型，内网环境也能用
- **零 C 盘占用** — 默认安装到 D 盘或自定义路径

## 快速开始（Windows）

1. 双击 `一键安装.bat`
2. 输入 DeepSeek API Key
3. 桌面自动生成快捷方式，双击即可使用

## 项目结构

```
HermesVoice_Setup/
├── 一键安装.bat              # Windows 双击入口
├── setup.ps1                 # PowerShell 部署脚本
├── setup.sh                  # Bash 部署脚本 (macOS/Linux)
└── files/
    ├── voice_server.py       # 语音 AI 服务端
    ├── voice_particles_v2.html  # 粒子特效界面
    ├── windows_desktop_mcp.py   # 桌面操控 MCP 服务
    ├── config_template.yaml     # 配置模板
    └── requirements.txt      # Python 依赖
```

## 关于项目

作者是一名传统运维工程师，通过业余时间自学 AI，从零搭建了这个端到端的语音 AI Agent 系统——包括语音识别、大模型调用、工具链、桌面操控、跨平台一键部署。这个项目是从运维转 AI 工程的作品集之一。

## 许可证

MIT — 自由使用、修改、分发。
