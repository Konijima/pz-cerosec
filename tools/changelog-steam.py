#!/usr/bin/env python3
"""Print the newest CHANGELOG.md section as Steam Change Notes.

    python3 tools/changelog-steam.py            newest released section
    python3 tools/changelog-steam.py unreleased what is waiting under Unreleased

Steam's change note takes BBCode; a heading becomes [b]...[/b] and the bullets
stay bullets.

What goes on Steam is NOT this output any more. Since 0.4.0 the note pasted on
the item is a short, plain, player-facing list written by hand into
tools/out/steam-note-<version>.txt -- see docs/RELEASE.md step 5b -- and the
changelog keeps the full notes, which are for GitHub. So a section over Steam's
8000 bytes is no longer a refusal: it is printed, with a warning on stderr
saying the long form is not what goes to Steam, and the exit status stays 0.
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
        sys.stderr.write(
            "warning: this section is %d bytes, over Steam's %d -- the long form is"
            " not what goes to Steam any more; write the short note by hand (RELEASE.md 5b)\n"
            % (len(out.encode("utf-8")), LIMIT)
        )
    if want == "unreleased" and not body.strip():
        out = "[b]Unreleased[/b]\n(nothing yet)\n"
    sys.stdout.write(out)
    break
else:
    sys.exit("no section found")
