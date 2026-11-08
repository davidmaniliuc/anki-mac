"""Run the Swift backend bench (AnkiKit/ankikit-bench) on the bench fixtures.

    python3 -I bench/run_ankikit.py [--runs 5] [fixture ...]

Builds the release binary first. Results go to bench/results/ankikit-backend.json,
with the same warm-up-then-median convention as run_baseline.py.
"""

import argparse
import json
import platform
import statistics
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "AnkiKit/.build/release/ankikit-bench"


def summarize(runs: list[dict]) -> dict:
    summary = {}
    for key, value in runs[0].items():
        if isinstance(value, dict):
            summary[key] = {q: round(statistics.median(r[key][q] for r in runs), 1) for q in value}
        else:
            summary[key] = round(statistics.median(r[key] for r in runs), 1)
    return summary


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--runs", type=int, default=5)
    parser.add_argument("fixtures", nargs="*", default=["user", "large"])
    args = parser.parse_args()

    subprocess.run(["swift", "build", "-c", "release"], cwd=ROOT / "AnkiKit", check=True)
    anki = subprocess.run(
        ["git", "describe", "--tags"], cwd=ROOT / "anki", capture_output=True, text=True
    ).stdout.strip()
    results = {
        "app": f"ankikit-bench (rslib {anki})",
        "machine": platform.machine(),
        "macos": platform.mac_ver()[0],
        "date": time.strftime("%Y-%m-%d %H:%M"),
        "note": "backend only, no UI; first run per fixture is a warm-up and excluded",
        "fixtures": {},
    }
    for name in args.fixtures:
        runs = []
        for _ in range(args.runs + 1):
            out = subprocess.run(
                [str(BINARY), str(ROOT / "bench/fixtures" / name)],
                capture_output=True, text=True, check=True,
            ).stdout
            runs.append(json.loads(out))
        results["fixtures"][name] = {"summary": summarize(runs[1:]), "runs": runs}
        print(name, json.dumps(results["fixtures"][name]["summary"], indent=1))

    out = ROOT / "bench/results/ankikit-backend.json"
    out.write_text(json.dumps(results, indent=1))
    print("wrote", out)


if __name__ == "__main__":
    main()
