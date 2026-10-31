"""CoreGraphics / DisplayServices 的 ctypes 绑定。

为什么不用 PyObjC：
  CGGetDisplayTransferByFormula 那一组函数带 9 个 out 参数，PyObjC 的
  "pass-by-reference out argument" 元数据在 Python 侧很难用对，直接 ctypes 反而干净。

这里只封装两类能力：
  1. 枚举在线显示器（内置 / 外接判定、厂商型号序列号）
  2. 两套亮度读写：
       - native：DisplayServices.framework（苹果私有，内置屏和部分外接屏走这条，真·背光）
       - gamma ：CGSetDisplayTransferByFormula（软件调光，任何显示器都能用，但会被系统重置）
"""

import ctypes
from ctypes import POINTER, byref, c_bool, c_float, c_int32, c_uint32

_CG_PATH = "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics"
_DS_PATH = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"

CG = ctypes.CDLL(_CG_PATH)
DS = ctypes.CDLL(_DS_PATH)

# ---- CoreGraphics -----------------------------------------------------------
CG.CGGetOnlineDisplayList.restype = c_int32
CG.CGGetOnlineDisplayList.argtypes = [c_uint32, POINTER(c_uint32), POINTER(c_uint32)]

CG.CGDisplayIsBuiltin.restype = c_bool
CG.CGDisplayIsBuiltin.argtypes = [c_uint32]

CG.CGDisplayIsActive.restype = c_bool
CG.CGDisplayIsActive.argtypes = [c_uint32]

CG.CGDisplayIsAsleep.restype = c_bool
CG.CGDisplayIsAsleep.argtypes = [c_uint32]

CG.CGDisplayIsMain.restype = c_bool
CG.CGDisplayIsMain.argtypes = [c_uint32]

for _fn in ("CGDisplayVendorNumber", "CGDisplayModelNumber", "CGDisplaySerialNumber"):
    getattr(CG, _fn).restype = c_uint32
    getattr(CG, _fn).argtypes = [c_uint32]

CG.CGSetDisplayTransferByFormula.restype = c_int32
CG.CGSetDisplayTransferByFormula.argtypes = [c_uint32] + [c_float] * 9

CG.CGGetDisplayTransferByFormula.restype = c_int32
CG.CGGetDisplayTransferByFormula.argtypes = [c_uint32] + [POINTER(c_float)] * 9

CG.CGDisplayRegisterReconfigurationCallback.restype = c_int32
CG.CGDisplayRegisterReconfigurationCallback.argtypes = [ctypes.c_void_p, ctypes.c_void_p]

# ---- DisplayServices -------------------------------------------------------
DS.DisplayServicesCanChangeBrightness.restype = c_bool
DS.DisplayServicesCanChangeBrightness.argtypes = [c_uint32]

DS.DisplayServicesGetBrightness.restype = c_int32
DS.DisplayServicesGetBrightness.argtypes = [c_uint32, POINTER(c_float)]

DS.DisplayServicesSetBrightness.restype = c_int32
DS.DisplayServicesSetBrightness.argtypes = [c_uint32, c_float]


# ---- 枚举 -------------------------------------------------------------------
def online_displays():
    """返回在线显示器 ID 列表。缓冲区不够会自动长大。"""
    cap = 8
    while True:
        arr = (c_uint32 * cap)()
        count = c_uint32(0)
        err = CG.CGGetOnlineDisplayList(cap, arr, byref(count))
        if err != 0:
            return []
        if count.value < cap:
            return list(arr)[: count.value]
        cap = count.value + 4


def is_builtin(display_id):
    return bool(CG.CGDisplayIsBuiltin(display_id))


def is_asleep(display_id):
    return bool(CG.CGDisplayIsAsleep(display_id))


def is_active(display_id):
    return bool(CG.CGDisplayIsActive(display_id))


def is_main(display_id):
    return bool(CG.CGDisplayIsMain(display_id))


def vendor(display_id):
    return int(CG.CGDisplayVendorNumber(display_id))


def model(display_id):
    return int(CG.CGDisplayModelNumber(display_id))


def serial(display_id):
    return int(CG.CGDisplaySerialNumber(display_id))


# ---- 原生亮度 ---------------------------------------------------------------
def native_supported(display_id):
    """系统是否认为这块屏的亮度可以由软件直接改（内置屏恒为 True）。"""
    return bool(DS.DisplayServicesCanChangeBrightness(display_id))


def native_get(display_id):
    """读原生亮度，返回 0..1；不支持则返回 None。"""
    value = c_float(0)
    if DS.DisplayServicesGetBrightness(display_id, byref(value)) != 0:
        return None
    return max(0.0, min(1.0, float(value.value)))


def native_set(display_id, value):
    value = max(0.0, min(1.0, float(value)))
    return DS.DisplayServicesSetBrightness(display_id, value) == 0


# ---- 软件调光（gamma） ------------------------------------------------------
def gamma_get(display_id):
    """读当前 gamma 的上限（三通道取最大值），1.0 表示没有调暗。"""
    outs = [(c_float * 1)() for _ in range(9)]
    err = CG.CGGetDisplayTransferByFormula(
        display_id, *[ctypes.cast(o, POINTER(c_float)) for o in outs]
    )
    if err != 0:
        return None
    return max(0.0, min(1.0, max(outs[1][0], outs[4][0], outs[7][0])))


def gamma_set(display_id, value):
    """用 gamma 传输函数把整块屏压暗。value=1.0 即恢复原样。"""
    value = max(0.0, min(1.0, float(value)))
    return CG.CGSetDisplayTransferByFormula(
        display_id, 0.0, value, 1.0, 0.0, value, 1.0, 0.0, value, 1.0
    ) == 0


# ---- 显示器变化通知 ---------------------------------------------------------
# 回调在系统主线程上同步触发，收到后不要在回调里做耗时操作。
_RECONFIG_CB = ctypes.CFUNCTYPE(None, c_uint32, c_uint32, ctypes.c_void_p)


def register_reconfiguration_callback(func):
    """func(display_id, flags) 会在显示器热插拔 / 睡眠 / 分辨率变化时被调用。

    返回的 CFUNCTYPE 对象必须由调用方持有，否则会被 GC 掉导致崩溃。
    """
    cb = _RECONFIG_CB(func)
    CG.CGDisplayRegisterReconfigurationCallback(cb, None)
    return cb
