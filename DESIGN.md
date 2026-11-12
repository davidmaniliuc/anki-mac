---
name: AnkiMac
description: A native, calm Mac frontend for Anki, a quiet desk to study at.
colors:
  accent-blue: "#2F6BFF"
  canvas-paper: "#FAF9F6"
  sidebar-linen: "#F1EFEA"
  card-white: "#FFFFFF"
  raised-oat: "#F6F4F0"
  hover-wash: "rgba(0, 0, 0, 0.04)"
  selection-wash: "rgba(0, 0, 0, 0.07)"
  hairline: "rgba(0, 0, 0, 0.08)"
  ink: "#1D1C1A"
  pencil: "#6B675F"
  faded-pencil: "#9E9A92"
  queue-new-blue: "#1A5CFF"
  queue-learn-coral: "#CA342A"
  queue-review-green: "#247C47"
  grade-hard-amber: "#936113"
  place-violet: "#7C5CE6"
  place-teal: "#1E9AAE"
  anki-star-blue: "#2E9BEA"
typography:
  display:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "30px"
    fontWeight: 700
  headline:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "17px"
    fontWeight: 600
  title:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "14.5px"
    fontWeight: 500
  body:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "14px"
    fontWeight: 400
  label:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "11px"
    fontWeight: 600
    letterSpacing: "0.8px"
  numeral:
    fontFamily: "SF Pro Rounded, ui-rounded, system-ui"
    fontSize: "44px"
    fontWeight: 600
    fontFeature: "tnum"
  count:
    fontFamily: "SF Pro Rounded, ui-rounded, system-ui"
    fontSize: "12px"
    fontWeight: 600
    fontFeature: "tnum"
rounded:
  keycap: "4px"
  row: "7px"
  button: "9px"
  list-row: "10px"
  grade: "11px"
  panel: "12px"
  card: "18px"
  pill: "9999px"
spacing:
  xxs: "2px"
  xs: "4px"
  sm: "8px"
  md: "12px"
  lg: "20px"
  xl: "32px"
components:
  button-primary:
    backgroundColor: "{colors.accent-blue}"
    textColor: "#FFFFFF"
    rounded: "{rounded.button}"
    padding: "0 16px"
    height: "36px"
  button-chip:
    backgroundColor: "{colors.raised-oat}"
    textColor: "{colors.ink}"
    rounded: "{rounded.pill}"
    padding: "0 12px"
    height: "28px"
  button-chip-pressed:
    backgroundColor: "{colors.selection-wash}"
  button-quiet:
    backgroundColor: "transparent"
    textColor: "{colors.pencil}"
    rounded: "{rounded.row}"
    padding: "0 4px"
  button-quiet-hover:
    backgroundColor: "{colors.hover-wash}"
    textColor: "{colors.ink}"
  due-summary:
    backgroundColor: "transparent"
    textColor: "{colors.ink}"
  sidebar-row:
    backgroundColor: "transparent"
    textColor: "{colors.ink}"
    rounded: "{rounded.row}"
    height: "30px"
  sidebar-row-selected:
    backgroundColor: "{colors.selection-wash}"
  deck-list-row:
    backgroundColor: "transparent"
    rounded: "{rounded.list-row}"
    padding: "0 12px"
    height: "50px"
  deck-list-row-hover:
    backgroundColor: "{colors.hover-wash}"
  keycap:
    backgroundColor: "{colors.hairline}"
    textColor: "{colors.pencil}"
    rounded: "{rounded.keycap}"
    padding: "0 5px"
    height: "17px"
---

# Design System: AnkiMac

`App/AnkiMac/Theme.swift` holds every value; the shared controls are in `App/AnkiMac/Views/Design.swift`. Each colour above is the light-appearance value. Every colour has a dark value too (listed in `.impeccable/design.json` and in `Theme.Palette`), and the app follows the system appearance.

## Overview

**Creative North Star: "The Quiet Desk"**

A tidy study desk in good light: warm paper, one blue pen, nothing out that isn't needed. The main window is made of warm neutrals in place of macOS's cool greys, with one electric blue accent and the queue colours Anki users already read at a glance. Nothing competes with the card or the counts. The interface gets out of the way while you study and stays ready when you're done.

The window is flat at rest: canvas, sidebar and panels are told apart by tone and hairlines, not shadows. Liquid Glass shows up only on what floats above that desk, like a toast over the card, a popover, or a floating panel, in the way Things 3's Quick Find and Rex's tab capsules sit over flat content. Lists are Things-like: a small spaced-capital eyebrow over a large title, quiet rows that show a hover wash, and actions that appear only when the pointer is over them.

The main window is the reference. The utility windows (Browser, Statistics, Deck Options, the editors) still use system controls and desktop's colours. They move onto this system gradually, without losing their density.

**Key Characteristics:**
- Warm paper neutrals; one blue accent; queue colours as information, never decoration.
- SF Pro for words, SF Pro Rounded with tabular figures for every number.
- Flat tonal layers with hairlines; glass only for things that float above them.
- Quiet controls that brighten on hover; one prominent action per page at most.
- Every study action shows its key (KeyCap) and works from the keyboard.

## Colors

Warm, low-chroma paper and ink, punctuated by one saturated blue and Anki's three queue colours.

### Primary
- **Electric Pen Blue** (accent-blue): the one prominent action on a page (Study Now), the play button on a hovered deck row, the selected deck's ring, and the window's tint. Its rarity is what makes it findable.

### Secondary
- **Queue New Blue / Learning Coral / Review Green** (queue-new-blue, queue-learn-coral, queue-review-green): Anki's new, learning and review counts in Anki's hues. In light mode they are deep enough (4.5:1 on the canvas) to read as text; dark mode uses lighter shades. They appear wherever counts appear: sidebar, the due summary on Today and the overview, the study title bar, statistics.
- **Grade colours:** Again uses Learning Coral, Hard uses Ochre Amber (grade-hard-amber), Good uses Review Green, Easy uses Queue New Blue. They colour the answer buttons' labels, and wash the button only under the pointer.

### Tertiary
- **Places violet and teal** (place-violet, place-teal): only the sidebar's Statistics and Browse icons.
- **Anki Star Blue** (anki-star-blue): the star beside Today, as in Anki's logo.

### Neutral
- **Canvas Paper** (canvas-paper): the main content and study background.
- **Sidebar Linen** (sidebar-linen): the sidebar, a step darker than the canvas (darker still in dark mode).
- **Card White** (card-white): panels and behind the card. The card's web page paints the same value so the two meet seamlessly.
- **Raised Oat** (raised-oat): chip button fill.
- **Ink / Pencil / Faded Pencil** (ink, pencil, faded-pencil): primary text, secondary text and icons, tertiary text and zero counts.
- **Hover, Selection, Hairline washes**: translucent black in light mode, translucent white in dark mode, so they work on any of the neutral layers.

### Named Rules
**The One Pen Rule.** Electric Pen Blue marks the single prominent action on a screen. Secondary actions are chips or quiet buttons, never a second blue fill.

**The Queue Colours Mean Queues Rule.** Blue, coral and green stand for new, learning and review (and the grades that share them). Don't reuse them for unrelated status or decoration. A zero count fades to Faded Pencil instead of showing its colour.

**The Warm Neutral Rule.** Main-window surfaces use the palette's warm neutrals, never `Color.gray` or the system's cool greys.

## Typography

**Interface Font:** SF Pro (system)
**Numerals:** SF Pro Rounded with monospaced (tabular) digits
**Code/Source:** SF Mono (template and HTML source editors)

**Character:** SF Pro keeps the app native; the rounded face for numbers adds the warmth of a friendly hand-written count and keeps columns of digits steady as they change.

### Hierarchy
- **Display** (bold 700, 30px; 24px in a small window): page titles, Today and the deck name, beside their icon.
- **Headline** (semibold 600, 17px): panel and sheet titles.
- **Title** (medium 500, 14.5px): deck names in page lists.
- **Sidebar row** (regular 400, 13.5px; semibold 600 on the selected row only): places and decks in the sidebar, so only the selection steps forward.
- **Body** (regular 400, 14px; lead 15px; caption 12px): descriptions, paths under deck names, secondary lines.
- **Label / Eyebrow** (semibold 600, 11px, 0.8px tracking, uppercase): section names and the path over a title, in Pencil.
- **Numeral** (rounded semibold 600, 44px, tabular): the one big due count on a page.
- **Queue count** (rounded semibold 600, 14px, tabular): the new / learning / review line under it.
- **Count** (rounded semibold 600, 12px, tabular): due counts in rows and the study title bar; interval captions under the grades are 12px medium.
- **Button** (semibold 600, 14px), **Chip** (medium 500, 12.5px), **KeyCap** (rounded semibold 600, 10.5px).

### Named Rules
**The Rounded Numbers Rule.** Every count, interval and statistic uses the rounded face with tabular digits; words never do.

**The Small Capitals Rule.** Uppercase appears only in eyebrows, small and tracked. Titles and buttons are sentence or title case from upstream's wording.

## Layout

- **Main window:** a 248px sidebar beside the content. Below 720px window width it becomes compact: the sidebar floats over the content behind a 30% black scrim and closes once something is picked, type shrinks, margins tighten, and rows drop to a single total count. The minimum window is 360 × 340, small enough to study in a corner of the screen.
- **Pages** (Today, deck overview): a single reading column capped at 680px, centred, with 56px side margins (18px compact) and 20px between blocks (12px compact). A named list (`PageSection`: an eyebrow over rows) sits a further 12px down, so the page reads in groups.
- **Study:** the card is capped at 860px wide on the canvas, the answer bar sits at the bottom (18px vertical), and the deck name and counts sit in the title bar. The card, the answer bar and the deck name share one side edge: 40px from the window (12px compact), or the centred card's edge when the window is wider than the card; no grade button reaches past the card. The sidebar is put away while studying and comes back when the session ends.
- **Spacing rhythm:** 2 / 4 / 8 / 12 / 20 / 32px. Sidebar rows are 30px with 14px of indent per deck level; list rows are 50px.
- **Gestures:** a two-finger sideways swipe of 60px shows or hides the sidebar.

## Elevation & Depth

Flat by default, with tonal layering: Sidebar Linen, Canvas Paper and Card White are separate layers, divided by 1px hairlines. The only shadow in the main window is the one under the floating sidebar in compact mode (black at 35%, 24px radius, offset 6px right). It's there because the sidebar is above the content, not to decorate.

Liquid Glass and materials are for things that float over the flat desk: the study toast (a capsule of regular material over the card), popovers, menus, sheets and future floating panels such as a quick-find palette. Toolbar buttons are drawn plainly, without the toolbar's glass capsule, so the title bar stays part of the page.

### Named Rules
**The Flat Desk Rule.** A surface that stays put is flat and toned; only what floats above it gets glass or a shadow.

**The Glass Is Rare Rule.** Glass marks something transient or overlaid. If glass appears on every surface it stops meaning "above", so don't put it on the sidebar, panels or rows.

## Shapes

Gently rounded throughout, with radius growing with the size of the element: 4px key caps, 7px sidebar rows and quiet buttons, 9px primary button, 10px list rows, 11px grade buttons, 12px panels, 18px card. Chips and toasts are full capsules. Panels carry a 1px hairline border inside their edge. Icons are SF Symbols, plus two drawn shapes: the Anki star (an outlined, plump-pointed star tilted -14°) and the deck ring.

## Components

### Buttons
- **Primary** (`PrimaryButtonStyle`): Electric Pen Blue fill, white 14px semibold label, 36px tall, 16px side padding, 9px radius. Darkens by 8% when pressed. One per page.
- **Chip** (`ChipButtonStyle`): Raised Oat capsule with a hairline border, 12.5px medium ink label, 28px tall. Hover wash under the pointer, selection wash when pressed, 40% when disabled. Used for a page's secondary actions.
- **Quiet** (`QuietButtonStyle`, `IconButton`): no fill at rest, Pencil foreground. On hover the foreground brightens to Ink with a hover wash; pressed shows the selection wash. Disabled drops to 40% opacity. Used for toolbar icons (30 × 28) and the sidebar footer.

### Grade Buttons (signature)
Again / Hard / Good / Easy (`GradeButtonStyle`). At rest each is a neutral hover wash with its label in the grade colour; the grade colour fills in only on hover (12%) and when pressed (22%), so the four read as one quiet row. Its number key follows the label in a KeyCap, and the next interval sits underneath in a rounded caption. They share the bar evenly up to 140px each and are 58px tall (48px compact). Good is the one outlined (1.5px, its colour at 55%), because it's the most common answer. Show Answer uses the same style in Ink, 200 × 38, with a Space KeyCap.

### Cards / Containers
- **Due summary** (`DueSummary`): unboxed, straight on the canvas. A 44px rounded numeral with "due" beside it in Pencil, and under it one line of queue counts ("12 new  3 learning  185 to review") with each number in its queue colour; a zero fades both the number and its word to Faded Pencil. The page's one action (Study Now) sits at the trailing edge, or below when the row is too narrow. With nothing due, the overview shows "All done for now" and Today a single line instead.
- **The study card:** upstream's reviewer in a web view on Card White, up to 860px wide, 18px radius. Its contents are styled by the note type, never by the app.

### Navigation
- **Sidebar:** Sidebar Linen. At the top, the "places": Today (Anki star, total due), then Browse and Statistics with coloured SF Symbols and their single-key shortcuts in KeyCaps, so they can't be read as counts. Below them sits the deck tree in 30px rows with a 7px radius and a selection wash for the selected row. Every deck, top-level or not, is the same row; a deck with subdecks has a disclosure arrow, and top-level decks with subdecks are set apart by 12px of space, never drawn as headings, since they can be selected and studied. then a footer behind a hairline with New Deck and Sync.
- **Deck list row:** 50px, deck ring, name and optional path, the queue counts, and an accent play button that appears only on hover. The row's content keeps to the page's edge; its hover wash (10px radius) reaches 12px past it on both sides, as in Things, so the ring and counts line up with the title and the due summary.

### Deck Ring (signature)
A deck's icon is a ring that fills like a pie as today's cards are answered. Its track is always a faint neutral hairline (the selection wash); only the filled arc carries colour, coral while cards in learning are waiting, accent blue when selected, and Pencil otherwise, so an untouched deck never reads as an unchecked to-do. It animates smoothly as progress changes.

### KeyCap
The key's name in a small 4px-rounded box (rounded 10.5px semibold, hairline fill, Pencil text; a white-on-accent variant exists). It sits beside the action it triggers, and is hidden from accessibility and in compact windows.

### Eyebrow + Page Title
A spaced-capital eyebrow (a greeting and date, or the parent deck path) over a 30px bold title with its icon, as Things titles a list.

## Do's and Don'ts

### Do:
- **Do** take every colour, size and spacing from `Theme`; add a token there before using a new value.
- **Do** show due counts in queue colours with the rounded tabular face, fading zeros to Faded Pencil.
- **Do** show the keyboard shortcut next to study actions with KeyCap, and in the sidebar for places.
- **Do** keep surfaces flat and divide them with 1px hairlines and tone steps.
- **Do** use glass or material for things that float over the window: toasts, popovers, quick-find style panels.
- **Do** reveal secondary row actions on hover, and keep each one reachable from a menu or key.
- **Do** design both appearances; every palette colour has a light and a dark value.

### Don't:
- **Don't** use a second blue-filled button on a screen (The One Pen Rule).
- **Don't** use the queue or grade colours for anything other than queues and grades.
- **Don't** use the system's cool greys or `Color.gray` on main-window surfaces.
- **Don't** add drop shadows to panels or rows; depth comes from tone.
- **Don't** spread glass onto fixed chrome such as the sidebar, page panels or the answer bar.
- **Don't** restyle card content; the note type owns it.
- **Don't** write new labels where upstream Anki has a translated string.
