"""界面：一个能看见的主窗口（Dock 图标 + 菜单栏小太阳两个入口）。

只靠菜单栏图标在这台带刘海的机器上容易被挤没，所以主入口是窗口，
菜单栏图标留着当快捷方式，两个入口打开的是同一个窗口。
"""

import threading
import time

import objc
from AppKit import (
    NSApplication,
    NSApplicationActivationPolicyAccessory,
    NSBackingStoreBuffered,
    NSButton,
    NSColor,
    NSFont,
    NSImage,
    NSMakeRect,
    NSMakeSize,
    NSObject,
    NSBezierPath,
    NSPopover,
    NSPopoverBehaviorTransient,
    NSSlider,
    NSTextField,
    NSTimer,
    NSVariableStatusItemLength,
    NSView,
    NSViewController,
    NSWindow,
    NSWindowStyleMaskClosable,
    NSWindowStyleMaskMiniaturizable,
    NSWindowStyleMaskTitled,
    NSWorkspace,
)

from . import login
from .controller import Controller, log
from .store import Store

WIDTH = 400
MARGIN = 34          # 滑块圆点在 0%/100% 时会画到轨道端点外，必须留出半径
ROW_HEIGHT = 64
FOOTER_HEIGHT = 70


def _label(text, size=12, bold=False, secondary=False, right=False, width=120):
    lbl = NSTextField.alloc().initWithFrame_(NSMakeRect(0, 0, width, 16))
    lbl.setStringValue_(text)
    lbl.setBezeled_(False)
    lbl.setDrawsBackground_(False)
    lbl.setEditable_(False)
    lbl.setSelectable_(False)
    lbl.setFont_(NSFont.boldSystemFontOfSize_(size) if bold else NSFont.systemFontOfSize_(size))
    lbl.setTextColor_(NSColor.secondaryLabelColor() if secondary else NSColor.labelColor())
    if right:
        lbl.setAlignment_(2)  # NSTextAlignmentRight
    return lbl


def _button(title, frame, target, action):
    btn = NSButton.alloc().initWithFrame_(frame)
    btn.setBezelStyle_(1)  # NSRoundedBezelStyle
    btn.setTitle_(title)
    btn.setFont_(NSFont.systemFontOfSize_(11))
    btn.setTarget_(target)
    btn.setAction_(action)
    return btn


class LumaSlider(NSView):
    """自绘滑块。

    macOS 26 的 NSSlider 会把圆点画到控件 bounds 之外再裁掉，
    拖动到 0%/100% 时圆点总是缺一块；自己画就没有这个问题。
    """

    def initWithFrame_(self, frame):
        self = objc.super(LumaSlider, self).initWithFrame_(frame)
        if self is None:
            return None
        self._value = 0.0
        self.key = ""
        self.dragging = False
        self.on_change = None
        return self

    def isFlipped(self):
        return False

    def value(self):
        return self._value

    def setValue_(self, value):
        value = max(0.0, min(1.0, float(value)))
        if abs(value - self._value) > 1e-6:
            self._value = value
            self.setNeedsDisplay_(True)

    def acceptsFirstMouse_(self, event):
        return True

    def _geometry(self):
        b = self.bounds()
        radius = min(9.0, b.size.height / 2.0 - 1.0)
        return b.size.width, b.size.height, radius

    def drawRect_(self, rect):
        width, height, radius = self._geometry()
        x0, x1 = radius, width - radius
        y = height / 2.0
        track_h = 4.0

        track = NSBezierPath.bezierPathWithRoundedRect_xRadius_yRadius_(
            NSMakeRect(x0, y - track_h / 2.0, max(0.0, x1 - x0), track_h),
            track_h / 2.0, track_h / 2.0)
        NSColor.quaternaryLabelColor().setFill()
        track.fill()

        cx = x0 + self._value * (x1 - x0)
        if cx > x0 + 0.5:
            fill = NSBezierPath.bezierPathWithRoundedRect_xRadius_yRadius_(
                NSMakeRect(x0, y - track_h / 2.0, cx - x0, track_h),
                track_h / 2.0, track_h / 2.0)
            NSColor.controlAccentColor().setFill()
            fill.fill()

        knob = NSBezierPath.bezierPathWithOvalInRect_(
            NSMakeRect(cx - radius, y - radius, radius * 2.0, radius * 2.0))
        NSColor.whiteColor().setFill()
        knob.fill()
        NSColor.blackColor().colorWithAlphaComponent_(0.18).setStroke()
        knob.setLineWidth_(0.5)
        knob.stroke()

    def mouseDown_(self, event):
        self.dragging = True
        self._updateFromEvent_(event)

    def mouseDragged_(self, event):
        self._updateFromEvent_(event)

    def mouseUp_(self, event):
        self.dragging = False

    def _updateFromEvent_(self, event):
        point = self.convertPoint_fromView_(event.locationInWindow(), None)
        width, _height, radius = self._geometry()
        span = width - radius * 2.0
        if span <= 0:
            return
        value = max(0.0, min(1.0, (point.x - radius) / span))
        self.setValue_(value)
        if self.on_change is not None:
            self.on_change(self.key, value)


class AppDelegate(NSObject):
    def initWithStatusItem_(self, status_item):
        self = objc.super(AppDelegate, self).init()
        if self is None:
            return None
        self.status_item = status_item
        self.store = Store()
        self.controller = Controller(self.store, on_change=self.sync_ui)
        self.window = None
        self.popover = None
        self.rows = {}
        self.show_on_launch = True
        self.with_status_item = True
        self._slider_touch = {}
        return self

    # ---- 启动 ---------------------------------------------------------------
    def applicationDidFinishLaunching_(self, notification):
        self.controller.start(watch=True)
        self._install_observers()
        self._install_timers()
        if self.with_status_item:
            self._build_status_item()
        self._build_window()
        if self.show_on_launch:
            self.showWindow_(None)
        log(f"启动完成：窗口可见={self.window.isVisible()} 滑块={len(self.rows)}")

    def _build_window(self):
        mask = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable
        window = NSWindow.alloc().initWithContentRect_styleMask_backing_defer_(
            NSMakeRect(0, 0, WIDTH, 260), mask, NSBackingStoreBuffered, False
        )
        window.setTitle_("Luma — 屏幕亮度")
        window.setReleasedWhenClosed_(False)
        window.center()
        self.window = window
        self.rebuild_content()

    def _build_status_item(self):
        if not self.with_status_item:
            return
        """创建状态栏图标，并安排两次自检。

        macOS 26 (Tahoe) 把第三方状态栏项交给 ControlCenter 排布，启动瞬间
        有可能被判成隐藏（窗口被推到屏幕外，y<0）。这种做法只能删掉重建。
        """
        self._create_status_item()
        NSTimer.scheduledTimerWithTimeInterval_target_selector_userInfo_repeats_(
            2.0, self, "checkStatusItem:", None, False
        )
        NSTimer.scheduledTimerWithTimeInterval_target_selector_userInfo_repeats_(
            8.0, self, "checkStatusItem:", None, False
        )

    def _create_status_item(self):
        from AppKit import NSStatusBar

        item = NSStatusBar.systemStatusBar().statusItemWithLength_(NSVariableStatusItemLength)
        try:
            item.setAutosaveName_("LumaStatusItem")
        except Exception:
            pass
        button = item.button()
        image = None
        for symbol in ("sun.max.fill", "sun.max", "sun.min.fill"):
            image = NSImage.imageWithSystemSymbolName_accessibilityDescription_(symbol, "Luma")
            if image is not None:
                break
        if image is not None:
            image.setTemplate_(True)
            button.setImage_(image)
            log("状态栏图标：使用 SF Symbol 太阳")
        else:
            button.setTitle_("☀")
            log("状态栏图标：SF Symbol 不可用，退回文字 ☀")
        button.setToolTip_("Luma 屏幕亮度")
        button.setTarget_(self)
        button.setAction_("showPanel:")
        self.status_item = item
        return item

    def _status_item_hidden(self):
        """判断状态栏图标是不是真的没显示。isVisible 在 Tahoe 上不可信。"""
        try:
            item = self.status_item
            button = item.button() if item else None
            window = button.window() if button else None
            if not button or not window:
                return True
            frame = window.frame()
            occlusion = int(window.occlusionState())
            visible = bool(occlusion & 2)  # NSWindowOcclusionStateVisible
            # 还没完成布局时 frame 是 0x0，不算隐藏（稍后再探）
            if frame.size.height <= 1:
                return False
            if not visible:
                return True
            if frame.origin.y < 0:
                return True
            return False
        except Exception:
            return False

    def checkStatusItem_(self, timer):
        if not self.with_status_item:
            return
        hidden = self._status_item_hidden()
        log(f"状态栏自检：hidden={hidden}")
        if not hidden:
            return
        # 被系统藏了：删掉重建，最多试两次
        for attempt in range(2):
            try:
                from AppKit import NSStatusBar

                if self.status_item is not None:
                    NSStatusBar.systemStatusBar().removeStatusItem_(self.status_item)
                    self.status_item = None
            except Exception as exc:
                log(f"移除状态栏项失败：{exc!r}")
            self._create_status_item()
            time.sleep(0.4)
            hidden = self._status_item_hidden()
            log(f"状态栏重建第 {attempt + 1} 次：hidden={hidden}")
            if not hidden:
                break

    def _install_observers(self):
        center = NSWorkspace.sharedWorkspace().notificationCenter()
        for name, selector in (
            ("NSWorkspaceDidWakeNotification", "onWake:"),
            ("NSWorkspaceScreensDidWakeNotification", "onScreensWake:"),
        ):
            try:
                center.addObserver_selector_name_object_(self, selector, name, None)
            except Exception as exc:
                log(f"注册 {name} 失败：{exc!r}")

        try:
            from Foundation import NSDistributedNotificationCenter

            NSDistributedNotificationCenter.defaultCenter().addObserver_selector_name_object_(
                self, "onExternalChange:", "com.tcxt.luma.changed", None
            )
        except Exception as exc:
            log(f"注册命令行通知失败：{exc!r}")

    def _install_timers(self):
        # 状态文件轮询：命令行改完 1 秒内生效
        NSTimer.scheduledTimerWithTimeInterval_target_selector_userInfo_repeats_(
            1.0, self, "pollTick:", None, True
        )
        if self.store.settings.get("watchdog"):
            NSTimer.scheduledTimerWithTimeInterval_target_selector_userInfo_repeats_(
                90.0, self, "watchdogTick:", None, True
            )

    # ---- 事件 ---------------------------------------------------------------
    def onWake_(self, notification):
        self.controller.handle_wake("system-wake")
        self._recheck_status_item_later()

    def onScreensWake_(self, notification):
        self.controller.handle_wake("screens-wake")
        self._recheck_status_item_later()

    def _recheck_status_item_later(self):
        NSTimer.scheduledTimerWithTimeInterval_target_selector_userInfo_repeats_(
            2.0, self, "checkStatusItem:", None, False
        )

    def onExternalChange_(self, notification):
        log("收到命令行变更通知，重新应用")
        self.store.load()
        self.controller.refresh(apply_stored=True)

    def pollTick_(self, timer):
        self.controller.poll_state()

    def watchdogTick_(self, timer):
        threading.Thread(target=self.controller.watchdog_check, daemon=True).start()

    def showWindow_(self, sender):
        if self.window is None:
            return
        if self.popover is not None and self.popover.isShown():
            self.popover.performClose_(sender)
        self.rebuild_content()
        app = NSApplication.sharedApplication()
        try:
            app.activate()  # macOS 14+
        except Exception:
            pass
        try:
            app.activateIgnoringOtherApps_(True)
        except Exception:
            pass
        self.window.makeKeyAndOrderFront_(None)
        log(f"显示窗口（可见={self.window.isVisible()}）")

    def _ensure_popover(self):
        if self.popover is not None:
            return self.popover
        popover = NSPopover.alloc().init()
        popover.setBehavior_(NSPopoverBehaviorTransient)
        vc = NSViewController.alloc().init()
        vc.setView_(NSView.alloc().initWithFrame_(NSMakeRect(0, 0, WIDTH, 240)))
        popover.setContentViewController_(vc)
        self.popover = popover
        return popover

    def showPanel_(self, sender):
        """点菜单栏图标：在图标正下方弹出面板（在哪块屏点的就弹在哪块屏）。"""
        if self.status_item is None or self.status_item.button() is None:
            self.showWindow_(sender)
            return
        popover = self._ensure_popover()
        if popover.isShown():
            popover.performClose_(sender)
            return
        view, height = self._build_view()
        popover.contentViewController().setView_(view)
        popover.setContentSize_(NSMakeSize(WIDTH, height))
        button = self.status_item.button()
        app = NSApplication.sharedApplication()
        try:
            app.activateIgnoringOtherApps_(True)
        except Exception:
            pass
        popover.showRelativeToRect_ofView_preferredEdge_(button.bounds(), button, 1)
        screen_name = "?"
        try:
            window = button.window()
            if window is not None and window.screen() is not None:
                screen_name = window.screen().localizedName()
        except Exception:
            pass
        log(f"弹出面板（屏幕={screen_name}）")

    def applicationShouldHandleReopen_hasVisibleWindows_(self, app, has_visible):
        self.showWindow_(None)
        return True

    # ---- 构建界面 -----------------------------------------------------------
    def rebuild_content(self):
        view, height = self._build_view()
        if self.popover is not None and self.popover.isShown():
            self.popover.contentViewController().setView_(view)
            self.popover.setContentSize_(NSMakeSize(WIDTH, height))
            surface = "面板"
        elif self.window is not None:
            self.window.setContentView_(view)
            self.window.setContentSize_(NSMakeSize(WIDTH, height))
            surface = "窗口"
        else:
            return
        log(f"界面重建：{len(self.controller.displays)} 块屏 → {surface}")

    def _build_view(self):
        displays = self.controller.displays
        height = 16 + max(1, len(displays)) * ROW_HEIGHT + FOOTER_HEIGHT
        view = NSView.alloc().initWithFrame_(NSMakeRect(0, 0, WIDTH, height))

        self.rows = {}
        if not displays:
            empty = _label("没有检测到显示器", 12, secondary=True, width=WIDTH - 2 * MARGIN)
            empty.setFrame_(NSMakeRect(MARGIN, height - 44, WIDTH - 2 * MARGIN, 16))
            view.addSubview_(empty)

        for i, d in enumerate(displays):
            row_top = height - 16 - (i + 1) * ROW_HEIGHT
            name = _label(d.name, 12, width=WIDTH - 160)
            name.setFrame_(NSMakeRect(MARGIN, row_top + 40, WIDTH - 160, 16))
            name.setToolTip_(f"控制方式：{d.backend_label}")

            pct = _label(f"{round(d.value * 100)}%", 12, right=True, width=80)
            pct.setFrame_(NSMakeRect(WIDTH - MARGIN - 80, row_top + 40, 80, 16))

            slider = LumaSlider.alloc().initWithFrame_(
                NSMakeRect(MARGIN, row_top + 6, WIDTH - 2 * MARGIN, 30))
            slider.setValue_(d.value)
            slider.key = d.key
            slider.on_change = self._slider_moved

            view.addSubview_(name)
            view.addSubview_(pct)
            view.addSubview_(slider)
            self.rows[d.key] = (slider, pct)

        hint = _label(self._hint_text(displays), 10, secondary=True, width=WIDTH - 2 * MARGIN)
        hint.setFrame_(NSMakeRect(MARGIN, 46, WIDTH - 2 * MARGIN, 14))
        view.addSubview_(hint)

        force_sw = self.store.settings.get("force_backend") == "gamma"
        self.software_btn = _button(
            "调光:软件" if force_sw else "调光:自动", NSMakeRect(MARGIN, 12, 104, 26),
            self, "toggleSoftware:",
        )
        self.login_btn = _button(
            "自启:开" if login.login_enabled() else "自启:关",
            NSMakeRect(MARGIN + 108, 12, 84, 26),
            self, "toggleLogin:",
        )
        quit_btn = _button("退出", NSMakeRect(WIDTH - MARGIN - 72, 12, 72, 26), self, "quit:")
        for btn in (self.software_btn, self.login_btn, quit_btn):
            view.addSubview_(btn)

        return view, height

    def _hint_text(self, displays):
        if _monitorcontrol_running():
            return "MonitorControl 也在跑，两个程序会抢亮度，建议退出它"
        gamma = [d.name for d in displays if d.backend == "gamma"]
        if gamma:
            return "唤醒后自动恢复 · 软件调光：" + "、".join(gamma)
        return "唤醒后自动恢复亮度"

    def _surface_visible(self):
        if self.popover is not None and self.popover.isShown():
            return True
        return self.window is not None and self.window.isVisible()

    def sync_ui(self, displays):
        if not self._surface_visible():
            return
        current_keys = {d.key for d in displays}
        if current_keys != set(self.rows.keys()):
            self.rebuild_content()
            return
        now = time.time()
        for d in displays:
            row = self.rows.get(d.key)
            if not row:
                continue
            # 用户刚动过这条滑块就别覆盖：否则轮询/应用回写会把滑块拽回去
            if now - self._slider_touch.get(d.key, 0.0) < 1.5:
                continue
            slider, pct = row
            if not getattr(slider, "dragging", False):
                slider.setValue_(d.value)
            pct.setStringValue_(f"{round(d.value * 100)}%")

    # ---- 动作 ---------------------------------------------------------------
    def _slider_moved(self, key, value):
        self._slider_touch[key] = time.time()
        row = self.rows.get(key)
        if row:
            row[1].setStringValue_(f"{round(value * 100)}%")
        self.controller.set_value(key, value)

    def toggleSoftware_(self, sender):
        current = self.store.settings.get("force_backend", "auto")
        new = "auto" if current == "gamma" else "gamma"
        self.store.set_setting("force_backend", new)
        for entry in self.store.data["displays"].values():
            entry["backend"] = None
        self.store.save()
        sender.setTitle_("调光:软件" if new == "gamma" else "调光:自动")
        self.controller.refresh(apply_stored=True)
        self.rebuild_content()

    def toggleLogin_(self, sender):
        try:
            if login.login_enabled():
                login.disable_login()
                sender.setTitle_("自启:关")
            else:
                login.enable_login()
                sender.setTitle_("自启:开")
        except Exception as exc:
            log(f"设置开机自启失败：{exc!r}")
            sender.setTitle_("自启:失败")

    def quit_(self, sender):
        self.controller.save_now()
        NSApplication.sharedApplication().terminate_(None)

    def applicationWillTerminate_(self, notification):
        self.controller.save_now()


def _monitorcontrol_running():
    try:
        for app in NSWorkspace.sharedWorkspace().runningApplications():
            if app.bundleIdentifier() == "app.monitorcontrol.MonitorControl":
                return True
    except Exception:
        pass
    return False


_KEEP_ALIVE = []
_LOCK_HANDLE = None


def _single_instance():
    """同一个用户只允许一个常驻实例，否则两个进程会互相覆盖 gamma。"""
    global _LOCK_HANDLE
    import fcntl
    import os

    from .store import STATE_DIR

    STATE_DIR.mkdir(parents=True, exist_ok=True)
    handle = open(STATE_DIR / "luma.lock", "w")
    try:
        fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        handle.close()
        return None
    handle.write(str(os.getpid()))
    handle.flush()
    _LOCK_HANDLE = handle
    return handle


def run(with_status_item=True, show_window=True):
    if _single_instance() is None:
        log("已经有一个 Luma 在运行，本次启动退出")
        return

    app = NSApplication.sharedApplication()
    # 菜单栏工具：不占 Dock，也不出现在 Cmd-Tab 里
    app.setActivationPolicy_(NSApplicationActivationPolicyAccessory)

    status_item = None
    delegate = AppDelegate.alloc().initWithStatusItem_(status_item)
    delegate.show_on_launch = show_window
    delegate.with_status_item = with_status_item
    # NSApplication 的 delegate 是 assign 语义，不自己拿着会被回收，图标和回调会一起消失
    _KEEP_ALIVE.append(delegate)
    app.setDelegate_(delegate)
    app.run()
