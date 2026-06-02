#!/usr/bin/env python3
"""Scaffold a KnowYou feature launch package from templates."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[4]
SKILL_DIR = Path(__file__).resolve().parents[1]
TEMPLATE_DIR = SKILL_DIR / "assets" / "templates"
DEFAULT_CHANNELS = ROOT / "docs" / "marketing" / "channels.json"
DEFAULT_OUTPUT_ROOT = ROOT / "docs" / "marketing" / "launches"


def slugify(text: str) -> str:
    slug = re.sub(r"[^a-zA-Z0-9]+", "-", text.strip().lower()).strip("-")
    return slug or "feature-launch"


def load_channels(path: Path) -> list[dict]:
    if not path.exists():
        return []
    data = json.loads(path.read_text(encoding="utf-8"))
    return [channel for channel in data.get("channels", []) if channel.get("enabled", True)]


def render(template: str, replacements: dict[str, str]) -> str:
    for key, value in replacements.items():
        template = template.replace("{{" + key + "}}", value)
    return template


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--feature", required=True, help="Feature title, e.g. MyWiki memory")
    parser.add_argument("--date", default=dt.date.today().isoformat(), help="YYYY-MM-DD")
    parser.add_argument("--slug", help="Optional slug override")
    parser.add_argument("--channels", type=Path, default=DEFAULT_CHANNELS)
    parser.add_argument("--output-root", type=Path, default=DEFAULT_OUTPUT_ROOT)
    args = parser.parse_args()

    slug = args.slug or slugify(args.feature)
    output_dir = args.output_root / f"{args.date}-{slug}"
    output_dir.mkdir(parents=True, exist_ok=True)

    replacements = {
        "FEATURE_TITLE": args.feature,
        "DATE": args.date,
        "SLUG": slug,
    }

    for template_path in sorted(TEMPLATE_DIR.glob("*.md")):
        target = output_dir / template_path.name
        if target.exists():
            continue
        target.write_text(render(template_path.read_text(encoding="utf-8"), replacements), encoding="utf-8")

    channels = load_channels(args.channels)
    selected_path = output_dir / "selected-channels.json"
    if channels and not selected_path.exists():
        selected_path.write_text(json.dumps({"channels": channels}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print(output_dir)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
