"""控制器：把「存了什么值」和「显示器现在多亮」对齐起来。

这里是整个工具的核心。唤醒失效的根因是系统在睡眠/唤醒时会把 gamma 表和
DisplayServices 状态重置掉，所以唤醒后必须主动把存下来的值重新写回去，
而且要写好几遍——系统自己也会在唤醒后一两秒里再动一次。
"""

import queue
import threading
import time
from datetime import datetime

from . import cg, displays as disp
from .store import LOG_PATH, STATE_PATH, Store

MAX_LOG_BYTES = 256 * 1024


def log(message):
    """简单文件日志，出问题（尤其是唤醒后）可以直接翻。"""
    try:
        LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
        try:
            if LOG_PATH.stat().st_size > MAX_LOG_BYTES:
                LOG_PATH.unlink()
        except OSError:
            pass
        line = f"{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}  {message}\n"
        with open(LOG_PATH, "a", encoding="utf-8") as fh:
            fh.write(line)
    except OSError:
        pass


class Controller:
    def __init__(self, store=None, on_change=None):
        self.store = store or Store()
        self.on_change = on_change
        self.displays = []
        self._lock = threading.RLock()
        self._queue = queue.Queue()
        self._save_timer = None
        self._refresh_timer = None
        self._last_user_action = 0.0
        self._last_state_mtime = 0
        self._reconfig_cb = None
        self._worker = threading.Thread(target=self._run, name="luma-worker", daemon=True)
        self._worker.start()

    # ---- 生命周期 -----------------------------------------------------------
    def start(self, watch=True):
        self.refresh(apply_stored=True)
        if watch:
            self._reconfig_cb = cg.register_reconfiguration_callback(self._on_reconfigure)
        return self

    def stop(self):
        """留给测试用：后台线程是 daemon，进程退出即结束。"""
        self.save_now()

    def wait_idle(self):
        """等后台队列跑完（CLI 测试唤醒恢复时用）。"""
        self._queue.join()

    # ---- 后台队列 -----------------------------------------------------------
    def _run(self):
        while True:
            task = self._queue.get()
            try:
                kind = task[0]
                if kind == "set":
                    self._do_set(*task[1:])
                elif kind == "restore":
                    self._do_restore(*task[1:])
                elif kind == "refresh":
                    self._do_refresh(*task[1:])
            except Exception as exc:  # 不让后台线程死掉
                log(f"任务失败 {task[:1]}: {exc!r}")
            finally:
                self._queue.task_done()

    def _submit(self, *task):
        self._queue.put(task)

    # ---- 枚举 ---------------------------------------------------------------
    def _overrides(self):
        per_display = {}
        for key, entry in (self.store.data.get("displays") or {}).items():
            backend = entry.get("backend")
            if backend in (disp.NATIVE, disp.GAMMA):
                per_display[key] = backend
        global_force = self.store.settings.get("force_backend", disp.AUTO)
        return per_display, global_force

    def refresh(self, apply_stored=False, blocking=False):
        """重新枚举显示器。blocking=True 时同步执行（CLI 用）。"""
        if blocking:
            return self._do_refresh(apply_stored)
        self._submit("refresh", apply_stored)
        return None

    # CLI 用的同步版本
    def refresh_now(self, apply_stored=False):
        return self._do_refresh(apply_stored)

    def set_now(self, key, value):
        self._do_set(key, float(value), True)

    def _do_refresh(self, apply_stored=False):
        per_display, global_force = self._overrides()
        found = disp.enumerate_displays(override=global_force, override_map=per_display)

        with self._lock:
            self.displays = found

        for d in found:
            stored = self.store.value_for(d.key)
            if stored is None:
                # 第一次见到这块屏：把当前亮度记下来，先不动它。
                self.store.remember(d, d.value, d.backend)
                log(f"新显示器 {d.name} key={d.key} backend={d.backend} 记录当前亮度 {d.value:.2f}")
        self._schedule_save()

        if apply_stored:
            self._apply_stored(found)
        self._notify()
        return found

    # ---- 应用亮度 -----------------------------------------------------------
    def set_value(self, key, value, persist=True):
        self._last_user_action = time.time()
        self._submit("set", key, float(value), persist)

    def _find(self, key):
        with self._lock:
            for d in self.displays:
                if d.key == key:
                    return d
        return None

    def _do_set(self, key, value, persist):
        d = self._find(key)
        if d is None:
            # 可能是刚插上的屏，重新枚举一次再找
            self._do_refresh()
            d = self._find(key)
            if d is None:
                return
        if d.asleep:
            return
        ok = d.write(value)
        if not ok and d.backend == disp.NATIVE:
            # 系统说能改但实际没生效，就地退回软件调光，保证滑块有效。
            log(f"{d.name} 原生亮度写入无效，改用软件调光")
            d.backend = disp.GAMMA
            ok = d.write(value)
        d.value = value
        if persist:
            self.store.remember(d, value, d.backend)
            self._schedule_save()
        self._notify()

    def _apply_stored(self, found=None):
        """把每块屏存下来的值写回去；返回是否全部成功。"""
        found = found or self.displays
        all_ok = True
        for d in found:
            stored = self.store.value_for(d.key)
            if stored is None:
                continue
            if d.asleep or not cg.is_active(d.display_id):
                all_ok = False
                continue
            ok = d.write(stored)
            if not ok and d.backend == disp.NATIVE:
                d.backend = disp.GAMMA
                ok = d.write(stored)
            if ok:
                d.value = stored
            else:
                all_ok = False
                log(f"恢复 {d.name} 失败（{d.backend}）")
        self._notify()
        return all_ok

    # ---- 唤醒 / 显示器变化 --------------------------------------------------
    def _on_reconfigure(self, display_id, flags, context):
        """CG 的显示器变化回调：热插拔、睡眠、分辨率切换都会来。

        签名必须和 CFUNCTYPE(None, uint32, uint32, void*) 完全一致——少一个
        context 参数就会每次都抛 TypeError（ctypes 会静默吞掉，最难查）。
        回调在系统主线程上同步执行，这里只做防抖和投递，绝不阻塞。
        """
        if self._refresh_timer is not None:
            self._refresh_timer.cancel()
        self._refresh_timer = threading.Timer(0.8, self._submit, args=("refresh", True))
        self._refresh_timer.daemon = True
        self._refresh_timer.start()

    def handle_wake(self, reason="wake"):
        """睡眠唤醒 / 屏幕点亮：多写几遍，直到系统不再覆盖。"""
        log(f"收到唤醒事件：{reason}")
        self._submit("restore", reason)

    def _do_restore(self, reason):
        # 系统在唤醒后会重新枚举显示器、重放 gamma，一轮写完很可能被覆盖，
        # 所以按递增间隔写四遍，最后一遍确保是终态。
        # 开盖/唤醒时的竞态：系统先点亮屏幕并恢复它自己的亮度（AOC 的 gamma
        # 直接回到 1.0），我们的进程这时才被调度起来。所以第一轮不等待、立刻
        # 写，后面再补几轮，把"闪一下"的时间尽量压短。
        gaps = [0.0, 0.2, 0.5, 1.0, 2.0, 4.0]
        for index, gap in enumerate(gaps):
            if gap:
                time.sleep(gap)
            self._do_refresh()
            ok = self._apply_stored()
            log(f"唤醒恢复 第{index + 1}轮 ok={ok}")
        self._notify()

    # ---- 状态文件轮询 -------------------------------------------------------
    def poll_state(self):
        """状态文件被别的进程（命令行）改过就重新应用。

        用轮询而不是分布式通知：通知在某些环境下会丢，而 stat 一次几乎不花钱。
        """
        try:
            mtime = STATE_PATH.stat().st_mtime_ns
        except OSError:
            return
        if mtime == self._last_state_mtime:
            return
        self._last_state_mtime = mtime
        self.store.load()
        self._apply_stored()

    # ---- 自检（可选） -------------------------------------------------------
    def watchdog_check(self):
        """定时比对「应该多亮」和「实际多亮」，被系统悄悄改掉就写回去。"""
        if time.time() - self._last_user_action < 5:
            return
        changed = False
        for d in list(self.displays):
            if d.asleep or d.backend != disp.GAMMA:
                continue
            stored = self.store.value_for(d.key)
            if stored is None:
                continue
            current = d.read()
            if current is not None and abs(current - stored) > 0.08:
                log(f"自检发现 {d.name} 被改成 {current:.2f}，应为 {stored:.2f}，写回")
                d.write(stored)
                changed = True
        if changed:
            self._notify()

    # ---- 落盘 / 通知 UI -----------------------------------------------------
    def _schedule_save(self):
        if self._save_timer is not None:
            self._save_timer.cancel()
        self._save_timer = threading.Timer(0.4, self.store.save)
        self._save_timer.daemon = True
        self._save_timer.start()

    def save_now(self):
        if self._save_timer is not None:
            self._save_timer.cancel()
            self._save_timer = None
        self.store.save()

    def _notify(self):
        if not self.on_change:
            return
        snapshot = list(self.displays)
        try:
            from PyObjCTools import AppHelper

            AppHelper.callAfter(self.on_change, snapshot)
        except Exception:
            try:
                self.on_change(snapshot)
            except Exception:
                pass
