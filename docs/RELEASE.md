# CeroSec — Release

The ordered checklist for putting a version on the Steam Workshop. Run it top to
bottom; nothing here is optional and nothing here is reversible by itself.

See also: [CONTRIBUTING.md](CONTRIBUTING.md) for why the Workshop folder is a copy
and never a link, [TESTING.md](TESTING.md) for what the suite proves, and
[PARCOURS-TEST.md](PARCOURS-TEST.md) for what it cannot.

## The checklist

| # | step | command |
| --- | --- | --- |
| 1 | Drop the two originals in place: `workshop/art/poster.png` (4:3) and `workshop/art/banner.png` (16:5) | by hand |
| 2 | Cut the four published images | `python3 tools/make-workshop-images.py` |
| 3 | Turn the two development flags off: `CeroSec.DEV_MANUAL_MENU = false` and `CeroSec.DEV_DEBUG_MENU = false` (the debug window is then offered only in the game's own debug mode -- [DEBUG.md](DEBUG.md)) | `sed -i 's/^CeroSec.DEV_MANUAL_MENU = true$/CeroSec.DEV_MANUAL_MENU = false/; s/^CeroSec.DEV_DEBUG_MENU = true$/CeroSec.DEV_DEBUG_MENU = false/' 42/media/lua/shared/CeroSec/CeroSecDefs.lua` |
| 4 | Check no other one crept in | `grep -rn 'DEV_MANUAL_MENU\|DEV_DEBUG\|DEV_TEST' 42/media/lua` |
| 5 | Set the version in `42/mod.info` | `sed -i 's/^modversion=.*/modversion=0.1.0/' 42/mod.info` |
| 5a | **Photograph the save shape this build writes**, and commit it — see below | `sh tools/capture-fixture.sh` |
| 6 | The headless suite must exit 0 | `sh tests/run.sh; echo rc=$?` |
| 7 | Walk the in-game checklist, all of it | [PARCOURS-TEST.md](PARCOURS-TEST.md) |
| 8 | Rebuild and look at the description | `python3 tools/bbcode-preview.py && google-chrome --headless=new --screenshot=tools/out/workshop-page.png --window-size=1100,2400 "file://$PWD/workshop/preview-page.html"` |
| 9 | Make the upload copy | `sh tools/workshop-sync.sh sync` |
| 10 | Upload: main menu, **Workshop**, **Submit item**, choose `CeroSec` | in game |
| 11 | Copy the `id=` Steam wrote back into the repo | `grep ^id= ~/Zomboid/Workshop/CeroSec/workshop.txt` |
| 12 | Add the banner as the item's **first screenshot** | Steam item page, **Add images** |
| 13 | Paste the `[img]` line into the description | see below |
| 14 | Remove the upload copy so the game loads the repo again | `sh tools/workshop-sync.sh clean` |
| 15 | Tag the commit | `git tag -a v0.1.0 -m 'CeroSec 0.1.0' && git push --tags` |
| 16 | Make the GitHub repository public | `gh repo edit Konijima/pz-cerosec --visibility public` |
| 17 | Flip the Workshop item to public | Steam item page, **Change visibility** |

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

**The banner cannot be served out of the mod.** Steam renders `[img]` from a URL and
has no idea what is inside the uploaded item, so `workshop/banner.png` has to be
hosted somewhere Steam will fetch it from. The item's own screenshots are the simplest
host: upload `workshop/banner.png` as the **first** screenshot (step 12), open it,
copy its direct image address, and make that the first line of the description, above
the tagline:

```
description=[img]<the URL of the uploaded banner>[/img]
description=[h1]THE NETWORK NEVER DIED.[/h1]
```

Edit it in `workshop/workshop.txt` and commit it, not only in the Steam text box, or
the next upload will put the old description back.

## What the sizes are, and why

Nothing in `tools/make-workshop-images.py` is a guess; each number is read off the
shipped jar or off vanilla Lua.

| file | size | where the size comes from |
| --- | --- | --- |
| `workshop/preview.png` | 512x512 PNG, under 1024000 bytes | `SteamWorkshopItem.validatePreviewImage` refuses anything else: over the byte ceiling is `PreviewFileSize`, non-square or a width that is neither 256 nor 512 is `PreviewDimensions`, unreadable is `PreviewFormat` |
| `42/poster.png` | 512x512 | the mod panel draws poster 0 with `drawTextureScaled(tex, ..., 200, 200)`, which does not keep the aspect ratio (`ModInfoPanelDesc.lua:12` and `:14`) |
| `42/icon.png` | 64x64 | drawn at `BUTTON_HGT` (`ModListBox.lua:8`, `:201`) and at 28x28 (`ModOrderListBox.lua:235`) |
| `workshop/banner.png` | 1000 px wide | the widest Steam shows an `[img]` at before scaling it down; the game never reads this file |

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
eat it.

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
