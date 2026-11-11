"""Launch out/app/AnkiMac.app on a copy of a fixture and drive it, saving window screenshots.

    python3 -I bench/shoot_app.py FIXTURE_DIR OUT_DIR STEP [STEP ...]

FIXTURE_DIR holds collection.anki2 and collection.media (see
bench/fixtures/make_parity_deck.py). It is cloned into OUT_DIR/profile first,
so the original is never touched. Screenshots land in OUT_DIR as PNG. Steps:

    wait:SECONDS         sleep
    shot:NAME            save OUT_DIR/NAME.png of the app window
    menu:MENU:ITEM       click a menu bar item, e.g. menu:Study:Study Now
    key:CHAR[:MOD,...]   keystroke, MOD from command, control, option, shift
    code:KEYCODE[:MOD]   key code (36 return, 53 escape, 49 space)
    type:TEXT            type text
    appearance:light|dark  switch the system appearance (restored on exit)

The terminal app needs Accessibility permission for System Events.
"""

import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "out/app/AnkiMac.app/Contents/MacOS/AnkiMac"


def osa(script: str) -> str:
    result = subprocess.run(["osascript", "-e", script], capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(result.stderr.strip())
    return result.stdout.strip()


# The launched instance's pid, so another AnkiMac that's running (the user's
# own, or another checkout's) never receives these clicks and keystrokes.
pid = 0


def system_events(command: str) -> str:
    return osa(f'tell application "System Events" to tell (first process whose unix id is {pid})\n{command}\nend tell')


def modifiers(spec: str | None) -> str:
    if not spec:
        return ""
    names = [f"{m.strip()} down" for m in spec.split(",")]
    return " using {" + ", ".join(names) + "}"


def shot(out: Path, name: str) -> None:
    x, y, w, h = (int(v) for v in system_events("get {position, size} of window 1").split(", "))
    subprocess.run(["screencapture", "-x", "-R", f"{x},{y},{w},{h}", str(out / f"{name}.png")], check=True)
    print("saved", out / f"{name}.png")


def step(out: Path, spec: str) -> None:
    kind, _, rest = spec.partition(":")
    if kind == "wait":
        time.sleep(float(rest))
    elif kind == "shot":
        shot(out, rest)
    elif kind == "menu":
        menu, item = rest.split(":", 1)
        system_events(f'click menu item "{item}" of menu "{menu}" of menu bar 1')
    elif kind == "key":
        char, _, mods = rest.partition(":")
        system_events("set frontmost to true\n" + f'keystroke "{char}"{modifiers(mods)}')
    elif kind == "code":
        code, _, mods = rest.partition(":")
        system_events("set frontmost to true\n" + f"key code {code}{modifiers(mods)}")
    elif kind == "type":
        system_events("set frontmost to true\n" + f'keystroke "{rest}"')
    elif kind == "appearance":
        osa(f'tell application "System Events" to tell appearance preferences to set dark mode to {str(rest == "dark").lower()}')
    else:
        raise SystemExit(f"unknown step {spec!r}")


def main() -> None:
    fixture, out = Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve()
    steps = sys.argv[3:]
    profile = out / "profile"
    shutil.rmtree(profile, ignore_errors=True)
    profile.mkdir(parents=True)
    for item in fixture.iterdir():
        subprocess.run(["/bin/cp", "-cR", str(item), str(profile)], check=True)

    original_dark = osa('tell application "System Events" to get dark mode of appearance preferences')
    log = (out / "app.log").open("w")
    proc = subprocess.Popen(
        [str(APP), "-CollectionPath", str(profile / "collection.anki2"), "-NSQuitAlwaysKeepsWindows", "NO"],
        stdout=log, stderr=subprocess.STDOUT)
    global pid
    pid = proc.pid
    try:
        for _ in range(100):
            time.sleep(0.2)
            try:
                system_events("set frontmost to true\nget window 1")
                break
            except RuntimeError:
                pass
        # Each launch cascades the window further right, off the screen edge.
        system_events("set position of window 1 to {40, 40}\nset size of window 1 to {720, 860}")
        time.sleep(1)
        for spec in steps:
            step(out, spec)
    finally:
        osa(f'tell application "System Events" to tell appearance preferences to set dark mode to {original_dark}')
        proc.terminate()
        proc.wait()


if __name__ == "__main__":
    main()
