---
name: Bug report
about: Something in CeroSec behaves wrongly in game
title: ''
labels: bug
assignees: ''
---

<!--
Four things make a report actionable: the build, the mod list, console.txt, and
where on the glass it happened. Please fill them in even if the bug looks
obvious — it usually is not, once another mod is in the room.
-->

## Game build

<!-- Exactly, from the main menu. e.g. 42.20.4 — not "latest". -->

**Build:** 
**CeroSec version** (`modversion` in `42/mod.info`, or the Workshop item's date): 
**Single player / Host / dedicated server:** 

## What happened

<!-- One or two sentences. What you expected, and what the machine did instead. -->

## Steps to reproduce

1. 
2. 
3. 

**Does it still happen with CeroSec as the only mod enabled?** yes / no / not tried

## Your mod list

<!--
Every enabled mod. CeroSec touches computers, doors, windows, light switches and
the radio; a mod that also touches any of those is the first suspect.
-->

## console.txt

<!--
~/Zomboid/console.txt — the lines AROUND the failure, not only the last one.
Set CeroSec.DEBUG = true in 42/media/lua/shared/CeroSec/CeroSecDefs.lua to get
this mod's own lines as well. Paste inside the fence; attach the file if it is long.
-->

```
```

## The parcours step

<!--
If you can find what you did in docs/PARCOURS-TEST.md (the in-game checklist),
give the step number — that turns a report into a reproduction. Otherwise say
"not in the parcours".
-->

**Step:** 

## Anything else

<!-- Screenshots, a save that shows it, whether it survives a reload. -->
