"""状态持久化：每块屏最后一次的亮度值 / 控制方式 / 全局设置。

文件位置：~/Library/Application Support/Luma/state.json
保存的是"这台显示器应该有多亮"，唤醒后就是拿它来重新写回去。
"""

import json
import os
import tempfile
import threading
from pathlib import Path

STATE_DIR = Path.home() / "Library/Application Support/Luma"
STATE_PATH = STATE_DIR / "state.json"
LOG_PATH = STATE_DIR / "luma.log"

DEFAULT_SETTINGS = {
    "force_backend": "auto",   # auto / native / gamma（全局）
    "launch_at_login": False,
    "watchdog": False,         # 定时自检，默认关闭，避免和 Night Shift 之类打架
}


class Store:
    def __init__(self, path=STATE_PATH):
        self.path = Path(path)
        self._lock = threading.RLock()
        self.data = {"version": 1, "displays": {}, "settings": dict(DEFAULT_SETTINGS)}
        self.load()

    # ---- 读写文件 -----------------------------------------------------------
    def load(self):
        """读状态文件。

        读失败（文件正在被替换、临时不可读）时**保留内存里的数据**，
        绝不能当成"空状态"——否则下一次刷新会把当前亮度当成记录值写回去，
        用户的设置就凭空丢了。
        """
        with self._lock:
            try:
                text = self.path.read_text("utf-8")
            except FileNotFoundError:
                text = None          # 首次运行，保持默认
            except OSError:
                return               # 读取失败：保留现状
            if text is None:
                return
            try:
                raw = json.loads(text)
            except ValueError:
                return               # 坏文件：保留现状
            if isinstance(raw, dict):
                displays = raw.get("displays")
                settings = raw.get("settings")
                self.data = {
                    "version": 1,
                    "displays": displays if isinstance(displays, dict) else {},
                    "settings": {**DEFAULT_SETTINGS, **(settings or {})},
                }

    def save(self):
        with self._lock:
            try:
                self.path.parent.mkdir(parents=True, exist_ok=True)
                fd, tmp = tempfile.mkstemp(dir=str(self.path.parent), prefix=".state-")
                try:
                    with os.fdopen(fd, "w", encoding="utf-8") as fh:
                        json.dump(self.data, fh, ensure_ascii=False, indent=2)
                        fh.write("\n")
                    os.replace(tmp, self.path)
                except BaseException:
                    try:
                        os.unlink(tmp)
                    except OSError:
                        pass
                    raise
            except OSError:
                pass

    # ---- 单屏状态 -----------------------------------------------------------
    def entry(self, key):
        with self._lock:
            return self.data["displays"].get(key)

    def remember(self, display, value, backend=None):
        with self._lock:
            old = self.data["displays"].get(display.key) or {}
            entry = {
                "name": display.name,
                "value": round(float(value), 4),
                "backend": backend or old.get("backend"),
                "vendor": display.vendor,
                "model": display.model,
                "serial": display.serial,
                "builtin": display.builtin,
            }
            self.data["displays"][display.key] = entry
            return entry

    def value_for(self, key, default=None):
        with self._lock:
            entry = self.data["displays"].get(key)
            if not entry:
                return default
            try:
                return float(entry.get("value"))
            except (TypeError, ValueError):
                return default

    def backend_for(self, key):
        with self._lock:
            entry = self.data["displays"].get(key) or {}
            return entry.get("backend")

    def set_backend(self, key, backend):
        with self._lock:
            entry = self.data["displays"].get(key)
            if entry is None:
                return False
            entry["backend"] = backend
            return True

    # ---- 全局设置 -----------------------------------------------------------
    @property
    def settings(self):
        with self._lock:
            return dict(self.data["settings"])

    def set_setting(self, name, value):
        with self._lock:
            self.data["settings"][name] = value
