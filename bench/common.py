"""Helpers shared by the bench harnesses. Plain Python: no anki imports."""

import json
import re
import statistics
import subprocess
from pathlib import Path


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
