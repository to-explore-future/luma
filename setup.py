"""py2app 打包配置：把 Python 运行时、PyObjC 和 luma 一起塞进 Luma.app。

这样 Dock 里显示的是 Luma（不再是一个 Python 图标），也不再依赖
~/Library/Application Support/Luma/venv，换台机器拷过去就能跑。
"""

from setuptools import setup

APP = ["run_luma.py"]

OPTIONS = {
    "argv_emulation": False,
    "packages": ["luma"],
    "includes": ["objc", "Foundation", "AppKit", "PyObjCTools", "Quartz", "CoreFoundation"],
    "iconfile": "assets/Luma.icns",
    "plist": {
        "CFBundleName": "Luma",
        "CFBundleDisplayName": "Luma",
        "CFBundleIdentifier": "com.tcxt.luma",
        "CFBundleShortVersionString": "1.0.0",
        "CFBundleVersion": "100",
        "CFBundleIconFile": "Luma.icns",
        "CFBundleDevelopmentRegion": "zh_CN",
        "CFBundleLocalizations": ["zh_CN", "en"],
        "LSUIElement": True,
        "NSHighResolutionCapable": True,
        "LSMinimumSystemVersion": "13.0",
        "NSHumanReadableCopyright": "Luma — 自己用的亮度工具",
    },
}

setup(
    name="Luma",
    app=APP,
    options={"py2app": OPTIONS},
)
