#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = ["fonttools"]
# ///
"""Record each registry family's digit height, the top of its `0` over the em, as `digit_height`."""

import json
import subprocess
import sys
from pathlib import Path

from fontTools.pens.boundsPen import BoundsPen
from fontTools.ttLib import TTFont

REGISTRY = Path(__file__).resolve().parent.parent / "data" / "font-registry.json"


def installed_face(family):
    """The file and face index fontconfig renders `family` from, or None when it would substitute another family."""
    result = subprocess.run(
        ["fc-match", "--format", "%{family}\n%{file}\n%{index}", f"{family}:style=Regular"],
        capture_output=True,
        text=True,
        check=True,
    )
    names, path, index = result.stdout.split("\n")
    if family.casefold() not in (name.casefold() for name in names.split(",")):
        return None
    return path, int(index)


def digit_height(path, index):
    # Measured from the outline, because the OS/2 table is the author's claim:
    # Serious Shanns declares a 0.576em cap height and draws its H 0.659em tall.
    font = TTFont(path, fontNumber=index)
    glyphs = font.getGlyphSet()
    pen = BoundsPen(glyphs)
    glyphs[font.getBestCmap()[ord("0")]].draw(pen)
    return round(pen.bounds[3] / font["head"].unitsPerEm, 3)


def main():
    registry = json.loads(REGISTRY.read_text(encoding="utf-8"))
    absent = []
    for family, entry in registry.items():
        face = installed_face(family)
        if face is None:
            absent.append(family)
            continue
        entry["digit_height"] = digit_height(*face)
        print(f"{entry['digit_height']:.3f}  {family}")
    REGISTRY.write_text(json.dumps(registry, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    if absent:
        print(f"\nNot installed here, so left as they were: {', '.join(absent)}", file=sys.stderr)


if __name__ == "__main__":
    main()
