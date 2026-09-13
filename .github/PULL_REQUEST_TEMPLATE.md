<!--
Read docs/CONTRIBUTING.md first if you have not. Leave a box unticked and say why
rather than ticking it hopefully — an unverified claim costs more to unpick than
an honest gap.
-->

## What this changes, and why

<!-- The why, not the diff. If it fixes an issue, link it. -->

## The suite

```
sh tests/run.sh ; echo $?
```

- [ ] `sh tests/run.sh` exits **0**, and I read the exit code rather than the last line.
- [ ] `luac5.1 -p` is clean on every Lua file I touched.
- [ ] If a layer could not run here (no game installed, so the Kahlua harness cannot),
      it is named below rather than skipped silently.

**rc=** 

**Could not run here:** 

## The benches

- [ ] Every new or changed assertion has been seen **red for the reason it exists**
      (break the guarded thing on purpose, watch it fail for that reason and no
      other, put it back, watch it pass).
- [ ] What I mutated, and what went red, is listed here:

<!-- e.g. "inverted the hasPower check in SCeroSecObject:turnOn -> window_test 41.3 red" -->

## Benchmarks

<!--
Only if you touched the scheduler, the step machine, the sensors or anything in
hostile_test.lua. Paste the `calibration` line and the figures the bench printed;
a ceiling is never raised to make a red go away.
-->

## The manual, the parcours, the changelog

- [ ] The in-game manual is in step with the code (`tests/manual_test.lua` pins
      every usage line and error string somewhere in the three volumes).
- [ ] `docs/PARCOURS-TEST.md` has the step that walks this on the glass, if a
      player can see the change.
- [ ] `CHANGELOG.md` has its line under **Unreleased**, in the words a subscriber
      reads.
- [ ] `CeroSecOS.DEVIATIONS` and Volume 1's *What is not Unix here* both name any
      new deviation from real 1993 behaviour.

## Compatibility

- [ ] Nothing is deleted: no state key, no item block, no recipe, no sandbox
      option. Anything retired is obsoleted and migrated.
- [ ] If a shape changed, the right version number moved and there is one
      migration step per number
      (see [docs/CONTRIBUTING.md](../docs/CONTRIBUTING.md#which-number-moves-and-when)).

## Anything you could not verify

<!-- Say it plainly here. -->
