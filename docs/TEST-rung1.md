# CeroSec rung 1 — manual test checklist

Build 42.20.4. Nothing here can be driven from a headless agent, so it needs a pair
of eyes. Enable **CeroSec** in the mod list of a **new** game each time (rung 1 adds a
GlobalObject system; an existing save has no `gos_cerosec.bin`, which is handled, but
a fresh world keeps the runs comparable).

Turn `CeroSec.DEBUG = true` in
`Contents/mods/CeroSec/42/media/lua/shared/CeroSec/CeroSecDefs.lua` if you want the
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
