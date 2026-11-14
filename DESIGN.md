---
name: AnkiMac
description: A native, calm Mac frontend for Anki, a quiet desk to study at.
colors:
  accent-blue: "#2F6BFF"
  canvas-paper: "#FAF9F6"
  sidebar-linen: "#F1EFEA"
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

The main window is the reference. Statistics is a page of the main window (see Statistics below). The utility windows (Browser, Deck Options, the editors) still use system controls and desktop's colours. They move onto this system gradually, without losing their density.

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
- **Marked and flagged:** over the card, a marked note's star is Pencil with no shadow; flags keep their own flag colours.

### Neutral
- **Canvas Paper** (canvas-paper): the main content and study background. The card's web page paints it too, so the card sits on the desk with no edge.
- **Sidebar Linen** (sidebar-linen): the sidebar, a step darker than the canvas (darker still in dark mode).
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

- **Main window:** a 248px sidebar beside the content. As in Things 3, showing or hiding it grows or shrinks the window from its right edge, and the page keeps its width and slides across over the sidebar, which stays put; only in full screen, or with no room left on screen, does it push the page aside. Narrowing the window by hand only narrows the page: a docked sidebar stays until it is hidden, and the window can't get narrower than the sidebar plus the 360px minimum. Shown in a window under 720px that can't widen, the sidebar floats over the content behind a 30% black scrim and closes once something is picked. A page narrower than 472px is compact: type shrinks, margins tighten, and rows drop to a single total count. The minimum window is 360 × 340, small enough to study in a corner of the screen.
- **Today is where the day starts:** the window opens on Today, with no deck selected. Its Study Now (Return) studies the first deck in its list (learning cards first, then the most due), as does a row's play button; a session started there ends back on Today, where the next deck is then first.
- **Pages** (Today, deck overview): a single reading column capped at 680px, centred, with 56px side margins (18px compact) and 20px between blocks (12px compact). A named list (`PageSection`: an eyebrow over rows) sits a further 12px down, so the page reads in groups.
- **Study:** when the session ends, its page (see Session end) takes the card's place in the same reading column as the other pages. The card is capped at 860px wide on the canvas, the answer bar sits at the bottom (18px vertical), and the deck name and counts sit in the title bar. The card, the answer bar and the deck name share one side edge: 40px from the window (12px compact), or the centred card's edge when the window is wider than the card; no grade button reaches past the card. Starting a session leaves the sidebar as it was.
- **Spacing rhythm:** 2 / 4 / 8 / 12 / 20 / 32px. Sidebar rows are 30px with 14px of indent per deck level; list rows are 50px.
- **Gestures:** a two-finger sideways swipe of 60px shows or hides the sidebar.
- **Arrow keys:** Up and Down move through the sidebar's rows (Left and Right fold a deck) until the page is clicked or scrolled; from then on they scroll the page 60px at a time, until something is picked in the sidebar again.
- **Notices:** after a change that has no page of its own, such as Delete Deck, a short message in a Liquid Glass capsule sits near the bottom of the window for 2.5 seconds and is announced to VoiceOver, in desktop's words ("12 cards deleted from Spanish."). Undo brings the deck back.
- **Media sync:** when media takes more than half a second to sync, a two-line Liquid Glass capsule over the bottom of the window shows desktop's counts ("Added: 2↑ 0↓  ·  Checked: 140") with a spinner, which takes over from the Sync button's. It stays at least 1.2 seconds, only ever grows wider, and materializes rather than sliding. It ends on "Media sync complete." with a green check for 1.5 seconds, which VoiceOver announces.

## Elevation & Depth

Flat by default, with tonal layering: Sidebar Linen and Canvas Paper are separate layers, divided by 1px hairlines. The only shadow in the main window is the one under the floating sidebar in compact mode (black at 35%, 24px radius, offset 6px right). It's there because the sidebar is above the content, not to decorate.

Liquid Glass and materials are for things that float over the flat desk: the study toast (a capsule of regular material over the card), popovers, menus, sheets and future floating panels such as a quick-find palette. Toolbar buttons are drawn plainly, without the toolbar's glass capsule, so the title bar stays part of the page. A toolbar holds only what has no other place: the overview's is Add Cards alone (Options is a chip on the page; Browse and Statistics are sidebar places), and Statistics' controls sit on its page.

### Named Rules
**The Flat Desk Rule.** A surface that stays put is flat and toned; only what floats above it gets glass or a shadow.

**The Glass Is Rare Rule.** Glass marks something transient or overlaid. If glass appears on every surface it stops meaning "above", so don't put it on the sidebar, panels or rows.

## Shapes

Gently rounded throughout, with radius growing with the size of the element: 4px key caps, 7px sidebar rows and quiet buttons, 9px primary button, 10px list rows, 11px grade buttons, 12px panels. The study card has no shape of its own. Chips and toasts are full capsules. Panels carry a 1px hairline border inside their edge. Icons are SF Symbols, plus two drawn shapes: the Anki star (an outlined, plump-pointed star tilted -14°) and the deck ring.

## Components

### Buttons
- **Primary** (`PrimaryButtonStyle`): Electric Pen Blue fill, white 14px semibold label, 36px tall, 16px side padding, 9px radius. Darkens by 8% when pressed. One per page.
- **Chip** (`ChipButtonStyle`): Raised Oat capsule with a hairline border, 12.5px medium ink label, 28px tall. Hover wash under the pointer, selection wash when pressed, 40% when disabled. Used for a page's secondary actions.
- **Quiet** (`QuietButtonStyle`, `IconButton`): no fill at rest, Pencil foreground. On hover the foreground brightens to Ink with a hover wash; pressed shows the selection wash. Disabled drops to 40% opacity. Used for toolbar icons (30 × 28) and the sidebar footer.

### Grade Buttons (signature)
Again / Hard / Good / Easy (`GradeButtonStyle`). At rest each is a neutral hover wash with its label in the grade colour; the grade colour fills in only on hover (12%) and when pressed (22%), so the four read as one quiet row. Its number key follows the label in a KeyCap, and the next interval sits underneath in a rounded caption. They share the bar evenly up to 140px each and are 58px tall (48px compact). Good is the one outlined (1.5px, its colour at 55%), because it's the most common answer. Show Answer uses the same style in Ink, 38px tall and as wide as its label and Space KeyCap, but with no wash or hairline at rest: the wash appears only under the pointer, so during the question the card is the only shape on the canvas.

### Cards / Containers
- **Due summary** (`DueSummary`): unboxed, straight on the canvas. A 44px rounded numeral with "due" beside it in Pencil, and under it one line of queue counts ("12 new  3 learning  185 to review") with each number in its queue colour; a zero fades both the number and its word to Faded Pencil. The page's one action (Study Now) sits at the trailing edge, or below when the row is too narrow. With nothing due, the overview shows upstream's "Congratulations! You have finished this deck for now." as a headline, as desktop's overview does, and Today a single lead line: when learning cards come back later today, upstream's "The next learning card will be ready in 5 minutes. There are 3 learning cards due later today." (kept current each minute, and the counts refresh when that card comes due), otherwise "Nothing is due. Come back tomorrow."
- **Today's list:** under the due summary, an upstream "Due" section lists each deck without subdecks that has cards due, learning first. The total comes from the top-level decks and follows their limits, so when the rows add up to more, a caption under them says so. The eyebrow greets by time of day and gives the date, redrawn each minute so it follows midnight.
- **Session end** (`SessionFinished`): a page in the same column as Today and the overview, over the card. The deck's path is the eyebrow, upstream's whole "Congratulations! You have finished this deck for now." is the title (no line limit), and its icon is an outlined tick in Ink that draws itself once as the page appears. Under it, in lead Pencil, what the session did in desktop's timebox wording ("12 cards studied in 8 minutes."). Then desktop's congratulations notes from the backend (learning cards still due later today, limits reached), then Back to Deck (Back to Today when the session started there; Return, the page's one primary) with Custom Study… (C) and Unbury as chips, and last, behind a hairline, the deck's description when its Markdown option is on, as desktop shows it.
- **The study card:** upstream's reviewer in a web view straight on Canvas Paper, up to 860px wide, with no box, border or radius, as desktop draws none. The question reads as text on the desk, with only Show Answer below it. Its contents are styled by the note type, never by the app; a note type's own background fills the column.

### Navigation
- **Sidebar:** Sidebar Linen. At the top, the "places": Today (Anki star, total due), then Browse and Statistics with coloured SF Symbols and their single-key shortcuts in KeyCaps, so they can't be read as counts. Statistics is selectable like Today, and the arrow keys step through Today, Statistics and the decks; Browse opens its window and is never selected. Below them sits the deck tree in 30px rows with a 7px radius and a selection wash for the selected row. Every deck, top-level or not, is the same row; a deck with subdecks has a disclosure arrow, and top-level decks with subdecks are set apart by 12px of space, never drawn as headings, since they can be selected and studied. Then a footer behind a hairline with New Deck on the left and, on the right, Collapse All / Expand All and Sync. Collapse All / Expand All is one icon-only button, two stacked chevrons drawn like Obsidian's: they point toward each other (Collapse All) while any deck is open and apart (Expand All) once all are folded, and they flatten and turn over as they switch. Folding everything moves a hidden selection up to its top-level deck. When something is waiting to sync, Sync carries a 7px accent dot at its top-right, and its tooltip and VoiceOver label say what ("Sync: changes are waiting"); when a one-way sync is needed its arrows also gain an exclamation mark, so the two states differ in shape, not only in words.
- **Deck list row:** 50px, deck ring, name and optional path, the queue counts, and an accent play button that appears only on hover. The row itself is a button that opens the deck: it takes keyboard focus (with the system's keyboard navigation, as buttons do), shows a 2px accent ring when focused, and Space opens it. VoiceOver reads it as one element (name, path, counts) with Study as an action; the hover-only play button is hidden from VoiceOver and skipped by Tab. The row's content keeps to the page's edge; its hover wash (10px radius) reaches 12px past it on both sides, as in Things, so the ring and counts line up with the title and the due summary.

- **Quick Find** (`QuickFind`, / or Command-F): a 400px Liquid Glass panel (20px radius, lightly tinted toward the canvas) over the top of the window, with a field and one-line rows. Before anything is typed it lists Today and the first six decks Today would study; typing narrows every deck as desktop's Study Deck does, then adds matching notes and, behind hairlines, New Deck and Continue Search in Browser. A deck's path follows its name on the same line in Faded Pencil, losing its start first. The selected row is an accent fill; on a deck it shows "Study" and a ⌘↩ KeyCap in place of its count, since Return opens the deck and Command-Return studies it. The choice follows the arrow keys and the moving pointer.

### Statistics
A page in the main window's detail area, like Today and the overview: the sidebar's Statistics row (T, or the Study menu) selects it, shown in semibold with its violet chart icon and the T KeyCap. It has the main window's Canvas Paper and the same side margins as the other pages (56px, 18px in a narrow window), and the window's toolbar holds nothing for it. The page names itself with a Display "Statistics" title and the violet chart icon. Above the title, an eyebrow shows what the graphs cover: the current deck's path, "collection", or the search. The controls sit at the title row's trailing edge and wrap under the title when the page is narrow, as Study Now does on Today: the scope (Deck / Collection / Search), the history as a chip with a menu, and Save PDF as a quiet icon, then a small spinner that keeps its room while hidden, last so it never pushes the controls in. In the Deck scope the eyebrow itself is the deck menu: the path with a small chevron, a hover wash reaching past it, opening the deck tree as nested menus (a deck with subdecks is a submenu that starts with the deck itself). Picking one makes it current, since a deck picked in the sidebar opens its overview. The Search scope shows a search field under the header, which takes the focus. The scope and every graph's switches are quiet segments, not system segmented controls: words in Pencil, the chosen one in Ink on the selection wash, chip-sized (28px), so a page of a dozen switches holds no accent blue. Desktop's graphs use the full page width, in one to three columns (each at least 440px, 32px gaps). Each graph sits unboxed under a hairline: a 17px semibold title, the subtitle in Pencil, its switches on one line (stacked when narrow), then the chart and its table (labels in Pencil, values in Ink). Every axis, figure and tooltip uses the rounded face. Bars use the queue colours: review green for future due, mature and young (young lighter); learning coral for relearning and learning (learning lighter); new blue for intervals, added, hours and the calendar. Answer Buttons use the grade colours. Ease, difficulty and retrievability keep desktop's red-to-green scale. Shades are mixed into the canvas so they stay opaque, and an empty calendar day is the selection wash. A running total is shaded behind the bars in the hover wash, the lightest there is, since it often covers most of the plot; the bar under the pointer gets a selection-wash column drawn over it, and its tooltip stays inside the plot, clear of the axis labels. Today's sentences keep upstream's wording with their numbers in the rounded face. The day under the pointer is outlined in Ink and shows its date and reviews in the charts' tooltip at once. A narrow page scrolls the calendar rather than shrinking its days below 9px. Up and Down scroll the page once it has been clicked, as on the other pages. VoiceOver reads each chart as one element with its bars (Audio Graphs included).

### Deck Ring (signature)
A deck's icon is a ring that fills like a pie as today's cards are answered. Its track is always a faint neutral hairline (the selection wash); only the filled arc carries colour, coral while cards in learning are waiting, accent blue when selected, and Pencil otherwise, so an untouched deck never reads as an unchecked to-do. The pie is a solid wedge from twelve o'clock, inset from the track. It fills from empty as the ring appears, then smoothly as progress changes; only the fill animates, never the ring's position.

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
