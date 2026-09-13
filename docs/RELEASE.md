# CeroSec — Release

The ordered checklist for putting a version on the Steam Workshop. Run it top to
bottom; nothing here is optional and nothing here is reversible by itself.

See also: [CONTRIBUTING.md](CONTRIBUTING.md) for why the Workshop folder is a copy
and never a link, [TESTING.md](TESTING.md) for what the suite proves, and
[PARCOURS-TEST.md](PARCOURS-TEST.md) for what it cannot.

## One-time break before 0.1.0: every hash changed (2026-09-12)

A save written by a build older than this one has passwords in it that **will not
verify any more**, and generated content (root's password, the sticky note, the
names, the logs) that is a different set of values. Accepted, because we are
pre-release and nothing is published yet.

Why: Kahlua's `%` operator is `a - (int)(a / b) * b` with a 32-bit `(int)` that
clamps at 2147483647, so it was wrong inside the mixer's `mul()` and the game's
hashes were never the same numbers as the bench's. The engine uses
`CeroSecOS.mod` now and both VMs give lua5.1's answer, which is the one every
fixture and every value in [CONTENT.md](CONTENT.md) already held -- so the
canonical numbers did not move, the game moved onto them. Same day, same cause
family: `tonumber(s, 16)` returned nil on Kahlua above `0x7fffffff` and is now
`CeroSecOS.hexValue`. See [TESTING.md](TESTING.md).

A machine caught by it: root's password is the one derived from the save's own
secret, so the BIOS repair hands it back -- and an account a player made himself
has to be reset by root. Nothing else on the machine is touched: the filesystem,
the files and the state shape are all unaffected.

## The checklist

| # | step | command |
| --- | --- | --- |
| 1 | Drop the two originals in place: `workshop/art/poster.png` (4:3) and `workshop/art/banner.png` (16:5) | by hand |
| 1a | **Choose the square poster.** Look at the three candidates side by side, at 512 and at 200, then set `POSTER_CANDIDATE` in `tools/make-workshop-images.py` to `A`, `B` or `C` — see "The square poster" below | `tools/out/poster-candidates.png` |
| 2 | Cut the four published images, and draw the eight section headers | `python3 tools/make-workshop-images.py && python3 tools/make-workshop-headers.py` |
| 2a | **Take the ten screenshots and the two GIFs** | [../workshop/SHOTS.md](../workshop/SHOTS.md) |
| 3 | Turn the two development flags off: `CeroSec.DEV_MANUAL_MENU = false` and `CeroSec.DEV_DEBUG_MENU = false` (the debug window is then offered only in the game's own debug mode -- [DEBUG.md](DEBUG.md)) | `sed -i 's/^CeroSec.DEV_MANUAL_MENU = true$/CeroSec.DEV_MANUAL_MENU = false/; s/^CeroSec.DEV_DEBUG_MENU = true$/CeroSec.DEV_DEBUG_MENU = false/' 42/media/lua/shared/CeroSec/CeroSecDefs.lua` |
| 4 | Check no other one crept in | `grep -rn 'DEV_MANUAL_MENU\|DEV_DEBUG\|DEV_TEST' 42/media/lua` |
| 5 | Set the version in `42/mod.info` | `sed -i 's/^modversion=.*/modversion=0.1.0/' 42/mod.info` |
| 5a | **Photograph the save shape this build writes**, and commit it — see below | `sh tools/capture-fixture.sh` |
| 6 | The headless suite must exit 0 | `sh tests/run.sh; echo rc=$?` |
| 6a | **In game, before step 3 takes the door away**: press **Self-test** in the debug window on a machine whose chunk is in. Both halves green, and the summary pasted into the release notes | see below |
| 6b | **In game**: press **Give diagnostics disk**, put it in a machine, `mount /dev/fd0 /mnt` then `sh /mnt/selftest.sh`. `FAIL 0`, and the summary pasted into the release notes | see below |
| 7 | Walk the in-game checklist, all of it | [PARCOURS-TEST.md](PARCOURS-TEST.md) |
| 8 | Rebuild and look at the description | `python3 tools/bbcode-preview.py && google-chrome --headless=new --screenshot=tools/out/workshop-page.png --window-size=760,6600 "file://$PWD/workshop/preview-page.html"` |
| 9 | Make the upload copy | `sh tools/workshop-sync.sh sync` |
| 10 | Upload: main menu, **Workshop**, **Submit item**, choose `CeroSec` | in game |
| 11 | Copy the `id=` Steam wrote back into the repo, and into the description's last-but-one line | `grep ^id= ~/Zomboid/Workshop/CeroSec/workshop.txt` |
| 12 | Upload the twelve item images, **in this order** | Steam item page, **Add images** — see below |
| 13 | Turn the ten `# SHOT` slots in `workshop/workshop.txt` into `[img]` lines, and commit | see below |
| 14 | Remove the upload copy so the game loads the repo again | `sh tools/workshop-sync.sh clean` |
| 15 | Tag the commit | `git tag -a v0.1.0 -m 'CeroSec 0.1.0' && git push --tags` |
| 16 | **Make the GitHub repository public.** The description's banner and its eight section headers are fetched from it: they are dead images until this is done | `gh repo edit Konijima/pz-cerosec --visibility public` |
| 17 | Open the item's own page in a browser and check the nine repo-hosted images actually rendered | Steam item page |
| 18 | Flip the Workshop item to public | Steam item page, **Change visibility** |

## Steps 6a and 6b: the two the headless suite cannot do

`sh tests/run.sh` runs on `lua5.1`. **The game does not.** On 2026-09-12 two
Kahlua-only bugs shipped past a fully green suite in one day -- `tonumber(s, 16)`
answering nil for half of all hashes, and the `%` operator wrong once the quotient
reaches 2^31 -- and neither was a missing assertion. The suite was asking the right
questions of the wrong VM. So no build goes up until somebody has run the engine on
the VM the player will have. The three layers and what each proves are in
[TESTING.md](TESTING.md).

**Order matters: both of these come BEFORE step 3.** The debug window is the door to
them and step 3 sets `CeroSec.DEV_DEBUG_MENU = false`, after which it is offered only
in the game's own debug mode. Running them after step 3 means launching in debug
mode, which is a different build from the one being shipped.

**6a -- the engine.** Open the debug window off a computer's dev submenu, click a row
on the **Machines** tab whose `chunk` column says `here` (**Teleport to it** if not
-- half of what this runs is the save path of the selected machine, and a machine
whose chunk is away has no sprite to mirror into, which the self-test reports as a
failure rather than skipping), then press **Self-test**. The verdict lands on the
line under the list, in the log at info, and in `console.txt` via `print`:

    CeroSec selftest: PASS 138 FAIL 0

Any failing line is in the log at **warn** -- the **Log** tab, `warn` filter -- and
names the vector, what lua5.1 answers and what the game answered. A failure here is
never cosmetic: it means the game computes something differently from every bench in
`tests/`, and it is a **stop**, not a note in the release.

**6b -- the shell.** Press **Give diagnostics disk** (no machine need be selected --
it is about your inventory), then right-click a computer, insert the disk, sit down
and:

    mount /dev/fd0 /mnt
    sh /mnt/selftest.sh

Twenty-six checks of the commands, the pipes, the redirects, the `$(( ))` reader and
the filesystem. One line per failure, then:

    PASS 26 FAIL 0

It also writes that into `RESULTS.TXT` on the floppy, so a run can be read back off
the disk afterwards. The exit status is non-zero on any failure (`echo $?`).

**Paste both summaries into the release notes**, with the build's own numbers. A
release whose notes say `PASS 138 FAIL 0` and `PASS 26 FAIL 0` is a release somebody
ran on Kahlua; a release with no numbers in it is one where nobody did, and that is
the whole point of writing them down rather than ticking a box. Two of the checklist
steps in [PARCOURS-TEST.md](PARCOURS-TEST.md) section X are the same two gestures,
with what to look at on the glass.

## What this release changes in an existing world

One thing, and it has to be said out loud because the compatibility contract only
allows a new sandbox option to change a world if the release notes say so plainly.

**`CeroSec.PrefilledMachines` defaults to ON.** In a save that already exists, every
computer **nobody has switched on yet** will come up as somebody's machine — his
accounts, his files, a motd, a week of log, sometimes a root password with a paper
to find. Floppies generated from now on may carry a program and a README, and papers
with passwords on them appear in desks and in the pockets of the dead.

**Nothing a player built is touched.** A machine somebody has already switched on
keeps its accounts, its files and its name; the option changes only machines that
have never had a filesystem. A server that wants the old world turns the option off
and gets it back exactly — two open accounts and an empty disk.

See [CONTENT.md](CONTENT.md).

## Step 5a: every release captures a fixture

`sh tools/capture-fixture.sh` builds a whole machine with the code as it stands —
two accounts, a home with files and a script, a cron line, a net record with its
exchange, the device-number book, a disk in the drive with a label on it — and writes
it out as a Lua table literal to `tests/fixtures/state-v<N>.lua`, where `<N>` is read
out of `CeroSecOS.STATE_VERSION` rather than passed in. **Commit the file.**

It is a photograph, and the point of it is that the *next* release has a real save from
*this* one to walk. `tests/migrate_test.lua` reads every fixture in that directory,
walks it up to whatever the code is then, and holds the result to the invariants — the
accounts still log in, the files are byte for byte, the script still runs, the disk
still mounts. It refuses to pass without a fixture for the shape one behind the current
`STATE_VERSION`, which is the save an update actually meets on somebody's disk.

Three rules:

- **Capture BEFORE bumping `STATE_VERSION`.** The number the file is named for is the
  shape inside it; capture after the bump and the shape the update will really meet is
  the one nobody photographed.
- **Never edit a fixture by hand**, and never to make a bench pass. It is what a build
  really wrote; editing it is the one thing that makes it worthless. If the bench goes
  red, the chain is wrong, not the photograph.
- **To capture a shape the current code cannot write any more**, give the tool a
  commit: `sh tools/capture-fixture.sh <commit>` checks that build's engine out into a
  temporary tree and captures from there. Nothing is checked out over the working tree.

The compatibility contract the chain is held to — which of the five version numbers
moves for which kind of change, and why an item block is never deleted — is in
[CONTRIBUTING.md](CONTRIBUTING.md#the-compatibility-contract).

## Three things that bite

**The `id=` line is Steam's, and `workshop-sync.sh sync` overwrites it.** The submit
screen calls `writeWorkshopTxt` the moment you leave its second page, so after the
first upload `~/Zomboid/Workshop/CeroSec/workshop.txt` carries the published file id
and the repo's copy does not. `sync` copies the repo's file over it
(`tools/workshop-sync.sh`, the `for f in workshop.txt preview.png` loop), so a second
release run without step 11 offers to create a **new item** instead of updating this
one. Copy the `id=` line into `workshop/workshop.txt` and commit it before syncing
again.

**That same rewrite drops the comments.** `writeWorkshopTxt` writes `version=1`, then
`id=`, `title=`, one `description=` a line, `tags=` and `visibility=`, and nothing
else. The header explaining the file format lives in git; put it back from there if a
pass through the submit screen has eaten it.

**Nothing in the mod can be served as an `[img]`.** Steam renders `[img]` from a URL
and has no idea what is inside the uploaded item, so every image in the description
has to be hosted somewhere Steam will fetch it from. There are two hosts and the
split is on purpose.

**The banner and the eight section headers come out of the GitHub repository.**
`https://raw.githubusercontent.com/Konijima/pz-cerosec/main/workshop/banner.png`
and `.../workshop/img/h-*.png`. Those URLs are **already written into
`workshop/workshop.txt`** and no line of it has to be edited at upload time. Three
things make that safe, and all three were checked rather than assumed:

- raw.githubusercontent.com answers `access-control-allow-origin: *` and
  `cross-origin-resource-policy: cross-origin`, so it survives the
  `crossorigin="anonymous"` Steam puts on a third-party description image;
- the images are versioned with the mod, so the page cannot drift from the build
  it describes;
- the repository going public (step 16) comes **before** the item goes public
  (step 18). Until step 16 those nine images are 404s, which is why step 17 is to
  open the page and look.

**The ten screenshots go on the item**, because that is where a Workshop screenshot
belongs: it shows in the item's own gallery as well as in the description. Their
URLs do not exist until the upload, so `workshop/workshop.txt` carries a commented
slot for each, naming its file from [../workshop/SHOTS.md](../workshop/SHOTS.md):

```
# SHOT 01 -- workshop/shots/01-boot-login.png, the hero shot
# description=[img]<url of 01-boot-login.png>[/img]
```

Turning one on is one edit: drop the `#` from the second line, and put the image's
direct address between the tags. To get that address: open the uploaded screenshot
on the item page, copy the image location, and **strip the whole query string** —
the live page serves `.../ugc/<id>/<hash>/?imw=268&imh=268&ima=fit&...`, and the
bare `.../ugc/<id>/<hash>/` is the full-size original. You cannot invent your own
resize parameters; `?imw=5000` answers 404.

**Upload order for step 12**, twelve images, because the first one is the item's
gallery cover:

1. `workshop/art/banner.png` at full size (1648 wide), as the **first** screenshot.
   The description shows the 630 px cut off the repository; this is the one a
   visitor gets when they click the gallery.
2. `workshop/shots/01-boot-login.png` through `10-telephone-and-radio.png`, in
   order.
3. The two GIFs.

Edit the description in `workshop/workshop.txt` and commit it, not only in the Steam
text box, or the next upload will put the old description back.

## The square poster: choosing one

`tools/make-workshop-images.py` draws three and writes all three to `tools/out/`
every run, whichever one `POSTER_CANDIDATE` publishes. Look at
`tools/out/poster-candidates.png` before setting it: it puts A, B and C side by
side at **512 and at 200** on neutral grey, and 200 is the size that decides it —
`ModInfoPanelDesc` draws poster 0 at 200x200, so a composition that only works at
512 is one most subscribers never see working.

| | keeps | loses |
| --- | --- | --- |
| **A** (default) | the monitor large and centred, the zombie at the window, the wordmark legible at 200 | the left edge of the bookshelf, so two of the four book spines are cut |
| **B** | every pixel of the original composition, all four spines | height on the subject: the monitor is smaller and the tagline is unreadable at 200 |
| **C** | the brand, and it is the only one of the three that is fully legible at 200 | the desk, the zombie, and the whole of the atmosphere |

The chosen one becomes both `workshop/preview.png` and `42/poster.png`. They are
the same picture at the same size on purpose: the Workshop preview and the mod
panel's poster are the same promise made twice.

## What the sizes are, and why

Nothing in `tools/make-workshop-images.py` is a guess; each number is read off the
shipped jar or off vanilla Lua.

| file | size | where the size comes from |
| --- | --- | --- |
| `workshop/preview.png` | 512x512 PNG, under 1024000 bytes | `SteamWorkshopItem.validatePreviewImage` refuses anything else: over the byte ceiling is `PreviewFileSize`, non-square or a width that is neither 256 nor 512 is `PreviewDimensions`, unreadable is `PreviewFormat` |
| `42/poster.png` | 512x512 | the mod panel draws poster 0 with `drawTextureScaled(tex, ..., 200, 200)`, which does not keep the aspect ratio (`ModInfoPanelDesc.lua:12` and `:14`) |
| `42/icon.png` | 64x64 | drawn at `BUTTON_HGT` (`ModListBox.lua:8`, `:201`) and at 28x28 (`ModOrderListBox.lua:235`) |
| `workshop/banner.png` | 630 px wide | Steam's own stylesheet: `.workshopItemDescription img { max-width: 630px }` in `public/css/skin_1/workshop.css` on community.akamai.steamstatic.com. The game never reads this file |
| `workshop/img/h-*.png` | 630x80 | the same rule. Eight section headers, drawn by `tools/make-workshop-headers.py` |

**The 630 corrects a 1000 that was in this table and in the script until
2026-09-13, and was never true.** Steam does not show an `[img]` at 1000 px: it
scales it down to 630, and a bitmap face scaled by 0.63 comes back with grey
edges instead of square ones. The number is in the stylesheet quoted above. While
that was being checked, the description column turned out to be about the same
width: `#leftContents` is `width: 650px` and `.workshopItemDescription` has
`padding-right: 8px`, so a 630 image is very nearly full bleed, which is why the
headers are drawn at exactly that and not at "something wide".

The preview image's name and place are not a convention either: the submit screen
looks for `<workshop folder>/preview.png` and nothing else
(`SteamWorkshopItem.getPreviewImage`).

## The item files

`workshop/workshop.txt` documents its own format in its header. The short version:
every line is trimmed, a blank line or one starting with `#` or `//` is skipped, and
the keys are `id=`, `title=`, `description=` (repeatable, joined with one newline),
`tags=` (split on `;`, legal set in the game's `media/WorkshopTags.txt`),
`visibility=` (`public`, `friendsOnly`, `private`, `unlisted`) and `version=`, which
is read and ignored.

`42/mod.info` is read by `ChooseGameInfo.readModInfoAux`, which is a different parser
with different rules: lines are **not** trimmed, keys are matched with
`String.contains` anywhere in the line, and repeated `description=` lines are
concatenated with **nothing** between them. Line breaks in that description are
`ISRichTextPanel`'s own `<LINE>`, and no line of it may contain another key's
spelling (`name=`, `url=`, `poster=`, `icon=`, `id=` and the rest) or that key will
eat it. **There is therefore no comment syntax in this file and nothing explaining
itself inside it** — a `#` line saying the word `description=` would be read as a
description.

**What the description is drawn into, and the two tags it uses.** The panel is
`ModInfoPanel.Desc` (`media/lua/client/OptionScreens/ModSelector/ModInfoPanelDesc.lua`).
Its `createChildren` builds the text box at `self.width - 200 - UI_BORDER_SPACING*2`,
and the chain above it is `MainScreen` → `ModSelector:new(0, 0, self.width, ...)` →
a mod list `self.width/2 - UI_BORDER_SPACING` wide → `ModInfoPanel` on what is left.
So the text box is **half the screen width, less 242 px**: 270 px at 1024, 398 at
1280, 718 at 1920. It is 200 px tall with scrollbars (`addScrollBars(true)`), which
is about a dozen lines at the narrow end. The description is written for that: the
tagline and the pitch are in the first screen and the housekeeping is under it,
because the scroll bar is the part nobody uses.

The tagline is green, and that is not a guess either. `ISRichTextPanel:processCommand`
takes `CENTRE`, `LEFT`, `RIGHT`, `LINE`, `BR`, `SPACE`, `RED`, `GREEN`, `ORANGE`,
`GHC`, `BHC`, `RGB:r,g,b`, `PUSHRGB:r,g,b` and `POPRGB`, the colours as floats 0 to 1.
`mod.info` uses the **push and pop** pair rather than a bare `RGB:`, which is the
same pair the engine's own `replaceKeyBinding` uses two hundred lines further down
the same file, so the colour is put back afterwards instead of running to the end of
the description.

## Tags

`Build 42;Interface;Items;Literature;Multiplayer;Realistic`, all six from the game's
own `media/WorkshopTags.txt`. `Items` and `Literature` are the three manual volumes
and the four floppy disks; `Interface` is the terminal and the book reader;
`Realistic` is the design rule. `Audio` and `Models` are true of the files shipped
(there are sounds and a floppy model) but false of the mod, which is not an audio or
a model mod, and a tag is for finding things.

`WIP` is left off on purpose. On the Workshop that tag warns a subscriber that the
item may not work yet. Everything listed in the description is finished, tested and
documented; this is a small first version, not a broken one, and the honest place for
what is still being built is the "Early release" section of the description.
