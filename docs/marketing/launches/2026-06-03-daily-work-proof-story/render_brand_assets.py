from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter


ROOT = Path(__file__).resolve().parents[4]
LAUNCH = Path(__file__).resolve().parent
ASSETS = LAUNCH / "assets"

APP_ICON = ROOT / "KnowYou/Assets.xcassets/AppIcon.appiconset/mac_512.png"
MAIN_SCREEN = ROOT / "demo-picture/knowyou-main-window.png"
SYNC_SCREEN = ROOT / "demo-picture/knowyou-sync-memory.png"
ENGINE_SCREEN = ROOT / "demo-picture/knowyou-diary-engine.png"


COLORS = {
    "bg": (22, 23, 25),
    "panel": (32, 34, 38),
    "panel2": (40, 42, 47),
    "line": (74, 80, 92),
    "text": (244, 245, 247),
    "muted": (164, 168, 176),
    "blue": (10, 132, 255),
    "yellow": (255, 214, 10),
    "green": (48, 209, 88),
    "purple": (143, 111, 220),
}


def font(size, bold=False, mono=False, cn=False):
    if cn:
        path = "/System/Library/Fonts/STHeiti Medium.ttc" if bold else "/System/Library/Fonts/STHeiti Light.ttc"
    elif mono:
        path = "/System/Library/Fonts/SFNSMono.ttf"
    else:
        path = "/System/Library/Fonts/SFNS.ttf"
    return ImageFont.truetype(path, size=size)


def rounded_mask(size, radius):
    mask = Image.new("L", size, 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], radius=radius, fill=255)
    return mask


def paste_rounded(base, img, box, radius=36, border=True):
    x, y, w, h = box
    img = img.resize((w, h), Image.Resampling.LANCZOS).convert("RGBA")
    shadow = Image.new("RGBA", (w + 60, h + 60), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.rounded_rectangle([30, 30, w + 30, h + 30], radius=radius, fill=(0, 0, 0, 115))
    shadow = shadow.filter(ImageFilter.GaussianBlur(18))
    base.alpha_composite(shadow, (x - 30, y - 18))
    mask = rounded_mask((w, h), radius)
    clipped = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    clipped.alpha_composite(img, (0, 0))
    base.paste(clipped, (x, y), mask)
    if border:
        d = ImageDraw.Draw(base)
        d.rounded_rectangle([x, y, x + w, y + h], radius=radius, outline=(78, 82, 90), width=2)


def draw_logo(base, draw, x, y, size=64, title_size=42, subtitle=None):
    icon = Image.open(APP_ICON).convert("RGBA").resize((size, size), Image.Resampling.LANCZOS)
    base.alpha_composite(icon, (x, y))
    draw.text((x + size + 18, y + 3), "KnowYou", fill=COLORS["text"], font=font(title_size, bold=True))
    if subtitle:
        subtitle_is_cn = any(ord(char) > 127 for char in subtitle)
        draw.text(
            (x + size + 20, y + title_size + 10),
            subtitle,
            fill=COLORS["muted"],
            font=font(20, cn=subtitle_is_cn),
        )


def wrap(draw, text, fnt, max_width):
    words = text.split(" ")
    lines, current = [], ""
    for word in words:
        candidate = word if not current else current + " " + word
        if draw.textlength(candidate, font=fnt) <= max_width:
            current = candidate
        else:
            if current:
                lines.append(current)
            current = word
    if current:
        lines.append(current)
    return lines


def multiline(draw, text, xy, fnt, fill, max_width, line_gap=10):
    x, y = xy
    for line in wrap(draw, text, fnt, max_width):
        draw.text((x, y), line, fill=fill, font=fnt)
        y += fnt.size + line_gap
    return y


def metric_card(draw, xy, title, value, color):
    x, y = xy
    draw.rounded_rectangle([x, y, x + 220, y + 112], radius=24, fill=COLORS["panel"], outline=(62, 66, 74), width=1)
    draw.ellipse([x + 22, y + 25, x + 48, y + 51], fill=color)
    draw.text((x + 62, y + 22), title, fill=COLORS["muted"], font=font(20))
    draw.text((x + 62, y + 55), value, fill=COLORS["text"], font=font(30, bold=True))


def render_english_hero():
    base = Image.new("RGBA", (1600, 900), COLORS["bg"] + (255,))
    draw = ImageDraw.Draw(base)
    draw_logo(base, draw, 74, 68, subtitle="Personal context for AI agents")
    draw.text((76, 205), "Proof of a full day", fill=COLORS["text"], font=font(76, bold=True))
    y = multiline(
        draw,
        "When work gets scattered across apps, KnowYou turns the day into a local memory you can actually show.",
        (80, 310),
        font(30),
        COLORS["muted"],
        545,
        12,
    )
    draw.rounded_rectangle([80, y + 30, 650, y + 128], radius=28, fill=(28, 31, 36), outline=(64, 68, 76), width=1)
    draw.text((116, y + 56), "“What did you do today?”", fill=COLORS["text"], font=font(28, bold=True))
    draw.text((116, y + 93), "Let the day answer with sources.", fill=COLORS["muted"], font=font(22))
    metric_card(draw, (80, 692), "Memories", "28", COLORS["blue"])
    metric_card(draw, (325, 692), "To-dos", "9", COLORS["yellow"])
    metric_card(draw, (570, 692), "Sources", "14", COLORS["green"])
    screen = Image.open(MAIN_SCREEN)
    paste_rounded(base, screen, (735, 84, 790, 668), radius=42)
    draw.rounded_rectangle([1064, 774, 1522, 838], radius=32, fill=(15, 17, 20), outline=(58, 63, 72), width=1)
    draw.text((1095, 792), "All data stays local on your Mac.", fill=COLORS["muted"], font=font(24))
    base.convert("RGB").save(ASSETS / "work-proof-english-hero.png", quality=95)


def render_chinese_hero():
    base = Image.new("RGBA", (1600, 900), COLORS["bg"] + (255,))
    draw = ImageDraw.Draw(base)
    draw_logo(base, draw, 74, 64, subtitle="本地优先的个人工作记忆")
    draw.text((78, 200), "今天到底", fill=COLORS["text"], font=font(82, bold=True, cn=True))
    draw.text((78, 300), "干了什么？", fill=COLORS["text"], font=font(82, bold=True, cn=True))
    y = multiline(
        draw,
        "不用凭记忆解释。KnowYou 把散在 Mac 上的一天工作整理成本地、可追溯的记忆。",
        (82, 430),
        font(32, cn=True),
        COLORS["muted"],
        580,
        12,
    )
    draw.rounded_rectangle([82, y + 34, 650, y + 146], radius=28, fill=COLORS["panel"], outline=(64, 68, 76), width=1)
    draw.text((118, y + 58), "你看，我今天真的做了很多。", fill=COLORS["text"], font=font(30, bold=True, cn=True))
    draw.text((118, y + 100), "时间线、来源、Todo 都在这里。", fill=COLORS["muted"], font=font(24, cn=True))
    screen = Image.open(MAIN_SCREEN)
    paste_rounded(base, screen, (720, 86, 805, 670), radius=42)
    draw.rounded_rectangle([80, 748, 636, 824], radius=38, fill=(15, 17, 20), outline=(58, 63, 72), width=1)
    draw.text((118, 771), "本地保存，不是监控。是你自己的上下文。", fill=COLORS["muted"], font=font(25, cn=True))
    base.convert("RGB").save(ASSETS / "work-proof-chinese-hero.png", quality=95)


def render_carousel():
    base = Image.new("RGBA", (1080, 1350), COLORS["bg"] + (255,))
    draw = ImageDraw.Draw(base)
    draw_logo(base, draw, 66, 58, size=60, title_size=38)
    draw.text((66, 150), "Your workday,\nremembered.", fill=COLORS["text"], font=font(66, bold=True), spacing=8)
    draw.text((66, 318), "A local memory layer for status updates, weekly reviews, and AI agents.", fill=COLORS["muted"], font=font(27))
    metric_card(draw, (66, 390), "Timeline", "auto", COLORS["blue"])
    metric_card(draw, (312, 390), "Sources", "linked", COLORS["green"])
    metric_card(draw, (558, 390), "Privacy", "local", COLORS["purple"])
    screen = Image.open(MAIN_SCREEN)
    paste_rounded(base, screen, (70, 550, 940, 585), radius=34)
    draw.rounded_rectangle([72, 1186, 1008, 1288], radius=30, fill=COLORS["panel"], outline=(62, 66, 74), width=1)
    draw.text((112, 1210), "When someone asks what you did today,", fill=COLORS["muted"], font=font(28))
    draw.text((112, 1248), "the day can answer with evidence.", fill=COLORS["text"], font=font(34, bold=True))
    base.convert("RGB").save(ASSETS / "work-proof-carousel.png", quality=95)


def render_devto_cover():
    base = Image.new("RGBA", (1000, 420), COLORS["bg"] + (255,))
    draw = ImageDraw.Draw(base)
    draw_logo(base, draw, 48, 44, size=52, title_size=34)
    draw.text((54, 135), "Your Workday,\nRemembered", fill=COLORS["text"], font=font(58, bold=True), spacing=4)
    draw.text((58, 286), "Local context for humans and AI agents", fill=COLORS["muted"], font=font(26))
    screen = Image.open(MAIN_SCREEN)
    paste_rounded(base, screen, (540, 50, 410, 255), radius=26)
    draw.rounded_rectangle([540, 330, 946, 382], radius=26, fill=COLORS["panel"], outline=(62, 66, 74), width=1)
    draw.text((566, 344), "Private by default. Source-linked.", fill=COLORS["muted"], font=font(22))
    base.convert("RGB").save(ASSETS / "workday-remembered-devto-cover.png", quality=95)


if __name__ == "__main__":
    ASSETS.mkdir(parents=True, exist_ok=True)
    render_english_hero()
    render_chinese_hero()
    render_carousel()
    render_devto_cover()
    print("Rendered brand-aligned assets into", ASSETS)
