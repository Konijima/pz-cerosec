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
url and quote. Anything else is left as literal text on purpose, so an unknown
tag shows up in the page instead of disappearing quietly.
"""

import html
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SRC = REPO / "workshop" / "workshop.txt"
OUT = REPO / "workshop" / "preview-page.html"
BANNER = REPO / "workshop" / "banner.png"

KNOWN = ("h1", "h2", "b", "i", "list", "*", "hr", "url", "quote")


def read_item(path):
    """Parse workshop.txt the way SteamWorkshopItem.readWorkshopTxt does."""
    item = {"title": "", "description": "", "tags": [], "visibility": "", "id": None}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
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


def bbcode_to_html(text):
    out = html.escape(text)

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

    # Whatever is left between two newlines is a paragraph.
    blocks = []
    for block in out.split("\n"):
        b = block.strip()
        if not b:
            continue
        if b.startswith("<"):
            blocks.append(b)
        else:
            blocks.append("<p>%s</p>" % b)
    return "\n".join(blocks)


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
  .page {{ max-width: 940px; margin: 0 auto; padding: 24px 16px 64px; }}
  .head {{ color: #ffffff; font-size: 26px; font-weight: 400; margin: 0 0 4px; }}
  .by {{ color: #8f98a0; font-size: 13px; margin: 0 0 20px; }}
  .card {{ background: #16202d; border-radius: 3px; padding: 20px 24px; }}
  .banner {{ display: block; width: 100%; border-radius: 3px; margin: 0 0 20px; }}
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

    if BANNER.is_file():
        banner = '<img class="banner" src="banner.png" alt="CeroSec">'
    else:
        banner = ('<div class="nobanner">workshop/banner.png is not built yet: run '
                  'tools/make-workshop-images.py once the source art is in '
                  'workshop/art/</div>')

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
