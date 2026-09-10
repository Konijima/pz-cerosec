# CeroSec rung 4 — manual test checklist

Build 42.20.4. What the headless benches cannot reach: the item as the game parses
it, the icon as the game draws it, the window as the eye sees it, and the book as it
actually turns up in the world.

`tests/manual_ui_test.lua` already covers the wrapping, the pagination, the
navigation, the bookmark on the item and the twelve loot lists. It covers all of that
against a **fake** font and a **fake** distribution table. Everything below is the
part where the real game gets a say. Turn `CeroSec.DEBUG = true` in
`42/media/lua/shared/CeroSec/CeroSecDefs.lua` for the console lines.

**The text is a separate file.** `42/media/lua/shared/CeroSec/CeroSecManual.lua`
holds the chapters and is written apart from the reader. If it is missing the book
still opens — a title leaf and an empty contents — which is itself worth one look
(step 6).

## Manual

### A — The item exists and the game parsed it

1. **No script errors on load.** Start a game with the mod on. The console
   (`~/Zomboid/console.txt`) has no `FileNotFoundException` and no script parse error
   naming `items_cerosec.txt`. A single bad key takes the **whole file** down, so a
   silent load is the whole of this check.
2. **It is in the item list.** Open the debug menu (or the admin panel) → **Items
   list**. Filter on `CeroSec`. `CeroSec.Manual` is there, its display category reads
   **Literature**, and its name reads **CeroSec OS User's Manual** — the name from
   `Translate/EN/ItemName.json`, not the `DisplayName` fallback and not the raw
   `Manual`.
3. **Spawn one.** Spawn it into the character's inventory. Weight 0.8, and the icon is
   the navy book with the little green screen on its cover — **not** the white
   question mark. A question mark means the texture did not resolve: check that the
   file is `common/media/textures/Item_CeroSecManual.png` exactly, since the game
   builds the name as `"Item_" .. Icon` and looks it up as
   `media/textures/<that>.png`.
4. **Drop it.** Drop the manual on the floor. There is a closed book model on the
   ground, it can be picked up again, and nothing is logged. (`WorldStaticModel`.)
5. **No vanilla read option.** Right-click the manual in the inventory. There is
   **"Read the manual"** and there is **no** vanilla "Read", no "Write", and no
   "Look at pictures". That is what `ItemType = base:normal` buys: a Literature item
   would offer vanilla's own read, which sits the character down for hours.

### B — Opening the book

**While `CeroSec.DEV_MANUAL_MENU` is on** you do not need a copy of the book for any
of section B, C or D's first three steps: right-click any computer and take the last
entry, **Read the CeroSec manual (dev)**. Do steps 18-22 with a real item, though —
they are about the bookmark on the item, which the door does not have.

6. **It opens.** Right-click → **Read the manual**. A window appears in the middle of
   the screen, titled with the book's own title. Two cream leaves side by side, a
   darker band down each inner edge where the paper curves into the gutter, page
   numbers at the outer foot of each leaf, and three buttons under the book: **< Back**,
   **Contents**, **Next >**.
7. **The character does nothing.** The survivor does not sit, does not play an
   animation, and the queue stays empty. Walk around with the book open — it stays
   open and the character walks. Open a door, chop a tree, get bitten: the book is
   still there. It is paper on the screen, not an action.
8. **Page 1 is the title leaf.** The book's title centred, a rule under it, the
   edition line under that in the dimmer ink. Page 2 is **Contents**.
9. **Nothing is off the paper.** Look along the right margin of every leaf you turn.
   No line of prose runs past the edge of the cream, and no word is cut in half by
   the paper's edge.
10. **Example lines look like the terminal.** A line that starts with two spaces is
    drawn in the terminal's monospaced font, dark green, on a faint band, and it is
    **not** wrapped. Compare one against the same command typed at a real CeroSec
    screen: same face, same column spacing.
11. **Font size.** Options → the UI font size, up one notch and back. With the book
    open the leaves re-lay themselves, the reader stays on the page he was on, and
    still nothing runs past the margin.

### C — Turning the leaves

12. **Buttons.** **Next >** turns one sheet: both leaves change, and the page numbers
    go up by two. **< Back** turns one back.
13. **Keys.** Right arrow does what **Next >** does; Left does what **< Back** does.
    They work with the mouse anywhere, including outside the window.
14. **The ends.** At the front, **< Back** and Left do nothing at all — no flicker, no
    blank spread. At the back, **Next >** and Right do nothing. The last spread is
    never half a sheet: if the book ran out on a left leaf, the right one is blank
    paper.
15. **Chapters open a leaf.** Turn through the whole book. Every chapter starts at the
    **top** of a leaf, with its title as the running head, and no chapter begins
    halfway down the page before it.
16. **Contents.** Press **Contents**. The rows highlight under the cursor. Click the
    third one: the book opens at the third chapter's **first** leaf, and the running
    head on that leaf is that chapter's title. Do it for every chapter and check the
    printed page number on the row against the number printed at the foot of the leaf
    it lands on — those are two different pieces of arithmetic and they have to agree.
17. **Escape closes.** Press Escape. The book shuts, and the key does **not** also
    open the game's own menu behind it.

### D — Page memory

18. **It reopens where it was left.** Turn to some spread in the middle. Close the
    book with Escape. Right-click → Read the manual: the same two leaves.
19. **Across a save.** Same again, then save and quit to the main menu, and load. The
    book still opens on the same spread — the bookmark rides on the item's modData,
    which is saved with the item.
20. **One bookmark per copy.** Spawn a second manual. Leave the first on chapter four
    and the second at the front. Each one opens where **it** was left.
21. **Two windows, one player.** With the book open, right-click the **other** copy
    and read it. The first window closes; there is one book open at a time.
22. **The book leaves your hands.** With the book open, drop it on the floor. The
    window shuts by itself.

### E — Finding one in the world

The weights are in `42/media/lua/server/CeroSec/CeroSecManualLoot.lua`, with the
vanilla numbers each one was set against.

23. **The lists were found.** With `CeroSec.DEBUG = true`, the console says
    `manual added to 12 distribution lists` once, on load. Anything less than 12 names
    a list vanilla has renamed — the missing one is logged by name right above it.
24. **It is really in the pool.** Debug menu → **Spawn rate checker** (LootZed), pick
    `LibraryComputer`. `CeroSec.Manual` is in the list at weight 4, sitting beside
    `Book_Computer` at 20 and 10.
25. **Find one in an office.** New game, walk into an office building, and loot every
    desk in it. This is the rarest placing on purpose (weight 1 against a pool of
    about seventy, four rolls a desk) so it will take a building or two — the point of
    the step is that it happens at all, and that the one you find reads and turns
    exactly like the one you spawned.
26. **Find one where it belongs.** Go to the library, the bookshop or a cyber cafe and
    loot the computer shelves. This should take a handful of containers, not a
    building. If it takes as long as the office desks did, the weight did not take.
27. **Not everywhere.** Loot a kitchen, a wardrobe and a garage. No manuals. It is a
    computer book; it belongs with the computers.

### F — Multiplayer

28. **It spawns on a server.** The distribution file is a server file. On a hosted
    game, loot a library computer shelf as a client and the manual turns up.
29. **Two players, two books.** Two clients each with a copy, each on a different
    spread. Neither one's turning moves the other's book — the window is a client
    window and the bookmark is on the item each of them is holding.
30. **The bookmark is local.** A bookmark written on a client is not sent to the
    server. Hand the book to another player: he gets a book, and where it opens for
    him is not promised to be where you left it. That is deliberate — it is a
    bookmark, not machine state — and it is the one place the manual behaves
    differently from the terminal.

## Before release

`CeroSec.DEV_MANUAL_MENU` in `42/media/lua/shared/CeroSec/CeroSecDefs.lua` is a
testing aid and **must be `false` before anything goes to the Workshop.** It is a
door straight into a piece of documentation the player is supposed to find, and it
is on every computer in Knox County.

31. **Turn it off.** Set `CeroSec.DEV_MANUAL_MENU = false`. Right-click a computer
    that is **on**: "Turn off computer" and "Use computer", and no third entry.
    Right-click one that is **off**: "Turn on computer" and nothing else. Not a
    greyed-out entry, not a submenu — nothing.
32. **The book still works.** With the flag off, spawn a manual and read it from the
    inventory. Everything in sections B, C and D still holds: the door was a way in,
    not the way it works.
33. **The flag is the only thing that changed.** `git diff` on the release commit
    touches `CeroSecDefs.lua` and nothing else.
