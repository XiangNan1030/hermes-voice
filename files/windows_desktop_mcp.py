#!/usr/bin/env python3
"""
Windows Desktop MCP Server — 通过 PyAutoGUI 提供截屏、鼠标、键盘能力

Hermes 配置:
  mcp_servers:
    windows_desktop:
      command: "python3"
      args: ["D:/hermes/scripts/windows_desktop_mcp.py"]
"""

import os, sys, json, tempfile, time
from pathlib import Path

if sys.platform != "win32":
    raise RuntimeError("此 MCP 服务仅支持 Windows")

import pyautogui
import mss
from mcp.server.fastmcp import FastMCP

# 截图目录
SCREENSHOT_DIR = os.environ.get(
    "HERMES_SCREENSHOT_DIR",
    os.path.join(tempfile.gettempdir(), "hermes_screenshots"),
)
os.makedirs(SCREENSHOT_DIR, exist_ok=True)

pyautogui.FAILSAFE = True
pyautogui.PAUSE = 0.1

mcp = FastMCP("windows-desktop")


# ── 工具定义 ──────────────────────────────────────────────────────────

@mcp.tool()
def screenshot(filename: str = "") -> str:
    """截取当前屏幕，保存为 PNG，返回文件路径。
    参数 filename 可选，不传则自动命名。
    使用 DirectX 捕获，确保截取真实桌面内容。"""
    import mss
    with mss.mss() as sct:
        # monitor 1 = 主显示器
        monitor = sct.monitors[1]
        img = sct.grab(monitor)
        if not filename:
            filename = f"screenshot_{int(time.time())}.png"
        filepath = os.path.join(SCREENSHOT_DIR, filename)
        mss.tools.to_png(img.rgb, img.size, output=filepath)
        return json.dumps({"path": filepath, "size": f"{img.width}x{img.height}"})


@mcp.tool()
def mouse_move(x: int, y: int, duration: float = 0.2) -> str:
    """移动鼠标到 (x, y)。duration 秒内平滑移动。"""
    pyautogui.moveTo(x, y, duration=duration)
    return json.dumps({"x": x, "y": y, "moved": True})


@mcp.tool()
def mouse_click(x: int = -1, y: int = -1, button: str = "left", clicks: int = 1) -> str:
    """鼠标点击。(x,y) 默认 -1 表示当前位置。button: left/right/middle。clicks: 1=单击 2=双击。"""
    if x >= 0 and y >= 0:
        pyautogui.click(x, y, clicks=clicks, button=button)
    else:
        pyautogui.click(clicks=clicks, button=button)
    pos = pyautogui.position()
    return json.dumps({"clicked": True, "position": f"{pos.x},{pos.y}", "button": button})


@mcp.tool()
def mouse_scroll(clicks: int) -> str:
    """鼠标滚轮。正数上滚，负数下滚。"""
    pyautogui.scroll(clicks)
    return json.dumps({"scrolled": clicks})


@mcp.tool()
def type_text(text: str, interval: float = 0.05) -> str:
    """键盘输入文字（剪贴板方案，支持中英文）。"""
    try:
        import pyperclip
        pyperclip.copy(text)
        pyautogui.hotkey('ctrl','v')
    except:
        pyautogui.typewrite(text, interval=interval)
    return json.dumps({"typed": True, "length": len(text)})


@mcp.tool()
def key_press(keys: str) -> str:
    """按下组合键，多键用 + 连接。例如 'enter', 'ctrl+c', 'alt+tab'。"""
    pyautogui.hotkey(*keys.split("+"))
    return json.dumps({"pressed": keys})


@mcp.tool()
def screen_size() -> str:
    """获取屏幕分辨率。"""
    s = pyautogui.size()
    return json.dumps({"width": s.width, "height": s.height})


@mcp.tool()
def mouse_position() -> str:
    """获取当前鼠标坐标。"""
    p = pyautogui.position()
    return json.dumps({"x": p.x, "y": p.y})


@mcp.tool()
def get_active_window() -> str:
    """获取当前活动窗口标题（Windows）。"""
    import ctypes
    from ctypes import wintypes
    user32 = ctypes.windll.user32
    hwnd = user32.GetForegroundWindow()
    length = user32.GetWindowTextLengthW(hwnd)
    buf = ctypes.create_unicode_buffer(length + 1)
    user32.GetWindowTextW(hwnd, buf, length + 1)
    return json.dumps({"title": buf.value})


# ── 启动 ──────────────────────────────────────────────────────────────
if __name__ == "__main__":
    mcp.run(transport="stdio")
