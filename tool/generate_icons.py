#!/usr/bin/env python3
"""从 assets/icon/app_icon_source.jpg 生成全平台 App 图标。

源图是带浅灰底、圆角、投影的「展示稿」；脚本会：
  1. 定位并裁出蓝色方形图标本体；
  2. 用边缘颜色延拓把四角补成直角（iOS/Android 自适应图标需要满幅方图）；
  3. 按各平台要求缩放导出。

用法： python tool/generate_icons.py
依赖： pillow, numpy
"""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "assets" / "icon" / "app_icon_source.jpg"
MASTER = ROOT / "assets" / "icon" / "app_icon.png"  # 1024 满幅母版

ANDROID_RES = ROOT / "android" / "app" / "src" / "main" / "res"
IOS_SET = ROOT / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
MACOS_SET = ROOT / "macos" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
WEB_ICONS = ROOT / "web" / "icons"
WEB_FAVICON = ROOT / "web" / "favicon.png"
WINDOWS_ICO = ROOT / "windows" / "runner" / "resources" / "app_icon.ico"

LAUNCHER_DP = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
ADAPTIVE_DP = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}


# --------------------------------------------------------------------------- #
# 源图解析
# --------------------------------------------------------------------------- #
def locate_icon(im: Image.Image) -> tuple[int, int, int]:
    """返回图标本体的 (left, top, size)。"""
    hsv = np.asarray(im.convert("HSV")).astype(np.int16)
    sat = hsv[..., 1]
    val = hsv[..., 2]
    blue = (sat > 140) & (val > 90)  # 蓝色块高饱和；灰底/阴影饱和度低

    h, w = blue.shape
    row = np.where(blue[h // 2])[0]
    col = np.where(blue[:, w // 2])[0]
    if row.size == 0 or col.size == 0:
        raise SystemExit("未能在源图中定位图标本体")
    left, right = int(row[0]), int(row[-1])
    top, bottom = int(col[0]), int(col[-1])
    size = min(right - left + 1, bottom - top + 1)
    return left, top, size


def corner_radius(im: Image.Image, left: int, top: int, size: int) -> float:
    """沿对角线探测圆角半径：斜向首个蓝色像素距角点约 0.2929R。"""
    hsv = np.asarray(im.convert("HSV")).astype(np.int16)
    sat, val = hsv[..., 1], hsv[..., 2]
    blue = (sat > 140) & (val > 90)
    for d in range(2, size // 2):
        x, y = left + d, top + d
        if blue[y, x]:
            return d / (1 - 1 / np.sqrt(2))
    return size * 0.22


def crop_icon(im: Image.Image) -> tuple[Image.Image, float, int]:
    left, top, size = locate_icon(im)
    radius = corner_radius(im, left, top, size)
    inset = max(3, round(size * 0.006))  # 去掉与灰底混色的边缘像素
    box = (left + inset, top + inset, left + size - inset, top + size - inset)
    crop = im.crop(box).convert("RGB")
    return crop, radius - inset, crop.width


def square_up(crop: Image.Image, radius: float, out: int = 1024) -> Image.Image:
    """把圆角方形补成满幅方图：四角按最近圆弧点的颜色延拓。"""
    img = crop.resize((out, out), Image.LANCZOS)
    arr = np.asarray(img).astype(np.float32)
    r = max(0.0, radius * out / crop.width)
    last = out - 1
    m = int(np.ceil(r)) + 1
    # (行区间, 列区间, 圆心 y, 圆心 x)：左上 / 右上 / 左下 / 右下
    corners = [
        (slice(0, m), slice(0, m), r, r),
        (slice(0, m), slice(int(np.floor(last - r)), out), r, last - r),
        (slice(int(np.floor(last - r)), out), slice(0, m), last - r, r),
        (slice(int(np.floor(last - r)), out), slice(int(np.floor(last - r)), out), last - r, last - r),
    ]

    yy, xx = np.mgrid[0:out, 0:out]
    for ys, xs, cy, cx in corners:
        y = yy[ys, xs].astype(np.float32)
        x = xx[ys, xs].astype(np.float32)
        vy, vx = y - cy, x - cx
        dist = np.hypot(vx, vy)
        # 沿圆弧留一段羽化带，既盖掉被灰底混色的 2~3px，也消除接缝
        band = max(3.0, r * 0.035)
        weight = np.clip((dist - (r - band)) / band, 0.0, 1.0)
        if weight.max() <= 0:
            continue
        scale = (r * 0.94) / np.maximum(dist, 1e-6)  # 稍往内取色，避开边缘杂色
        fx = cx + vx * scale
        fy = cy + vy * scale
        # 双线性采样：把圆弧上的颜色沿径向平滑延拓到角上
        x0 = np.clip(np.floor(fx).astype(int), 0, last)
        y0 = np.clip(np.floor(fy).astype(int), 0, last)
        x1 = np.clip(x0 + 1, 0, last)
        y1 = np.clip(y0 + 1, 0, last)
        wx = (fx - x0)[..., None]
        wy = (fy - y0)[..., None]
        sampled = (
            arr[y0, x0] * (1 - wx) * (1 - wy)
            + arr[y0, x1] * wx * (1 - wy)
            + arr[y1, x0] * (1 - wx) * wy
            + arr[y1, x1] * wx * wy
        )
        w = weight[..., None]
        arr[ys, xs] = arr[ys, xs] * (1 - w) + sampled * w

    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGB")


def rounded_alpha(full: Image.Image, radius_ratio: float, pad: float = 0.0) -> Image.Image:
    """满幅方图 -> 透明底的圆角图标（可选留白），用于 macOS / Windows。"""
    size = full.width
    inner = round(size * (1 - 2 * pad))
    icon = full.resize((inner, inner), Image.LANCZOS)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    ss = 4  # 超采样抗锯齿
    mask = Image.new("L", (inner * ss, inner * ss), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, inner * ss - 1, inner * ss - 1], radius=int(radius_ratio * inner * ss), fill=255
    )
    mask = mask.resize((inner, inner), Image.LANCZOS)
    canvas.paste(icon, ((size - inner) // 2, (size - inner) // 2), mask)
    return canvas


def circle_alpha(full: Image.Image) -> Image.Image:
    size = full.width
    ss = 4
    mask = Image.new("L", (size * ss, size * ss), 0)
    r = size * ss / 2 * 0.995
    ImageDraw.Draw(mask).ellipse([size * ss / 2 - r, size * ss / 2 - r, size * ss / 2 + r, size * ss / 2 + r], fill=255)
    mask = mask.resize((size, size), Image.LANCZOS)
    out = full.convert("RGBA")
    out.putalpha(mask)
    return out


def save(img: Image.Image, path: Path, size: int, opaque: bool = False) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    resized = img.resize((size, size), Image.LANCZOS)
    if opaque:
        resized = resized.convert("RGB")
    else:
        resized = resized.convert("RGBA")
    resized.save(path, optimize=True)


def main() -> None:
    src = Image.open(SRC).convert("RGB")
    crop, radius, width = crop_icon(src)
    print(f"源图 {src.width}x{src.height} -> 图标本体 {width}px，圆角半径 {radius:.1f}px")

    full = square_up(crop, radius, 1024)
    full = full.filter(ImageFilter.UnsharpMask(radius=2, percent=45, threshold=3))
    MASTER.parent.mkdir(parents=True, exist_ok=True)
    full.save(MASTER, optimize=True)
    print(f"母版 -> {MASTER.relative_to(ROOT)}")

    radius_ratio = radius / width

    # ---------------- Android ----------------
    legacy = rounded_alpha(full, radius_ratio)
    round_icon = circle_alpha(full)
    for density, px in LAUNCHER_DP.items():
        save(legacy, ANDROID_RES / f"mipmap-{density}" / "ic_launcher.png", px)
        save(round_icon, ANDROID_RES / f"mipmap-{density}" / "ic_launcher_round.png", px)
    # 自适应图标：背景层为满幅图，前景层留空（图形本身已满幅）
    transparent = Image.new("RGBA", (432, 432), (0, 0, 0, 0))
    for density, px in ADAPTIVE_DP.items():
        save(full, ANDROID_RES / f"mipmap-{density}" / "ic_launcher_background.png", px, opaque=True)
        save(transparent, ANDROID_RES / f"mipmap-{density}" / "ic_launcher_foreground.png", px)
    print("Android -> mipmap-*/ic_launcher*.png + 自适应图层")

    # ---------------- iOS ----------------
    contents = json.loads((IOS_SET / "Contents.json").read_text(encoding="utf-8"))
    count = 0
    for entry in contents["images"]:
        base = float(entry["size"].split("x")[0])
        scale = int(entry["scale"].rstrip("x"))
        save(full, IOS_SET / entry["filename"], round(base * scale), opaque=True)
        count += 1
    print(f"iOS -> {count} 个尺寸（无 alpha）")

    # ---------------- macOS ----------------
    mac_icon = rounded_alpha(full, radius_ratio, pad=0.09)
    for px in (16, 32, 64, 128, 256, 512, 1024):
        save(mac_icon, MACOS_SET / f"app_icon_{px}.png", px)
    print("macOS -> 7 个尺寸")

    # ---------------- Web ----------------
    save(full, WEB_ICONS / "Icon-192.png", 192, opaque=True)
    save(full, WEB_ICONS / "Icon-512.png", 512, opaque=True)
    save(full, WEB_ICONS / "Icon-maskable-192.png", 192, opaque=True)
    save(full, WEB_ICONS / "Icon-maskable-512.png", 512, opaque=True)
    save(full, WEB_FAVICON, 64, opaque=True)
    print("Web -> icons/*.png + favicon.png")

    # ---------------- Windows ----------------
    ico_sizes = [16, 24, 32, 48, 64, 128, 256]
    WINDOWS_ICO.parent.mkdir(parents=True, exist_ok=True)
    base = legacy.convert("RGBA")
    base.save(WINDOWS_ICO, format="ICO", sizes=[(s, s) for s in ico_sizes])
    print(f"Windows -> {WINDOWS_ICO.relative_to(ROOT)} ({', '.join(map(str, ico_sizes))})")


if __name__ == "__main__":
    main()
