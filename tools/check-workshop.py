#!/usr/bin/env python3
"""Hold workshop/workshop.txt and workshop/preview.png to Steam's own limits.

    python3 tools/check-workshop.py            checks the repo's item
    python3 tools/check-workshop.py <file>     checks another workshop.txt

Run by `sh tests/run.sh`. Exits non-zero and names the offending number on any
failure, because the failure mode this exists to stop is silent: on 2026-09-13
the first update to item 3801094056 was accepted by the submit screen and the
published page came back **0 bytes, no preview, no description**. Nothing said
why. The description was 9502 bytes and the ceiling is 8000.

Where every number here comes from
----------------------------------

Valve's own constants, `ISteamRemoteStorage` on partner.steamgames.com, which
`ISteamUGC.SetItemDescription` and its neighbours refer to by name:

    k_cchPublishedDocumentDescriptionMax   8000
    k_cchPublishedDocumentTitleMax         128 + 1
    k_cchTagListMax                        1024 + 1

They are documented as a maximum **size in bytes**, not in characters, so every
length here is measured on the UTF-8 encoding. Today the description is ASCII
and the two agree; the day a translated page carries one accented letter they
stop agreeing, and the byte is the one Steam counts.

The preview image's three rules are the game's, not Steam's, and were read off
the shipped jar: `javap -p -c zombie.core.znet.SteamWorkshopItem` shows
`validatePreviewImage` refusing a file in exactly three ways -- over 1024000
bytes is `PreviewFileSize`, width != height or a width that is neither 256 nor
512 is `PreviewDimensions`, and anything `PNGDecoder` cannot read is
`PreviewFormat`.

The tags are checked against the game's own `media/WorkshopTags.txt`, which is
the list `SteamWorkshopItem.readWorkshopTxt` validates against. A tag not in
that file is not a tag, it is a typo that will be dropped in silence.

The reserve
-----------

`workshop.txt` carries ten commented `# SHOT` slots, one per screenshot, that
become `[img]<url>[/img]` lines once the item has been uploaded and its
screenshots have URLs. Those lines do not exist yet and therefore do not count
today, which is exactly how a description that fits now stops fitting later. So
the check counts them too, at `SHOT_RESERVE_BYTES` each, and holds the sum to
the same 8000. A page that only fits before its pictures are in it is a page
that is going to be rejected on the day the pictures go in.
"""

import re
import struct
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
ITEM = REPO / "workshop" / "workshop.txt"
PREVIEW = REPO / "workshop" / "preview.png"

# The game's own tag list. The suite already cannot run without the game
# installed (tests/kahlua-run.sh wants projectzomboid.jar and its jre64), so a
# missing file here is a broken environment and is reported as one rather than
# quietly skipping the check.
GAME = Path.home() / ".local/share/Steam/steamapps/common/ProjectZomboid/projectzomboid"
TAGS_FILE = GAME / "media" / "WorkshopTags.txt"

# Valve's constants; see the docstring.
DESCRIPTION_MAX_BYTES = 8000
TITLE_MAX_BYTES = 128
TAGLIST_MAX_BYTES = 1024

# SteamWorkshopItem.validatePreviewImage; see the docstring.
PREVIEW_MAX_BYTES = 1024000
PREVIEW_SIZES = (256, 512)

# What one screenshot line will cost once it has a URL. A Steam UGC address is
# https://images.steamusercontent.com/ugc/<18 digits>/<40 hex>/ which is 87,
# plus [img][/img] is 98; 100 is that rounded up.
SHOT_RESERVE_BYTES = 100
SHOT_SLOT = re.compile(r"^#\s*description=\[img\]<url of ")

VISIBILITY = ("public", "friendsOnly", "private", "unlisted")


def read_item(path):
    """Parse it the way SteamWorkshopItem.readWorkshopTxt does, and count the
    commented screenshot slots on the way past, which it does not."""
    item = {"title": "", "description": "", "tags": [], "visibility": "",
            "id": None, "slots": 0}
    seen_description = False
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if SHOT_SLOT.match(line):
            item["slots"] += 1
            continue
        if not line or line.startswith("#") or line.startswith("//"):
            continue
        if line.startswith("id="):
            item["id"] = line[len("id="):]
        elif line.startswith("description="):
            if seen_description:
                item["description"] += "\n"
            item["description"] += line[len("description="):]
            seen_description = True
        elif line.startswith("tags="):
            item["tags"] += line[len("tags="):].split(";")
        elif line.startswith("title="):
            item["title"] = line[len("title="):]
        elif line.startswith("visibility="):
            item["visibility"] = line[len("visibility="):]
    return item


def png_size(path):
    """Width and height out of the IHDR, without needing PIL.

    A PNG is the 8-byte signature, then a chunk whose length is 4 bytes, whose
    type is the 4 bytes "IHDR", and whose first eight bytes of data are the two
    dimensions, big-endian. Anything else is not a PNG, which is the third way
    validatePreviewImage refuses a file.
    """
    head = path.read_bytes()[:24]
    if len(head) < 24 or head[:8] != b"\x89PNG\r\n\x1a\n" or head[12:16] != b"IHDR":
        return None
    return struct.unpack(">II", head[16:24])


def check(path):
    fails = []

    def bad(msg):
        fails.append(msg)

    item = read_item(path)

    # 1. The description, and the room the screenshots still need.
    body = len(item["description"].encode("utf-8"))
    reserve = item["slots"] * SHOT_RESERVE_BYTES
    print("description: %d bytes, %d screenshot slots reserving %d, %d of %d used"
          % (body, item["slots"], reserve, body + reserve, DESCRIPTION_MAX_BYTES))
    if body > DESCRIPTION_MAX_BYTES:
        bad("description is %d bytes and Steam's ceiling is %d "
            "(k_cchPublishedDocumentDescriptionMax). Over it, the update is "
            "accepted and the published page comes back empty."
            % (body, DESCRIPTION_MAX_BYTES))
    elif body + reserve > DESCRIPTION_MAX_BYTES:
        bad("description is %d bytes and fits, but the %d screenshot slots "
            "still to be filled in will add about %d, for %d against a ceiling "
            "of %d. It fits today and will not fit on upload day."
            % (body, item["slots"], reserve, body + reserve,
               DESCRIPTION_MAX_BYTES))

    # 2. The title and the tag list, same source.
    title = len(item["title"].encode("utf-8"))
    if title > TITLE_MAX_BYTES:
        bad("title is %d bytes and the ceiling is %d "
            "(k_cchPublishedDocumentTitleMax)" % (title, TITLE_MAX_BYTES))
    if not item["title"]:
        bad("no title= line")

    taglist = len(",".join(item["tags"]).encode("utf-8"))
    if taglist > TAGLIST_MAX_BYTES:
        bad("tag list is %d bytes and the ceiling is %d (k_cchTagListMax)"
            % (taglist, TAGLIST_MAX_BYTES))

    # 3. Every tag in the game's own list.
    if not TAGS_FILE.is_file():
        bad("cannot read the game's tag list at %s, so no tag can be checked"
            % TAGS_FILE)
    else:
        legal = {t.strip() for t in TAGS_FILE.read_text(encoding="utf-8").splitlines()
                 if t.strip()}
        unknown = [t for t in item["tags"] if t not in legal]
        for tag in unknown:
            bad("tag %r is not in %s, and a tag the game does not know is "
                "dropped in silence" % (tag, TAGS_FILE.name))
        if not unknown:
            print("tags: %d, all in %s" % (len(item["tags"]), TAGS_FILE.name))

    if item["visibility"] not in VISIBILITY:
        bad("visibility=%r is not one of %s"
            % (item["visibility"], ", ".join(VISIBILITY)))

    # 4. The preview image, against the jar's three refusals.
    if not PREVIEW.is_file():
        bad("no %s, and the submit screen looks for that name and no other"
            % PREVIEW.relative_to(REPO))
    else:
        size = PREVIEW.stat().st_size
        dims = png_size(PREVIEW)
        if dims is None:
            bad("%s is not a PNG the decoder will read (PreviewFormat)"
                % PREVIEW.relative_to(REPO))
        else:
            w, h = dims
            print("preview.png: %dx%d, %d bytes" % (w, h, size))
            if w != h:
                bad("preview.png is %dx%d and has to be square "
                    "(PreviewDimensions)" % (w, h))
            elif w not in PREVIEW_SIZES:
                bad("preview.png is %d wide and the only legal widths are %s "
                    "(PreviewDimensions)"
                    % (w, " and ".join(str(s) for s in PREVIEW_SIZES)))
        if size > PREVIEW_MAX_BYTES:
            bad("preview.png is %d bytes and the ceiling is %d "
                "(PreviewFileSize)" % (size, PREVIEW_MAX_BYTES))

    if fails:
        print("check-workshop: FAILED")
        for f in fails:
            print("  " + f)
        return 1
    print("check-workshop: passed")
    return 0


def main():
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else ITEM
    if not path.is_file():
        print("check-workshop: missing %s" % path, file=sys.stderr)
        return 1
    return check(path)


if __name__ == "__main__":
    sys.exit(main())
