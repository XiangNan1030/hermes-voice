#!/usr/bin/env bash
# =============================================================================
# Hermes Voice 一键部署脚本 (跨平台: Windows/macOS/Linux)
# =============================================================================
# 自动检测操作系统和架构，安装完整 Hermes + 语音助手 环境
#
# 用法:
#   chmod +x setup.sh && ./setup.sh
#   Windows: 右键 Git Bash Here → ./setup.sh
#
# 可选参数:
#   --data-dir DIR   数据目录 (默认: Windows=D:/hermes, Unix=~/.hermes)
#   --app-dir DIR    程序目录 (默认: Windows=F:/Hermes, Unix=~/hermes-apps)
#   --skip-desktop   跳过 Hermes Desktop 安装
#   --skip-webui     跳过 Hermes WebUI
#   --dry-run        仅检测环境，不实际安装
#   -y               跳过确认，全部默认
# =============================================================================

set -euo pipefail

# ── 颜色 ──────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

step()  { echo -e "\n${CYAN}>>> $*${NC}"; }
ok()   { echo -e "    ${GREEN}[OK]${NC} $*"; }
warn() { echo -e "    ${YELLOW}[WARN]${NC} $*"; }
err()  { echo -e "    ${RED}[ERROR]${NC} $*"; }
info() { echo -e "    $*"; }

# ── 参数解析 ──────────────────────────────────────────────────────────
SKIP_DESKTOP=false; SKIP_WEBUI=false; DRY_RUN=false; AUTO_YES=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --data-dir) DATA_DIR="$2"; shift 2 ;;
        --app-dir)  APP_DIR="$2"; shift 2 ;;
        --skip-desktop) SKIP_DESKTOP=true; shift ;;
        --skip-webui)   SKIP_WEBUI=true; shift ;;
        --dry-run)  DRY_RUN=true; shift ;;
        -y)         AUTO_YES=true; shift ;;
        -h|--help)
            echo "用法: $0 [选项]"
            echo "  --data-dir DIR   数据目录"
            echo "  --app-dir DIR    程序目录"
            echo "  --skip-desktop   跳过桌面应用"
            echo "  --skip-webui     跳过 WebUI"
            echo "  --dry-run        环境检测"
            echo "  -y               全部默认"
            exit 0 ;;
        *) warn "未知参数: $1"; shift ;;
    esac
done

# ── 操作系统检测 ──────────────────────────────────────────────────────
detect_os() {
    case "$(uname -s)" in
        Darwin)  OS="macos" ;;
        MINGW*|MSYS*|CYGWIN*) OS="windows" ;;
        Linux)   OS="linux" ;;
        *)       err "不支持的操作系统: $(uname -s)"; exit 1 ;;
    esac
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64|amd64) ARCH="x64" ;;
        arm64|aarch64) ARCH="arm64" ;;
    esac
    echo -e "${BOLD}系统:${NC} $OS ($ARCH)"
}

# ── 路径设置 ──────────────────────────────────────────────────────────
set_paths() {
    case "$OS" in
        windows)
            # 磁盘 fallback：D:/F: 不存在则用用户目录
            if [[ -z "$DATA_DIR" ]]; then
                if [[ -d "/d" ]]; then DATA_DIR="D:/hermes"
                else DATA_DIR="$HOME/.hermes"; fi
            fi
            if [[ -z "$APP_DIR" ]]; then
                if [[ -d "/f" ]]; then APP_DIR="F:/Hermes"
                else APP_DIR="$HOME/Hermes"; fi
            fi
            VOICE_DIR="$DATA_DIR/voice"
            SCRIPTS_DIR="$DATA_DIR/scripts"
            WEBUI_DIR="${WEBUI_DIR:-$APP_DIR/hermes-webui}"
            DESKTOP_APP_DIR="$APP_DIR/HermesDesktop"
            AGENT_INSTALL_DIR="$DATA_DIR/hermes-agent"
            WIN_HOME="$(cmd.exe /c "echo %USERPROFILE%" 2>/dev/null | tr -d '\r' || echo "$HOME")"
            DESKTOP_PATH="$WIN_HOME/Desktop"
            PYTHON_CMD="python"
            VENV_PYTHON="$VOICE_DIR/venv/Scripts/python.exe"
            ;;
        macos)
            DATA_DIR="${DATA_DIR:-$HOME/.hermes}"
            APP_DIR="${APP_DIR:-$HOME/hermes-apps}"
            VOICE_DIR="$DATA_DIR/voice"
            SCRIPTS_DIR="$DATA_DIR/scripts"
            WEBUI_DIR="${WEBUI_DIR:-$APP_DIR/hermes-webui}"
            DESKTOP_APP_DIR="/Applications/Hermes.app"
            AGENT_INSTALL_DIR="$DATA_DIR/hermes-agent"
            PYTHON_CMD="python3"
            VENV_PYTHON="$VOICE_DIR/venv/bin/python3"
            ;;
        linux)
            DATA_DIR="${DATA_DIR:-$HOME/.hermes}"
            APP_DIR="${APP_DIR:-$HOME/hermes-apps}"
            VOICE_DIR="$DATA_DIR/voice"
            SCRIPTS_DIR="$DATA_DIR/scripts"
            WEBUI_DIR="${WEBUI_DIR:-$APP_DIR/hermes-webui}"
            DESKTOP_APP_DIR=""
            AGENT_INSTALL_DIR="$DATA_DIR/hermes-agent"
            PYTHON_CMD="python3"
            VENV_PYTHON="$VOICE_DIR/venv/bin/python3"
            SKIP_DESKTOP=true  # Linux 暂无 Desktop 版
            ;;
    esac
}

# ── 环境检测 ──────────────────────────────────────────────────────────
check_prereqs() {
    # Python
    if command -v python3 &>/dev/null; then
        PY_VER=$(python3 --version 2>&1 | awk '{print $2}')
        ok "Python: $PY_VER"
    elif command -v python &>/dev/null; then
        PY_VER=$(python --version 2>&1 | awk '{print $2}')
        ok "Python: $PY_VER"
    else
        err "需要 Python 3.11+"
        info "下载: https://www.python.org/downloads/"
        [[ "$DRY_RUN" != true ]] && exit 1
    fi

    # Git（可选，不再强制要求）
    if command -v git &>/dev/null; then
        ok "Git: $(git --version 2>&1 | head -1) (可选)"
    else
        info "Git 未安装（WebUI 将使用 zip 下载）"
    fi

    # 磁盘空间检测
    local free_kb
    if [[ "$OS" == "windows" ]]; then
        # Git Bash: 将 D:/hermes 转为 /d/hermes 再查 df
        local df_path
        df_path=$(cygpath "$DATA_DIR" 2>/dev/null || echo "$DATA_DIR")
        free_kb=$(df -k "$df_path" 2>/dev/null | awk 'NR==2{print $4}' || echo 0)
    else
        free_kb=$(df -k "$DATA_DIR" 2>/dev/null | awk 'NR==2{print $4}' || echo 0)
    fi
    local free_gb=$(( free_kb / 1024 / 1024 ))
    if [[ $free_gb -lt 2 ]]; then
        err "可用空间 ${free_gb}GB，建议至少 2GB"
        [[ "$DRY_RUN" != true ]] && exit 1
    else
        ok "可用空间: ${free_gb}GB"
    fi
}

# ── 目录创建 ──────────────────────────────────────────────────────────
create_dirs() {
    for d in "$DATA_DIR" "$VOICE_DIR" "$SCRIPTS_DIR" "$WEBUI_DIR" \
             "$DATA_DIR/logs" "$DATA_DIR/tmp" "$DATA_DIR/models/whisper" \
             "$DATA_DIR/sessions" "$DATA_DIR/skills" "$DATA_DIR/memories"; do
        mkdir -p "$d"
    done
    ok "目录结构已创建"
}

# ── 复制文件 ──────────────────────────────────────────────────────────
copy_files() {
    local src="$(cd "$(dirname "$0")" && pwd)/files"
    if [[ ! -d "$src" ]]; then
        warn "未找到 files/ 目录，使用当前目录下的脚本"
        src="$(cd "$(dirname "$0")" && pwd)"
    fi

    # 复制核心脚本
    for f in voice_server.py voice_particles_v2.html windows_desktop_mcp.py; do
        if [[ -f "$src/$f" ]]; then
            cp "$src/$f" "$SCRIPTS_DIR/" 2>/dev/null && info "  $f → $SCRIPTS_DIR/"
        else
            warn "  未找到 $f (跳过)"
        fi
    done

    # 复制 requirements
    if [[ -f "$src/requirements.txt" ]]; then
        cp "$src/requirements.txt" "$VOICE_DIR/"
    fi
}

# ── Python 虚拟环境 ───────────────────────────────────────────────────
setup_venv() {
    if [[ -d "$VOICE_DIR/venv" ]]; then
        ok "venv 已存在: $VOICE_DIR/venv"
    else
        info "创建虚拟环境..."
        "$PYTHON_CMD" -m venv "$VOICE_DIR/venv"
        ok "venv 已创建"
    fi

    # 升级 pip + 安装依赖
    info "安装 Python 依赖（可能需要几分钟）..."
    "$VENV_PYTHON" -m pip install --upgrade pip -q 2>/dev/null || true

    if [[ -f "$VOICE_DIR/requirements.txt" ]]; then
        "$VENV_PYTHON" -m pip install -r "$VOICE_DIR/requirements.txt" --timeout 300 -q 2>&1 | tail -3
    else
        # 直接安装核心依赖
        "$VENV_PYTHON" -m pip install \
            faster-whisper edge-tts fastapi uvicorn websockets openai \
            numpy sounddevice soundfile mss pyautogui pyyaml \
            --timeout 300 -q 2>&1 | tail -3
    fi
    ok "依赖安装完成"
}

# ── Whisper 模型 ──────────────────────────────────────────────────────
download_model() {
    local model_dir="$DATA_DIR/models/whisper/models--Systran--faster-whisper-base"
    if [[ -d "$model_dir" ]]; then
        ok "Whisper base 模型已下载"
    else
        info "下载 Whisper base 模型 (~250MB)..."
        "$VENV_PYTHON" -c "
import os; os.environ['HF_ENDPOINT']='https://hf-mirror.com'
from faster_whisper import WhisperModel
m = WhisperModel('base', device='cpu', compute_type='int8', download_root='$DATA_DIR/models/whisper')
print('OK')
" 2>&1
        ok "模型下载完成"
    fi
}

# ── Hermes CLI ─────────────────────────────────────────────────────────
install_hermes_cli() {
    local cli_bin="$AGENT_INSTALL_DIR/venv/bin/hermes"
    [[ "$OS" == "windows" ]] && cli_bin="$AGENT_INSTALL_DIR/venv/Scripts/hermes"

    if [[ -f "$cli_bin" ]] || command -v hermes &>/dev/null; then
        ok "Hermes CLI 已安装"
        return
    fi

    info "安装 Hermes CLI..."
    export HERMES_HOME="$DATA_DIR"
    bash <(curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh) 2>&1 | tail -5

    # 迁移到指定目录（如果装到了默认位置）
    local default_agent=""
    case "$OS" in
        macos|linux) default_agent="$HOME/.hermes/hermes-agent" ;;
        windows)     default_agent="$WIN_HOME/AppData/Local/hermes/hermes-agent" ;;
    esac
    if [[ -d "$default_agent" && "$default_agent" != "$AGENT_INSTALL_DIR" ]]; then
        mv "$default_agent" "$AGENT_INSTALL_DIR" 2>/dev/null || cp -R "$default_agent" "$AGENT_INSTALL_DIR"
        ok "CLI 已迁移到 $AGENT_INSTALL_DIR"
    fi
    ok "Hermes CLI 安装完成"
}

# ── Hermes WebUI ──────────────────────────────────────────────────────
install_webui() {
    if [[ -f "$WEBUI_DIR/server.py" ]]; then
        ok "WebUI 已存在: $WEBUI_DIR"
        return
    fi

    info "下载 Hermes WebUI..."
    local zip_file="$TMPDIR/hermes-webui.zip"
    local extract_dir="$TMPDIR/hermes-webui-extract"
    if curl -fsSL "https://github.com/nesquena/hermes-webui/archive/refs/heads/main.zip" -o "$zip_file" 2>&1; then
        mkdir -p "$extract_dir"
        unzip -qo "$zip_file" -d "$extract_dir"
        local inner="$extract_dir/hermes-webui-main"
        if [[ -d "$inner" ]]; then
            mkdir -p "$WEBUI_DIR"
            cp -R "$inner/"* "$WEBUI_DIR/" 2>/dev/null || true
        fi
        ok "WebUI 安装完成"
    else
        warn "WebUI 下载失败，语音助手仍可使用"
    fi
    # 清理
    rm -f "$zip_file" 2>/dev/null
    rm -rf "$extract_dir" 2>/dev/null
}

# ── 配置文件 ──────────────────────────────────────────────────────────
write_config() {
    local cfg="$DATA_DIR/config.yaml"
    if [[ -f "$cfg" ]]; then
        warn "config.yaml 已存在，跳过"
        return
    fi

    echo ""
    echo "  请输入 DeepSeek API Key（可从 https://platform.deepseek.com 获取）"
    echo "  如果现在没有，可以之后编辑 $cfg"
    read -r -p "  API Key (回车跳过): " api_key

    cat > "$cfg" << YAMLEOF
model:
  api_key: ${api_key:-YOUR_API_KEY}
  base_url: https://api.deepseek.com/v1
  default: deepseek-v4-pro
  provider: deepseek
agent:
  max_turns: 90
  tool_use_enforcement: auto
terminal:
  backend: local
  timeout: 180
compression:
  enabled: true
  threshold: 0.5
display:
  language: zh
memory:
  memory_enabled: true
  user_profile_enabled: true
delegation:
  max_iterations: 50
approvals:
  mode: manual
security:
  redact_secrets: true
tts:
  provider: edge
stt:
  enabled: true
  provider: local
onboarding:
  seen:
    api_key: true
    welcome: true
mcp_servers:
  windows_desktop:
    command: "$VENV_PYTHON"
    args:
      - "$SCRIPTS_DIR/windows_desktop_mcp.py"
    timeout: 30
_config_version: 24
YAMLEOF
    ok "config.yaml 已写入"

    # desktop.json
    echo '{"locale":"zh-CN","onboardingComplete":true}' > "$DATA_DIR/desktop.json"

    # SOUL.md
    echo "# SOUL" > "$DATA_DIR/SOUL.md"
}

# ── 创建快捷方式 ──────────────────────────────────────────────────────
create_launchers() {
    case "$OS" in
        windows)
            # 批处理启动器
            cat > "$SCRIPTS_DIR/启动Hermes语音.bat" << BATEOF
@echo off
title Hermes Voice
set HERMES_HOME=$DATA_DIR
cd /d $SCRIPTS_DIR
echo Starting Hermes Voice...
echo Open http://127.0.0.1:8282 in your browser
start http://127.0.0.1:8282
"$VENV_PYTHON" -u voice_server.py
pause >nul
BATEOF

            # 桌面快捷方式
            cat > /tmp/create_shortcut.vbs << VBSEOF
Set oWS = WScript.CreateObject("WScript.Shell")
sLink = oWS.SpecialFolders("Desktop") & "\\Hermes语音助手.lnk"
Set oL = oWS.CreateShortcut(sLink)
oL.TargetPath = "$SCRIPTS_DIR\\启动Hermes语音.bat"
oL.WorkingDirectory = "$SCRIPTS_DIR"
oL.Description = "Hermes Voice - 粒子特效+AI语音"
oL.Save
WScript.Echo "Done"
VBSEOF
            cscript //nologo "$(cygpath -w /tmp/create_shortcut.vbs)" 2>/dev/null && \
                ok "桌面快捷方式已创建" || warn "快捷方式创建失败"
            ;;

        macos|linux)
            # Shell 启动器
            cat > "$SCRIPTS_DIR/启动Hermes语音.sh" << SHEOF
#!/usr/bin/env bash
export HERMES_HOME="$DATA_DIR"
cd "$SCRIPTS_DIR"
# 杀掉旧进程
lsof -ti:8282 | xargs kill -9 2>/dev/null || true
# 打开浏览器
sleep 2 && open http://127.0.0.1:8282 2>/dev/null || xdg-open http://127.0.0.1:8282 2>/dev/null &
# 启动服务
$VENV_PYTHON voice_server.py
SHEOF
            chmod +x "$SCRIPTS_DIR/启动Hermes语音.sh"
            ok "启动脚本: $SCRIPTS_DIR/启动Hermes语音.sh"
            ;;
    esac
}

# ── 主流程 ────────────────────────────────────────────────────────────
main() {
    echo -e "${BOLD}============================================${NC}"
    echo -e "${BOLD}  Hermes Voice 一键部署${NC}"
    echo -e "${BOLD}============================================${NC}"
    echo ""

    detect_os
    set_paths

    echo ""
    info "数据目录: $DATA_DIR"
    info "程序目录: $APP_DIR"
    info "脚本目录: $SCRIPTS_DIR"
    echo ""

    if [[ "$DRY_RUN" == true ]]; then
        check_prereqs
        echo -e "\n${YELLOW}环境检测完成。运行 ./setup.sh 开始安装。${NC}"
        exit 0
    fi

    if [[ "$AUTO_YES" != true ]]; then
        echo -e "${YELLOW}按 Enter 开始安装，Ctrl+C 取消${NC}"
        read -r
    fi

    # ── 执行安装 ──
    step "1/9  检测环境"
    check_prereqs

    step "2/9  创建目录"
    create_dirs

    step "3/9  复制脚本"
    copy_files

    step "4/9  Python 环境"
    setup_venv

    step "5/9  Whisper 模型"
    download_model

    step "6/9  Hermes CLI"
    install_hermes_cli

    if [[ "$SKIP_WEBUI" != true ]]; then
        step "7/9  Hermes WebUI"
        install_webui
    fi

    step "8/9  配置文件"
    write_config

    step "9/9  启动器"
    create_launchers

    # ── 完成 ──
    echo ""
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}  部署完成！${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo ""
    echo "  启动方式:"
    case "$OS" in
        windows) echo "    双击桌面「Hermes语音助手」或运行 $SCRIPTS_DIR/启动Hermes语音.bat" ;;
        macos)   echo "    终端运行: $SCRIPTS_DIR/启动Hermes语音.sh" ;;
        linux)   echo "    终端运行: $SCRIPTS_DIR/启动Hermes语音.sh" ;;
    esac
    echo "    浏览器打开: http://127.0.0.1:8282"
    echo ""
}

main "$@"
