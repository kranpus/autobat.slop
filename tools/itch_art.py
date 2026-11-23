#!/usr/bin/env python3
"""Cover (630x500) and banner (960x300) for the itch.io page, made from the
battle screenshot (run tools/itch_shots.gd first) and the game's Cinzel font.
    python3 tools/itch_art.py
"""
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageEnhance

SHOT = "itch/screenshots/01_battle.png"
FONT = "assets/fonts/Cinzel.ttf"
GOLD = (233, 196, 106)
GOLD_DARK = (122, 90, 34)
INK = (20, 14, 8)


def font(size, weight):
    f = ImageFont.truetype(FONT, size)
    try:
        f.set_variation_by_axes([weight])
    except Exception:
        pass
    return f


def cover_crop(img, box, size):
    """Crop `box` (keeping the target aspect) and scale to `size`."""
    x0, y0, x1, y1 = box
    tw, th = size
    w = x1 - x0
    h = round(w * th / tw)
    return img.crop((x0, y0, x0 + w, y0 + h)).resize(size, Image.LANCZOS)


def shade(img, top=0.55, bottom=0.85):
    """Darken towards the top and bottom edges so the title reads."""
    w, h = img.size
    grad = Image.new("L", (1, h))
    for y in range(h):
        t = y / (h - 1)
        a = max(top * (1 - t / 0.45) if t < 0.45 else 0, bottom * ((t - 0.55) / 0.45) if t > 0.55 else 0)
        grad.putpixel((0, y), int(255 * min(1, a)))
    grad = grad.resize((w, h))
    black = Image.new("RGB", (w, h), (8, 6, 4))
    return Image.composite(black, img, grad)


def text_center(img, y, text, f, fill=GOLD, outline=INK, stroke=3, glow=True):
    d = ImageDraw.Draw(img)
    w = d.textbbox((0, 0), text, font=f, stroke_width=stroke)[2]
    x = (img.width - w) // 2
    if glow:
        layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
        ImageDraw.Draw(layer).text((x, y), text, font=f, fill=(0, 0, 0, 230), stroke_width=stroke + 6, stroke_fill=(0, 0, 0, 230))
        layer = layer.filter(ImageFilter.GaussianBlur(8))
        img.paste(layer, (0, 0), layer)
        d = ImageDraw.Draw(img)
    d.text((x, y), text, font=f, fill=fill, stroke_width=stroke, stroke_fill=outline)


def frame(img, width=4):
    d = ImageDraw.Draw(img)
    w, h = img.size
    d.rectangle((0, 0, w - 1, h - 1), outline=(10, 8, 6), width=1)
    d.rectangle((1, 1, w - 2, h - 2), outline=GOLD_DARK, width=width)
    d.rectangle((1 + width, 1 + width, w - 2 - width, h - 2 - width), outline=(30, 22, 12), width=1)


def main():
    shot = Image.open(SHOT).convert("RGB")
    shot = ImageEnhance.Color(shot).enhance(1.15)

    cover = cover_crop(shot, (300, 180, 1300, 980), (630, 500))
    cover = shade(cover, top=0.75, bottom=0.9)
    text_center(cover, 22, "AUTOBAT", font(74, 700))
    text_center(cover, 98, "LEGIONS", font(74, 700))
    text_center(cover, 418, "Thousand-unit auto-battles", font(26, 600), fill=(240, 228, 200), stroke=2)
    text_center(cover, 452, "Collect  ·  Upgrade  ·  Conquer", font(20, 500), fill=(214, 190, 140), stroke=2)
    frame(cover)
    cover.save("itch/cover.png")

    banner = cover_crop(shot, (0, 300, 1920, 900), (960, 300))
    banner = shade(banner, top=0.35, bottom=0.6)
    text_center(banner, 70, "AUTOBAT LEGIONS", font(78, 700))
    text_center(banner, 178, "Raise a legion. Watch a thousand units clash.", font(26, 600), fill=(240, 228, 200), stroke=2)
    banner.save("itch/banner.png")
    print("wrote itch/cover.png and itch/banner.png")


if __name__ == "__main__":
    main()
