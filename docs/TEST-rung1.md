# CeroSec rung 1 — manual test checklist

See also [TESTING.md](TESTING.md) for the headless suites and the other rungs.

Build 42.20.4. Nothing here can be driven from a headless agent, so it needs a pair
of eyes. Enable **CeroSec** in the mod list of a **new** game each time (rung 1 adds a
GlobalObject system; an existing save has no `gos_cerosec.bin`, which is handled, but
a fresh world keeps the runs comparable).

Turn `CeroSec.DEBUG = true` in
`42/media/lua/shared/CeroSec/CeroSecDefs.lua` if you want the
toggle and light lines in the console.

## A — Solo

1. **Find a computer.** Any office or house desk: the beige desktop from the
   `Desktop` tile group (`appliances_com_01_72`..`_75`). Debug shortcut: the debug
   menu can spawn the tile, or use a Computer moveable from a crate.
2. **Right-click it.** "Turn on computer" appears. If the building has power, it is
   clickable; if not, it is greyed out and hovering shows "This computer has no power."
3. **Turn it on.** The character walks adjacent, faces the computer, spends about a
   second, then: the sprite changes to the lit screen (`_76`..`_79`, same facing) and
   `CeroSecBootStart` plays.
4. **Glow at night.** Wait for dark (or sleep). The screen should throw a dim bluish
   glow about 3 squares across. It is deliberately faint — a monitor, not a lamp.
   Check it from a few angles and from an unlit room.
5. **Turn it off.** Right-click → "Turn off computer". Sprite goes back to the dark
   screen, `CeroSecToggle` plays, glow gone.
6. **All four facings.** Repeat 3-5 on computers facing S, E, N and W. The lit sprite
   must keep the facing (a computer facing the wall must not flip to face the room).
7. **Save/load while on.** Turn one on, save and quit to the main menu, reload the
   save. The computer is still lit, and still glows at night. (This is the
   `gos_cerosec.bin` round trip plus `stateToIsoObject` on chunk load.)
8. **Pick up.** Turn the computer **off** first — a lit computer is not pickable,
   because the vanilla lit tiles `_76`..`_79` carry neither `IsMoveAble` nor
   `PickUpWeight`. Then right-click → Pick Up. You get a Computer item.
9. **Place it.** Place the item back down. It must come down **off** and dark, whatever
   it was before. Right-click → "Turn on computer" works again.
10. **Place it while it was on.** Turn a computer on, then use the debug/admin tools to
    remove and re-place it (or repeat 8-9 with the modData carried): after placement it
    is always off.
11. **Power loss.** Two ways:
    - Sandbox: start a game with `ElecShutModifier` set to 0 days so the grid is
      already down, and check "Turn on computer" is greyed out everywhere except
      near a running generator.
    - In game: turn a computer on inside a generator-powered building, then turn the
      generator off. **Within one in-game minute** the computer turns itself off:
      sprite back to dark, glow gone, `CeroSecToggle` plays.
12. **Generator square.** With a generator running and the computer in the same
    building, "Turn on computer" must be available and work.
13. **No leaked glow.** Turn one on, walk far enough that the chunk unloads, come back.
    Exactly one glow, no doubling, and the lit sprite is still there.
14. **Console clean.** No Lua errors in `~/Zomboid/console.txt` through all of the above,
    and no stray `CeroSec:` prints with `DEBUG = false`.

## B — Host (co-op) with a second client

Host a game from the same install, join with a second machine or a second Steam account.

15. **Sprite reaches the client.** Host turns a computer on. The **client** sees the
    sprite change to the lit screen without reloading, and sees the glow at night.
    Then the client turns it off; the **host** sees it go dark.
16. **Client toggles.** Client right-clicks a computer the host has never touched and
    turns it on. Host sees it.
17. **No-power tooltip on the client.** The greyed-out option and tooltip behave the
    same on the client (the check is `square:haveElectricity() or (hasGridPower and
    getRoom())`, evaluated locally, and the server checks again before flipping the
    state, so a client with a stale view cannot force a computer on).
18. **Client joins later.** Host turns a computer on, then a fresh client connects and
    walks to it. The client must see it lit **and glowing** (this is the
    `newLuaObjectOnClient` announcement on chunk load).
19. **Sound.** Both host and client should hear the toggle nearby. **Known doubt:**
    the sound goes out through `playServerSound` when `isServer()`, which is the
    vanilla pattern (`STrapGlobalObject.lua:118-124`) but sends to *remote*
    connections — the host may not hear its own toggle. Note what actually happens.
20. **Power loss in Host mode.** Cut the generator; the computer turns off on both
    sides within a minute.

## Things worth watching that I could not test

- The `file = media/sound/CeroSecToggle.ogg` clip form is not used by any vanilla
  sound script (they all use FMOD `event =`). If nothing plays, the sound script is
  the first suspect, not the toggle logic — `CeroSec.DEBUG = true` will still show the
  state flipping.
- The glow colour and radius (`CeroSec.LIGHT_R/G/B` = 0.55/0.65/0.85, radius 3, in
  `client/CeroSec/CCeroSecObject.lua`) are a guess made without seeing a screen.
  Adjust there.
- `IsoObject.checkLightSourceActive` deactivates a light on an unpowered square, so a
  lit computer that somehow keeps its sprite on a dead square would go dark before our
  one-minute check catches it. That should look right, but confirm it does not flicker.

# CeroSec rung 1b — stand in front, reach it or don't

Same rules as above: fresh game, mod enabled, eyes on the screen. Rung 1b changes
*how* the toggle is reached, never what it does, so re-run at least steps 3, 5 and
6 of rung 1 after this section to be sure nothing regressed.

## C — Posture and access

21. **On a desk (the normal case).** Right-click an office computer, "Turn on
    computer". The character must walk to the square the **screen looks at** — not
    the nearest free tile — stop on it, turn to the monitor, and only then play the
    standing loot animation and flip the sprite. Watch the walk: if he ends up
    beside or behind the desk, the front square is wrong.
22. **All four facings.** Repeat 21 on computers facing S, E, N and W. The square he
    stands on is always the one the screen points at: S → the square below (y+1),
    N → above (y-1), E → to the right (x+1), W → to the left (x-1).
23. **On the floor (low).** Pick a computer up, drop it on bare floor, right-click →
    "Turn on computer". Same walk, but the animation must be the **crouched** loot
    (`Bob_IdleLooting_Low`), not the standing one. The sprite still flips and the
    glow still appears.
24. **On two stacked crates (too high).** Stack two crates (place one, place the
    second on it), put the computer on top. The option must be **greyed out** and the
    tooltip reads "This computer is too high to reach." / "Cet ordinateur est trop
    haut pour l'atteindre." Note the crate heights used — the threshold is vanilla's
    own 64-pixel stacking limit, so a single crate should still be usable and two
    should not.
25. **Front square against a wall.** Push a desk against a wall so the computer's
    screen looks *into* the wall. The option is greyed out with "You cannot stand in
    front of this computer." / "Impossible de se placer devant cet ordinateur." Going
    round to the back must not help: the front square is the only way in.
26. **Front square blocked by furniture.** Put something solid on the front square (a
    second desk, a fridge). Same greyed option and the same tooltip.
27. **Front square across a window.** Computer inside, front square outside through a
    closed window: greyed out. Open the window and it stays greyed — a window is not
    a place to stand.
28. **Already standing there.** Stand on the front square, right-click → toggle. No
    walk at all, straight into the animation.
29. **Interrupt the walk.** Start the toggle from across the room and press a movement
    key while he walks. He stops, the computer does **not** toggle, no Lua error.
30. **Path blocked mid-walk.** Start the toggle, then close a door in the way (or use
    a spot with no path at all). The walk fails and nothing toggles.
31. **Walk away during the action.** Start the toggle, and as the animation begins run
    off the front square. The action drops and the sprite does not change.
32. **No-power tooltip still there.** With the power out, a reachable computer on a
    desk still shows "This computer has no power." — the reach checks come first,
    so a computer that is both unreachable and unpowered shows the reach reason.
33. **Turn off has the same manners.** A lit computer greys out the same way when it
    is too high or has no front square, and the walk-and-face happens before it goes
    dark.

## D — Host (co-op)

34. **Client walks too.** From a second client, everything in section C behaves the
    same.
35. **Server refuses a far toggle.** The server now drops a `toggle` from a player
    who is not adjacent to the computer (1.6 squares on each axis, same level). Nothing
    in normal play should hit this; what matters is that normal play never hits it —
    if a legitimate toggle is ever ignored on a host game, this check is the first
    suspect.

## Rung 1b doubts only the game can settle

- The "too high" threshold is vanilla's placement limit (`currentSurface <= 64`,
  `ISMoveableSpriteProps.lua:1622`), not a documented reach limit. Two crates may or
  may not cross it depending on the crate sprites' `Surface` values — step 24 is
  what tells us.
- A desk whose tile lacks `IsTable`/`Surface` reads as height 0, so the character
  would crouch to a desk-height computer. If step 21 plays the low animation, that
  desk is the reason.
- The turn is a step of its own, not a condition. On arrival the character stands
  still on the front square, pivots to the screen, and only then starts the loot
  animation; he stays turned for the whole animation. Watch that order in steps 21,
  23 and 28 — a toggle that fires while he still faces the way he walked in, or a
  character who drifts back to his walking direction mid-animation, means
  `waitToStart`/`update` are not doing their job.
- The pivot costs a fraction of a second before the action starts. If it ever reads
  as a hitch, or if the character seems stuck turning forever without the animation
  beginning, `shouldBeTurning` never returns false and the action never starts.

## E — Picking

The option must appear wherever the computer is *drawn*, not wherever the game
decides the click belongs. Right-click each spot and read the menu; turn
`CeroSec.DEBUG = true` in `CeroSecDefs.lua` first if a spot misbehaves — the
console then prints the mouse point and every candidate box that was tested.

36. **Bottom of the monitor, on a crate.** A computer on a crate, right-click the
    lower half of the screen. "Turn on computer" is there. (This already worked.)
37. **Top of the monitor, on a crate.** Same computer, right-click the topmost
    pixels of the monitor. "Turn on computer" is there now. Before the fix this
    showed only the options of the square behind ("Sit on ground", "Walk to").
38. **Just above the monitor.** Right-click one or two pixels above the sprite's
    top edge. The option is **gone** — we must not steal clicks off the object.
39. **On the crate behind.** Right-click a crate standing on the square behind the
    computer, on pixels that belong to that crate and not to the monitor. The
    crate's own options show and there is no "Turn on computer".
40. **Between the keys.** Right-click a transparent gap inside the computer's
    sprite box (the corner of the tile diamond, beside the tower). No option: the
    test is on the sprite's pixels, not on its box.
41. **On the floor.** A computer sitting on the ground, right-click low and high on
    it. The option is there both times, and the greying rules are unchanged.
42. **On a desk.** Same, on a desk or counter: both halves of the monitor answer.
43. **Zoomed all the way in, and all the way out.** Repeat 37 and 39 at both zoom
    ends. The boxes are scaled by the zoom, so a spot that works at one zoom and
    misses at another means the zoom factor is wrong, not the offset.
44. **Two computers, one behind the other.** Put a computer on a desk and another
    on the square in front of it. Right-click where the front one covers the back
    one: the option acts on the **front** one (walk target, on/off state).
45. **Joypad.** With a controller, open the world menu on a computer. There is no
    mouse to test, so the old square scan answers and the option still appears.

## Picking doubts only the game can settle

- The whole diagnosis rests on `FBORenderObjectPicker.getObjectsAt`, read in the
  **older** decompiled build. If 42.20.4 widened its `leftSideXy`/`rightSideXy`
  walk, or if `PerformanceSettings.fboRenderChunk` is off (the legacy
  `IsoObjectPicker.Add` path registers every rendered sprite and has no such
  window), the top-of-monitor click was already working and our pass simply
  agrees with it. Step 37 is what tells us the fix was needed.
- The drawn box is rebuilt as vanilla does for the water shader's click box
  (`FBORenderObjectPicker.handleWaterShader`): 64 x 128 tile units at the
  square's screen position, raised by `getRenderYOffset() * tileScale`. It leaves
  out `IsoObject.offsetX/offsetY`, which are public fields with no getter and are
  zero for a static world object. A computer that answers a few pixels off in one
  direction only would be that.
- `PICK_REACH = 2` covers a raise of 128 screen pixels at zoom 1, which is the
  vanilla placement ceiling (`Surface <= 64`, times `tileScale` 2). A computer on
  something taller than the game itself allows would need a third step.
- Step 44 assumes the front-most computer wins. The order is by `x + y` then by
  index in the square; if the wrong one answers, that ordering is the suspect.
