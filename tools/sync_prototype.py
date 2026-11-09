"""Synchronize the standalone prototype's embedded editable source fragment."""

from __future__ import annotations

import argparse
import html
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "prototype" / "source.html"
STANDALONE = ROOT / "prototype" / "index.html"
START = '<div id="fjob-prototype" class="viz-dotted-background">'
END = '\n<script src="https://unpkg.com/@floating-ui/core@1.7.3/'


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="only verify synchronization")
    args = parser.parse_args()

    page = STANDALONE.read_text(encoding="utf-8")
    match = re.search(r'data-srcdoc="(.*?)"\s*>', page, re.DOTALL)
    if match is None:
        raise SystemExit("Prototype iframe data-srcdoc was not found.")
    inner = html.unescape(match.group(1))
    if inner.count(START) != 1 or inner.count(END) != 1:
        raise SystemExit("Prototype source boundaries are ambiguous.")
    start = inner.index(START)
    end = inner.index(END, start)
    source = SOURCE.read_text(encoding="utf-8")
    if args.check:
        if inner[start:end] != source:
            raise SystemExit("Standalone prototype is out of sync with source.html.")
        print("Standalone prototype matches source.html.")
        return

    updated_inner = inner[:start] + source + inner[end:]
    updated_page = page[: match.start(1)] + html.escape(updated_inner, quote=True) + page[match.end(1) :]
    STANDALONE.write_text(updated_page, encoding="utf-8", newline="\n")
    print("Standalone prototype synchronized from source.html.")


if __name__ == "__main__":
    main()
