from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter


ROOT = Path(__file__).resolve().parents[4]
LAUNCH = Path(__file__).resolve().parent
ASSETS = LAUNCH / "assets"

APP_ICON = ROOT / "KnowYou/Assets.xcassets/AppIcon.appiconset/mac_512.png"
MAIN_SCREEN = ROOT / "demo-picture/knowyou-main-window.png"
SYNC_SCREEN = ROOT / "demo-picture/knowyou-sync-memory.png"

SOURCE_LOGOS = [
    ROOT / "KnowYou/Assets.xcassets/SourceLogoXcode.imageset/logo.png",
    ROOT / "KnowYou/Assets.xcassets/SourceLogoClaude.imageset/logo.png",
    ROOT / "KnowYou/Assets.xcassets/SourceLogoCursor.imageset/logo.png",
    ROOT / "KnowYou/Assets.xcassets/SourceLogoChrome.imageset/logo.png",
    ROOT / "KnowYou/Assets.xcassets/SourceLogoSlack.imageset/logo.png",
    ROOT / "KnowYou/Assets.xcassets/SourceLogoNotes.imageset/logo.png",
    ROOT / "KnowYou/Assets.xcassets/SourceLogoObsidian.imageset/logo.png",
    ROOT / "KnowYou/Assets.xcassets/SourceLogoTerminal.imageset/logo.png",
]

COLORS = {
    "bg": (22, 23, 25),
    "panel": (32, 34, 38),
    "panel2": (40, 42, 47),
    "line": (72, 78, 90),
    "text": (244, 245, 247),
    "muted": (165, 169, 178),
    "blue": (10, 132, 255),
    "green": (48, 209, 88),
    "purple": (143, 111, 220),
    "yellow": (255, 214, 10),
}


def font(size, bold=False, mono=False):
    if mono:
        path = "/System/Library/Fonts/SFNSMono.ttf"
    else:
        path = "/System/Library/Fonts/SFNS.ttf"
    return ImageFont.truetype(path, size=size)


def rounded_mask(size, radius):
    mask = Image.new("L", size, 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], radius=radius, fill=255)
    return mask


def paste_rounded(base, img, box, radius=34, shadow=True, border=True):
    x, y, w, h = box
    img = img.resize((w, h), Image.Resampling.LANCZOS).convert("RGBA")
    if shadow:
        sh = Image.new("RGBA", (w + 70, h + 70), (0, 0, 0, 0))
        sd = ImageDraw.Draw(sh)
        sd.rounded_rectangle([35, 35, w + 35, h + 35], radius=radius, fill=(0, 0, 0, 120))
        sh = sh.filter(ImageFilter.GaussianBlur(20))
        base.alpha_composite(sh, (x - 35, y - 20))
    mask = rounded_mask((w, h), radius)
    base.paste(img, (x, y), mask)
    if border:
        draw = ImageDraw.Draw(base)
        draw.rounded_rectangle([x, y, x + w, y + h], radius=radius, outline=(78, 82, 90), width=2)


def logo(base, draw, x, y, subtitle=None):
    icon = Image.open(APP_ICON).convert("RGBA").resize((58, 58), Image.Resampling.LANCZOS)
    base.alpha_composite(icon, (x, y))
    draw.text((x + 74, y + 1), "KnowYou", fill=COLORS["text"], font=font(38, True))
    if subtitle:
        draw.text((x + 76, y + 45), subtitle, fill=COLORS["muted"], font=font(18))


def draw_pill(draw, xy, text, color, width=None):
    x, y = xy
    w = width or int(draw.textlength(text, font=font(22, True)) + 54)
    draw.rounded_rectangle([x, y, x + w, y + 50], radius=25, fill=(28, 31, 36), outline=(58, 64, 74), width=1)
    draw.ellipse([x + 18, y + 17, x + 30, y + 29], fill=color)
    draw.text((x + 42, y + 12), text, fill=COLORS["text"], font=font(22, True))
    return w


def multiline(draw, lines, xy, text_font, fill, line_gap=10):
    x, y = xy
    for line in lines:
        draw.text((x, y), line, fill=fill, font=text_font)
        y += text_font.size + line_gap
    return y


def card(draw, xy, size, title, body, color):
    x, y = xy
    w, h = size
    draw.rounded_rectangle([x, y, x + w, y + h], radius=24, fill=COLORS["panel"], outline=(62, 66, 74), width=1)
    draw.ellipse([x + 24, y + 26, x + 46, y + 48], fill=color)
    draw.text((x + 62, y + 21), title, fill=COLORS["text"], font=font(25, True))
    yy = y + 66
    for line in body:
        draw.text((x + 28, yy), line, fill=COLORS["muted"], font=font(19))
        yy += 30


def render_hero():
    base = Image.new("RGBA", (1600, 900), COLORS["bg"] + (255,))
    draw = ImageDraw.Draw(base)
    logo(base, draw, 78, 72, "Local context for AI agents")
    draw.text((82, 190), "MyWiki, Search,\nand richer Sources", fill=COLORS["text"], font=font(72, True), spacing=12)
    multiline(
        draw,
        ["KnowYou turns scattered Mac context", "into a searchable, source-linked memory layer."],
        (86, 405),
        font(28),
        COLORS["muted"],
        12,
    )
    draw_pill(draw, (86, 500), "MyWiki", COLORS["purple"], 170)
    draw_pill(draw, (282, 500), "Semantic Search", COLORS["blue"], 260)
    draw_pill(draw, (86, 568), "Richer Sources", COLORS["green"], 240)
    card(draw, (86, 660), (280, 126), "Local-first", ["Memory stays on", "your Mac."], COLORS["green"])
    card(draw, (394, 660), (320, 126), "Agent-ready", ["Context for Codex,", "Claude Code, Cursor."], COLORS["blue"])
    screen = Image.open(MAIN_SCREEN)
    paste_rounded(base, screen, (825, 86, 700, 642), radius=42)
    draw.rounded_rectangle([1038, 765, 1525, 830], radius=32, fill=(15, 17, 20), outline=(58, 64, 74), width=1)
    draw.text((1072, 783), "Your day becomes reusable context.", fill=COLORS["muted"], font=font(25))
    base.convert("RGB").save(ASSETS / "knowyou-ph-release-hero.png", quality=95)


def render_mywiki_search():
    base = Image.new("RGBA", (1600, 900), COLORS["bg"] + (255,))
    draw = ImageDraw.Draw(base)
    logo(base, draw, 76, 66)
    draw.text((78, 155), "Daily memories become a living wiki", fill=COLORS["text"], font=font(58, True))
    draw.text((82, 230), "Search across decisions, todos, people, projects, and source evidence.", fill=COLORS["muted"], font=font(26))

    draw.rounded_rectangle([82, 322, 720, 780], radius=32, fill=COLORS["panel"], outline=(62, 66, 74), width=1)
    draw.text((122, 362), "MyWiki", fill=COLORS["text"], font=font(34, True))
    wiki_items = [
        ("# OpenClaw integration", "Daily notes, agent runs, and project context"),
        ("# Product Hunt launch", "Copy, assets, replies, and feedback"),
        ("# Onboarding flow", "Install gate, permissions, first useful moment"),
        ("# Source coverage", "Apps and logs included in memory"),
    ]
    y = 424
    for i, (title, body) in enumerate(wiki_items):
        draw.rounded_rectangle([122, y, 680, y + 72], radius=18, fill=(26, 28, 32), outline=(48, 53, 62), width=1)
        draw.ellipse([146, y + 24, 166, y + 44], fill=[COLORS["purple"], COLORS["blue"], COLORS["green"], COLORS["yellow"]][i])
        draw.text((184, y + 13), title, fill=COLORS["text"], font=font(22, True))
        draw.text((184, y + 43), body, fill=COLORS["muted"], font=font(17))
        y += 88

    draw.rounded_rectangle([780, 322, 1518, 780], radius=32, fill=COLORS["panel"], outline=(62, 66, 74), width=1)
    draw.text((820, 362), "Search", fill=COLORS["text"], font=font(34, True))
    draw.rounded_rectangle([820, 420, 1478, 476], radius=18, fill=(15, 17, 20), outline=(58, 64, 74), width=1)
    draw.text((850, 434), "why did we change the onboarding flow?", fill=COLORS["text"], font=font(24))
    results = [
        ("Apr 06 - Product cohesion", "A source-linked memory explains the first-run flow decision."),
        ("MyWiki - Onboarding flow", "Install gate before permissions; show Demo Day first."),
        ("Source - Xcode / Notes", "Original notes and implementation logs are still attached."),
    ]
    y = 512
    for title, body in results:
        draw.rounded_rectangle([820, y, 1478, y + 86], radius=20, fill=(26, 28, 32), outline=(48, 53, 62), width=1)
        draw.text((850, y + 16), title, fill=COLORS["text"], font=font(22, True))
        draw.text((850, y + 48), body, fill=COLORS["muted"], font=font(18))
        y += 104
    base.convert("RGB").save(ASSETS / "knowyou-ph-mywiki-search.png", quality=95)


def render_sources():
    base = Image.new("RGBA", (1600, 900), COLORS["bg"] + (255,))
    draw = ImageDraw.Draw(base)
    logo(base, draw, 76, 66)
    draw.text((78, 155), "Richer Sources", fill=COLORS["text"], font=font(60, True))
    draw.text((82, 235), "Every memory keeps its source evidence attached.", fill=COLORS["muted"], font=font(26))

    draw.rounded_rectangle([84, 330, 642, 760], radius=32, fill=COLORS["panel"], outline=(62, 66, 74), width=1)
    draw.text((124, 370), "Included Sources", fill=COLORS["text"], font=font(34, True))
    for idx, path in enumerate(SOURCE_LOGOS):
        row = idx // 2
        col = idx % 2
        x = 124 + col * 250
        y = 442 + row * 72
        draw.rounded_rectangle([x, y, x + 210, y + 52], radius=18, fill=(26, 28, 32), outline=(48, 53, 62), width=1)
        if path.exists():
            icon = Image.open(path).convert("RGBA").resize((30, 30), Image.Resampling.LANCZOS)
            base.alpha_composite(icon, (x + 18, y + 11))
        label = path.parts[-2].replace("SourceLogo", "").replace(".imageset", "")
        draw.text((x + 60, y + 14), label, fill=COLORS["text"], font=font(19, True))

    screen = Image.open(SYNC_SCREEN)
    paste_rounded(base, screen, (750, 332, 690, 520), radius=38)
    draw.rounded_rectangle([790, 176, 1438, 274], radius=28, fill=COLORS["panel"], outline=(62, 66, 74), width=1)
    draw.text((828, 204), "Sources are not decoration.", fill=COLORS["text"], font=font(30, True))
    draw.text((828, 242), "They are the trust layer behind every memory.", fill=COLORS["muted"], font=font(22))
    base.convert("RGB").save(ASSETS / "knowyou-ph-sources.png", quality=95)


if __name__ == "__main__":
    ASSETS.mkdir(parents=True, exist_ok=True)
    render_hero()
    render_mywiki_search()
    render_sources()
    print("Rendered Product Hunt assets into", ASSETS)
