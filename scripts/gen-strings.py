#!/usr/bin/env python3
"""Generates App/AnkiMac/Generated/Tr.swift from upstream's English Fluent
files, so native screens use desktop's wording and pick up upstream's edits
when the submodule is bumped.

Usage: python3 -I scripts/gen-strings.py

Every message of the files in WHOLE_FILES is included, plus the single
messages in EXTRA. Variables become parameters: a number (Int or Double) when
a selector on plural categories or numbers ([one], [0]) uses them, shown with
at most two decimals as desktop's Fluent arguments are; otherwise a String,
already formatted by the caller. A selector on other keys ([seconds]) compares
its String against them. Either way the variant marked * is the fallback.
Lines inside a paragraph are joined with spaces, as desktop's Markdown
renderer does; blank lines stay paragraph breaks.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FTL = ROOT / "anki/ftl/core"
FTL_QT = ROOT / "anki/ftl/qt"
OUT = ROOT / "App/AnkiMac/Generated/Tr.swift"

WHOLE_FILES = [
    "deck-config.ftl",
    "adding.ftl",
    "custom-study.ftl",
    "preferences.ftl",
    "database-check.ftl",
    "media-check.ftl",
    "empty-cards.ftl",
    "sync.ftl",
    "fields.ftl",
    "card-templates.ftl",
    "change-notetype.ftl",
    "card-stats.ftl",
    "statistics.ftl",
]
EXTRA = [
    "actions-add",
    "browsing-change-notetype",
    "decks-deck",
    "editing-show-duplicates",
    "editing-tags",
    "editing-toggle-sticky",
    "editing-mathjax-inline",
    "editing-mathjax-block",
    "editing-mathjax-chemistry",
    "editing-mathjax-placeholder",
    "editing-add-media",
    "editing-attach-picturesaudiovideo",
    "editing-record-audio",
    "editing-equations",
    "editing-latex",
    "editing-latex-equation",
    "editing-latex-math-env",
    "media-recordingtime",
    "qt-misc-unable-to-record",
    "actions-save",
    "actions-rebuild",
    "actions-name",
    "actions-filter",
    "decks-build",
    "decks-limit-to",
    "decks-cards-selected-by",
    "decks-reschedule-cards-based-on-my-answers",
    "decks-enable-second-filter",
    "decks-delay-for-button",
    "decks-zero-minutes-hint",
    "decks-filter-2",
    "decks-unmovable-cards",
    "search-view-in-browser",
    "studying-again",
    "studying-hard",
    "studying-good",
    "studying-easy",
    "scheduling-time-span-seconds",
    "scheduling-time-span-minutes",
    "scheduling-time-span-hours",
    "scheduling-time-span-days",
    "scheduling-time-span-months",
    "scheduling-time-span-years",
    "studying-empty",
    "scheduling-seconds",
    "editing-collapse",
    "editing-collapse-field",
    "editing-expand",
    "editing-expand-field",
    "importing-cards-added",
    "notetypes-type",
    "actions-auto-advance",
    "actions-preview",
    "actions-replay-audio",
    "actions-shortcut-key",
    "actions-options-for",
    "actions-processing",
    "actions-cancel",
    "actions-close",
    "actions-suspend-card",
    "card-templates-discard-changes",
    "decks-latest-added-first",
    "decks-order-added",
    "decks-relative-overdueness",
    "scheduling-easy-bonus",
    "scheduling-easy-interval",
    "scheduling-graduating-interval",
    "scheduling-hard-interval",
    "scheduling-interval-modifier",
    "scheduling-lapses",
    "scheduling-leech-action",
    "scheduling-leech-threshold",
    "scheduling-maximum-interval",
    "scheduling-maximum-reviewsday",
    "scheduling-minimum-interval",
    "scheduling-new-cards",
    "scheduling-new-cardsday",
    "scheduling-new-interval",
    "scheduling-show-answer-timer",
    "scheduling-starting-ease",
    "scheduling-tag-only",
    "scheduling-the-default-configuration-cant-be-removed",
    "studying-bury-card",
    "actions-rename",
    "actions-delete",
    "actions-custom-study",
    "studying-unbury",
    "studying-what-would-you-like-to-unbury",
    "studying-manually-buried-cards",
    "studying-buried-siblings",
    "studying-all-buried-cards",
    "errors-100-tags-max",
    "notetypes-add",
    "notetypes-add-note-type",
    "notetypes-cards",
    "notetypes-clone",
    "notetypes-copy",
    "notetypes-create-scalable-images-with-dvisvgm",
    "notetypes-delete-this-note-type-and-all",
    "notetypes-delete-this-unused-note-type",
    "notetypes-fields",
    "notetypes-footer",
    "notetypes-header",
    "notetypes-note-types",
    "notetypes-options",
    "notetypes-please-add-another-note-type-first",
    "notetypes-basic-name",
    "notetypes-basic-reversed-name",
    "notetypes-basic-optional-reversed-name",
    "notetypes-basic-type-answer-name",
    "notetypes-cloze-name",
    "notetypes-image-occlusion-name",
    "browsing-note-count",
    "browsing-find-duplicates",
    "browsing-tag-duplicates",
    "browsing-duplicate",
    "browsing-found-as-across-bs",
    "browsing-group",
    "browsing-search-in",
    "browsing-optional-filter",
    "actions-search",
    "actions-new-name",
    "actions-reposition",
    "actions-card-info",
    "actions-previous-card-info",
    "actions-copy",
    "actions-create-copy",
    "actions-replay-audio",
    "actions-with-ellipsis",
    "actions-flag-red",
    "actions-flag-orange",
    "actions-flag-green",
    "actions-flag-blue",
    "actions-flag-pink",
    "actions-flag-turquoise",
    "actions-flag-purple",
    "studying-flag-card",
    "studying-mark-note",
    "studying-bury-note",
    "studying-suspend-note",
    "editing-cards",
    "editing-customize-card-templates",
    "card-stats-current-card",
    "card-stats-previous-card",
    "decks-study",
    "exporting-all-decks",
    "exporting-anki-collection-package",
    "exporting-anki-deck-package",
    "exporting-cards-in-plain-text",
    "exporting-export",
    "exporting-export-format",
    "exporting-include",
    "exporting-include-html-and-media-references",
    "exporting-include-media",
    "exporting-include-scheduling-information",
    "exporting-include-deck-configs",
    "exporting-include-tags",
    "exporting-support-older-anki-versions",
    "exporting-notes-in-plain-text",
    "exporting-selected-notes",
    "exporting-exporting-file",
    "exporting-include-deck",
    "exporting-include-notetype",
    "exporting-include-guid",
    "exporting-collection",
    "importing-merge-notetypes",
    "importing-merge-notetypes-help",
    "importing-update-if-newer",
    "importing-update-always",
    "importing-update-never",
    "importing-update-notes",
    "importing-update-notes-help",
    "importing-update-notetypes",
    "importing-update-notetypes-help",
    "importing-include-reviews",
    "importing-include-reviews-help",
    "importing-with-deck-configs",
    "importing-with-deck-configs-help",
    "importing-this-will-delete-your-existing-collection",
    "importing-importing-complete",
    "importing-import-log",
    "importing-no-notes-in-file",
    "importing-notes-found-in-file2",
    "importing-notes-added",
    "importing-notes-updated",
    "importing-existing-notes-skipped",
    "importing-notes-failed",
    "importing-conflicting-notes-skipped",
    "importing-conflicting-notes-skipped2",
    "importing-import-options",
    "importing-updates",
    "importing-tab",
    "importing-pipe",
    "importing-semicolon",
    "importing-colon",
    "importing-comma",
    "studying-space",
    "importing-field-separator",
    "importing-field-separator-guessed",
    "importing-field-separator-help",
    "importing-allow-html-in-fields",
    "importing-allow-html-in-fields-help",
    "importing-file",
    "importing-field-mapping",
    "importing-existing-notes",
    "importing-existing-notes-help",
    "importing-update",
    "importing-preserve",
    "importing-duplicate",
    "importing-match-scope",
    "importing-match-scope-help",
    "importing-notetype-and-deck",
    "importing-notetype-help",
    "importing-deck-help",
    "importing-tag-all-notes",
    "importing-tag-all-notes-help",
    "importing-tag-updated-notes",
    "importing-tag-updated-notes-help",
    "importing-new-deck-will-be-created",
    "importing-preview-truncated",
    "change-notetype-nothing",
    "notetypes-notetype",
    "importing-all-supported-formats",
    "importing-packaged-anki-deckcollection-apkg-colpkg-zip",
    "actions-import",
    "actions-export",
    "studying-card-suspended",
    "studying-note-suspended",
    "studying-cards-buried",
    "studying-delete-note",
    "studying-pause-audio",
    "studying-audio-5s",
    "studying-audio-and5s",
    "studying-record-own-voice",
    "studying-replay-own-voice",
    "studying-you-havent-recorded-your-voice-yet",
    "studying-question-time-elapsed",
    "studying-answer-time-elapsed",
    "actions-auto-advance-activated",
    "actions-auto-advance-deactivated",
    "studying-card-studied-in-minute",
    "studying-continue",
    "studying-finish",
    "browsing-cards-deleted",
    "undo-action-undone",
    "undo-undo",
    "undo-redo",
    "undo-undo-action",
    "undo-redo-action",
    "scheduling-set-due-date-done",
    "scheduling-forgot-cards",
    "actions-set-due-date",
    "actions-forget-card",
    "actions-options",
    "profiles-open",
    "profiles-open-backup",
    "profiles-profiles",
    "profiles-quit",
    "profiles-user-1",
    "profiles-downgrade-and-quit",
    "profiles-anki-could-not-rename-your-profile",
    "qt-misc-name-exists",
    "qt-misc-there-must-be-at-least-one",
    "qt-misc-all-cards-notes-and-media-for2",
    "qt-misc-the-following-character-can-not-be",
    "qt-accel-switch-profile",
    "profiles-backup-created",
    "profiles-backup-unchanged",
    "profiles-backup-creation-failed",
    "qt-accel-create-backup",
    "qt-accel-load-backup",
    "qt-misc-revert-to-backup",
    "qt-misc-replace-your-collection-with-an-earlier2",
    "qt-misc-automatic-syncing-and-backups-have-been",
    "statistics-due-date",
    "statistics-elapsed-time-seconds",
    "statistics-elapsed-time-minutes",
    "statistics-elapsed-time-hours",
    "statistics-elapsed-time-days",
    "statistics-elapsed-time-months",
    "statistics-elapsed-time-years",
    "scheduling-description",
    "decks-study-deck",
    "decks-new-deck-name",
    "studying-this-is-a-special-deck-for",
    "studying-cards-will-be-automatically-returned-to",
    "studying-deleting-this-deck-from-the-deck",
    "actions-search",
    "actions-all-selected",
    "actions-any-selected",
    "actions-rename-deck",
    "actions-rename-tag",
    "actions-rename-with-parents",
    "browsing-sidebar-save-current-search",
    "browsing-update-saved-search",
    "browsing-confirm-saved-search-overwrite",
    "browsing-please-give-your-filter-a-name",
    "browsing-tag-rename-warning-empty",
    "browsing-add-to-selected-notes",
    "browsing-remove-from-selected-notes",
    "browsing-manage-note-types",
    "browsing-clear-unused-tags",
    "browsing-removed-unused-tags-count",
    "browsing-notes-updated",
    "browsing-add-notes",
    "editing-image-occlusion-select-tool",
    "editing-image-occlusion-rectangle-tool",
    "editing-image-occlusion-ellipse-tool",
    "editing-image-occlusion-polygon-tool",
    "editing-image-occlusion-text-tool",
    "editing-image-occlusion-mode",
    "editing-image-occlusion-zoom-out",
    "editing-image-occlusion-zoom-in",
    "editing-image-occlusion-zoom-reset",
    "editing-image-occlusion-toggle-translucent",
    "editing-image-occlusion-delete",
    "editing-image-occlusion-duplicate",
    "editing-image-occlusion-group",
    "editing-image-occlusion-ungroup",
    "editing-image-occlusion-select-all",
    "editing-image-occlusion-fill-tool",
    "editing-image-occlusion-alignment",
    "editing-image-occlusion-align-left",
    "editing-image-occlusion-align-h-center",
    "editing-image-occlusion-align-right",
    "editing-image-occlusion-align-top",
    "editing-image-occlusion-align-v-center",
    "editing-image-occlusion-align-bottom",
    "editing-no-image-found-on-clipboard",
    "notetypes-occlusion-mask",
    "notetypes-occlusion-note",
    "notetypes-hide-all-guess-one",
    "notetypes-hide-one-guess-one",
    "notetypes-error-loading-image-occlusion",
    "notetypes-error-getting-imagecloze",
    "notetypes-no-occlusion-created2",
    "notetypes-io-select-image",
    "notetypes-io-paste-image-from-clipboard",
    "undo-undo",
    "undo-redo",
]


def parse(path: Path) -> dict[str, str]:
    """Message id -> raw value (continuation lines dedented, newlines kept)."""
    messages: dict[str, str] = {}
    current: str | None = None
    lines: list[str] = []

    def flush() -> None:
        if current is not None:
            while lines and not lines[-1].strip():
                lines.pop()
            messages[current] = "\n".join(lines)

    for raw in path.read_text().splitlines():
        match = re.match(r"^(-?[a-z][a-z0-9-]*)\s*=\s?(.*)$", raw)
        if match:
            flush()
            current, first = match.group(1), match.group(2).rstrip()
            lines = [first] if first.strip() else []
        elif current is not None and (raw.startswith(" ") or not raw.strip()):
            lines.append(raw)
        else:
            flush()
            current, lines = None, []
    flush()
    for key, value in messages.items():
        messages[key] = "\n".join(l.strip() for l in value.split("\n")).strip("\n")
    return messages


def camel(key: str) -> str:
    parts = re.split(r"[-_]", key)
    name = parts[0] + "".join(p[:1].upper() + p[1:] for p in parts[1:])
    return name if not name[0].isdigit() else "_" + name


def swift_literal(text: str) -> str:
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


class Compiler:
    def __init__(self, messages: dict[str, str]):
        self.messages = messages

    PLURAL_KEYS = {"zero", "one", "two", "few", "many", "other"}

    def segments(self, text: str, plural_vars: set[str], all_vars: list[str]) -> list[str]:
        """Swift expressions whose concatenation is the message."""
        out: list[str] = []
        i = 0
        literal = ""
        while i < len(text):
            if text[i] == "{":
                end = self.matching(text, i)
                inner = text[i + 1 : end].strip()
                if literal:
                    out.append(swift_literal(literal))
                    literal = ""
                out.append(self.placeable(inner, plural_vars, all_vars))
                i = end + 1
            else:
                literal += text[i]
                i += 1
        if literal:
            out.append(swift_literal(literal))
        return out

    @staticmethod
    def matching(text: str, start: int) -> int:
        depth = 0
        for j in range(start, len(text)):
            if text[j] == "{":
                depth += 1
            elif text[j] == "}":
                depth -= 1
                if depth == 0:
                    return j
        raise ValueError(f"unbalanced braces in {text!r}")

    def placeable(self, inner: str, plural_vars: set[str], all_vars: list[str]) -> str:
        select = re.match(r"^\$([a-zA-Z_-]+)\s*->\s*(.*)$", inner, re.S)
        if select:
            var = select.group(1)
            if var not in all_vars:
                all_vars.append(var)
            variants, default = self.variants(select.group(2))
            numeric = all(k in self.PLURAL_KEYS or k.isdigit() for k in variants)
            if numeric:
                plural_vars.add(var)
            expr = self.join(self.segments(variants[default], plural_vars, all_vars))
            for key, text in reversed(list(variants.items())):
                # English has no zero/two/few/many plural forms.
                if key == default or key in self.PLURAL_KEYS - {"one"}:
                    continue
                if numeric:
                    test = f"{camel(var)}.trValue == {1 if key == 'one' else key}"
                else:
                    test = f'{camel(var)} == "{key}"'
                expr = f"({test} ? {self.join(self.segments(text, plural_vars, all_vars))} : {expr})"
            return expr
        if inner.startswith("$"):
            var = inner[1:]
            if var not in all_vars:
                all_vars.append(var)
            return f"Tr.number({camel(var)})" if var in self.numeric_vars else camel(var)
        if inner.startswith('"') and inner.endswith('"'):
            return swift_literal(inner[1:-1])
        # A reference to another message, inlined.
        return self.join(self.segments(self.normalise(self.messages[inner]), plural_vars, all_vars))

    def variants(self, body: str) -> tuple[dict[str, str], str]:
        """Variant key -> text, and the key of the * default."""
        found: dict[str, str] = {}
        default = "other"
        pattern = re.compile(r"(\*?)\[([a-z0-9]+)\]\s*")
        positions = [m for m in pattern.finditer(body) if self.depth_at(body, m.start()) == 0]
        for n, match in enumerate(positions):
            stop = positions[n + 1].start() if n + 1 < len(positions) else len(body)
            found[match.group(2)] = " ".join(body[match.end():stop].split())
            if match.group(1):
                default = match.group(2)
        return found, default

    @staticmethod
    def depth_at(text: str, index: int) -> int:
        return text[:index].count("{") - text[:index].count("}")

    @staticmethod
    def join(parts: list[str]) -> str:
        if not parts:
            return '""'
        return parts[0] if len(parts) == 1 else "(" + " + ".join(parts) + ")"

    @staticmethod
    def normalise(text: str) -> str:
        """Joins the lines of each paragraph; keeps list items on their own line."""
        paragraphs = re.split(r"\n\s*\n", text)
        out = []
        for paragraph in paragraphs:
            lines = [l.strip() for l in paragraph.split("\n") if l.strip()]
            merged: list[str] = []
            for line in lines:
                if merged and not line.startswith("- ") and not Compiler.in_select(merged[-1]):
                    merged[-1] += " " + line
                elif merged and Compiler.in_select(merged[-1]):
                    merged[-1] += " " + line
                else:
                    merged.append(line)
            out.append("\n".join(merged))
        return "\n\n".join(out)

    @staticmethod
    def in_select(text: str) -> bool:
        return text.count("{") > text.count("}")

    def emit(self, key: str) -> str:
        text = self.normalise(self.messages[key])
        # A first pass finds the numeric variables, so a { $count } placed
        # before its selector is formatted as a number too.
        self.numeric_vars: set[str] = set()
        self.segments(text, self.numeric_vars, [])
        plural_vars: set[str] = set()
        all_vars: list[str] = []
        expr = self.join(self.segments(text, plural_vars, all_vars))
        name = camel(key)
        if key.startswith("qt-accel-"):
            expr = expr.replace("&", "", 1)  # the Qt menu mnemonic
        expr = expr.replace("&&", "&")  # Qt's escaped ampersand on a button
        if not all_vars:
            return f"    static let {name} = {expr}"
        params = ", ".join(f"{camel(v)}: {'some TrNumber' if v in plural_vars else 'String'}" for v in all_vars)
        return f"    static func {name}({params}) -> String {{\n        {expr}\n    }}"


def main() -> None:
    messages: dict[str, str] = {}
    for path in sorted(FTL.glob("*.ftl")) + sorted(FTL_QT.glob("*.ftl")):
        messages.update(parse(path))
    keys: list[str] = []
    for name in WHOLE_FILES:
        keys += [k for k in parse(FTL / name) if not k.startswith("-") and k not in keys]
    keys += [k for k in dict.fromkeys(EXTRA) if k not in keys]
    compiler = Compiler(messages)
    body = "\n".join(compiler.emit(k) for k in keys)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(
        "// GENERATED by scripts/gen-strings.py from anki/ftl/core and anki/ftl/qt. Do not edit.\n\n"
        "/// A number argument: desktop's Fluent selects plurals on its value and\n"
        "/// shows it with at most two decimals.\n"
        "nonisolated protocol TrNumber { var trValue: Double { get } }\n"
        "nonisolated extension Int: TrNumber { var trValue: Double { Double(self) } }\n"
        "nonisolated extension Double: TrNumber { var trValue: Double { self } }\n\n"
        "/// Desktop's English strings, by Fluent id in camel case.\n"
        "nonisolated enum Tr {\n"
        "    static func number(_ value: some TrNumber) -> String {\n"
        "        value.trValue.formatted(.number.precision(.fractionLength(0...2)))\n"
        "    }\n" + body + "\n}\n"
    )
    print(f"wrote {len(keys)} strings to {OUT.relative_to(ROOT)}", file=sys.stderr)


if __name__ == "__main__":
    main()
