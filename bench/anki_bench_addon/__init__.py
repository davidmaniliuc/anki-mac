# Benchmark add-on, loaded only into the throwaway base folder that
# bench/run_baseline.py creates. It drives the stock Anki desktop app through a
# fixed scenario and records wall-clock timestamps to <base>/bench_events.json.
# The harness reads that file; it also samples memory when phase == "idle".

import json
import os
import time

from aqt import dialogs, gui_hooks, mw
from aqt.qt import QTimer

ANSWERS = 30
IDLE_SETTLE_MS = 4000
IDLE_SAMPLE_MS = 3000

state: dict = {"events": {}, "answer_ms": [], "phase": "starting"}


def mark(name: str) -> None:
    state["events"].setdefault(name, time.time())
    flush()


def flush() -> None:
    if not mw or not mw.pm or not mw.pm.base:
        return
    path = os.path.join(mw.pm.base, "bench_events.json")
    with open(path + ".tmp", "w") as f:
        json.dump(state, f)
    os.replace(path + ".tmp", path)


def later(ms: int, fn) -> None:
    QTimer.singleShot(ms, fn)


def after_paint(web, fn) -> None:
    # JS queued after the page's own eval calls runs once they have executed.
    web.evalWithCallback("1", lambda _: fn())


state["events"]["addon_import"] = time.time()

gui_hooks.main_window_did_init.append(lambda: mark("main_window_init"))
gui_hooks.profile_did_open.append(lambda: mark("profile_open"))


def on_deck_browser(_db) -> None:
    if "deck_browser_render" in state["events"]:
        return
    mark("deck_browser_render")
    after_paint(mw.deckBrowser.web, on_deck_browser_painted)


def on_deck_browser_painted() -> None:
    mark("deck_browser_painted")
    later(IDLE_SETTLE_MS, start_idle)


gui_hooks.deck_browser_did_render.append(on_deck_browser)


def start_idle() -> None:
    state["phase"] = "idle"
    flush()
    later(IDLE_SAMPLE_MS, start_study)


# Study: open the deck with the most due cards and answer Good repeatedly.

review = {"pending": None, "count": 0}


def start_study() -> None:
    state["phase"] = "study"
    best, best_due = None, 0
    for node in mw.col.sched.deck_due_tree().children:
        due = node.review_count + node.learn_count + node.new_count
        if due > best_due:
            best, best_due = node.deck_id, due
    if best is None:
        state["study_skipped"] = "no due cards"
        flush()
        later(0, start_browser)
        return
    mw.col.decks.select(best)
    gui_hooks.reviewer_did_show_question.append(on_question)
    gui_hooks.reviewer_did_show_answer.append(on_answer)
    review["pending"] = "first"
    mark("study_start")
    mw.moveToState("review")
    # The reviewer shows the congrats page instead if nothing is queued.
    later(5000, lambda: review["pending"] == "first" and finish_study("timeout"))


def on_question(_card) -> None:
    after_paint(mw.reviewer.web, question_painted)


def question_painted() -> None:
    now = time.time()
    if review["pending"] == "first":
        mark("study_first_question")
    elif isinstance(review["pending"], float):
        state["answer_ms"].append((now - review["pending"]) * 1000)
    review["pending"] = None
    if review["count"] >= ANSWERS:
        finish_study("done")
        return
    later(0, mw.reviewer._showAnswer)


def on_answer(_card) -> None:
    after_paint(mw.reviewer.web, answer_painted)


def answer_painted() -> None:
    review["count"] += 1
    review["pending"] = time.time()
    mw.reviewer._answerCard(3)
    # The last due card leads to the overview, not another question.
    later(3000, lambda: review["pending"] and finish_study("ran out of cards"))


def finish_study(reason: str) -> None:
    if state.get("study_end"):
        return
    state["study_end"] = reason
    gui_hooks.reviewer_did_show_question.remove(on_question)
    gui_hooks.reviewer_did_show_answer.remove(on_answer)
    mw.moveToState("deckBrowser")
    later(500, start_browser)


# Browser: open it, then time a whole-collection search.


def start_browser() -> None:
    state["phase"] = "browser"
    mark("browser_open_start")
    gui_hooks.browser_did_search.append(on_first_search)
    dialogs.open("Browser", mw)


def on_first_search(_ctx) -> None:
    gui_hooks.browser_did_search.remove(on_first_search)
    later(0, browser_shown)


def browser_shown() -> None:
    mark("browser_shown")
    browser = dialogs._dialogs["Browser"][1]
    for query in ("deck:*", "is:due", "front:*a*"):
        start = time.time()
        browser.search_for(query)
        mw.app.processEvents()
        state.setdefault("search_ms", {})[query] = (time.time() - start) * 1000
    state["browser_rows"] = browser.table.len()
    browser.close()
    later(500, quit_app)


def quit_app() -> None:
    state["phase"] = "quitting"
    mark("quit_requested")
    mw.close()
