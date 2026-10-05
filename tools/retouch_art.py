# -*- coding: utf-8 -*-
"""水墨素材修板工具（AI 原图 → 入库成品）。

用法：
  python tools/retouch_art.py --kind beast assets/art/_raw/gudiao.png -o assets/art/beasts/gudiao.png
  python tools/retouch_art.py --kind brush assets/art/_raw/brush_splash_1.png -o assets/art/brushes/
  python tools/retouch_art.py --kind paper assets/art/_raw/paper_01.png -o assets/art/paper/

三步（分工规划 §四修板四步的自动化部分）：
  1) 白底转透明：亮度→alpha（白=0，浓墨=1，中间羽化）
  2) 三阶墨 posterize：浓 #2B2620 / 中 #6E675C / 淡 #B9B2A2（色值与 theme.json/InkPalette 同源）
  3) 内容 bbox 裁切 + 方形透明补齐 + 缩放（beast 128 / brush 256 / paper 512）
"""
import argparse
import sys
from pathlib import Path

from PIL import Image

INK_DEEP = (0x2B, 0x26, 0x20)
INK_MID = (0x6E, 0x67, 0x5C)
INK_LIGHT = (0xB9, 0xB2, 0xA2)

SIZE = {"beast": 128, "brush": 256, "paper": 512, "field": 512}
WHITE_GATE = 238   # 亮度高于此 → 全透明
INK_GATE = 108     # 亮度低于此 → 全不透明
DEEP_SPLIT = 88    # posterize 分档
MID_SPLIT = 176
FEATHER = 48       # field 模式：四边羽化带宽度（px，弱化 AI 平铺接缝）


def ink_alpha(lum: int) -> int:
    """亮度→alpha：白纸透、浓墨实，中间线性羽化。"""
    if lum >= WHITE_GATE:
        return 0
    if lum <= INK_GATE:
        return 255
    span = WHITE_GATE - INK_GATE
    return int(255 * (WHITE_GATE - lum) / span)


def ink_level(lum: int):
    if lum < DEEP_SPLIT:
        return INK_DEEP
    if lum < MID_SPLIT:
        return INK_MID
    return INK_LIGHT


def retouch(src: Path, kind: str, deepen: bool = False) -> Image.Image:
    image = Image.open(src).convert("L")  # 统一灰度：彩色图也按明度压入墨阶
    alpha = Image.eval(image, ink_alpha)
    if kind == "paper":
        return image.convert("RGB").resize((SIZE[kind], SIZE[kind]), Image.LANCZOS)
    if kind == "brush":
        # 笔刷只做白底转 alpha，保留连续灰阶（运行时再上色）
        out = Image.merge("RGBA", (*image.convert("RGB").split(), alpha))
    elif kind == "field":
        # 整片场贴图（水纹等）：百分位对比度拉伸（AI 常把"淡墨"画得只比纸底深一二十级）
        # → 紧致门限转 alpha（拉伸后线暗、纸底亮，用更高的白门槛把背景噪声归零）
        # → 四边羽化（接缝化为空档）；不裁切不补方形——保持可平铺的满幅场
        image = _stretch(image)
        alpha = image.point(_field_alpha)
        out = Image.merge("RGBA", (*image.convert("RGB").split(), _feather_edges(alpha, FEATHER)))
    else:
        # 三阶墨查表（浓/中/淡，档位边界与 alpha 羽化衔接）；deepen=整体加深一档
        solid = Image.new("RGB", image.size)
        sp = solid.load()
        px = image.load()
        for y in range(image.height):
            for x in range(image.width):
                lum = px[x, y]
                level = 0 if lum < DEEP_SPLIT else (1 if lum < MID_SPLIT else 2)
                if deepen and level > 0:
                    level -= 1
                sp[x, y] = (INK_DEEP, INK_MID, INK_LIGHT)[level]
        out = Image.merge("RGBA", (*solid.split(), alpha))
    out = _fit(out, SIZE[kind]) if kind != "field" else out.resize((SIZE[kind], SIZE[kind]), Image.LANCZOS)
    if kind == "beast":
        out = _despeckle(out)  # 笔刷的卫星墨滴是设计特征，不清
    return out


def _fade_bottom(image: Image.Image, frac: float) -> Image.Image:
    """底部 band 像素线性淡出到透明（山脚/树根虚化，没骨法衔接淡墨底）。"""
    w, h = image.size
    band = max(1, int(h * frac))
    px = image.load()
    for y in range(h - band, h):
        fade = 1.0 - (y - (h - band)) / band
        for x in range(w):
            r, g, b, a = px[x, y]
            px[x, y] = (r, g, b, int(a * fade))
    return image


def _stretch(image: Image.Image, low_q: float = 0.02, high_q: float = 0.995) -> Image.Image:
    """按亮度百分位把实际动态范围拉到全量程（low_q→0，high_q→255）。"""
    hist = image.histogram()
    total = sum(hist)

    def threshold(q: float) -> int:
        acc = 0
        for value in range(256):
            acc += hist[value]
            if acc >= total * q:
                return value
        return 255

    lo = threshold(low_q)
    hi = threshold(high_q)
    if hi <= lo:
        return image
    lut = [max(0, min(255, int((v - lo) * 255 / (hi - lo)))) for v in range(256)]
    return image.point(lut)


def _field_alpha(lum: int, white: int = 210, ink: int = 100) -> int:
    """field 模式专用：拉伸后的亮度 → alpha（门限比通用白底抠图更紧，压掉纸底噪声）。"""
    if lum >= white:
        return 0
    if lum <= ink:
        return 255
    return int(255 * (white - lum) / (white - ink))


def _feather_edges(alpha: Image.Image, band: int) -> Image.Image:
    """四边 band 像素宽的 alpha 线性淡出（0→原值），把平铺接缝化为稀疏空档。"""
    w, h = alpha.size
    out = alpha.copy()
    px = out.load()
    for y in range(h):
        for x in range(w):
            d = min(x, y, w - 1 - x, h - 1 - y)
            if d < band:
                px[x, y] = int(px[x, y] * d / band)
    return out


def _despeckle(image: Image.Image, min_area: int = 8) -> Image.Image:
    """清孤立碎点：alpha>16 的连通域面积 < min_area 整块清零（AI 原图飞墨+缩放粉尘）。"""
    alpha = image.getchannel("A")
    w, h = image.size
    seen = bytearray(w * h)
    px = image.load()
    for start in range(w * h):
        if seen[start] or alpha.getpixel((start % w, start // w)) <= 16:
            continue
        stack = [start]
        seen[start] = 1
        blob = []
        while stack:
            idx = stack.pop()
            blob.append(idx)
            x, y = idx % w, idx // w
            for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                if 0 <= nx < w and 0 <= ny < h:
                    n = ny * w + nx
                    if not seen[n] and alpha.getpixel((nx, ny)) > 16:
                        seen[n] = 1
                        stack.append(n)
        if len(blob) < min_area:
            for idx in blob:
                r, g, b, _a = px[idx % w, idx // w]
                px[idx % w, idx // w] = (r, g, b, 0)
    return image


def _fit(image: Image.Image, size: int) -> Image.Image:
    """bbox 裁切 + 6% 边距 + 方形透明补齐 + 缩放。"""
    bbox = image.getchannel("A").getbbox()
    if bbox is None:
        raise SystemExit(f"FAIL 全图透明（白底抠空）：请检查原图是否白底")
    w = bbox[2] - bbox[0]
    h = bbox[3] - bbox[1]
    margin = int(max(w, h) * 0.06)
    bbox = (max(0, bbox[0] - margin), max(0, bbox[1] - margin),
            min(image.width, bbox[2] + margin), min(image.height, bbox[3] + margin))
    image = image.crop(bbox)
    side = max(image.width, image.height)
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(image, ((side - image.width) // 2, (side - image.height) // 2))
    return canvas.resize((size, size), Image.LANCZOS)


def main() -> None:
    parser = argparse.ArgumentParser(description="水墨素材修板")
    parser.add_argument("src", type=Path)
    parser.add_argument("-o", "--out", type=Path, required=True)
    parser.add_argument("--kind", choices=["beast", "brush", "paper", "field"], default="beast")
    parser.add_argument("--deepen", action="store_true", help="墨阶整体加深一档（淡→中→浓）")
    parser.add_argument("--fade-bottom", type=float, default=0.0, help="底部渐隐比例（如 0.3 = 底部30%%线性淡出，山脚/树根虚化衔接）")
    args = parser.parse_args()
    result = retouch(args.src, args.kind, args.deepen)
    if args.fade_bottom > 0:
        result = _fade_bottom(result, args.fade_bottom)
    out = args.out
    if out.is_dir():
        out = out / args.src.name
    out.parent.mkdir(parents=True, exist_ok=True)
    result.save(out)
    coverage = sum(result.getchannel("A").histogram()[17:]) / (result.width * result.height)
    print(f"OK {out} {result.width}x{result.height} 不透明覆盖 {coverage:.0%}")


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main()
