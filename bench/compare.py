#!/usr/bin/env python3
"""Print a Markdown comparison of the latest bench results.

    python3 -I bench/compare.py [--out FILE]

Reads the newest `results/baseline-anki-*.json`, plus `ankimac-app.json` and
`ankikit-backend.json`, and prints one table per fixture. Every row is a time
in milliseconds unless it says otherwise, so lower is better. Ratios compare
the desktop app with AnkiMac.

Pooled answer time: the harness stores every answer→next-card sample from every
run, and both apps' samples quantize to the display refresh (about 15 ms or
33 ms at 60 Hz), so the median over all samples is reported, as in the runs.
"""

import argparse
import json
import statistics
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
RESULTS = ROOT / "results"


def load(path: Path) -> dict:
    return json.loads(path.read_text())


def latest_baseline() -> Path:
    files = sorted(RESULTS.glob("baseline-anki-*.json"), key=lambda p: p.stat().st_mtime)
    if not files:
        sys.exit("no baseline results; run bench/run_baseline.py first")
    return files[-1]


def pooled_answer_ms(fixture: dict) -> float | None:
    samples = [ms for run in fixture.get("runs", []) for ms in run.get("answer_ms", [])]
    return round(statistics.median(samples), 1) if samples else None


def value(fixture: dict, key: str):
    return fixture.get("summary", {}).get(key)


def search(fixture: dict, query: str):
    return fixture.get("summary", {}).get("search_ms", {}).get(query)


def num(v, decimals: int = 0) -> str:
    if v is None:
        return "—"
    if isinstance(v, str):
        return v
    return f"{v:,.{decimals}f}"


def ratio(desktop, app, memory: bool = False) -> str:
    if not desktop or not app:
        return "—"
    better, worse = ("less memory", "more memory") if memory else ("faster", "slower")
    if app < desktop:
        return f"**{desktop / app:.1f}× {better}**"
    return f"{app / desktop:.1f}× {worse}"


def table(name: str, desktop: dict, app: dict) -> str:
    rows = [
        ("Launch → deck list", value(desktop, "launch_to_deck_list_ms"),
         value(app, "launch_to_deck_list_ms")),
        ("Idle memory (MB)", value(desktop, "idle_memory_mb"),
         value(app, "idle_memory_mb")),
        ("Open study screen", value(desktop, "study_open_ms"),
         value(app, "study_open_ms")),
        ("Answer → next card", pooled_answer_ms(desktop), pooled_answer_ms(app)),
        ("Open browser", value(desktop, "browser_open_ms"),
         value(app, "browser_open_ms")),
        ("Search `deck:*`", search(desktop, "deck:*"), search(app, "deck:*")),
        ("Search `is:due`", search(desktop, "is:due"), search(app, "is:due")),
        ("Search `front:*a*`", search(desktop, "front:*a*"), search(app, "front:*a*")),
        ("Quit", value(desktop, "quit_ms"), value(app, "quit_ms")),
    ]
    lines = [
        f"### {name}",
        "",
        "| | Anki desktop | AnkiMac | AnkiMac vs desktop |",
        "|---|---:|---:|---:|",
    ]
    for label, d, a in rows:
        memory = label.startswith("Idle memory")
        # One decimal where the difference matters (answers, searches) or the
        # value is in MB; whole milliseconds otherwise.
        decimals = 1 if memory or label.startswith(("Answer", "Search")) else 0
        unit = " MB" if memory else ""
        lines.append(
            f"| {label} | {num(d, decimals)}{unit if d is not None else ''} "
            f"| {num(a, decimals)}{unit if a is not None else ''} | {ratio(d, a, memory)} |"
        )
    rows_desktop = value(desktop, "browser_rows")
    rows_app = value(app, "browser_rows")
    if rows_desktop or rows_app:
        lines.append(f"| Browser rows (`front:*a*`) | {num(rows_desktop)} | {num(rows_app)} | — |")
    return "\n".join(lines)


def backend_table(name: str, backend: dict) -> str:
    """The no-UI floor: the same backend calls with no window or web view."""
    rows = [
        ("Process start → deck tree", value(backend, "process_start_to_deck_tree_ms"), 0),
        ("Open collection", value(backend, "open_collection_ms"), 1),
        ("Build deck tree", value(backend, "deck_tree_ms"), 0),
        ("First card (queue + render)", value(backend, "study_first_card_ms"), 0),
        ("Answer → next card", value(backend, "answer_to_next_card_ms"), 1),
        ("Search `deck:*`", search(backend, "deck:*"), 1),
        ("Search `is:due`", search(backend, "is:due"), 1),
        ("Search `front:*a*`", search(backend, "front:*a*"), 1),
        ("Statistics (365 days)", value(backend, "graphs_ms"), 0),
        ("Close collection", value(backend, "close_collection_ms"), 1),
    ]
    lines = [
        f"**Backend only, no UI — `{name}`**",
        "",
        "| | ms |",
        "|---|---:|",
    ]
    for label, v, decimals in rows:
        lines.append(f"| {label} | {num(v, decimals)} |")
    lines.append(f"| Idle footprint | {num(value(backend, 'footprint_mb'), 1)} MB |")
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()

    baseline = load(latest_baseline())
    app = load(RESULTS / "ankimac-app.json")
    backend_path = RESULTS / "ankikit-backend.json"
    backend = load(backend_path) if backend_path.exists() else None

    lines = [
        "## Measurements",
        "",
        f"- Anki desktop: `{baseline['app']}`",
        f"- AnkiMac: `{app['app']}`",
    ]
    if backend:
        lines.append(f"- Backend only: `{backend['app']}`")
    lines += [
        f"- Machine: {baseline.get('machine', '—')}, macOS {baseline.get('macos', '—')}",
        f"- Desktop runs: {len(baseline['fixtures'].get('user', {}).get('runs', []))} per fixture "
        "(first is a warm-up and excluded)",
        f"- AnkiMac runs: {len(app['fixtures'].get('user', {}).get('runs', []))} per fixture "
        "(first is a warm-up and excluded)",
    ]
    for name in baseline["fixtures"]:
        if name in app["fixtures"]:
            lines += ["", table(name, baseline["fixtures"][name], app["fixtures"][name])]
    if backend:
        lines += ["", "### Backend floor", "",
                  "Same backend calls through the Swift bridge, no window or web view. "
                  "Separate from the app numbers above: these time the calls themselves."]
        for name in backend["fixtures"]:
            lines += ["", backend_table(name, backend["fixtures"][name])]

    text = "\n".join(lines) + "\n"
    if args.out:
        args.out.write_text(text)
        print(f"wrote {args.out}")
    else:
        print(text)


if __name__ == "__main__":
    main()
