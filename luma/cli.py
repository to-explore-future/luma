"""命令行入口：list / get / set / nudge / restore / backend / doctor / daemon。"""

import platform
import subprocess
import sys

from . import cg, displays as disp, login
from .controller import Controller, log
from .store import LOG_PATH, STATE_PATH, Store


def _fmt(value):
    return f"{round((value or 0) * 100):3d}%"


def _text_width(text):
    """终端里中文占两列，len() 对不齐。"""
    import unicodedata

    return sum(2 if unicodedata.east_asian_width(ch) in ("W", "F") else 1 for ch in str(text))


def _pad(text, width):
    text = str(text)
    return text + " " * max(0, width - _text_width(text))


def _print_table(rows, header):
    widths = [max(_text_width(r[i]) for r in rows + [header]) for i in range(len(header))]
    print("  ".join(_pad(h, w) for h, w in zip(header, widths)))
    print("  ".join("-" * w for w in widths))
    for r in rows:
        print("  ".join(_pad(c, w) for c, w in zip(r, widths)))


def _controller():
    return Controller(Store())


def cmd_list(args):
    ctl = _controller()
    found = ctl.refresh_now()
    if not found:
        print("没有检测到显示器")
        return 0
    rows = []
    for i, d in enumerate(found, 1):
        rows.append([i, d.name, d.backend_label, _fmt(d.value),
                     "内置" if d.builtin else "外接", "主屏" if d.main else ""])
    _print_table(rows, ["#", "名称", "控制方式", "当前亮度", "类型", "备注"])
    return 0


def cmd_get(args):
    ctl = _controller()
    found = disp.match(ctl.refresh_now(), args.query)
    if not found:
        print("没找到匹配的显示器")
        return 1
    for d in found:
        print(f"{d.name}: {_fmt(d.value)}（{d.backend_label}）")
    return 0


def cmd_set(args):
    ctl = _controller()
    found = disp.match(ctl.refresh_now(), args.query)
    if not found:
        print("没找到匹配的显示器")
        return 1
    value = max(0.0, min(1.0, args.value / 100.0))
    return _apply(ctl, found, {d.key: value for d in found})


def cmd_nudge(args):
    ctl = _controller()
    found = disp.match(ctl.refresh_now(), args.query)
    if not found:
        print("没找到匹配的显示器")
        return 1
    values = {}
    for d in found:
        values[d.key] = max(0.0, min(1.0, (d.value or 0) + args.delta / 100.0))
    return _apply(ctl, found, values)


def _apply(ctl, found, values):
    """统一写入入口。

    gamma 调光是"按进程"生效的：别的进程写完一退出，系统会把表还原成原样，
    连常驻 App 写的值一起冲掉。所以只要 App 在跑，gamma 屏就只记账不动手，
    交给 App 去写；App 不在跑才自己写（并提示不持久）。
    """
    app_running = _app_running()
    deferred = []
    for d in found:
        value = values[d.key]
        if app_running and d.backend == "gamma":
            ctl.store.remember(d, value, d.backend)
            deferred.append(d)
        else:
            ctl.set_now(d.key, value)
        print(f"{d.name} -> {_fmt(value)}")

    ctl.save_now()
    if deferred:
        _notify_gui()
        if not _wait_applied(deferred, values):
            print("（等常驻 Luma 应用超时，可能它没响应通知）")
    _warn_gamma_persistence(found, app_running)
    return 0


def _wait_applied(targets, values, timeout=2.5):
    import time

    deadline = time.time() + timeout
    while time.time() < deadline:
        ok = True
        for d in targets:
            current = d.read()
            if current is None or abs(current - values[d.key]) >= 0.04:
                ok = False
                break
        if ok:
            return True
        time.sleep(0.1)
    return False


def cmd_wake(args):
    """手动跑一遍唤醒恢复流程（调试用，正常情况下由常驻进程自动触发）。"""
    import time

    if _app_running():
        _notify_gui()
        time.sleep(1.6)
        ctl = _controller()
        found = ctl.refresh_now()
    else:
        ctl = _controller()
        ctl.refresh_now()
        ctl.handle_wake("cli")
        ctl.wait_idle()
        found = ctl.displays
    for d in found:
        print(f"{d.name}: 目标 {_fmt(ctl.store.value_for(d.key))} 实际 {_fmt(d.value)}")
    return 0


def _warn_gamma_persistence(found, app_running=None):
    if app_running is None:
        app_running = _app_running()
    if not app_running and any(d.backend == "gamma" for d in found):
        print("\n注意：软件调光的屏幕（{}）要靠 Luma 常驻才能保住亮度，".format(
            "、".join(d.name for d in found if d.backend == "gamma")))
        print("      单独跑一下命令行、进程退出后它会自己变回去。请启动 Luma.app。")


def _app_running():
    """判断常驻 Luma 在不在（要排除命令行自己，它也是 python -m luma）。"""
    import os

    pids = set()
    for pattern in ("-m luma", "Luma.app/Contents/MacOS/Luma"):
        try:
            out = subprocess.run(["pgrep", "-f", "--", pattern],
                                 capture_output=True, timeout=5)
            pids |= {int(x) for x in out.stdout.split() if x.isdigit()}
        except Exception:
            continue
    pids.discard(os.getpid())
    return bool(pids)


def cmd_restore(args):
    import time

    ctl = _controller()
    found = ctl.refresh_now()
    if _app_running():
        # 交给常驻进程写（gamma 必须由它持有）
        _notify_gui()
        time.sleep(1.6)
        found = ctl.refresh_now()
    else:
        found = ctl.refresh_now(apply_stored=True)
    for d in found:
        stored = ctl.store.value_for(d.key)
        print(f"{d.name}: 目标 {_fmt(stored)} 实际 {_fmt(d.value)}")
    return 0


def cmd_backend(args):
    import time

    ctl = _controller()
    found = disp.match(ctl.refresh_now(), args.query)
    if not found:
        print("没找到匹配的显示器")
        return 1
    for d in found:
        backend = None if args.mode == "auto" else args.mode
        entry = ctl.store.data["displays"].get(d.key)
        if entry is None:
            print(f"{d.name}: 还没有这屏的记录，先 luma list 一次")
            continue
        entry["backend"] = backend
        print(f"{d.name}: 控制方式 -> {'自动' if backend is None else ('系统原生' if backend == 'native' else '软件调光')}")
    if args.mode in ("gamma", "auto"):
        ctl.store.data["settings"]["force_backend"] = "auto"
    ctl.store.save()
    if _app_running():
        _notify_gui()
        time.sleep(1.2)
        ctl.refresh_now()
    else:
        ctl.refresh_now(apply_stored=True)
    return 0


def cmd_watchdog(args):
    store = Store()
    store.set_setting("watchdog", args.mode == "on")
    store.save()
    print(f"定时自检：{'开' if args.mode == 'on' else '关'}（重启 Luma 生效）")
    return 0


def cmd_login(args):
    if args.mode == "on":
        login.enable_login()
        print("已设置登录自启")
    else:
        login.disable_login()
        print("已取消登录自启")
    return 0


def cmd_doctor(args):
    print(f"macOS      : {platform.mac_ver()[0]} ({platform.machine()})")
    print(f"Python     : {platform.python_version()} {sys.executable}")
    try:
        import objc

        print(f"PyObjC     : {objc.__version__}")
    except Exception:
        print("PyObjC     : 未安装")
    print(f"状态文件   : {STATE_PATH}")
    print(f"登录自启   : {login.launch_agent_status()}")

    running = _monitorcontrol_running()
    print(f"MonitorControl: {'正在运行（建议退出，否则会和 Luma 抢亮度）' if running else '未运行'}")

    ctl = _controller()
    found = ctl.refresh_now()
    print()
    for d in found:
        print(f"- {d.name}")
        print(f"    display_id={d.display_id} key={d.key}")
        print(f"    内置={'是' if d.builtin else '否'} 主屏={'是' if d.main else '否'} 睡眠={'是' if d.asleep else '否'}")
        print(f"    系统原生可改亮度={cg.native_supported(d.display_id)}")
        print(f"    原生亮度={cg.native_get(d.display_id)}  gamma={cg.gamma_get(d.display_id)}")
        print(f"    当前控制方式={d.backend_label}  记录值={ctl.store.value_for(d.key)}")

    if LOG_PATH.exists():
        print("\n最近日志：")
        try:
            lines = LOG_PATH.read_text("utf-8", errors="replace").splitlines()[-12:]
            for line in lines:
                print("  " + line)
        except OSError:
            pass
    return 0


def cmd_daemon(args):
    from . import app

    app.run(with_status_item=False)
    return 0


def _notify_gui():
    try:
        from Foundation import NSDistributedNotificationCenter

        NSDistributedNotificationCenter.defaultCenter().postNotificationName_object_(
            "com.tcxt.luma.changed", None
        )
    except Exception:
        pass


def _monitorcontrol_running():
    try:
        from AppKit import NSWorkspace

        for app in NSWorkspace.sharedWorkspace().runningApplications():
            if app.bundleIdentifier() == "app.monitorcontrol.MonitorControl":
                return True
    except Exception:
        try:
            out = subprocess.run(["pgrep", "-x", "MonitorControl"], capture_output=True)
            return out.returncode == 0
        except Exception:
            pass
    return False


def build_parser():
    import argparse

    parser = argparse.ArgumentParser(prog="luma", description="Luma — macOS 亮度控制（唤醒不失效）")
    sub = parser.add_subparsers(dest="command")

    sub.add_parser("list", help="列出所有显示器和当前亮度")

    p = sub.add_parser("get", help="读取亮度")
    p.add_argument("query", nargs="?", default="all", help="显示器名字片段 / 序号 / all")

    p = sub.add_parser("set", help="设置亮度（0-100）")
    p.add_argument("value", type=float)
    p.add_argument("query", nargs="?", default="all")

    p = sub.add_parser("nudge", help="在当前亮度上加减（百分点）")
    p.add_argument("delta", type=int)
    p.add_argument("query", nargs="?", default="all")

    sub.add_parser("restore", help="把所有显示器恢复成记录值")
    sub.add_parser("wake", help="手动执行一遍唤醒恢复（调试用）")

    p = sub.add_parser("backend", help="指定控制方式")
    p.add_argument("mode", choices=["auto", "native", "gamma"])
    p.add_argument("query", nargs="?", default="all")

    p = sub.add_parser("watchdog", help="定时自检开关")
    p.add_argument("mode", choices=["on", "off"])

    p = sub.add_parser("login", help="登录自启开关")
    p.add_argument("mode", choices=["on", "off"])

    sub.add_parser("doctor", help="自检：显示器和环境")
    sub.add_parser("daemon", help="只守护不显示菜单栏图标")
    return parser


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    parser = build_parser()
    args = parser.parse_args(argv)
    if not args.command:
        parser.print_help()
        return 0

    handlers = {
        "list": cmd_list,
        "get": cmd_get,
        "set": cmd_set,
        "nudge": cmd_nudge,
        "restore": cmd_restore,
        "wake": cmd_wake,
        "backend": cmd_backend,
        "watchdog": cmd_watchdog,
        "login": cmd_login,
        "doctor": cmd_doctor,
        "daemon": cmd_daemon,
    }
    return handlers[args.command](args) or 0
