# AnkiMac vs Anki desktop: measured comparison

**14 November 2026** · Apple M1 (8 GB), macOS 27.2

- AnkiMac `df95179` (rslib `26.09.4`)
- Anki desktop `26.09.4 (c06370ff)`

AnkiMac replaces Anki's Qt interface but runs the same Rust core, so scheduling, the collection
format, card rendering and AnkiWeb sync are identical by construction. This document compares what
changes for the person using it: launch, memory, opening a session, answering, browsing/searching,
and quitting. Both apps were driven through the same scripted scenario, on the same two fixture
collections, five measured runs each after one warm-up. Numbers are medians; raw runs are in the
JSON files under `bench/results/`.

## Headline

| | `user` | `large` |
|---|---|---|
| Launch → deck list | 1,645 → **363 ms** (4.5× faster) | 1,595 → **483 ms** (3.3× faster) |
| Idle memory | 331 → **95 MB** (3.5× less) | 340 → **107 MB** (3.2× less) |
| Open study screen | 110 → **95 ms** (1.2× faster) | 134 → **94 ms** (1.4× faster) |
| Answer → next card | 15.2 → **8.6 ms** (1.8× faster) | 32.8 → **16.5 ms** (2.0× faster) |
| Open browser | 120 → **217 ms** (1.8× slower) | 195 → **253 ms** (1.3× slower) |
| Search `deck:*` | 81 → **33 ms** (2.5× faster) | 112 → **48 ms** (2.4× faster) |
| Quit | 274 → **80 ms** (3.4× faster) | 460 → **140 ms** (3.3× faster) |

Each cell reads desktop → AnkiMac, in milliseconds unless marked. The only user-visible path where
desktop is clearly faster is **opening the Browser**; searching itself is at parity or faster in
AnkiMac.

## Method

**Fixtures.** Both apps open throwaway copies of the same collections, never the real profile:

- `user`: 700 cards / 700 notes / 7,713 reviews across 28 decks, with 4,806 media files (143 MB).
- `large`: 50,000 cards / 50,000 notes / 180,000 reviews across 46 decks (33 MB).

**Scenario.** Identical for both apps, scripted from inside the app:

1. Launch and paint the deck list.
2. Settle for 4 s, then sample memory while idle.
3. Study the top-level deck with the most due cards: up to 30 cards, each shown, answered Good, and
   the next question awaited.
4. Open the Browser and run three whole-collection searches: `deck:*`, `is:due`, `front:*a*`.
5. Quit.

AnkiMac is driven by `App/AnkiMac/BenchDriver.swift`; desktop by `bench/anki_bench_addon/`, which
records the same event names into `bench_events.json`. `bench/run_app.py` and
`bench/run_baseline.py` read those files.

**Timing definitions.**

- *Launch → deck list*: process start to the deck list painted after the collection is open.
- *Open study screen*: from starting the session to the first question's HTML being in the page.
- *Answer → next card*: from the answer being committed to the next question being in the page.
- *Open browser*: from asking for the Browser to the first search's rows on screen.
- *Search*: from submitting the query to the rows being on screen.
- *Quit*: from the quit request to process exit.

**Memory.** `footprint` over the desktop process tree (Anki, three QtWebEngine helpers, mpv) and,
for AnkiMac, the app plus the WebKit content, GPU and networking services that appeared after launch.

**Conditions.** One app at a time, no benchmark running concurrently, warm caches. The first run of
each fixture is a warm-up and excluded. The two apps run the same rslib commit, so backend work is
comparable.

## Results

### `user` — 700 cards, 28 decks, 4,806 media files

| | Anki desktop | AnkiMac | AnkiMac vs desktop |
|---|---:|---:|---:|
| Launch → deck list | 1,645 ms | 363 ms | **4.5× faster** |
| Idle memory | 331.0 MB | 94.8 MB | **3.5× less** |
| Open study screen | 110 ms | 95 ms | **1.2× faster** |
| Answer → next card | 15.2 ms | 8.6 ms | **1.8× faster** |
| Open browser | 120 ms | 217 ms | 1.8× slower |
| Search `deck:*` | 81.4 ms | 33.2 ms | **2.5× faster** |
| Search `is:due` | 22.1 ms | 20.1 ms | 1.1× faster |
| Search `front:*a*` | 23.7 ms | 24.0 ms | parity |
| Quit | 274 ms | 80 ms | **3.4× faster** |
| Rows for `front:*a*` | 601 | 601 | — |

### `large` — 50,000 cards, 46 decks, 180,000 reviews

| | Anki desktop | AnkiMac | AnkiMac vs desktop |
|---|---:|---:|---:|
| Launch → deck list | 1,595 ms | 483 ms | **3.3× faster** |
| Idle memory | 339.8 MB | 106.5 MB | **3.2× less** |
| Open study screen | 134 ms | 94 ms | **1.4× faster** |
| Answer → next card | 32.8 ms | 16.5 ms | **2.0× faster** |
| Open browser | 195 ms | 253 ms | 1.3× slower |
| Search `deck:*` | 112.1 ms | 47.5 ms | **2.4× faster** |
| Search `is:due` | 33.3 ms | 37.5 ms | 1.1× slower |
| Search `front:*a*` | 72.6 ms | 69.1 ms | parity |
| Quit | 460 ms | 140 ms | **3.3× faster** |
| Rows for `front:*a*` | 47,592 | 47,592 | — |

Differences under about 10% are within run-to-run noise on this machine; treat `is:due` and
`front:*a*` as parity rather than as wins.

## Reading the results

### Launch: 3.3–4.5× faster, mostly by not being Python

Desktop spends about 1.05 s before any collection work: starting Python, importing Qt and loading
the add-on framework. Its window appears at 1.39 s and the deck list at 1.65 s. AnkiMac starts the
Rust backend on a background thread while SwiftUI builds the window; earlier traces put the window
at roughly 280 ms, and the deck list lands at 363 ms.

On `large`, AnkiMac pays 120 ms more for launch, much of it rslib building a 46-deck tree over
50,000 cards (58 ms of backend work alone). Desktop pays nearly the same interpreter cost either
way, which is why its launch barely changes with collection size.

This is a real user-facing win, but part of it is architectural: desktop is doing more at startup
(Python, Qt, add-on scanning) before it shows anything.

### Memory: 3.2–3.5× less

AnkiMac's 95 MB on `user` is made up of about 52 MB for the app, 27 MB Web Content, 9 MB GPU and
5.6 MB networking. On `large` the app process grows to 65 MB, for 107 MB total.

In a sampled desktop run, about 265 MB sat in the main Python/Qt process, 54 MB across three
QtWebEngine helpers, and 18 MB in mpv; the median total across runs was 331 MB. AnkiMac still keeps
a web engine resident for cards; it is simply a system service shared with the rest of macOS rather
than three bundled helper processes.

### Study: close, and backend-bound on a large collection

On AnkiMac a session opens in about 95 ms on both fixtures; desktop takes 110 ms on `user` and
134 ms on `large`. The backend-only bench puts the first card's queue and HTML at 4 ms on `user` and
47 ms on `large`; on the large collection, both apps are mostly waiting for Anki's scheduler, not
drawing.

AnkiMac avoids two costs desktop pays when the study screen opens: its card web view is created once
at launch and stays mounted, and its toolbar items are fixed rather than appearing on demand.

### Answering: 1.8–2.0× faster, with a measurement caveat

AnkiMac's answer-to-next-question times are tightly clustered: 6.9–11.2 ms (10th–90th percentile)
on `user`, 12.2–17.4 ms on `large`. Desktop's are quantized by the display: on `user`, 67 of 175
samples are 25 ms or more and most of the rest cluster near 15 ms (one run skewed faster); on
`large`, more than half are about 33 ms, which is why its median jumps to 32.8 ms.

The backend accounts for 0.4–0.5 ms, so all of this is web-view plumbing. The two harnesses stamp
the end of the same reviewer update, but AnkiMac takes its stamp inside the reviewer's own update
queue while desktop's callback returns through Qt's UI thread, where samples fall on frame
boundaries. Both are proxies for perceived latency, not identical stopwatches. The 1.8–2.0× should
be treated as indicative, not exact.

### Browser: the one place desktop wins

AnkiMac takes 217 ms to open the Browser on `user` (253 ms on `large`) against desktop's 120 ms
(195 ms). The first open builds the AppKit window and table and runs the initial search; desktop's
browser code is older and cheaper to bring up. This is the clearest optimisation target in the app.

Once open, search is not the problem. `deck:*` is 2.5× faster in AnkiMac on `user` and 2.4× faster
on `large`; the other two queries are at parity. The table keeps its rows virtualised in both apps,
so 47,592 results cost about the same to display.

### Quit: 3.3–3.4× faster

Desktop spends 274 ms (`user`) to 460 ms (`large`) flushing the collection, tearing down Python and
stopping mpv. AnkiMac takes 80–140 ms; the backend-only bench closes the collection in 1–10 ms, so
most of what remains is window teardown and WebKit.

## Backend floor

The same calls through the Swift bridge with no window or web view, at the same rslib commit. This
is context for where the time goes, not a like-for-like column: these time the calls themselves,
while the app numbers above time to something on screen.

| | `user` | `large` |
|---|---:|---:|
| Process start → deck tree | 29 ms | 83 ms |
| Open collection | 4.9 ms | 3.7 ms |
| Build deck tree | 3 ms | 58 ms |
| First card (queue + render) | 4 ms | 47 ms |
| Answer → next card | 0.4 ms | 0.5 ms |
| Search `deck:*` | 1.1 ms | 62.5 ms |
| Search `is:due` | 0.3 ms | 11.6 ms |
| Search `front:*a*` | 2.0 ms | 44.0 ms |
| Statistics (365 days) | 4 ms | 219 ms |
| Close collection | 1.4 ms | 9.9 ms |
| Idle footprint | 9.1 MB | 63.3 MB |

On `large`, the backend costs that matter are the deck tree (58 ms), the first card (47 ms),
`front:*a*` (44 ms), `deck:*` (62.5 ms) and statistics (219 ms). Neither UI is the bottleneck for
those; the native app needs to keep them off the main thread, which it does.

Searches are the one place where the app can appear faster than this "floor": the bench times the
whole result set and sort, while the app timestamps the first rows painted. Don't subtract one from
the other; compare app with desktop, which time the same visible milestone.

## What the numbers do not cover

Both apps share Anki's core, but the interfaces are not at feature parity yet. This comparison
measures only the paths both implement.

| | Anki desktop | AnkiMac |
|---|---|---|
| Platforms | macOS, Windows, Linux | macOS 26+ |
| Interface | Qt / Python | SwiftUI + AppKit |
| Core, collection format, sync | rslib | same rslib, same format, same AnkiWeb sync |
| Card rendering | upstream `reviewer.js` + CSS | same upstream `reviewer.js` + CSS |
| Add-ons | Python add-on ecosystem | not implemented |
| AnkiHub | integrated | not implemented |
| Languages | translated via Fluent | English native strings; upstream English FTL generated into `Tr.swift` |
| Install size (this machine) | 655 MB | 79 MB |
| Keyboard and accessibility | desktop's keys; Qt accessibility | desktop's study keys, VoiceOver labels, system focus and keyboard navigation |
| Feature coverage | complete | broad (study, decks, browser, editor, templates, image occlusion, stats, FSRS, import/export, backups, profiles, sync), not complete |

Not measured: statistics rendering, deck options, import/export, image-occlusion editing, sync
throughput, energy use, cold start (reboot or `sudo purge`), sessions longer than 30 answers, and
multi-window behaviour.

## Threats to validity

- **Warm caches, one machine.** These are warm-start numbers on one M1 with 8 GB, macOS 27.2. They
  are not cold-start numbers and not a claim about other hardware.
- **One desktop outlier.** A single desktop `user` run stalled for 136 s before Python finished
  starting (an I/O hiccup on the machine); the median is unaffected and the run is kept in
  `baseline-anki-26.09.4.json` rather than deleted.
- **Frame quantization on desktop.** Some desktop answer samples land on the next 16.7 ms frame,
  others miss it; one `user` run skewed fast. The pooled median is reported rather than a mean.
- **Different stopping points.** Desktop is doing more at launch and supports features AnkiMac does
  not; the comparison is of the same user path, not of equal work.
- **Answer timing.** See the caveat above: the two harnesses stamp slightly different points in the
  same reviewer update.
- **Memory attribution.** Desktop is sampled as a process tree; AnkiMac's WebKit helpers are XPC
  services found by diffing the process list around launch. Apps opened mid-run can add noise.

## Reproduce

```sh
./scripts/build-app.sh Release

~/Library/Application\ Support/AnkiProgramFiles/.venv/bin/python -I bench/run_baseline.py --runs 5
python3 -I bench/run_app.py --runs 5
python3 -I bench/run_ankikit.py --runs 5
python3 -I bench/compare.py          # prints these tables from the JSON
```

`bench/run_baseline.py` now imports Anki's version from the app bundle rather than the
`AnkiProgramFiles` venv, which can lag behind an app update and mislabel results.

Raw data: `bench/results/baseline-anki-26.09.4.json`, `bench/results/ankimac-app.json`,
`bench/results/ankikit-backend.json`.
