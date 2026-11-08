"""Build benchmark collections in bench/fixtures/.

Run with the Python that ships with Anki, so the collection is written by the
same anki library version as the app under test:

    ~/Library/Application\\ Support/AnkiProgramFiles/.venv/bin/python -I bench/make_fixtures.py

Fixtures:
  user/   a copy of the real profile's collection and media (never modified in place)
  large/  a synthetic 50k-note collection with review history
"""

import random
import shutil
import sqlite3
import subprocess
import sys
import time
from pathlib import Path
from urllib.parse import quote

from anki.collection import Collection

ROOT = Path(__file__).resolve().parent / "fixtures"
USER_PROFILE = Path.home() / "Library/Application Support/Anki2/User 1"

NOTES = 50_000
DECKS = 40
REVIEWED_FRACTION = 0.6
REVLOG_PER_CARD = 6
WORDS = (
    "alpha beta gamma delta epsilon zeta theta kappa lambda sigma omega "
    "maison chat chien arbre soleil lune mer montagne riviere ville livre"
).split()


def copy_user() -> None:
    dest = ROOT / "user"
    if dest.exists():
        shutil.rmtree(dest)
    dest.mkdir(parents=True)
    # The collection is copied through SQLite's backup so a running Anki or a
    # pending WAL cannot leave a torn copy.
    src = USER_PROFILE / "collection.anki2"
    with sqlite3.connect(f"file:{quote(str(src))}?mode=ro", uri=True) as source:
        with sqlite3.connect(dest / "collection.anki2") as target:
            source.backup(target)
    # APFS clone: instant and takes no extra space.
    subprocess.run(
        ["/bin/cp", "-cR", str(USER_PROFILE / "collection.media"), str(dest)], check=True
    )
    print("user fixture copied")


def sentence(rng: random.Random, n: int) -> str:
    return " ".join(rng.choice(WORDS) for _ in range(n))


def make_large() -> None:
    dest = ROOT / "large"
    if dest.exists():
        shutil.rmtree(dest)
    dest.mkdir(parents=True)
    rng = random.Random(42)
    col = Collection(str(dest / "collection.anki2"))

    deck_ids = []
    for i in range(DECKS):
        parent = f"Subject {i // 8}"
        deck_ids.append(col.decks.id(f"{parent}::Topic {i}"))

    basic = col.models.by_name("Basic")
    start = time.time()
    for i in range(NOTES):
        note = col.new_note(basic)
        note["Front"] = f"<b>{sentence(rng, 3)}</b> #{i}"
        note["Back"] = f"{sentence(rng, 12)}<br><i>{sentence(rng, 6)}</i>"
        note.tags = [f"tag{rng.randrange(30)}"]
        col.add_note(note, rng.choice(deck_ids))
    print(f"added {NOTES} notes in {time.time() - start:.1f}s")

    # Turn most cards into reviews with a spread of due dates, then fake a
    # revlog so stats and FSRS have history to chew on.
    today = col.sched.today
    card_ids = col.db.list("select id from cards")
    reviewed = rng.sample(card_ids, int(len(card_ids) * REVIEWED_FRACTION))
    now_ms = int(time.time() * 1000)
    rows, revlog = [], []
    for cid in reviewed:
        ivl = rng.choice([1, 3, 7, 15, 30, 60, 120, 240])
        due = today + rng.randint(-3, ivl)
        rows.append((ivl, due, rng.randint(1300, 2800), rng.randint(1, 20), cid))
        for k in range(REVLOG_PER_CARD):
            rid = now_ms - rng.randint(1, 365 * 86_400_000) + k
            revlog.append(
                (rid, cid, rng.choice([1, 3, 3, 3, 4]), ivl, ivl // 2, 2500, rng.randint(2000, 15000), 1)
            )
    col.db.executemany(
        "update cards set type=2, queue=2, ivl=?, due=?, factor=?, reps=? where id=?",
        rows,
    )
    col.db.executemany(
        "insert or ignore into revlog (id, cid, usn, ease, ivl, lastIvl, factor, time, type)"
        " values (?, ?, -1, ?, ?, ?, ?, ?, ?)",
        revlog,
    )
    col.close()
    print(f"large fixture: {NOTES} notes, {len(reviewed)} reviewed, {len(revlog)} revlog rows")


if __name__ == "__main__":
    which = sys.argv[1:] or ["user", "large"]
    if "user" in which:
        copy_user()
    if "large" in which:
        make_large()
