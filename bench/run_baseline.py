"""Measure the official Anki desktop app on the bench fixtures.

Run with Anki's bundled Python (it supplies int_version for the prefs file):

    ~/Library/Application\\ Support/AnkiProgramFiles/.venv/bin/python -I bench/run_baseline.py [--runs 5] [fixture ...]

Each run gets a fresh throwaway base folder (sync and update checks off, the
bench add-on installed, the fixture cloned in), so the real profile is never
opened. Results go to bench/results/baseline-<anki version>.json.
"""

import argparse
import json
import pickle
import platform
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import time
from pathlib import Path

from anki.utils import int_version, version_with_build

# -I leaves this folder off the path.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import descendants, footprint, read_events, summarize

BENCH = Path(__file__).resolve().parent
ANKI = "/Applications/Anki.app/Contents/MacOS/Anki"
PROFILE = "User 1"
TIMEOUT_S = 180


def make_base(fixture: Path) -> Path:
    base = Path(tempfile.mkdtemp(prefix="anki-bench-"))
    meta = dict(
        ver=0,
        updates=False,
        created=int(time.time()),
        id=1,
        lastMsg=0,
        suppressUpdate=True,
        firstRun=False,
        defaultLang="en_US",
        last_run_version=int_version(),
        last_loaded_profile_name=PROFILE,
    )
    profile = dict(
        mainWindowGeom=None,
        mainWindowState=None,
        numBackups=50,
        lastOptimize=int(time.time()),
        searchHistory=[],
        syncKey=None,
        syncMedia=False,
        autoSync=False,
        allowHTML=False,
        importMode=1,
        lastColour="#00f",
        stripHTML=True,
        deleteMedia=False,
    )
    with sqlite3.connect(base / "prefs21.db") as db:
        db.execute(
            "create table profiles (name text primary key collate nocase, data blob not null)"
        )
        db.execute("insert into profiles values ('_global', ?)", (pickle.dumps(meta, protocol=4),))
        db.execute("insert into profiles values (?, ?)", (PROFILE, pickle.dumps(profile, protocol=4)))
    (base / PROFILE).mkdir()
    for item in fixture.iterdir():
        subprocess.run(["/bin/cp", "-cR", str(item), str(base / PROFILE)], check=True)
    shutil.copytree(BENCH / "anki_bench_addon", base / "addons21" / "anki_bench")
    return base








def run_once(fixture: Path) -> dict:
    base = make_base(fixture)
    try:
        t0 = time.time()
        proc = subprocess.Popen(
            [ANKI, "-b", str(base)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        memory = None
        while proc.poll() is None:
            if time.time() - t0 > TIMEOUT_S:
                proc.kill()
                raise TimeoutError(f"no exit after {TIMEOUT_S}s, last events: {read_events(base)}")
            state = read_events(base)
            if memory is None and state and state["phase"] == "idle":
                memory = footprint(descendants(proc.pid))
            time.sleep(0.05)
        t_exit = time.time()
        state = read_events(base) or {}
        ev = state.get("events", {})
        rel = lambda name: (ev[name] - t0) * 1000 if name in ev else None
        return {
            "launch_to_addons_ms": rel("addon_import"),
            "launch_to_main_window_ms": rel("main_window_init"),
            "launch_to_profile_open_ms": rel("profile_open"),
            "launch_to_deck_list_ms": rel("deck_browser_painted"),
            "idle_memory_mb": memory and memory["total_mb"],
            "idle_memory_processes": memory and memory["processes"],
            "study_open_ms": (ev["study_first_question"] - ev["study_start"]) * 1000
            if "study_first_question" in ev
            else None,
            "study_end": state.get("study_end") or state.get("study_skipped"),
            "answer_ms": state.get("answer_ms", []),
            "browser_open_ms": (ev["browser_shown"] - ev["browser_open_start"]) * 1000
            if "browser_shown" in ev
            else None,
            "browser_rows": state.get("browser_rows"),
            "search_ms": state.get("search_ms", {}),
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

    results = {
        "app": f"Anki {version_with_build()}",
        "machine": f"{platform.machine()} {subprocess.run(['sysctl', '-n', 'machdep.cpu.brand_string'], capture_output=True, text=True).stdout.strip()}",
        "macos": platform.mac_ver()[0],
        "date": time.strftime("%Y-%m-%d %H:%M"),
        "note": "first run per fixture is a warm-up and excluded from the summary",
        "fixtures": {},
    }
    for name in args.fixtures:
        fixture = BENCH / "fixtures" / name
        runs = []
        for i in range(args.runs + 1):
            run = run_once(fixture)
            print(name, i, json.dumps({k: v for k, v in run.items() if k != "idle_memory_processes"}))
            runs.append(run)
        results["fixtures"][name] = {"summary": summarize(runs[1:]), "runs": runs}
        print(name, "summary", json.dumps(results["fixtures"][name]["summary"], indent=1))

    out = BENCH / "results" / f"baseline-anki-{version_with_build().split()[0]}.json"
    out.parent.mkdir(exist_ok=True)
    out.write_text(json.dumps(results, indent=1))
    print("wrote", out)


if __name__ == "__main__":
    main()
