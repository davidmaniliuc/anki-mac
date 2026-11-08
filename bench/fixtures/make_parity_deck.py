"""Build a small collection that exercises every reviewer feature.

Run with the Python that ships with Anki:

    ~/Library/Application\\ Support/AnkiProgramFiles/.venv/bin/python -I \\
        bench/fixtures/make_parity_deck.py OUT_DIR

OUT_DIR gets collection.anki2 and collection.media. The deck "Parity" holds one
note each for: an image, a [sound:] file, a TTS tag, MathJax, type-in-the-answer,
a red flag and a "marked" tag. The mp3 comes from ffmpeg.
"""

import struct
import subprocess
import sys
import zlib
from pathlib import Path

from anki.collection import Collection

FRONT_PREFIX = "Parity"


def write_png(path: Path, size: int = 96) -> None:
    rows = b""
    for y in range(size):
        row = b"".join(
            bytes((255 * x // size, 255 * y // size, 160)) for x in range(size)
        )
        rows += b"\x00" + row

    def chunk(kind: bytes, data: bytes) -> bytes:
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    header = struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0)
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b"")
    )


def write_mp3(path: Path) -> None:
    subprocess.run(
        ["ffmpeg", "-loglevel", "error", "-y", "-f", "lavfi", "-i", "sine=frequency=440:duration=1",
         "-c:a", "libmp3lame", "-b:a", "32k", str(path)],
        check=True,
    )


def main() -> None:
    out = Path(sys.argv[1]).resolve()
    out.mkdir(parents=True, exist_ok=True)
    col = Collection(str(out / "collection.anki2"))
    media = Path(col.media.dir())
    write_png(media / "parity.png")
    write_mp3(media / "x.mp3")

    deck = col.decks.id("Parity")
    basic = col.models.by_name("Basic")
    typing = col.models.by_name("Basic (type in the answer)")

    tts = col.models.copy(basic)
    tts["id"] = 0
    tts["name"] = "Parity TTS"
    tts["tmpls"][0]["qfmt"] = "{{tts en_US:Front}}"
    col.models.add_dict(tts)
    tts = col.models.by_name("Parity TTS")

    def add(model, front, back, tags=()):
        note = col.new_note(model)
        note["Front"], note["Back"] = front, back
        note.tags = list(tags)
        col.add_note(note, deck)
        return note

    add(basic, f"{FRONT_PREFIX} image<br><img src=\"parity.png\">", "Image answer")
    add(basic, f"{FRONT_PREFIX} sound [sound:x.mp3]", "Sound answer")
    add(tts, "Text to speech", "TTS answer")
    add(basic, f"{FRONT_PREFIX} math \\(x^2\\)", "\\[\\int_0^1 x\\,dx\\]")
    add(typing, f"{FRONT_PREFIX} type: capital of France", "Paris")
    flagged = add(basic, f"{FRONT_PREFIX} flagged", "Red flag")
    add(basic, f"{FRONT_PREFIX} marked", "Marked note", tags=["marked"])
    col.set_user_flag_for_cards(1, [flagged.cards()[0].id])
    col.close()


main()
