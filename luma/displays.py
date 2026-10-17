"""显示器模型：枚举、命名、稳定标识、控制方式选择。"""

from dataclasses import dataclass, field

from . import cg

NATIVE = "native"
GAMMA = "gamma"

AUTO = "auto"


@dataclass
class Display:
    display_id: int
    name: str
    builtin: bool
    backend: str
    vendor: int
    model: int
    serial: int
    value: float = 1.0
    asleep: bool = False
    main: bool = False
    key: str = ""
    maker: str = ""

    @property
    def backend_label(self):
        if self.backend == NATIVE:
            return "系统原生"
        return "软件调光"

    def read(self):
        """读当前亮度；读不到返回 None。"""
        if self.backend == NATIVE:
            return cg.native_get(self.display_id)
        return cg.gamma_get(self.display_id)

    def write(self, value):
        """写亮度，返回是否成功。"""
        if self.backend == NATIVE:
            ok = cg.native_set(self.display_id, value)
            if ok:
                # 有些外接屏系统说能改、实际改不动，用读回兜底判断。
                back = cg.native_get(self.display_id)
                if back is not None and abs(back - value) > 0.05:
                    return False
            return ok
        return cg.gamma_set(self.display_id, value)


def _maker_name(vendor_id):
    """EDID 厂商码：16 位里塞了三个 5 位字母，AOC / XMI / APP 之类。"""
    if not vendor_id:
        return ""
    chars = [(vendor_id >> 10) & 0x1F, (vendor_id >> 5) & 0x1F, vendor_id & 0x1F]
    if not all(1 <= c <= 26 for c in chars):
        return ""
    return "".join(chr(ord("A") + c - 1) for c in chars)


def _screen_names():
    """NSScreen.localizedName() 比私有 CoreDisplay 字典省事，且本地化过。"""
    try:
        from AppKit import NSScreen

        names = {}
        for screen in NSScreen.screens():
            info = screen.deviceDescription()
            num = info.get("NSScreenNumber")
            if num is not None:
                names[int(num)] = screen.localizedName()
        return names
    except Exception:
        return {}


def _pick_backend(display_id, builtin, override):
    if builtin:
        return NATIVE
    if override == GAMMA:
        return GAMMA
    if override == NATIVE:
        return NATIVE
    # 自动：系统自己说能改就用系统通道（真背光），否则退回软件调光。
    return NATIVE if cg.native_supported(display_id) else GAMMA


def enumerate_displays(override=None, override_map=None):
    """枚举当前所有在线显示器。

    override：全局强制 NATIVE / GAMMA / AUTO；
    override_map：{key: backend} 单屏覆盖，优先于全局。
    """
    names = _screen_names()
    result = []
    used_keys = {}

    for display_id in cg.online_displays():
        builtin = cg.is_builtin(display_id)
        v, m, s = cg.vendor(display_id), cg.model(display_id), cg.serial(display_id)

        if builtin:
            base_key = "builtin"
        else:
            base_key = f"{v:04x}{m:04x}{s}"

        # 两台一模一样且序列号都报 0 的显示器会撞 key，加序号区分。
        used_keys[base_key] = used_keys.get(base_key, 0) + 1
        key = base_key if used_keys[base_key] == 1 else f"{base_key}#{used_keys[base_key]}"

        name = names.get(display_id)
        if not name:
            name = "内建显示器" if builtin else f"外接显示器 {v:04x}:{m:04x}"

        per_display = (override_map or {}).get(key)
        backend = _pick_backend(display_id, builtin, per_display or override)

        d = Display(
            display_id=display_id,
            name=name,
            builtin=builtin,
            backend=backend,
            vendor=v,
            model=m,
            serial=s,
            asleep=cg.is_asleep(display_id),
            main=cg.is_main(display_id),
            key=key,
            maker=_maker_name(v),
        )
        current = d.read()
        if current is not None:
            d.value = current
        result.append(d)

    return result


def match(displays, query):
    """按名字片段 / 序号（从 1 开始）/ all / main 找显示器。"""
    q = (query or "").strip().lower()
    if q in ("", "all", "*"):
        return list(displays)
    if q in ("main", "primary", "主"):
        mains = [d for d in displays if d.main]
        return mains or displays[:1]
    if q.isdigit():
        idx = int(q) - 1
        if 0 <= idx < len(displays):
            return [displays[idx]]
        return []
    hits = [d for d in displays if q in d.name.lower() or q in d.key.lower() or q in d.maker.lower()]
    return hits
