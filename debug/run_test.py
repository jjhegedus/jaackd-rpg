#!/usr/bin/env python3
"""DebugBridge test runner.

Usage:
    python debug/run_test.py <test_file.json> [--godot /path/to/godot] [--headless]

The Godot project must be built in debug mode. The runner sets the
GODOT_DEBUG_BRIDGE=1 environment variable so the in-game bridge activates.

Test file format (JSON):
{
  "name": "Human-readable test name",
  "default_timeout_sec": 30,
  "steps": [
    {"type": "wait_for", "event": "bridge_ready", "desc": "..."},
    {"type": "wait_for", "event": "screen_ready", "scene": "MainMenu", "desc": "..."},
    {"type": "cmd", "desc": "...", "payload": {"cmd": "click", "target": "ForgeBtn"}},
    {"type": "assert", "event": "screen_ready", "panel": "SetupPanel", "desc": "..."}
  ]
}

Step types:
  wait_for  — block until an event of the given type (and optional scene/panel) arrives
  cmd       — send a command and wait for its ack
  assert    — alias for wait_for; semantically means "this must have happened"

Command payloads (cmd field values):
  click        target: <node_id>
  set_text     target: <node_id>, value: <string>
  set_value    target: <node_id>, value: <number>
  select_item  target: <node_id>, index: <int>
  teleport     x, y, z: <float>
  quit
"""

import argparse
import json
import os
import subprocess
import sys
import time


def wait_for_event(events_path, event_type, timeout_sec, extra_filter=None):
    """Read events.jsonl until an event matching event_type (and extra_filter) appears.

    Returns the matched event dict, or None on timeout.
    """
    deadline = time.monotonic() + timeout_sec
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
            if event.get("type") == event_type:
                if extra_filter is None or extra_filter(event):
                    return event

        seen_count = len(lines)
        time.sleep(0.1)

    return None


def send_command(commands_path, cmd):
    with open(commands_path, "w", encoding="utf-8") as f:
        json.dump(cmd, f)


def _make_filter(panel, scene):
    def f(e):
        if panel and e.get("panel") != panel:
            return False
        if scene and e.get("scene") != scene:
            return False
        return True
    return f


def run_test(test_path, godot_exe, headless):
    with open(test_path, encoding="utf-8") as f:
        test = json.load(f)

    test_name = test.get("name", os.path.basename(test_path))
    default_timeout = test.get("default_timeout_sec", 30)
    steps = test.get("steps", [])

    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.dirname(script_dir)
    debug_dir = script_dir
    events_path = os.path.join(debug_dir, "events.jsonl")
    commands_path = os.path.join(debug_dir, "commands.json")

    # Remove stale files from previous runs.
    for path in (events_path, commands_path):
        if os.path.exists(path):
            os.remove(path)

    godot_args = [godot_exe, "--path", project_root]
    if headless:
        godot_args += ["--headless"]

    env = os.environ.copy()
    env["GODOT_DEBUG_BRIDGE"] = "1"

    print(f"[runner] {test_name}")
    print(f"[runner] Launch: {' '.join(godot_args)}")

    log_path = os.path.join(debug_dir, "godot_output.log")
    with open(log_path, "w", encoding="utf-8") as log_file:
        proc = subprocess.Popen(
            godot_args,
            stdout=log_file,
            stderr=log_file,
            env=env,
        )

    cmd_seq = 1
    passed = 0
    failed = 0

    try:
        for i, step in enumerate(steps):
            step_type = step.get("type")
            timeout = step.get("timeout_sec", default_timeout)
            desc = step.get("desc", f"step {i + 1}")

            print(f"  [{i + 1}/{len(steps)}] {step_type}: {desc}")

            if step_type in ("wait_for", "assert"):
                event_type = step["event"]
                filt = _make_filter(step.get("panel"), step.get("scene"))
                ev = wait_for_event(events_path, event_type, timeout, filt)
                if ev is None:
                    print(f"    TIMEOUT waiting for '{event_type}' after {timeout}s")
                    failed += 1
                    break
                print(f"    OK  seq={ev.get('seq')} t={ev.get('t'):.1f}")
                passed += 1

            elif step_type == "cmd":
                payload = dict(step.get("payload", {}))
                payload["id"] = cmd_seq
                cmd_seq += 1
                send_command(commands_path, payload)

                ack = wait_for_event(
                    events_path,
                    "cmd_ack",
                    timeout,
                    lambda e, cid=payload["id"]: e.get("id") == cid,
                )
                if ack is None:
                    print(f"    TIMEOUT waiting for ack of cmd {payload['id']}")
                    failed += 1
                    break
                if not ack.get("ok"):
                    print(f"    FAIL  {ack.get('error', 'unknown error')}")
                    failed += 1
                    break
                print(f"    OK  ack id={ack.get('id')}")
                passed += 1

            else:
                print(f"    SKIP  unknown step type: {step_type}")

    finally:
        if proc.poll() is None:
            try:
                send_command(commands_path, {"id": cmd_seq, "cmd": "quit"})
                try:
                    proc.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    proc.kill()
            except Exception:
                proc.kill()

    total = passed + failed
    status = "PASSED" if failed == 0 else "FAILED"
    print(f"\n[runner] {status} — {passed}/{total} steps passed  ({test_name})")
    return failed == 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="DebugBridge test runner")
    parser.add_argument("test", help="Path to test JSON file")
    parser.add_argument(
        "--godot",
        default="godot",
        help="Path to Godot 4 executable (default: 'godot' on PATH)",
    )
    parser.add_argument(
        "--headless",
        action="store_true",
        help="Run Godot headless (no window)",
    )
    args = parser.parse_args()

    ok = run_test(args.test, args.godot, args.headless)
    sys.exit(0 if ok else 1)
