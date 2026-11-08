# Benchmarks

Two harnesses run the same scenario on the same fixtures:

| Script | Measures |
|---|---|
| `run_baseline.py` | The official Anki desktop app, end to end, driven by `anki_bench_addon` inside a throwaway base folder (sync and update checks off). |
| `run_ankikit.py` | `ankikit-bench`: the same backend calls through our Swift bridge, with no UI. This is the floor the SwiftUI app builds on. |
| `run_app.py` | The AnkiMac app, end to end. Launched with `-BenchEventsPath`, `App/AnkiMac/BenchDriver.swift` plays the desktop add-on's scenario and writes the same event file. |

Scenario: launch → deck list → idle memory → study the deck with the most due cards (30 answers, Good) → browser searches → stats (Swift only, for now) → quit.

## Fixtures

Built by `make_fixtures.py` (run it with Anki's bundled Python) into `fixtures/`, which is gitignored:

- `user`: a copy of the real profile (601 cards, 4,806 media files). The original is never opened.
- `large`: synthetic, 50,000 notes across 40 decks, 30,000 in review, 180,000 revlog rows.

```sh
~/Library/Application\ Support/AnkiProgramFiles/.venv/bin/python -I bench/make_fixtures.py
~/Library/Application\ Support/AnkiProgramFiles/.venv/bin/python -I bench/run_baseline.py
python3 -I bench/run_ankikit.py
scripts/build-app.sh && python3 -I bench/run_app.py
```

## AnkiMac app vs desktop, 2026-11-08 (M1, 8 GB, macOS 27)

Medians of 5 runs after one warm-up, both apps end to end with the same scenario and fixtures. Results in `results/ankimac-app.json`.

| | Desktop `user` | AnkiMac `user` | Desktop `large` | AnkiMac `large` |
|---|---:|---:|---:|---:|
| Launch → deck list | 1,508 ms | 367 ms | 1,473 ms | 402 ms |
| Idle memory (app + helper processes) | 285 MB | 85 MB | 288 MB | 87 MB |
| Open study screen | 101 ms | 48 ms | 125 ms | 92 ms |
| Answer → next card shown | 12.8 ms | 7.2 ms | 15.9 ms | 7.1 ms |
| Quit | 269 ms | 60 ms | 450 ms | 85 ms |

How the app's numbers are taken, and where the time goes:

- "Shown" is the same point for both apps: the card's HTML has been put into the page by upstream's `reviewer.js`. AnkiMac reports it from inside the reviewer's update queue, after `_showQuestion` has finished, which is slightly later than the desktop add-on's eval callback.
- Memory: the app is about 43 MB; WebKit's web content (27 MB), GPU (9 MB) and networking (5 MB) processes make up the rest. They are XPC services rather than child processes, so `run_app.py` finds them by diffing the process list around the launch.
- Launch (`user`, warm): the window is up at about 280 ms, the collection opens about 25 ms later, and the deck list paints at about 360 ms. The backend starts on a background thread while SwiftUI builds the window. The card web view is created only after the deck list is painted.
- Answer: rslib takes under 1 ms. The rest is the JS round trip into the web content process and back.
- Opening study used to take about 100 ms. Two things cost the most: NSToolbar re-laying out the window when the study buttons appeared (~45 ms), and attaching the card web view to the window (~30 ms). The toolbar items are now fixed and only enable or disable, and the web view stays mounted (hidden) from launch. Batching the reviewer's script calls into one per run-loop turn made answers slower (10 ms), so each call goes out immediately.
- `large` study open (92 ms) is mostly rslib building the queue (48 ms in `ankikit-bench`).
- Not yet compared: the browser and search (no browser in the app yet), and stats.

## Backend only, 2026-11-08 (M1, 8 GB, macOS 27)

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
