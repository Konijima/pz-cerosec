#!/usr/bin/env python3
"""Print the newest CHANGELOG.md section as Steam Change Notes.

    python3 tools/changelog-steam.py            newest released section
    python3 tools/changelog-steam.py unreleased what is waiting under Unreleased

Steam's change note takes BBCode; a heading becomes [b]...[/b] and the bullets
stay bullets. The limit is the same 8000 bytes as a description, and this
script refuses past it rather than let Steam cut the tail.
"""
import re
import sys
from pathlib import Path

LIMIT = 8000
text = (Path(__file__).resolve().parent.parent / "CHANGELOG.md").read_text(encoding="utf-8")
sections = re.split(r"^## ", text, flags=re.M)[1:]
want = "unreleased" if len(sys.argv) > 1 and sys.argv[1] == "unreleased" else None
for section in sections:
    head, _, body = section.partition("\n")
    if want == "unreleased" and not head.startswith("Unreleased"):
        continue
    if want is None and head.startswith("Unreleased"):
        continue
    lines = []
    for line in body.strip("\n").split("\n"):
        if line.startswith("- "):
            lines.append("[*] " + line[2:].strip())
        elif line.startswith("  ") and lines and lines[-1].startswith("[*]"):
            lines[-1] += " " + line.strip()
        elif line.strip() == "":
            lines.append("")
        else:
            lines.append(line.strip())
    out = "[b]" + head.strip() + "[/b]\n" + "\n".join(lines).strip("\n") + "\n"
    if len(out.encode("utf-8")) > LIMIT:
        sys.exit("change note is %d bytes, over Steam's %d" % (len(out.encode("utf-8")), LIMIT))
    if want == "unreleased" and not body.strip():
        out = "[b]Unreleased[/b]\n(nothing yet)\n"
    sys.stdout.write(out)
    break
else:
    sys.exit("no section found")
