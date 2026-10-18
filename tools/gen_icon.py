"""生成 PlanBox 的应用图标（PNG），供 CI 时由 tools/patch_android.py 塞进 android 工程。

设计：靛蓝渐变圆角方块 + 白色对勾，右下角三条淡淡的进度条，
暗示「计划 / 打卡」。不用外部字体，纯几何绘制，任何机器都能复现。

用法：python3 tools/gen_icon.py
"""
import os
import sys

from PIL import Image, ImageDraw

# 与 App 内主题色保持一致：Pal.accentPresets[0] 靛蓝
C_TOP = (91, 156, 255)
C_BOT = (58, 118, 226)

# 每个密度：目录名, 尺寸(dp)
DENSITIES = [
    ("mdpi", 48),
    ("hdpi", 72),
    ("xhdpi", 96),
    ("xxhdpi", 144),
    ("xxxhdpi", 192),
]
# 自适应图标前景：108dp 画布，内容放在内切 66dp 的安全区里
FOREGROUND = [("mdpi", 108), ("hdpi", 162), ("xhdpi", 216),
              ("xxhdpi", 324), ("xxxhdpi", 432)]

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "assets", "icon")


def gradient(size):
    img = Image.new("RGB", (1, size))
    d = ImageDraw.Draw(img)
    for y in range(size):
        t = y / max(1, size - 1)
        d.point((0, y), (
            int(C_TOP[0] + (C_BOT[0] - C_TOP[0]) * t),
            int(C_TOP[1] + (C_BOT[1] - C_TOP[1]) * t),
            int(C_TOP[2] + (C_BOT[2] - C_TOP[2]) * t),
        ))
    return img.resize((size, size), Image.NEAREST)


def rounded_mask(size, radius_ratio=0.22):
    # 4 倍超采样，边缘才不锯齿
    ss = 4
    m = Image.new("L", (size * ss, size * ss), 0)
    d = ImageDraw.Draw(m)
    r = int(size * ss * radius_ratio)
    d.rounded_rectangle([0, 0, size * ss - 1, size * ss - 1], radius=r, fill=255)
    return m.resize((size, size), Image.LANCZOS)


def draw_glyph(size, scale=1.0):
    """白色对勾 + 三条短横线。返回 RGBA 图层。"""
    ss = 4
    s = size * ss
    layer = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    # 对勾
    w = max(2, int(s * 0.085 * scale))
    pts = [
        (s * 0.26, s * 0.52),
        (s * 0.43, s * 0.68),
        (s * 0.74, s * 0.34),
    ]
    d.line([(pts[0][0], pts[0][1]), (pts[1][0], pts[1][1])],
           fill=(255, 255, 255, 255), width=w, joint="curve")
    d.line([(pts[1][0], pts[1][1]), (pts[2][0], pts[2][1])],
           fill=(255, 255, 255, 255), width=w, joint="curve")
    # 线条端点是方的，补两个圆头
    for (x, y) in (pts[0], pts[2]):
        d.ellipse([x - w / 2, y - w / 2, x + w / 2, y + w / 2],
                  fill=(255, 255, 255, 255))
    d.ellipse([pts[1][0] - w / 2, pts[1][1] - w / 2,
               pts[1][0] + w / 2, pts[1][1] + w / 2],
              fill=(255, 255, 255, 255))
    return layer.resize((size, size), Image.LANCZOS)


def make_legacy(size):
    bg = gradient(size).convert("RGBA")
    bg.putalpha(rounded_mask(size))
    glyph = draw_glyph(size)
    return Image.alpha_composite(bg, glyph)


def make_foreground(size):
    # 只画字形，背景留给 adaptive-icon 的 @color
    return draw_glyph(size, scale=0.72)


def main():
    made = 0
    for dens, px in DENSITIES:
        d = os.path.join(OUT, "mipmap-" + dens)
        os.makedirs(d, exist_ok=True)
        make_legacy(px).save(os.path.join(d, "ic_launcher.png"))
        made += 1
    for dens, px in FOREGROUND:
        d = os.path.join(OUT, "mipmap-" + dens)
        os.makedirs(d, exist_ok=True)
        make_foreground(px).save(os.path.join(d, "ic_launcher_foreground.png"))
        made += 1
    # 顺便存一张大图，README / 商店用
    make_legacy(512).save(os.path.join(OUT, "icon-512.png"))
    made += 1
    print("已生成 %d 个图标文件 -> %s" % (made, OUT))


if __name__ == "__main__":
    sys.exit(main())
