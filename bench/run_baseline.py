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
import re
import shutil
import sqlite3
import statistics
import subprocess
import tempfile
import time
from pathlib import Path

from anki.utils import int_version, version_with_build

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


def descendants(pid: int) -> list[int]:
    out = subprocess.run(["ps", "-A", "-o", "pid=,ppid="], capture_output=True, text=True).stdout
    children: dict[int, list[int]] = {}
    for line in out.splitlines():
        p, pp = map(int, line.split())
        children.setdefault(pp, []).append(p)
    tree, todo = [], [pid]
    while todo:
        p = todo.pop()
        tree.append(p)
        todo.extend(children.get(p, []))
    return tree


def footprint(pids: list[int]) -> dict:
    args = ["footprint", "-f", "bytes", "--noCategories"]
    for p in pids:
        args += ["-p", str(p)]
    out = subprocess.run(args, capture_output=True, text=True).stdout
    procs = re.findall(r"^(.+?) \[(\d+)\]: 64-bit\s+Footprint: (\d+) B", out, re.M)
    return {
        "total_mb": sum(int(b) for *_, b in procs) / 2**20,
        "processes": {f"{name} [{pid}]": int(b) / 2**20 for name, pid, b in procs},
    }


def read_events(base: Path) -> dict | None:
    try:
        return json.loads((base / "bench_events.json").read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return None


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


def summarize(runs: list[dict]) -> dict:
    def med(values):
        values = [v for v in values if v is not None]
        return round(statistics.median(values), 1) if values else None

    summary = {
        key: med(r[key] for r in runs)
        for key in runs[0]
        if isinstance(runs[0][key], (int, float)) and key != "exit_code"
    }
    summary["answer_ms"] = med(ms for r in runs for ms in r["answer_ms"])
    summary["search_ms"] = {
        q: med(r["search_ms"].get(q) for r in runs) for q in runs[0]["search_ms"]
    }
    return summary


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
