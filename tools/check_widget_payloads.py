"""Validate widget payloads produced by the Dart engine against the schema.

Usage:
    flutter test tool/dump_widget_timeline_test.dart   (in apps/mobile)
    python tools/check_widget_payloads.py

Requires jsonschema (see docs/06-acceptance.md).
"""

import json
from pathlib import Path

from jsonschema import Draft202012Validator, FormatChecker

ROOT = Path(__file__).resolve().parents[1]
SCHEMA_PATH = ROOT / "contracts" / "widget-snapshot.schema.json"
PAYLOAD_DIR = ROOT / "apps" / "mobile" / "build" / "contracts"
PAYLOADS = [
    "widget-timeline.json",
    "widget-timeline-private.json",
    "widget-tombstone.json",
]


def main() -> None:
    schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
    validator = Draft202012Validator(schema, format_checker=FormatChecker())
    total = 0
    for name in PAYLOADS:
        path = PAYLOAD_DIR / name
        if not path.exists():
            raise SystemExit(
                f"missing {path}; run flutter test tool/dump_widget_timeline_test.dart first"
            )
        payload = json.loads(path.read_text(encoding="utf-8"))
        entries = payload["entries"]
        assert payload["timelineVersion"] == 1
        assert len(entries) <= 289
        for entry in entries:
            validator.validate(entry)
        total += len(entries)
        print(f"PASS {name}: {len(entries)} entries")
    print(f"PASS widget snapshot schema over {total} entries")


if __name__ == "__main__":
    main()
