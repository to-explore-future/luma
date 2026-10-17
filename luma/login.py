"""登录自启：写 ~/Library/LaunchAgents/com.tcxt.luma.plist。"""

import os
import plistlib
import subprocess
from pathlib import Path

LABEL = "com.tcxt.luma"
AGENT_PATH = Path.home() / "Library/LaunchAgents" / f"{LABEL}.plist"


def launcher_path():
    """找到 Luma.app/Contents/MacOS/Luma；不在 bundle 里跑就返回 None。"""
    here = Path(__file__).resolve()
    for parent in here.parents:
        if parent.name == "Contents":
            candidate = parent / "MacOS" / "Luma"
            if candidate.exists():
                return candidate
    return None


def _domain():
    return f"gui/{os.getuid()}"


def login_enabled():
    if not AGENT_PATH.exists():
        return False
    try:
        out = subprocess.run(
            ["launchctl", "print", f"{_domain()}/{LABEL}"],
            capture_output=True,
            text=True,
            timeout=5,
        )
        return out.returncode == 0
    except (OSError, subprocess.SubprocessError):
        return False


def enable_login():
    launcher = launcher_path()
    if launcher is None:
        raise RuntimeError("只能在 Luma.app 里设置开机自启（找不到 Launcher）")

    AGENT_PATH.parent.mkdir(parents=True, exist_ok=True)
    state_dir = Path.home() / "Library" / "Application Support" / "Luma"
    state_dir.mkdir(parents=True, exist_ok=True)
    payload = {
        "Label": LABEL,
        "ProgramArguments": [str(launcher), "--agent"],
        "RunAtLoad": True,
        "KeepAlive": {"SuccessfulExit": False},
        "LimitLoadToSessionType": "Aqua",
        "ProcessType": "Interactive",
        "StandardOutPath": str(state_dir / "agent.out.log"),
        "StandardErrorPath": str(state_dir / "agent.err.log"),
    }
    with open(AGENT_PATH, "wb") as fh:
        plistlib.dump(payload, fh)

    subprocess.run(["launchctl", "bootout", f"{_domain()}/{LABEL}"],
                   capture_output=True, timeout=5)
    done = subprocess.run(["launchctl", "bootstrap", _domain(), str(AGENT_PATH)],
                          capture_output=True, text=True, timeout=10)
    if done.returncode != 0:
        # 老系统 / 特殊情况下退回 load
        subprocess.run(["launchctl", "load", "-w", str(AGENT_PATH)],
                       capture_output=True, timeout=10)
    return True


def disable_login():
    subprocess.run(["launchctl", "bootout", f"{_domain()}/{LABEL}"],
                   capture_output=True, timeout=5)
    try:
        AGENT_PATH.unlink()
    except OSError:
        pass
    return True


def launch_agent_status():
    """launchctl 里能不能查到（比看文件准，文件在但没加载也常见）。"""
    try:
        out = subprocess.run(
            ["launchctl", "print", f"{_domain()}/{LABEL}"],
            capture_output=True,
            text=True,
            timeout=5,
        )
        if out.returncode == 0:
            return "已加载"
    except (OSError, subprocess.SubprocessError):
        pass
    return "已加载" if AGENT_PATH.exists() else "未安装"
