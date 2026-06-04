#!/usr/bin/env python3
"""Hermes Voice Web — 语音 AI + 工具调用 + 粒子特效"""
import os, sys, json, time, io, base64, warnings, asyncio, datetime, re, subprocess, shutil
import ctypes
warnings.filterwarnings("ignore")

HERMES_HOME = os.environ.get("HERMES_HOME",
    "D:/hermes" if sys.platform == "win32" else os.path.expanduser("~/.hermes"))
IS_WIN = sys.platform == "win32"
os.environ["HF_ENDPOINT"] = "https://hf-mirror.com"

# ── 交互日志 ──────────────────────────────────────────────
LOG_DIR = os.path.join(HERMES_HOME, "logs")
os.makedirs(LOG_DIR, exist_ok=True)
LOG_PATH = os.path.join(LOG_DIR, "voice_interactions.log")
MAX_LOG_SIZE = 2 * 1024 * 1024  # 2 MB 轮转

def voice_log(typ, detail):
    ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    line = f"[VOICE] [{ts}] [{typ}] {detail}\n"
    print(line, end="", flush=True)
    try:
        with open(LOG_PATH, "a", encoding="utf-8") as f:
            f.write(line)
            if os.path.getsize(LOG_PATH) > MAX_LOG_SIZE:
                bak = LOG_PATH + ".1"
                if os.path.exists(bak):
                    os.remove(bak)
                os.rename(LOG_PATH, bak)
    except:
        pass

import numpy as np
from faster_whisper import WhisperModel
from openai import OpenAI
import edge_tts, yaml
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import HTMLResponse
import uvicorn

SAMPLE_RATE = 16000

print("Loading Whisper base (CPU)...", flush=True, end=" ")
whisper = WhisperModel("base", device="cpu", compute_type="int8", download_root=os.path.join(HERMES_HOME, "models", "whisper"))
print("OK", flush=True)

try:
    with open(os.path.join(HERMES_HOME, "config.yaml"), encoding="utf-8") as f:
        cfg = yaml.safe_load(f)
except (FileNotFoundError, KeyError) as e:
    print(f"[WARN] config.yaml not found or invalid: {e}", flush=True)
    print("  Using defaults. Set DEEPSEEK_API_KEY env var or edit config.yaml", flush=True)
    cfg = {"model": {"api_key": os.environ.get("DEEPSEEK_API_KEY", ""),
                      "base_url": "https://api.deepseek.com/v1",
                      "default": "deepseek-v4-pro"}}
model_cfg = cfg.get("model", {})
deepseek = OpenAI(
    api_key=model_cfg.get("api_key") or os.environ.get("DEEPSEEK_API_KEY") or "",
    base_url=model_cfg.get("base_url", "https://api.deepseek.com/v1"))
model_name = model_cfg.get("default", "deepseek-v4-pro")
print(f"LLM: {model_name}", flush=True)

app = FastAPI()
# HTML 路径：优先找安装包里的，其次当前目录，最后脚本同目录
_script_dir = os.path.dirname(os.path.abspath(__file__))
_candidates = [
    os.path.join(_script_dir, "voice_particles_v2.html"),
    os.path.join(_script_dir, "..", "..", "..", "hermes-webui", "output", "voice_particles_v2.html"),
    os.path.join(HERMES_HOME, "scripts", "voice_particles_v2.html"),
]
HTML_PATH = ""
for _c in _candidates:
    if os.path.exists(_c): HTML_PATH = _c; break
if not HTML_PATH: HTML_PATH = _candidates[0]  # 兜底

@app.get("/")
async def home():
    if os.path.exists(HTML_PATH):
        with open(HTML_PATH, encoding="utf-8") as f:
            return HTMLResponse(f.read())
    return HTMLResponse("<h1>HTML not found</h1>")

def transcribe(audio_bytes: bytes, sr: int = 16000) -> str:
    audio = np.frombuffer(audio_bytes, dtype=np.float32)
    if audio.ndim > 1: audio = audio.mean(axis=1)
    audio = audio.astype(np.float32)
    if sr != 16000 and len(audio) > 0:
        ratio = 16000 / sr
        target_len = int(len(audio) * ratio)
        indices = np.linspace(0, len(audio)-1, target_len)
        audio = np.interp(indices, np.arange(len(audio)), audio).astype(np.float32)
    segments, _ = whisper.transcribe(audio, language="zh", beam_size=2,
        initial_prompt="以下是普通话的句子。")
    return " ".join([s.text for s in segments]).strip()

async def generate_tts(text: str) -> bytes:
    out = io.BytesIO()
    comm = edge_tts.Communicate(text, "zh-CN-XiaoxiaoNeural", rate="+10%")
    async for chunk in comm.stream():
        if chunk["type"] == "audio": out.write(chunk["data"])
    return out.getvalue()

# ── 工具集 ──────────────────────────────────────────────────────────

TOOLS = {}

def _register(name, desc):
    def decorator(fn):
        TOOLS[name] = (desc, fn)
        return fn
    return decorator

# ── 启动程序（支持快捷方式扫描） ──
@_register("open", "打开程序。支持: 记事本/计算器/抖音/wegame/网易云/桌面快捷方式路径")
def tool_open(app: str):
    app = app.strip().strip('"\'')
    # 1. 先查已知映射
    known = {
        "记事本":"notepad.exe","notepad":"notepad.exe",
        "计算器":"calc.exe","calc":"calc.exe",
        "画图":"mspaint.exe","mspaint":"mspaint.exe",
        "cmd":"cmd.exe","终端":"cmd.exe",
        "资源管理器":"explorer.exe","explorer":"explorer.exe",
        "网易云":r"D:\Wangyiyun\NetEase\CloudMusic\cloudmusic.exe",
        "网易云音乐":r"D:\Wangyiyun\NetEase\CloudMusic\cloudmusic.exe",
        "edge":"msedge.exe","浏览器":"msedge.exe",
        "steam":"steam://rungameid/",
    }
    low = app.lower()
    target = app  # 默认值
    if low in known:
        target = known[low]
    # 2. 扫描桌面快捷方式（仅 Windows）
    elif IS_WIN:
        desktop = os.path.join(os.environ.get("USERPROFILE",""), "Desktop")
        if os.path.isdir(desktop):
            for fn in os.listdir(desktop):
                if fn.lower().endswith(".lnk"):
                    name = fn[:-4].lower()
                    if low in name or name in low:
                        try:
                            import pythoncom; pythoncom.CoInitialize()
                            from win32com.client import Dispatch
                            shell = Dispatch("WScript.Shell")
                            target = shell.CreateShortcut(os.path.join(desktop, fn)).TargetPath
                            break
                        except: pass
    
    try:
        if os.path.exists(target):
            if IS_WIN: os.startfile(target)
            else: subprocess.Popen(["open" if sys.platform=="darwin" else "xdg-open", target])
        else:
            subprocess.Popen(target, shell=True)
        return f"已打开 {app}"
    except Exception as e:
        return f"无法打开 {app}: {e}"

# ── 系统命令（白名单，仅允许安全操作） ──
SAFE_CMDS = ["dir","echo","whoami","hostname","ipconfig","ping","tracert",
             "tasklist","date","time","ver","systeminfo","netstat","cd ","type",
             "set","find","findstr","where","help","clip","chcp","path","cls"]
@_register("run", "执行终端命令。如: dir D:\\hermes, tasklist, whoami, ipconfig")
def tool_run(cmd: str):
    low = cmd.lower().strip()
    base = low.split()[0] if low.split() else ""
    base = base.split("/")[-1].split("\\")[-1]  # 提取命令名
    if base not in SAFE_CMDS:
        return (f"[已拦截] '{base}' 不在安全命令列表中。\n"
                f"允许的命令: {', '.join(sorted(SAFE_CMDS[:10]))} 等")
    try:
        if IS_WIN:
            r = subprocess.run(["cmd","/c",cmd], capture_output=True, text=True,
                              timeout=30, encoding="utf-8", errors="replace")
        else:
            r = subprocess.run(cmd, shell=True, capture_output=True, text=True,
                              timeout=30, encoding="utf-8", errors="replace")
        return (r.stdout.strip() or r.stderr.strip())[:500] or "执行完成"
    except subprocess.TimeoutExpired:
        return "命令超时(>30s)"
    except Exception as e:
        return f"失败: {e}"

# ── 音量（Windows Core Audio API） ──
@_register("volume", "设置音量 0-100")
def tool_volume(level: str):
    if not IS_WIN: return "音量调节仅支持 Windows"
    try:
        pct = min(max(int(level.strip()), 0), 100)
        ps_code = f'''
Add-Type -TypeDefinition @"
using System.Runtime.InteropServices;
[Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IAudioEndpointVolume {{
    int GetMasterVolumeLevelScalar(out float f);
    int SetMasterVolumeLevelScalar(float f, System.Guid g);
}}
[Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDevice {{
    int Activate(ref System.Guid id, int clsCtx, int pAct, out IAudioEndpointVolume vol);
}}
[Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDeviceEnumerator {{
    int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice dev);
}}
public class Vol {{
    public static void Set(int pct) {{
        var eType = System.Type.GetTypeFromCLSID(new System.Guid("BCDE0395-E52F-467C-8E3D-C4579291692E"));
        var e = (IMMDeviceEnumerator)System.Activator.CreateInstance(eType);
        IMMDevice dev; e.GetDefaultAudioEndpoint(0, 0, out dev);
        IAudioEndpointVolume vol; dev.Activate(ref new System.Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), 7, 0, out vol);
        vol.SetMasterVolumeLevelScalar(pct/100f, new System.Guid());
    }}
}}
"@
[Vol]::Set({pct})
'''
        subprocess.run(["powershell", "-Command", ps_code], capture_output=True, timeout=10)
        return f"音量 {pct}%"
    except Exception as e:
        return f"失败: {e}"

# ── 时间 ──
@_register("time", "当前日期时间")
def tool_time(_=""):
    return datetime.datetime.now().strftime("%Y年%m月%d日 %H:%M:%S")

# ── 截图 ──
@_register("shot", "屏幕截图")
def tool_screenshot(_=""):
    import mss
    with mss.mss() as sct:
        img = sct.grab(sct.monitors[1])
        path = os.path.join(HERMES_HOME,"tmp",f"shot_{int(time.time())}.png")
        mss.tools.to_png(img.rgb,img.size,output=path)
    return f"截图: {path}"

# ── 鼠标点击 ──
@_register("click", "鼠标点击(x,y)。如: 500,300")
def tool_click(pos: str):
    import pyautogui
    parts = pos.replace("，",",").split(",")
    x, y = int(parts[0]), int(parts[1])
    pyautogui.click(x, y)
    return f"已点击 ({x},{y})"

# ── 键盘输入（剪贴板方案，支持中文） ──
@_register("type", "键盘输入文字（支持中英文）")
def tool_type(text: str):
    import pyautogui
    try:
        import pyperclip
        pyperclip.copy(text)
        pyautogui.hotkey('ctrl','v')
    except:
        pyautogui.typewrite(text, interval=0.05)
    return f"已输入: {text[:30]}"

# ── 委托给 Hermes CLI（复杂任务：文件操作、多步骤、桌面操控等）─────
if IS_WIN:
    HERMES_CLI = os.path.join(
        os.environ.get("LOCALAPPDATA", os.path.expanduser("~/AppData/Local")),
        "hermes", "hermes-agent", "venv", "Scripts", "hermes"
    )
else:
    HERMES_CLI = os.path.expanduser("~/.hermes/hermes-agent/venv/bin/hermes")

@_register("hermes", "复杂任务委托。打开桌面文件、整理文件夹、操作软件等内置工具做不了的事")
def tool_hermes(task: str):
    try:
        r = subprocess.run(
            [HERMES_CLI, "chat", "-Q", "-q", task],
            capture_output=True, text=True, timeout=120, encoding="utf-8", errors="replace",
            env={**os.environ, "HERMES_HOME": HERMES_HOME}
        )
        out = r.stdout
        lines = [l.strip() for l in out.split('\n') if l.strip() and not l.startswith(("session_id","[","hermes"))]
        return '\n'.join(lines[-3:]) or "处理完成"
    except subprocess.TimeoutExpired:
        return "处理超时"
    except Exception as e:
        return f"失败: {e}"

# ── Agent Loop ───────────────────────────────────────────────────────

SYSTEM = f"""你是Hermes AI语音助手，能说话也会干活。用中文，简短自然。

重要安全规则:
1. 不随意修改/删除电脑文件，操作前告诉用户要做什么
2. 每次操作后说明：做了什么、对电脑有无影响
3. 不确定时先问用户，不要自作主张
4. C盘和D:\\0000声卡文件绝对不能碰

可用工具:
{chr(10).join(f'- [{n}] {d}' for n,(d,_) in TOOLS.items())}

工具格式:
<tool>名字</tool>
<arg>参数</arg>

例: <tool>volume</tool><arg>50</arg>
例: <tool>time</tool><arg></arg>
例: <tool>open</tool><arg>记事本</arg>

收到工具结果后，用一句话告诉用户结果和是否有风险。不需要工具时直接聊。"""

history = [{"role": "system", "content": SYSTEM}]
MAX_HISTORY = 50

def agent_reply(text: str, is_cancelled=None) -> str:
    history.append({"role": "user", "content": text})
    # 定期裁剪历史，保留 system prompt + 最近对话
    if len(history) > MAX_HISTORY:
        history[:] = [history[0]] + history[-(MAX_HISTORY-1):]
    for _ in range(3):
        if is_cancelled and is_cancelled(): return "好的，已取消。"
        resp = deepseek.chat.completions.create(
            model=model_name, messages=history[-20:], max_tokens=300, temperature=0.7)
        reply = resp.choices[0].message.content
        history.append({"role": "assistant", "content": reply})
        
        m = re.search(r'<tool>(.*?)</tool>', reply, re.DOTALL)
        if m:
            name = m.group(1).strip()
            a = re.search(r'<arg>(.*?)</arg>', reply, re.DOTALL)
            arg = a.group(1).strip() if a else ""
            if name in TOOLS:
                if is_cancelled and is_cancelled(): return "好的，已取消。"
                try:
                    r = TOOLS[name][1](arg)
                    voice_log("TOOL", f"{name}({arg}) -> {r[:200]}")
                    print(f"  🔧 {name}({arg}) -> {r}", flush=True)
                except Exception as e:
                    r = f"失败: {e}"
                history.append({"role": "user", "content": f"[工具返回] {r}\n一句话告诉用户。"})
                continue
        if reply.strip(): return reply
        break
    return "抱歉，出了点问题。"

# ── WebSocket ────────────────────────────────────────────────────────

@app.websocket("/ws")
async def ws_endpoint(ws: WebSocket):
    await ws.accept()
    buf = bytearray(); sil = 0; spk = 0; csr = SAMPLE_RATE
    BPS = SAMPLE_RATE * 4; MIN = int(BPS * 0.5); SIL = int(BPS * 1.0); CD = int(BPS * 2.0); cd_rem = 0; TH = 0.008
    cancelled = False

    async def sm(t, **kw):
        try: await ws.send_json({"type": t, **kw})
        except: pass

    try:
        while True:
            raw = await ws.receive()
            if "bytes" in raw: chunk = raw["bytes"]
            elif "text" in raw:
                try:
                    m = json.loads(raw["text"])
                    if m.get("type") == "sr": csr = m["value"]
                    elif m.get("type") == "cancel":
                        cancelled = True
                        await sm("status", text="idle")
                        await sm("reply_text", text="已取消")
                        print("  ⏸️ 用户取消", flush=True)
                except: pass
                continue
            else: continue

            buf.extend(chunk)
            if cd_rem > 0: cd_rem -= len(chunk); continue

            e = float(np.sqrt(np.mean(np.frombuffer(chunk, np.float32) ** 2)))
            if e > TH: sil = 0; spk += len(chunk); await sm("status", text="listening")
            else: sil += len(chunk)

            if spk >= MIN and sil >= SIL:
                await sm("status", text="thinking")
                raw = bytes(buf); buf.clear(); sil = spk = 0
                txt = transcribe(raw, csr)
                if not txt or len(txt) < 2:
                    await sm("status", text="idle"); await sm("reply_text", text="没听清")
                    continue
                voice_log("STT", txt)
                print(f"  📝 {txt}", flush=True); await sm("user_text", text=txt)
                cancelled = False  # 重置
                reply = await asyncio.to_thread(agent_reply, txt, is_cancelled=lambda: cancelled)
                if cancelled:
                    await sm("status", text="idle"); cd_rem = CD; continue
                voice_log("REPLY", reply)
                print(f"  💬 {reply}", flush=True); await sm("reply_text", text=reply)
                await sm("status", text="speaking")
                try:
                    mp3 = await generate_tts(reply)
                    await sm("audio", data=base64.b64encode(mp3).decode())
                except: pass
                await sm("status", text="idle"); cd_rem = CD
    except WebSocketDisconnect: pass
    except Exception as e: print(f"WS: {e}", flush=True)

if __name__ == "__main__":
    print(f"\n  Hermes Voice http://127.0.0.1:8282\n")
    uvicorn.run(app, host="127.0.0.1", port=8282, log_level="warning")
