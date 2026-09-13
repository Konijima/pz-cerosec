#!/usr/bin/env python3
"""Render workshop/workshop.txt as a local approximation of its Steam page.

This exists to be looked at, not to be exact. Steam's own renderer is not
public; what is copied here is the dark page, the column width, the fonts and
the spacing of a Workshop item description, so that a badly balanced list or a
wall of text is visible before the item is ever uploaded.

    python3 tools/bbcode-preview.py            writes workshop/preview-page.html

The description is read the way the game reads it (see the header of
workshop/workshop.txt): repeated "description=" lines joined with a newline.
The tags handled are the ones the description uses: h1, h2, b, i, list, *, hr,
url, quote, code and img. Anything else is left as literal text on purpose, so
an unknown tag shows up in the page instead of disappearing quietly.

Two things this does that Steam does not, both so the page can be judged before
a single byte is uploaded:

  * an [img] whose URL is under RAW_PREFIX is served from the FILE it will be
    served from at release. The banner and the seven section headers live in the
    repository and are fetched off raw.githubusercontent.com by the real page
    (workshop/workshop.txt explains why that host), so the same line renders
    here against workshop/banner.png and workshop/img/h-*.png. A URL under the
    prefix with no file behind it is drawn as a red box rather than as a broken
    image: a header that has not been generated yet must not look like a header
    that has.

  * the commented screenshot slots -- the "# SHOT nn -- ..." lines the game's
    parser skips -- are drawn as dashed placeholders at their real place in the
    page. The ten screenshots are the half of the layout that does not exist
    yet, and a preview that leaves them out is a preview of a page nobody is
    going to publish. SHOW_SHOT_SLOTS turns them off to see the page as Steam
    would show it today.
"""

import html
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SRC = REPO / "workshop" / "workshop.txt"
OUT = REPO / "workshop" / "preview-page.html"
BANNER = REPO / "workshop" / "banner.png"

KNOWN = ("h1", "h2", "b", "i", "list", "*", "hr", "url", "quote", "code", "img", "shot")

# Where the real page fetches the banner and the headers from, and what that
# maps to on disk. Keep the two in step with workshop/workshop.txt.
RAW_PREFIX = "https://raw.githubusercontent.com/Konijima/pz-cerosec/main/"
SHOW_SHOT_SLOTS = True


def read_item(path):
    """Parse workshop.txt the way SteamWorkshopItem.readWorkshopTxt does.

    With one addition the game has no use for: a comment of the form
    "# SHOT nn -- path" is kept as a placeholder line, so the preview can show
    where the ten screenshots go. The game and Steam both skip it.
    """
    item = {"title": "", "description": "", "tags": [], "visibility": "", "id": None}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if line.startswith("# SHOT ") and SHOW_SHOT_SLOTS:
            if item["description"]:
                item["description"] += "\n"
            item["description"] += "[shot]%s[/shot]" % line[2:]
            continue
        if not line or line.startswith("#") or line.startswith("//"):
            continue
        if line.startswith("id="):
            item["id"] = line.replace("id=", "")
        elif line.startswith("description="):
            if item["description"]:
                item["description"] += "\n"
            item["description"] += line.replace("description=", "")
        elif line.startswith("tags="):
            item["tags"] += line.replace("tags=", "").split(";")
        elif line.startswith("title="):
            item["title"] = line.replace("title=", "")
        elif line.startswith("visibility="):
            item["visibility"] = line.replace("visibility=", "")
    return item


def local_for(url):
    """The file a released [img] URL will really be served from, or None."""
    if not url.startswith(RAW_PREFIX):
        return None
    return REPO / url[len(RAW_PREFIX):]


def bbcode_to_html(text):
    out = html.escape(text)

    # [code] first and whole: what is inside it is a transcript and must not
    # have its brackets or its spacing touched by anything below.
    codes = []

    def stash_code(m):
        codes.append(m.group(1).strip("\n"))
        return "\x00CODE%d\x00" % (len(codes) - 1)

    out = re.sub(r"\[code\](.*?)\[/code\]", stash_code, out, flags=re.S)

    def do_img(m):
        url = html.unescape(m.group(1)).strip()
        path = local_for(url)
        if path is None:
            return ('<div class="missing">[img] from a host this preview does '
                    'not resolve: %s</div>' % html.escape(url))
        if not path.is_file():
            return ('<div class="missing">no file behind %s &mdash; run the '
                    'image scripts</div>' % html.escape(str(path.relative_to(REPO))))
        return '<img class="bbimg" src="%s" alt="">' % html.escape(
            str(path.relative_to(OUT.parent)))

    out = re.sub(r"\[img\](.*?)\[/img\]", do_img, out, flags=re.S)

    out = re.sub(r"\[shot\](.*?)\[/shot\]",
                 lambda m: '<div class="shot">%s</div>' % m.group(1),
                 out, flags=re.S)

    # [url=x]y[/url] before anything else, so the href is not touched again.
    out = re.sub(r"\[url=([^\]]+)\](.*?)\[/url\]",
                 lambda m: '<a href="%s">%s</a>' % (html.unescape(m.group(1)), m.group(2)),
                 out, flags=re.S)

    out = out.replace("[hr][/hr]", "<hr>")
    for tag, el in (("h1", "h1"), ("h2", "h2"), ("b", "strong"), ("i", "em")):
        out = out.replace("[%s]" % tag, "<%s>" % el).replace("[/%s]" % tag, "</%s>" % el)
    out = out.replace("[quote]", "<blockquote>").replace("[/quote]", "</blockquote>")

    # Lists: Steam's [*] has no closing tag, so each item runs to the next [*]
    # or to the end of the list.
    def do_list(m):
        items = [i.strip() for i in m.group(1).split("[*]") if i.strip()]
        return "<ul>" + "".join("<li>%s</li>" % i for i in items) + "</ul>"

    out = re.sub(r"\[list\](.*?)\[/list\]", do_list, out, flags=re.S)

    # Whatever is left between two newlines is a paragraph. "Starts with a
    # tag" is NOT the test for one: every FAQ answer starts with [b], which is
    # a <strong> by now, and treating those as block level ran all eight
    # questions together into one grey slab -- which is exactly the defect this
    # tool exists to catch, so it had better not be the tool causing it.
    block_level = ("<h1", "<h2", "<ul", "<hr", "<blockquote", "<pre", "<img",
                   "<div")
    blocks = []
    for block in out.split("\n"):
        b = block.strip()
        if not b:
            continue
        if b.startswith(block_level) or b.startswith("\x00CODE"):
            blocks.append(b)
        else:
            blocks.append("<p>%s</p>" % b)
    page = "\n".join(blocks)

    for i, body in enumerate(codes):
        page = page.replace("\x00CODE%d\x00" % i, "<pre>%s</pre>" % body)
    return page


PAGE = """<!doctype html>
<meta charset="utf-8">
<title>CeroSec on the Steam Workshop (local preview)</title>
<style>
  :root {{ color-scheme: dark; }}
  body {{
    margin: 0; background: #1b2838;
    font: 15px/1.5 "Motiva Sans", Arial, Helvetica, sans-serif;
    color: #c6d4df;
  }}
  /* The real column, not a guess: #leftContents is width: 650px and
     .workshopItemDescription has padding-right: 8px, both in
     public/css/skin_1/workshop.css. So the description is read at about 642 px
     and an [img] caps at 630. Previewing it at 940 made every paragraph three
     lines shorter than it really is and made the headers look narrow. */
  .page {{ max-width: 690px; margin: 0 auto; padding: 24px 16px 64px; }}
  .head {{ color: #ffffff; font-size: 26px; font-weight: 400; margin: 0 0 4px; }}
  .by {{ color: #8f98a0; font-size: 13px; margin: 0 0 20px; }}
  .card {{ background: #16202d; border-radius: 3px; padding: 20px 16px 20px 8px; }}
  .banner {{ display: block; width: 100%; border-radius: 3px; margin: 0 0 20px; }}
  /* Steam caps a description image at 630px, in the rule for
     .workshopItemDescription img in public/css/skin_1/workshop.css. Copied
     exactly: a header that only lines up at 940 is a header that does not. */
  .bbimg {{ display: block; max-width: 630px; margin: 22px 0 14px; }}
  pre {{
    background: #0d1117; border: 1px solid #2a3f5a; border-radius: 3px;
    padding: 14px 16px; overflow-x: auto; color: #9fd8ad;
    font: 13px/1.35 "DejaVu Sans Mono", Consolas, monospace; margin: 0 0 14px;
  }}
  .shot {{
    max-width: 630px; border: 1px dashed #4c6b8a; border-radius: 3px;
    padding: 30px 16px; margin: 14px 0; text-align: center;
    color: #7d8a95; font-size: 12px; letter-spacing: .04em;
  }}
  .missing {{
    max-width: 630px; border: 1px solid #a33; border-radius: 3px;
    padding: 14px 16px; margin: 14px 0; color: #e08; font-size: 12px;
  }}
  .nobanner {{
    border: 1px dashed #4c6b8a; border-radius: 3px; padding: 28px;
    text-align: center; color: #8f98a0; font-size: 13px; margin: 0 0 20px;
  }}
  h1 {{ color: #ffffff; font-size: 21px; font-weight: 400; margin: 24px 0 10px; }}
  h2 {{ color: #ffffff; font-size: 17px; font-weight: 400; margin: 20px 0 8px; }}
  p {{ margin: 0 0 12px; }}
  strong {{ color: #e5e9ea; font-weight: 700; }}
  hr {{ border: 0; border-top: 1px solid #2a3f5a; margin: 24px 0; }}
  ul {{ margin: 0 0 12px; padding-left: 22px; }}
  li {{ margin: 0 0 8px; }}
  blockquote {{
    margin: 16px 0 0; padding: 12px 16px;
    background: #1b2838; border-left: 2px solid #4c6b8a; color: #a7b6c2;
  }}
  a {{ color: #66c0f4; }}
  .meta {{ margin-top: 28px; color: #8f98a0; font-size: 13px; }}
  .tag {{
    display: inline-block; background: #2a3f5a; color: #c6d4df;
    border-radius: 2px; padding: 3px 9px; margin: 0 6px 6px 0; font-size: 12px;
  }}
</style>
<div class="page">
  <p class="head">{title}</p>
  <p class="by">Made by Konijima &middot; Project Zomboid &middot; Build 42</p>
  <div class="card">
    {banner}
    {body}
  </div>
  <div class="meta">
    <p>Tags: {tags}</p>
    <p>Visibility: {visibility} &middot; Workshop ID: {wid}</p>
    <p>Local preview of workshop/workshop.txt. Steam's own renderer is not this
    one; use this page to judge the structure, not the pixels.</p>
  </div>
</div>
"""


def main():
    if not SRC.is_file():
        print("missing %s" % SRC, file=sys.stderr)
        return 1
    item = read_item(SRC)

    unknown = sorted(set(re.findall(r"\[/?([a-z0-9*]+)", item["description"])) - set(KNOWN))
    if unknown:
        print("unhandled bbcode tags left as text: %s" % ", ".join(unknown), file=sys.stderr)

    # No banner of the preview's own: the description's first line is the
    # [img] for it, and two banners is a page nobody is publishing.
    banner = ""

    OUT.write_text(PAGE.format(
        title=html.escape(item["title"]),
        banner=banner,
        body=bbcode_to_html(item["description"]),
        tags="".join('<span class="tag">%s</span>' % html.escape(t) for t in item["tags"]),
        visibility=html.escape(item["visibility"]),
        wid=html.escape(item["id"] or "not uploaded yet"),
    ), encoding="utf-8")
    print("wrote %s (%d bytes)" % (OUT, OUT.stat().st_size))
    return 0


if __name__ == "__main__":
    sys.exit(main())
