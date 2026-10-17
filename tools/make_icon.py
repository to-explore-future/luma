"""生成 App 图标（一个暖色太阳），输出 Luma.icns。"""

import math
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw

OUT = Path(__file__).resolve().parent.parent / "assets"
ICONSET = OUT / "Luma.iconset"


def rounded_rect(size, radius_ratio=0.225):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    radius = int(size * radius_ratio)
    draw.rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=(28, 26, 36, 255))
    # 纵向渐变
    top = (52, 44, 74)
    bottom = (18, 20, 30)
    for y in range(size):
        t = y / max(1, size - 1)
        color = tuple(int(top[i] * (1 - t) + bottom[i] * t) for i in range(3))
        draw.line([(0, y), (size, y)], fill=color + (255,))
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    img.putalpha(mask)
    return img


def draw_sun(size):
    img = rounded_rect(size)
    draw = ImageDraw.Draw(img)
    cx = cy = size / 2
    r = size * 0.165
    # 光芒
    rays = 12
    for i in range(rays):
        angle = i * (2 * math.pi / rays)
        inner = r * 1.42
        outer = r * (2.05 if i % 2 == 0 else 1.78)
        width = max(2, int(size * 0.022))
        draw.line(
            [(cx + inner * math.cos(angle), cy + inner * math.sin(angle)),
             (cx + outer * math.cos(angle), cy + outer * math.sin(angle))],
            fill=(255, 214, 138, 255), width=width,
        )
    # 日轮
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(255, 236, 186, 255))
    draw.ellipse([cx - r * 0.62, cy - r * 0.62, cx + r * 0.62, cy + r * 0.62],
                 fill=(255, 205, 112, 255))
    return img


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    if ICONSET.exists():
        for f in ICONSET.iterdir():
            f.unlink()
    ICONSET.mkdir(exist_ok=True)

    master = draw_sun(1024)
    sizes = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
             (256, 1), (256, 2), (512, 1), (512, 2)]
    for base, scale in sizes:
        px = base * scale
        name = f"icon_{base}x{base}{'@2x' if scale == 2 else ''}.png"
        master.resize((px, px), Image.LANCZOS).save(ICONSET / name)

    icns = OUT / "Luma.icns"
    subprocess.run(["iconutil", "-c", "icns", str(ICONSET), "-o", str(icns)], check=True)
    print(f"已生成 {icns}")


if __name__ == "__main__":
    sys.exit(main())
