# Benchmarks

Two harnesses run the same scenario on the same fixtures:

| Script | Measures |
|---|---|
| `run_baseline.py` | The official Anki desktop app, end to end, driven by `anki_bench_addon` inside a throwaway base folder (sync and update checks off). |
| `run_ankikit.py` | `ankikit-bench`: the same backend calls through our Swift bridge, with no UI. This is the floor the SwiftUI app builds on. |

Scenario: launch → deck list → idle memory → study the deck with the most due cards (30 answers, Good) → browser searches → stats (Swift only, for now) → quit.

## Fixtures

Built by `make_fixtures.py` (run it with Anki's bundled Python) into `fixtures/`, which is gitignored:

- `user`: a copy of the real profile (601 cards, 4,806 media files). The original is never opened.
- `large`: synthetic, 50,000 notes across 40 decks, 30,000 in review, 180,000 revlog rows.

```sh
~/Library/Application\ Support/AnkiProgramFiles/.venv/bin/python -I bench/make_fixtures.py
~/Library/Application\ Support/AnkiProgramFiles/.venv/bin/python -I bench/run_baseline.py
python3 -I bench/run_ankikit.py
```

## Results, 2026-11-08 (M1, 8 GB, macOS 27)

Medians of 5 runs after one warm-up. Desktop is Anki 25.09.4, the version installed here. AnkiKit uses rslib 26.09.4.

| | Desktop `user` | AnkiKit `user` | Desktop `large` | AnkiKit `large` |
|---|---:|---:|---:|---:|
| Launch → deck list | 1,508 ms | 15 ms | 1,473 ms | 68 ms |
| Idle memory (whole process tree) | 285 MB | 9 MB | 288 MB | 64 MB |
| Open study screen | 101 ms | 2 ms | 125 ms | 48 ms |
| Answer → next card shown | 12.8 ms | 0.2 ms | 15.9 ms | 0.5 ms |
| Search `deck:*` | 72 ms | 0.5 ms | 104 ms | 24 ms |
| Search `front:*a*` | 17 ms | 1.2 ms | 63 ms | 51 ms |
| Stats (365 days) | — | 3 ms | — | 224 ms |
| Quit | 269 ms | 1 ms | 450 ms | 15 ms |

How to read this:

- The AnkiKit column has no UI. A window, a WKWebView and a first paint will add to it. The SwiftUI app is measured end to end once it exists, and that number replaces this column.
- Desktop pays about 1 s before any Anki code runs (the launcher, starting Python, importing Qt). A native app does not have that cost, which is where most of the launch win comes from.
- Desktop memory is about 222 MB for the main process (Python + Qt), 3 × ~17 MB for QtWebEngine helpers, and 16 MB for an idle mpv.
- The rslib time is the same for both apps. On `large`, the deck tree (52 ms), first card (48 ms), `front:*a*` (51 ms) and stats (224 ms) are backend costs. The native app needs to keep these off the main thread rather than try to beat them.
- Desktop's "answer → next card" includes the reviewer web view repainting. It splits into about 8 ms and 17 ms, which suggests frame-aligned painting.
- The first desktop launch after a while took 3.4 s (it's the warm-up run, excluded above). There is no true cold-start number yet; that needs a reboot or `sudo purge` between runs.
