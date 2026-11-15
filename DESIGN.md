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
    rounded: "{rounded.pill}"
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

The main window is the reference. Statistics is a page of the main window (see Statistics below). The note editor shared by Add Cards, the Browser and the study Edit sheet is drawn in the same quiet controls (see Note editor below). The Browser is on this system too, in a denser form (see Browser below), and so are the Add window (see Add Cards below), Deck Options (see Deck Options below), the Settings window (see Settings below), the profile list (see Profiles below), the text import sheet (see Text import below), the main window's and the study screen's sheets (see Sheets below) and the Browser's Preview (see Preview below). The other utility windows (the template editors, the FSRS simulator) still use system controls and desktop's colours. They move onto this system gradually, without losing their density.

**Key Characteristics:**
- Warm paper neutrals; one blue accent; queue colours as information, never decoration.
- SF Pro for words, SF Pro Rounded with tabular figures for every number.
- Flat tonal layers with hairlines; glass only for things that float above them.
- Quiet controls that brighten on hover; one prominent action per page at most.
- Every study action shows its key (KeyCap) and works from the keyboard.

## Colors

Warm, low-chroma paper and ink, punctuated by one saturated blue and Anki's three queue colours.

### Primary
- **Electric Pen Blue** (accent-blue): the one prominent action on a page (Study Now), the play button on a hovered deck row, the selected deck's ring, and the window's tint. Its rarity is what makes it findable. Dark mode keeps it as deep (#2E6AF5) rather than lifting it, so a white label on it stays at 4.5:1 or better and it never reads as Queue New Blue.

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
- **Browser row** (regular 400, 13px; counts and dates in the rounded face, medium 500, 12.5px, tabular): sidebar and table rows in the Browser, with column titles in the Eyebrow's face without capitals.
- **Button** (semibold 600, 14px), **Chip** (medium 500, 12.5px), **KeyCap** (rounded semibold 600, 10.5px).

### Named Rules
**The Rounded Numbers Rule.** Every count, interval and statistic uses the rounded face with tabular digits; words never do.

**The Small Capitals Rule.** Uppercase appears only in eyebrows, small and tracked. Titles and buttons are sentence or title case from upstream's wording.

## Layout

- **Main window:** a 248px sidebar beside the content. As in Things 3, showing or hiding it grows or shrinks the window from its right edge, and the page keeps its width and slides across over the sidebar, which stays put; only in full screen, or with no room left on screen, does it push the page aside. Narrowing the window by hand only narrows the page: a docked sidebar stays until it is hidden, and the window can't get narrower than the sidebar plus the 360px minimum. Shown in a window under 720px that can't widen, the sidebar floats over the content behind a 30% black scrim and closes once something is picked. A page narrower than 472px is compact: type shrinks, margins tighten, and rows drop to a single total count. The minimum window is 360 × 340, small enough to study in a corner of the screen.
- **Full screen:** the toolbar hides with the menu bar, in the main window and the Browser alike, and each window draws its own controls in a 52px band at its top. The bar that comes down with the menu bar is see-through and holds only the traffic lights, in a Liquid Glass pill (30px tall, 9px past the lights at each side), so they read over the sidebar or the page under them. AppKit puts that bar in a window of its own (`NSToolbarFullScreenWindow`) and paints an opaque grey behind it from a layer the view tree doesn't show: the content view's `opaqueBackstopLayer`, switched by `needsOpaqueBackstop`. Clearing the title bar, the toolbar's background or the window's colour leaves that grey in place; `FullScreenTitlebar` (Design.swift) turns the switch off and hides the layer each time the bar's window updates, since AppKit restores both as the bar comes down.
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

Liquid Glass and materials are for things that float over the flat desk: the study toast (a capsule of regular material over the card), popovers, menus, sheets and future floating panels such as a quick-find palette. Toolbar buttons are drawn plainly, without the toolbar's glass capsule, so the title bar stays part of the page. A toolbar holds only what has no other place: every page's starts with Quick Find (a magnifying glass), and the overview adds Add Cards (Options is a chip on the page; Browse and Statistics are sidebar places), and Statistics' controls sit on its page.

### Named Rules
**The Flat Desk Rule.** A surface that stays put is flat and toned; only what floats above it gets glass or a shadow.

**The Glass Is Rare Rule.** Glass marks something transient or overlaid. If glass appears on every surface it stops meaning "above", so don't put it on the sidebar, panels or rows.

## Shapes

Gently rounded throughout, with radius growing with the size of the element: 4px key caps, 7px sidebar rows and quiet buttons, 10px list rows, 11px grade buttons, 12px panels. The study card has no shape of its own. The primary button, chips and toasts are full capsules, so a page's actions share one shape. Panels carry a 1px hairline border inside their edge. Icons are SF Symbols, plus two drawn shapes: the Anki star (an outlined, plump-pointed star tilted -14°) and the deck ring.

### App icon

`App/AnkiMac/AnkiMac.icon`, an Icon Composer document. Anki's star so large it doesn't fit: drawn at 1.1 and moved right and down, its left point stays on the tile while the others run off it, so the icon is one cropped shape and not a small logo on a square. The star is two glass layers, the blue (`blu.svg`, in Icon Composer's automatic fill) inside its white outline (`whoute.svg`), over a tile that goes from black at the top to dark grey (`bg.svg`). Both star layers share one scale and translation in icon.json; move them together.

## Components

### Buttons
- **Primary** (`PrimaryButtonStyle`): a capsule of Liquid Glass tinted Electric Pen Blue, which answers the press itself, white 14px semibold label, 36px tall, 16px side padding. Its key follows the label as the bare glyph at 65%, with no box of its own inside the button's. Muted, while the action would only explain why it can't be done (Add with the first field empty, or a cloze where it can't go), the glass loses its tint and the label turns Pencil; it stays clickable, and the click or ⌘↩ shows desktop's reason. One per page. Study Now sits in the study bar at the bottom of the window (`studyBar`); elsewhere the primary leads the page's action row (`ActionRow`), with the chips after it, and when they don't fit on one line the chips go under it together, and only then one to a line, so the primary never moves. In a window's band (Add) it is compact: 28px tall like the controls beside it, 13px label, 12px side padding.
- **Chip** (`ChipButtonStyle`): Raised Oat capsule with a hairline border, 12.5px medium ink label, 28px tall. Hover wash under the pointer, selection wash when pressed, 40% when disabled. Used for a page's secondary actions.
- **Quiet** (`QuietButtonStyle`, `IconButton`): no fill at rest, Pencil foreground. On hover the foreground brightens to Ink with a hover wash; pressed shows the selection wash. Disabled drops to 40% opacity. Used for toolbar icons (30 × 28) and the sidebar footer.

### Grade Buttons (signature)
Again / Hard / Good / Easy (`GradeButtonStyle`). At rest each is a neutral hover wash with its label in the grade colour; the grade colour fills in only on hover (12%) and when pressed (22%), so the four read as one quiet row. Its number key follows the label in a KeyCap, and the next interval sits underneath in a rounded caption. They share the bar evenly up to 140px each and are 58px tall (48px compact). Good is the one outlined (1.5px, its colour at 55%), because it's the most common answer. Show Answer uses the same style in Ink, 38px tall and as wide as its label and Space KeyCap, but with no wash or hairline at rest: the wash appears only under the pointer, so during the question the card is the only shape on the canvas.

### Cards / Containers
- **Due summary** (`DueSummary`): unboxed, straight on the canvas. A 44px rounded numeral with "due" beside it in Pencil, and under it one line of queue counts ("12 new  3 learning  185 to review") with each number in its queue colour; a zero fades both the number and its word to Faded Pencil. Study Now (Return) is not on the page: it sits centred at the bottom of the window, in the answer bar's place and size (58px with 18px above and below, 48px and 10px compact), so Show Answer comes up where it was clicked. The page scrolls under it on the canvas. The overview's chips follow the counts 12px under them, ahead of its subdecks. With nothing due, the overview shows upstream's "Congratulations! You have finished this deck for now." as a headline, as desktop's overview does, and Today a single lead line: when learning cards come back later today, upstream's "The next learning card will be ready in 5 minutes. There are 3 learning cards due later today." (kept current each minute, and the counts refresh when that card comes due), otherwise "Nothing is due. Come back tomorrow."
- **Today's list:** under the due summary, an upstream "Due" section lists each deck without subdecks that has cards due, learning first. The total comes from the top-level decks and follows their limits, so when the rows add up to more, a caption under them says so. The eyebrow greets by time of day and gives the date, redrawn each minute so it follows midnight.
- **Session end** (`SessionFinished`): a page in the same column as Today and the overview, over the card. The deck's path is the eyebrow, upstream's whole "Congratulations! You have finished this deck for now." is the title (no line limit), and its icon is an outlined tick in Ink that draws itself once as the page appears. Under it, in lead Pencil, what the session did in desktop's timebox wording ("12 cards studied in 8 minutes."). Then desktop's congratulations notes from the backend (learning cards still due later today, limits reached), then Back to Deck (Back to Today when the session started there; Return, the page's one primary) with Custom Study… (C) and Unbury as chips, and last, behind a hairline, the deck's description when its Markdown option is on, as desktop shows it.
- **The study card:** upstream's reviewer in a web view straight on Canvas Paper, up to 860px wide, with no box, border or radius, as desktop draws none. The question reads as text on the desk, with only Show Answer below it. Its contents are styled by the note type, never by the app; a note type's own background fills the column.

### Navigation
- **Sidebar:** Sidebar Linen. At the top, the "places": Today (Anki star, total due), then Browse and Statistics with coloured SF Symbols and their single-key shortcuts in KeyCaps, so they can't be read as counts. Statistics is selectable like Today, and the arrow keys step through Today, Statistics and the decks; Browse opens its window and is never selected. Below them sits the deck tree in 30px rows with a 7px radius and a selection wash for the selected row. Every deck, top-level or not, is the same row; a deck with subdecks has a disclosure arrow, and top-level decks with subdecks are set apart by 12px of space, never drawn as headings, since they can be selected and studied. Then a footer behind a hairline with New Deck on the left and, on the right, Collapse All / Expand All and Sync. Collapse All / Expand All is one icon-only button, two stacked chevrons drawn like Obsidian's: they point toward each other (Collapse All) while any deck is open and apart (Expand All) once all are folded, and they flatten and turn over as they switch. Folding everything moves a hidden selection up to its top-level deck. When something is waiting to sync, Sync carries a 7px accent dot at its top-right, and its tooltip and VoiceOver label say what ("Sync: changes are waiting"); when a one-way sync is needed its arrows also gain an exclamation mark, so the two states differ in shape, not only in words.
- **Deck list row:** 50px, deck ring, name and optional path, the queue counts, and an accent play button that takes the counts' place only on hover, so at rest the counts keep to the page's edge, under the title row's action. The row itself is a button that opens the deck: it takes keyboard focus (with the system's keyboard navigation, as buttons do), shows a 2px accent ring when focused, and Space opens it. VoiceOver reads it as one element (name, path, counts) with Study as an action; the hover-only play button is hidden from VoiceOver and skipped by Tab. The row's content keeps to the page's edge; its hover wash (10px radius) reaches 12px past it on both sides, as in Things, so the ring and counts line up with the title and the due summary.

- **Quick Find** (`QuickFind`, / or Command-F): a 400px Liquid Glass panel (20px radius, lightly tinted toward the canvas) over the top of the window, with a field and one-line rows. Before anything is typed it lists Today and the first six decks Today would study; typing narrows every deck as desktop's Study Deck does, then adds matching notes and, behind hairlines, New Deck and Continue Search in Browser. A deck's path follows its name on the same line in Faded Pencil, losing its start first. The selected row is an accent fill; on a deck it shows "Study" and a ⌘↩ KeyCap in place of its count, since Return opens the deck and Command-Return studies it. The choice follows the arrow keys and the moving pointer.

### Statistics
A page in the main window's detail area, like Today and the overview: the sidebar's Statistics row (T, or the Study menu) selects it, shown in semibold with its violet chart icon and the T KeyCap. It has the main window's Canvas Paper and the same side margins as the other pages (56px, 18px in a narrow window), and the window's toolbar holds only Quick Find for it. Unlike them it is not held to the 680px reading column: in a wide window its graphs spread into columns, so its title stays at the margin while Today's and the overview's move to their centred column. That's on purpose; a dashboard earns the width. The page names itself with a Display "Statistics" title and the violet chart icon (set at 20px, since it is wider than tall). Every page title's icon sits in one 26px slot, centred, so the title's first letter starts at the same place on every page. Above the title, an eyebrow shows what the graphs cover: the current deck's path or the search. The Collection scope has none, since its segment already says so, but the eyebrow's line keeps its height so the title never moves as the scope changes. The controls sit at the title row's trailing edge and wrap under the title when the page is narrow, as Study Now does on Today: the scope (Deck / Collection / Search), the history as a chip with a menu, and Save PDF as a quiet icon, which a small spinner replaces while the graphs reload, so the controls reach the page's edge and nothing moves. When quiet segments start a line, they are pulled out by their padding so the first word lines up with the text above, and the chosen one's wash reaches past the edge, as a list row's does. In the Deck scope the eyebrow itself is the deck menu: the path with a small chevron, a hover wash reaching past it, opening the deck tree as nested menus (a deck with subdecks is a submenu that starts with the deck itself). Picking one makes it current, since a deck picked in the sidebar opens its overview. The Search scope shows a search field under the header, which takes the focus. The scope and every graph's switches are quiet segments, not system segmented controls: words in Pencil, the chosen one in Ink on the selection wash, chip-sized (28px), so a page of a dozen switches holds no accent blue. Easy Days is a row per weekday like any other, its slider 220px wide where the others' controls sit, under a caption line naming the three stops (Minimum, Reduced, Normal) over the sliders' column. Desktop's graphs use the full page width, in one to three columns (each at least 440px, 32px gaps). Each graph sits unboxed under a hairline: a 17px semibold title, the subtitle in Pencil, its switches on one line (stacked when narrow), then the chart and its table (labels in Pencil, values in Ink). Every axis, figure and tooltip uses the rounded face. Bars use the queue colours: review green for future due, mature and young (young lighter); learning coral for relearning and learning (learning lighter); new blue for intervals, added, hours and the calendar. Answer Buttons use the grade colours. Ease, difficulty and retrievability keep desktop's red-to-green scale. Shades are mixed into the canvas so they stay opaque, and an empty calendar day is the selection wash. A running total is shaded behind the bars in the hover wash, the lightest there is, since it often covers most of the plot; the bar under the pointer gets a selection-wash column drawn over it, and its tooltip stays inside the plot, clear of the axis labels. Today's sentences keep upstream's wording with their numbers in the rounded face. The day under the pointer is outlined in Ink and shows its date and reviews in the charts' tooltip at once. A narrow page scrolls the calendar rather than shrinking its days below 9px. Up and Down scroll the page once it has been clicked, as on the other pages. VoiceOver reads each chart as one element with its bars (Audio Graphs included).

### Note editor
The editor shared by Add Cards, the Browser's side panel and the study Edit sheet (`NoteEditorView`) has no boxes of its own. Its format bar is one row of quiet icon buttons (`QuietButtonStyle`, 13px medium glyphs in 26 × 24 hit areas, 2px apart) that wraps in a narrow pane. Groups of buttons are told apart by 1 × 14px hairlines, not frames: Cards… (a quiet chip-font label), bold, italic, underline and strikethrough, superscript and subscript, text and highlight colour, remove formatting, then cloze, attach, record and equations. The two colour buttons apply the last colour, which shows as a 3px bar under the glyph, as in Pages; a tiny chevron beside each opens the system colour panel for that kind. Under the bar a hairline, not a divider.

**Audio.** A `[sound:]` tag in a field is a small player, as an audio message is in Messages: a pill in a tag chip's Raised Oat and hairline at a control's 28px, with an Ink play glyph, the file's waveform as thirty 2px bars against its loudest stretch, and its length in rounded tabular figures. At rest the bars are Pencil; while it plays the glyph is pause, the part played is Ink, the rest Faded Pencil, and the length counts up. A click plays or pauses; a drag or a sideways swipe along the waveform moves through the sound, as in Messages, and never a click; one sound plays at a time. The player is one character, centred on the capitals of the text around it: Delete removes the tag, and the field's HTML still shows it as written. Until the file is read the bars are a row of dots. A file that isn't in the media folder is a 22px pill with a Pencil speaker and its name in the chip font, a long name cut in its middle. The recording sheet (Record Audio here, Record Own Voice in study) is 320px of Canvas Paper: a Learning Coral microphone that breathes while recording (still under Reduce Motion), upstream's "Recording..." as a Headline, its time in rounded tabular figures at the trailing edge, and under them a 44px level meter, a 2px Coral bar per twentieth of a second with the newest at the trailing edge, so speech moves across it and silence is a row of dots. Its buttons sit at the trailing edge as a dialog's do, Cancel a chip and Save the compact primary with its Return key. On a card a sound with a file is the same player a size up (36px, 20px bars, a 13px length), drawn by the card's page inside upstream's `.replay-button`, with the same click, drag and swipe; it follows the audio wherever it was started from (autoplay, R, the player) and never sets `display`, so a note type that hides play buttons still hides it. Speech and a sound whose file is missing keep upstream's play button, which keeps its 40px but is drawn quietly: a Raised Oat disc with a faint edge and a soft-cornered Pencil triangle that turns Ink under the pointer, dips when pressed, and takes a 2px accent ring from the keyboard. Its rules are no more specific than upstream's, so a note type that styles `.replay-button` still wins.

Fields are unboxed rows under hairlines, 8px of space above and below each, with 12px at the sides. A field's label is a chevron and its name in 12px medium Pencil, which steps to Ink while that field has focus; its sticky pin and Show HTML switches sit quietly at the trailing edge, and show Ink on the selection wash while on (`QuietButtonStyle(selected:)`). The text has no fill at rest and the hover wash, in a 7px radius, under the pointer. A duplicate keeps desktop's red tint as its fill. The HTML source is the same unboxed block with the hover wash always on, so code reads as a block. Image Occlusion's Mask and Note tabs are quiet segments (`QuietSegments`, as Statistics' switches are). The tags below are a tag symbol and a borderless field (`TagField`), as Things': each tag a chip (Raised Oat capsule under a hairline, 12.5px medium Ink, 22px tall), then the text being typed. Space, comma, Return or Tab ends a tag; Delete on empty text selects the last chip in accent blue, and again removes it; double-clicking a chip takes it back to edit. As you type, matching tags float in a Liquid Glass list (14px radius, tinted toward the canvas, in a window of its own so it can pass the editor's edge) under the text, or over it when the screen ends below: a tag symbol and the name in 28px rows, the highlighted one an accent fill, and behind a hairline "New Tag “…”" for the text as typed. The arrow keys and the pointer move the highlight; Return or Tab takes it, Escape closes the list.

### Add Cards

Add stays its own window, as desktop's, so it can sit beside a source or the Browser and open over a study session; it asks before closing over unsaved input. Its chrome is the Browser's: Canvas Paper from the top edge, an empty toolbar only so the traffic lights sit centred in a 52px band, and the controls drawn plainly in that band, which drags the window. After the traffic lights, the note type and the deck are quiet menus: the name in Pencil ("Type", "Deck"), the choice in Ink, a small up-down chevron, all 12.5px medium, with the hover wash under the pointer. The deck menu opens the tree as nested menus, as Statistics' does, holding only decks a note can go to (no filtered decks), and the path reads "M1 › FSGBD", losing its start first when the window is narrow. At the trailing edge, History is a quiet clock icon whose menu lists the notes added, and Add is the window's one Primary button, compact, with a ⌘↩ KeyCap on it, 12px from the window's edge. The note editor follows straight under the band, then a hairline and the tags. "Added" shows for a moment in a Liquid Glass capsule near the bottom, as the main window's notices. In full screen the toolbar hides with the menu bar and the band keeps the controls, starting at the margin since the lights come down in their own pill.

### Deck Options

Deck Options stays its own window per deck, as desktop's, and asks before closing over unsaved changes. Its chrome is Add's: Canvas Paper from the top edge, an empty toolbar only so the traffic lights sit centred in a 52px band, and the controls drawn plainly in that band, which drags the window. After the traffic lights, the deck's path (15px semibold, "M1 › FSGBD", losing its start first); at the trailing edge, the preset as a quiet menu ("Preset" in Pencil, its name in Ink, the up-down chevron) and Save, the window's one Primary button, compact, with ⌘S on it. The preset menu lists every preset with how many decks use it, then desktop's gear commands (Add, Clone, Rename, Remove Preset…, then Save to All Subdecks), so the band holds one menu, not a picker and a gear.

The settings follow in desktop's section order, in one column capped at 620px with 24px margins, 32px between sections. Each section is named by an eyebrow, with a quiet help icon at its end that opens desktop's help for every setting in a popover. Its rows sit unboxed under hairlines, 40px tall whatever their control (a quiet menu, the tallest, fills one with 4px to spare above and below), growing only when a title wraps: the title in 13.5px Ink (its tooltip as a help tag), and at the trailing edge the control, then a quiet restore arrow in Pencil, which keeps its place while hidden so controls don't shift as values change. A note or a setting's actions under a row (desktop's alerts, the Preset / This deck / Today only switch, Help Me Decide) belongs to it, so no hairline comes between them. Controls are quiet: choices are quiet menus as Add's, their hover room hanging past the trailing edge so the chevron ends where a field or a switch does; numbers, learning steps and the FSRS search are typed into a 24px Raised Oat box under a hairline, deepened by the selection wash while focused (no field has an accent ring: the caret shows where typing goes) and figures in the rounded face, numbers keeping a small stepper; the limit scopes are quiet segments under the title, pulled out by their padding so the first word lines up with it; switches and sliders are small and tinted Pencil, so a page of a dozen switches holds no accent blue. Easy Days is a row per weekday like any other, its slider 220px wide where the others' controls sit, under a caption line naming the three stops (Minimum, Reduced, Normal) over the sliders' column. A globe in Pencil marks a setting that affects the whole collection; it is the only sign of that reach, so it doesn't fade to Faded Pencil. Desktop's alerts are caption lines in Pencil whose icon carries the level: Pencil for information, ochre for a warning, red for danger. The FSRS actions (Optimize, Evaluate, Optimize All Presets, the simulator) are chips. Custom scheduling's code is an unboxed block with the hover wash always on, as the editor's HTML source; while it's empty a sample script shows in Faded Pencil, so it's clear the box takes JavaScript, and under it desktop's warning sits as a caption with the manual's chapter linked. Once the settings scroll under the band, a hairline appears at its foot to mark where they go out of sight. In full screen the toolbar hides with the menu bar and the band keeps the controls.

### Settings

The Settings window (⌘,) keeps the Mac's shape: desktop's tabs are the toolbar's panes (Review, Editing, Syncing, Backups, in desktop's names and order), and the window takes each pane's height, up to the screen's less the title bar and tabs; a taller pane scrolls rather than running off the screen. Under the tabs the window is Canvas Paper, and each pane is drawn as Deck Options' settings are: a 560px column with 24px margins and 20px under the tabs, sections named by eyebrows 32px apart, rows of 40px under hairlines, the title in 13.5px Ink and the control at the trailing edge. A setting here has no restore arrow, since desktop's preferences have no defaults to go back to, so the controls keep to the edge. Numbers are typed in the quiet box with a small stepper, with desktop's unit after them in Pencil ("hours past midnight", "mins"); a section's units share the widest one's width, set from its leading edge, so the boxes start in one column; switches are small and tinted Pencil; the default deck is a quiet menu and the default search a quiet box. Desktop's explanations are caption lines: the answer keys' over their rows, the backups' over theirs, and the warning that media isn't backed up under them, with its ochre icon. Review ends with URL Schemes, typed in place in a quiet box rather than in desktop's prompt, then Answer keys: a row per rating, its key in a small centred box, empty for none; the answer buttons and the Study menu show the keys chosen. Syncing holds the profile's switches (media, sync on open and close, periodic media sync, and the one-way sync, which stays on and greyed once set, since it can't be taken back) and the network timeout in seconds, then the AnkiWeb account: desktop's introduction with Log In as a chip, or the user name with Log Out, then the self-hosted server in a quiet box with desktop's note under it. Logging in opens the sign-in sheet over Settings. Changes are saved as they are made, as Mac settings are, with no OK button; typed text (the default search, URL schemes, the server) is saved when typing ends, so each keystroke doesn't reload the decks. A pane whose settings aren't there keeps 120px and says why in a centred caption: a small spinner while they load, "Open a profile to change these settings." while no collection is open (a closed profile's values never stay on screen to be changed), or the failure with Try Again as a chip. VoiceOver reads each number with its unit ("4 hours past midnight").

### Profiles

While no profile is open, desktop's profile manager is a sheet on the main window, at launch and after Switch Profile alike, and the window behind it is dimmed, since with no profile open there's nothing in it to use; the window itself never hides or moves. The sheet is 480px wide on Canvas Paper and as tall as its page, which has 24px margins, a Display "Profiles" title with a person symbol in Pencil, and no way to dismiss it but opening a profile or quitting. A profile that fails to open says so on the sheet. Each profile is a 50px list row holding only the name in Ink, the title's symbol standing for them all, with the hover wash under the pointer and the selection wash on the chosen one, its wash reaching 12px past the page's edge as a deck row's does; a lone profile shows no selection, since there is nothing to choose. A click selects, a double click opens, Up and Down move the selection, Delete deletes after desktop's confirmation. Under the rows, the page's action row: Open (Return) as its one Primary, then Add (⌘N), Rename and, set a little apart, Delete as chips. A profile is named in its row, not in desktop's prompt, as a deck is renamed in the sidebar: Add puts an empty row at the end with "Name" in Faded Pencil, Rename turns the chosen row's name into the field, both under the selection wash. What's wrong with the name (taken, or a character a folder can't hold) shows under the row as it is typed, as Deck Options' alerts do, its icon red and its words Pencil. Return keeps the name, or beeps and keeps the typing while there's a problem; clicking away keeps it only if it can be used; Esc puts things back. While a name is typed, Open and the other buttons are off, so Return ends the typing. Behind a hairline, Open Backup… at the leading edge, and Downgrade & Quit and Quit together at the trailing edge, are quiet text buttons, since they are rarely needed; Downgrade & Quit's help tag says what it does.

### Text import

Importing a .csv, .tsv or .txt file is a 600 × 660px sheet on the main window, on Canvas Paper, drawn as Deck Options' settings. The file's name is its Headline at the top, losing its middle first; under it desktop's three sections (File, Import options, Field mapping) scroll in one column with 24px margins, each named by an eyebrow with the quiet help icon listing upstream's help for its settings. Rows are Deck Options': 40px under hairlines, the title in 13.5px Ink with its help tag, the control at the trailing edge, with no restore arrow since an import has no defaults to go back to. The separator, note type, existing notes and match scope are quiet menus. A field's column is one too, reading as a column rather than as a card: its index in the rounded face, semibold Ink, as the preview heads it, then what the column holds (its header, or its first value) in Pencil, losing its end at 320px so the field's name never wraps; the list itself keeps upstream's "1: …" titles; the deck is the tree as nested menus, as Add's, led by the deck the file names when the collection lacks it, with upstream's "will be created" note under the row as a caption. A note type or deck read from a column of the file is that column's name in Pencil, since there is nothing to choose. Allow HTML is a small Pencil switch. The two tag rows are tag fields (`TagField`) in the quiet box, deepening while focused as a typed field does, 280px wide, their chips wrapping inside it. The file's first rows sit in the File section as a dense table, as the Browser's: column titles in the Eyebrow's face without capitals, one hairline under them across the section's whole width, 26px rows of 13px Ink with no grid, each column at most 220px, scrolling sideways when the file is wide. The settings scroll between the name and the buttons, which stay on the canvas: no hairline and no blur marks the edge, as on the main window's pages. At the foot, a spinner with "Processing..." while the file is read again or imported, or a failure as a caption with its red icon; at the trailing edge Cancel as a chip and Import, the sheet's one Primary, compact, with its Return key.

### Sheets

Custom Study, a filtered deck's options, a deck's Description and the study screen's Set Due Date, Reset Card, Reposition and Edit are sheets on the main window, drawn as the text import sheet is (`SettingsSheet`): Canvas Paper, 24px margins, the title as a Headline (a deck's path over it as an eyebrow when the sheet belongs to one), Deck Options' rows under hairlines with no restore arrow, and at the foot what's happening or what failed as a caption with its red icon, then Cancel as a chip and the sheet's one Primary, compact, with its key (`DialogButtons`). A failure stays on the sheet, beside the buttons, so the criteria can be changed and tried again, and clears when they are. A sheet is as tall as its rows, growing and shrinking as they come and go; past its cap they scroll between the title and the buttons. Every title, row and button keeps desktop's words.

**Custom Study** (560px wide, as the filtered deck's and the description's, up to 600px) lists desktop's six choices as rows (`ChoiceRow`): the title in Ink and the hover wash under the pointer on the others, reaching a little past the text. The chosen row holds its number at its trailing edge, where a Mac settings list puts its check: the quiet number box with its stepper and the unit after it in Pencil ("days"). The title already says what the number is, so desktop's sentence ("Review ahead by") is only the box's VoiceOver label, never a line repeating the title. The box takes the focus as it appears, so Up and Down move the choice from there, as in Quick Find. Under the row, with no hairline, what's available as a caption, and for Study by card state or tag, the kind of cards as a quiet menu. For that choice, Selective Study follows under its eyebrow: desktop's two tag lists are two tag fields in the quiet box (Require one or more of these tags, Select tags to exclude), completing from the deck's tags. The primary is Study, or OK for a limit, which stays off while the limit would rise by nothing.

**Filtered deck** (560px wide, up to 660px) is titled "Options for …" with the deck's name as it opened. The name is a quiet box, as wide as the search field and its button together so both start in one column; the Filter section holds the search in the Browser's search field (`BrowserSearchField`, through `SearchFieldSource`), its filters as chips and the same suggestions, written to the deck as it's typed since Return builds rather than searches, with a quiet arrow out of a window that shows it in the Browser, Limit to as a number, the order as a quiet menu, and Show any excluded cards as a chip under them; Filter 2 starts with its switch and shows the same rows once on; Options holds rescheduling, the three delays as numbers with "seconds" after them and the zero hint as a caption, and Create/update this deck even if empty. The primary is Build, or Rebuild for an existing deck, with a small spinner beside it while it builds.

**Description** has the deck's path over "Description", Interpret as Markdown as a small switch with upstream's three-line hint as its title's help tag, as a Deck Options setting's tooltip is, so the text block leads the sheet, then 8px under that row the text as an unboxed 240px block with the hover wash always on, as the editor's HTML source, which takes the focus. Return starts a new line there, so Save takes ⌘↩, shown on it.

**The study prompts** are 420px wide, and the Browser asks the same three about its selection on the same sheets, the due date's title counting the cards. Set Due Date has a 120px quiet box for the days in rounded figures, in a row under a hairline as the other prompts' rows are, then upstream's examples as a small table, what to type in rounded semibold Ink beside what it does in Pencil. Reset Card is its two switches. Reposition New Cards puts the queue's top and bottom in a caption, then Start position and Step as numbers and its two switches; it is offered only while a new card is shown, in the Cards menu as in the study screen's. Each prompt closes once its change is made, so a failure (a due date that can't be read) stays beside its buttons. **Edit** is the note editor on the canvas, as in Add, a hairline, the tags, then Cancel and Save with ⌘↩.

### Browser
The Browser stays its own window, but its chrome is the main window's, set closer together because it is the densest one. The window is Canvas Paper, with the table's header and rows straight on it. The sidebar on the left is Sidebar Linen, flat and with no vibrancy, and the editor on the right is the canvas. A 1px hairline, not the system's grey, divides the three panes. It has no toolbar items, since each would sit in its own glass capsule: an empty toolbar only keeps the traffic lights centred in a 52px band, and the controls are drawn plainly in that band, as a pane's header in Rex. Over the sidebar, the sidebar button sits beside the traffic lights. Over the table, "Browse" (15px semibold) sits on the table's text edge with the count under it in caption Pencil ("18 of 195 notes selected", or a change's message for a moment), then at the trailing edge the Cards and Notes switch as quiet segments (`QuietSegments`) and the search field. Preview and the editor's button, as quiet icons, sit at the window's top trailing corner, where the main window keeps its buttons: in the editor's band while the editor is shown, and at the end of the table's once it is hidden. The editor's format bar is 28px here, as tall as the column titles, so one hairline runs under both. While the sidebar is hidden its button moves into the table's band, in the same place. In a narrow pane the count under "Browse" loses its end before the search field shrinks away. A search error sits over the table as a flat Raised Oat bar under a hairline, with its warning triangle in colour.

The search field (`BrowserSearchField`) reads as Mail's, not as upstream's query text. What a sidebar row stands for (a deck, a tag, a note type, a card state, a flag) shows as a chip: 20px, Raised Oat under a hairline, the sidebar's icon in its colour, then the name (a deck or tag by its whole path, "L3 › S6", losing its start first) and a small × that removes it. The rest of the search stays as typed after the chips, and the chips scroll with it when there are too many, fading out over 12px under the magnifier. A search with a top-level OR, or a filter that names no one row (`deck:Spa*`), stays text; `deck:*`, every deck, shows as an empty field. The field is a 28px capsule in the hover wash, deepening to the selection wash while focused, with no accent ring: it has the focus nearly always. Typing lists what the word being typed could mean in a Liquid Glass panel under the field, as the tag field's list: "Search for" the text first, then decks, tags, note types, card states, flags and saved searches whose names match, under eyebrows, a deck or tag's parents after its name in Faded Pencil. A name that starts with the word comes first. `deck:`, `tag:`, `note:`, `is:` or `flag:` before the word keeps the list to that kind, and Down Arrow opens it with nothing typed. After `is:` only a name or search keyword that starts with the word is listed (`is:l` finds Learning), and the card states are joined by keywords no sidebar row stands for, such as Due (`is:due`), which stay text once picked. Picking a row turns the word into a chip and searches at once; Return on "Search for" searches for the text. Delete on empty text selects the last chip, in the accent, and again removes it; Esc closes the list, then takes back what was typed.

The sidebar's rows are 26px, with 13px labels in Ink, 14px icons in Pencil and 14px of indent per level. Flags keep their flag colours. Section names are eyebrows, 11px semibold capitals in Pencil with 12px of extra space above all but the first, and they can't be selected. They start 16px in, with no triangle in the margin: clicking one folds it, and under the pointer a chevron at its end shows whether it is open, as in Finder. A folded section keeps its chevron, and a section with no rows never shows one, so the two can be told apart; an empty Saved Searches stays, since its menu is where a search is saved. From the keyboard, Left Arrow on a section's own row, once it has nothing open under it, folds the section, and Right Arrow opens it again with that row selected. The rows of a flat section (Card State, Flags, Note Types) start on their name's edge. Only a section with rows that fold (Decks, nested Tags) steps its rows in by one 14px level, as the main sidebar's deck tree does, and there a deck's triangle sits inside the wash, before its icon. Decks keep a plain stack symbol in Pencil, not the main sidebar's ring: a ring shows the day's progress, which a filter has nothing to say about. New, Learning and Review take their queue colours. The selected row is the selection wash in a 7px radius, kept 8px in from the pane's edges, with its label in semibold and still Ink. Under the pointer a row shows the hover wash. Renaming in place keeps the row's place and sets the name over the canvas. What is open (sections, decks, tags) is remembered for the next time the Browser opens.

The table's rows are 26px with 13px Ink text 12px from the pane's edge, with no stripes and no grid lines, vertical or horizontal. The selection is the same wash, in the same shape, and it doesn't change when the table loses focus. Adjacent selected rows join into one block. A flagged, marked, suspended or buried row keeps desktop's tint over the wash, in the wash's shape. Counts, intervals, dates and scheduling figures use the rounded face with tabular digits (12.5px medium), and keep to the column's trailing edge with their title, wherever upstream would centre them, so columns of them stay steady. Words never use it, even in such a column: Due's "New #198" and "(learning)" stay in the cell's face. The last column takes the width the others leave, so the table always reaches the editor. With several rows selected the editor's empty pane says how many ("18 Notes Selected"). A deck's path reads as the main window writes it, "M1 › FSGBD", not upstream's "M1::FSGBD". A card or note deleted since the search ran reads "(deleted)" in Pencil. The header is 28px, on the canvas, with column titles in 11px semibold Pencil in the case upstream gives them, the sort arrow beside the sorted one, and one hairline under it and no separators between columns.

**The dense rule.** A utility window whose job is many rows uses 26px rows, 13px text, hairlines in place of stripes or grids, and the selection wash in place of the system's blue bar. It keeps the main window's colours and quiet controls, and it still shows nothing that isn't needed.

### Preview
The Browser's Preview stays a window of its own, as desktop's, with Add's chrome: Canvas Paper from the top edge, an empty toolbar only so the traffic lights sit centred in a 52px band, and desktop's controls drawn plainly in that band, which drags the window. After the traffic lights, Back Side Only is a quiet text switch in the chip font led by a box (B). While on, the box fills with a check in Ink; there is no selection wash, which beside the check only looked hovered. Where the words don't fit, in a narrow window or a long translation, the box stands alone with the same help tag, so the steps never leave the band and the window can be as narrow as 300px. Replay Audio has no button, as on the study screen: R replays, and the card's own players play on a click. At the trailing edge, Previous Card and Next Card are quiet chevrons, faded while there is nowhere to go. Every help tag is the control's name over upstream's "Shortcut key: …" line, the name alone being what VoiceOver reads; the main window's and the study screen's icons follow the same form. The band's empty space is the title bar: dragging it moves the window, and a double click zooms or minimises it as set in Desktop & Dock, as on Add's and Deck Options' bands. The card follows straight under the band on the canvas, as on the study screen, with a marked note's star and the flag over it; there is no bottom bar, so nothing but the card sits below the band. In full screen the toolbar hides with the menu bar and the band keeps the controls.

### Deck Ring (signature)
A deck's icon is a ring that fills like a pie as today's cards are answered. Its track is always a faint neutral hairline (the selection wash); only the filled arc carries colour, coral while cards in learning are waiting, accent blue when selected, and Pencil otherwise, so an untouched deck never reads as an unchecked to-do. The pie is a solid wedge from twelve o'clock, inset from the track. It fills from empty as the ring appears, then smoothly as progress changes; only the fill animates, never the ring's position.

### KeyCap
The key's name in a small 4px-rounded box (rounded 10.5px semibold, hairline fill, Pencil text). On an accent fill it is the bare glyph in the label's font, white at 65%, so no box sits inside the button's or row's. It sits beside the action it triggers, and is hidden from accessibility and in compact windows.

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
