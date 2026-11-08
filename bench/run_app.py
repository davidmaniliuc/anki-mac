"""Measure the AnkiMac app end to end on the bench fixtures.

    python3 -I bench/run_app.py [--runs 5] [fixture ...]

Build it first with scripts/build-app.sh (Release). Each run clones the
fixture into a throwaway folder and launches the app with -BenchEventsPath,
which makes BenchDriver.swift play the same scenario as the desktop add-on and
write the same event file. Results go to bench/results/ankimac-app.json.

Memory counts the app plus the WebKit helper processes (web content, GPU,
networking) that appeared after launch. They are XPC services, not children of
the app, so they are found by diffing the process list: don't open Safari or
other WebKit apps during a run.
"""

import argparse
import json
import platform
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

# -I leaves this folder off the path.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import footprint, read_events, summarize

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "out/app/AnkiMac.app/Contents/MacOS/AnkiMac"
TIMEOUT_S = 120


def webkit_pids() -> set[int]:
    out = subprocess.run(["ps", "-A", "-o", "pid=,comm="], capture_output=True, text=True).stdout
    pids = set()
    for line in out.splitlines():
        pid, comm = line.strip().split(maxsplit=1)
        if "com.apple.WebKit." in comm:
            pids.add(int(pid))
    return pids


def run_once(fixture: Path) -> dict:
    base = Path(tempfile.mkdtemp(prefix="ankimac-bench-"))
    try:
        for item in fixture.iterdir():
            subprocess.run(["/bin/cp", "-cR", str(item), str(base)], check=True)
        before = webkit_pids()
        t0 = time.time()
        proc = subprocess.Popen(
            [
                str(APP),
                "-CollectionPath", str(base / "collection.anki2"),
                "-BenchEventsPath", str(base / "bench_events.json"),
                # Don't restore a window size from earlier runs.
                "-NSQuitAlwaysKeepsWindows", "NO",
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        memory = None
        while proc.poll() is None:
            if time.time() - t0 > TIMEOUT_S:
                proc.kill()
                raise TimeoutError(f"no exit after {TIMEOUT_S}s, last events: {read_events(base)}")
            state = read_events(base)
            if memory is None and state and state["phase"] == "idle":
                memory = footprint([proc.pid, *sorted(webkit_pids() - before)])
            time.sleep(0.05)
        t_exit = time.time()
        state = read_events(base) or {}
        ev = state.get("events", {})
        rel = lambda name: (ev[name] - t0) * 1000 if name in ev else None
        return {
            "launch_to_deck_list_ms": rel("deck_browser_painted"),
            "idle_memory_mb": memory and memory["total_mb"],
            "idle_memory_processes": memory and memory["processes"],
            "study_open_ms": (ev["study_first_question"] - ev["study_start"]) * 1000
            if "study_first_question" in ev
            else None,
            "study_end": state.get("study_end"),
            "answer_ms": state.get("answer_ms", []),
            "search_ms": {},
            "quit_ms": (t_exit - ev["quit_requested"]) * 1000 if "quit_requested" in ev else None,
            "exit_code": proc.returncode,
        }
    finally:
        shutil.rmtree(base, ignore_errors=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--runs", type=int, default=5)
    parser.add_argument("fixtures", nargs="*", default=["user", "large"])
    args = parser.parse_args()

    anki = subprocess.run(
        ["git", "describe", "--tags"], cwd=ROOT / "anki", capture_output=True, text=True
    ).stdout.strip()
    commit = subprocess.run(
        ["git", "rev-parse", "--short", "HEAD"], cwd=ROOT, capture_output=True, text=True
    ).stdout.strip()
    results = {
        "app": f"AnkiMac {commit} (rslib {anki})",
        "machine": f"{platform.machine()} {subprocess.run(['sysctl', '-n', 'machdep.cpu.brand_string'], capture_output=True, text=True).stdout.strip()}",
        "macos": platform.mac_ver()[0],
        "date": time.strftime("%Y-%m-%d %H:%M"),
        "note": "first run per fixture is a warm-up and excluded from the summary",
        "fixtures": {},
    }
    for name in args.fixtures:
        fixture = ROOT / "bench/fixtures" / name
        runs = []
        for i in range(args.runs + 1):
            run = run_once(fixture)
            print(name, i, json.dumps({k: v for k, v in run.items() if k not in ("idle_memory_processes", "answer_ms")}))
            runs.append(run)
        results["fixtures"][name] = {"summary": summarize(runs[1:]), "runs": runs}
        print(name, "summary", json.dumps(results["fixtures"][name]["summary"], indent=1))

    out = ROOT / "bench/results/ankimac-app.json"
    out.write_text(json.dumps(results, indent=1))
    print("wrote", out)


if __name__ == "__main__":
    main()
