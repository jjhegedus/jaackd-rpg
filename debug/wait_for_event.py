#!/usr/bin/env python3
"""Wait for a DebugBridge event and print it.

Usage:
    python debug/wait_for_event.py <event_type> [timeout_sec]
    python debug/wait_for_event.py screen_ready 15
    python debug/wait_for_event.py screen_ready 15 --panel PeoplePanel

Exits 0 if the event was found, 1 on timeout.
Prints the matched event JSON to stdout.
"""

import argparse
import json
import os
import sys
import time


def main():
    parser = argparse.ArgumentParser(description="Wait for a DebugBridge event")
    parser.add_argument("event_type", help="Event type to wait for (e.g. screen_ready)")
    parser.add_argument("timeout_sec", nargs="?", type=float, default=30.0,
                        help="Seconds to wait (default 30)")
    parser.add_argument("--panel", default="", help="Optional panel filter")
    parser.add_argument("--scene", default="", help="Optional scene filter")
    args = parser.parse_args()

    script_dir = os.path.dirname(os.path.abspath(__file__))
    events_path = os.path.join(script_dir, "events.jsonl")

    deadline = time.monotonic() + args.timeout_sec
    seen_count = 0

    while time.monotonic() < deadline:
        if not os.path.exists(events_path):
            time.sleep(0.1)
            continue
        try:
            with open(events_path, "r", encoding="utf-8") as f:
                lines = f.readlines()
        except OSError:
            time.sleep(0.1)
            continue

        for line in lines[seen_count:]:
            stripped = line.strip()
            if not stripped:
                continue
            try:
                event = json.loads(stripped)
            except json.JSONDecodeError:
                continue
            if event.get("type") != args.event_type:
                continue
            if args.panel and event.get("panel") != args.panel:
                continue
            if args.scene and event.get("scene") != args.scene:
                continue
            print(json.dumps(event, indent=2))
            sys.exit(0)

        seen_count = len(lines)
        time.sleep(0.1)

    print(
        f"Timeout: '{args.event_type}' not seen in {args.timeout_sec}s",
        file=sys.stderr,
    )
    sys.exit(1)


if __name__ == "__main__":
    main()
