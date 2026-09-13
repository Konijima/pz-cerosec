# What the right-click gives the menu — the proof

Everything below is read out of the shipped jar of **B42 42.20.4**,

```
javap -p -c -cp ~/.local/share/Steam/steamapps/common/ProjectZomboid/projectzomboid/projectzomboid.jar <class>
```

and out of the vanilla Lua under
`~/.local/share/Steam/steamapps/common/ProjectZomboid/projectzomboid/media/lua/`.
`decompiled-src` is from January, older than the jar, and is not cited.
Bytecode offsets are the `javap -c` offsets of the method named beside them.

This note exists because the picking code in `CeroSecReach.lua` was written on a
guess — that the game's picker "only walks a 3-tile diagonal" and therefore never
looks at the square of a raised sprite — and the guess was wrong in a way that
hid two real defects. Both are named at the end.

---

## 1. The pipeline, end to end

### `UIManager.update` — one object, chosen on the mouse MOVE

`zombie.ui.UIManager.update`:

| offset | what |
| --- | --- |
| `1078-1086` | `IsoObjectPicker.Instance.ContextPick(mx, my)` → `UIManager.setPicked(ClickObject)` |
| `615-656` | right button pressed: fires `OnObjectRightMouseButtonDown` with `picked.tile` |
| `751-802` | right button released: fires **`OnObjectRightMouseButtonUp`** with `picked.tile`, an `IsoObject` |

So the object the menu is built for is picked on the last **mouse move**, stored in
a static field, and the click only reads it back. It is exactly **one**
`IsoObject`.

### `ISObjectClickHandler.doRClick` — `worldobjects` is that one object plus six

`media/lua/server/ISObjectClickHandler.lua:22-64`, bound at the bottom of the file
to `OnObjectRightMouseButtonUp`:

```lua
local objects = {}
if (sq and sq:isSeen(0)) or instanceof(object, "IsoWindow") or ... then
    table.insert(objects, object);
end
-- then PickDoor, PickWindow, PickWindowFrame, PickThumpable, PickHoppable, PickTree
if #objects == 0 then return end
ISContextManager.getInstance().createWorldMenu( 0, object, objects, x, y );
```

`ISContextManager.createWorldMenu` → `ISMenuContextWorld.createMenu` →
`ISWorldObjectContextMenu.createMenu(player, worldobjects, x, y, test)`
(`media/lua/client/ISUI/ISWorldObjectContextMenu.lua:143`), which triggers
`OnFillWorldObjectContextMenu` at `:213`.

**Therefore: `worldobjects` is the single picked object, plus a door, a window, a
window frame, a thumpable, a hoppable and a tree — none of which is ever a
computer.** A mod that reads `worldobjects` reads one object.

### The debug lines in the screenshot name that object

`ISWorldObjectContextMenuLogic.fetch` (Java) sets `fetch.tilename` and
`fetch.tileObj` from **each** object in turn (`@499-591`), so the last one wins,
and `fetch.clickedSquare` from that object's square (`@2474-2482`).
`createMenuEntries` prints them:

* `Tile Report: <tilename>` — `ISWorldObjectContextMenu.addTileDebugInfo`, called at `@156-185`
* `Room Report: <room>, x, y, z` — `@253-337`, the x/y/z of **`clickedSquare`**

So `Tile Report: furniture_seating_indoor_02_0` /
`Room Report: office, x: 2089, y: 5833, z: 0` is not a ground projection and not
the mouse tile: it is **the picked object and its own square**. The game picked
the chair.

### `ContextPick` — per-object alpha mask over every rendered object

`IsoObjectPicker.ContextPick` (`@0-14`) forwards to
`FBORenderObjectPicker.ContextPick` when `PerformanceSettings.fboRenderChunk` is
on, and otherwise runs the legacy path in the same method (`@15-719`) over
`thisFrame`, the list the renderer filled by calling `IsoObjectPicker.Add`. **Both
paths do the same three things**, which is what matters here:

`FBORenderObjectPicker.ContextPick`:

| offset | what |
| --- | --- |
| `11-23` | the mouse is multiplied by `Core.getZoom(0)` — world screen units |
| `43-50` | `getClickObjects(mx, my, clickObjects)` |
| `71-98` | walks the candidates **backwards** |
| `130-164` | skips `targetAlpha == 0` and `shouldIgnoreWallLikeObject` |
| `167-224` | box test against the ClickObject's `x, y, width, height` |
| `333` / `429` | **`IsoObject.isMaskClicked(px - x, py - y, flip)`** — the sprite's own alpha mask |
| `528-549` | every survivor gets `ClickObject.calculateScore()` |
| `558-580` | sorted with `IsoObjectPicker.comp` |
| `601-620` | **the LAST element is returned** |

`IsoObjectPicker.comp` (`IsoObjectPicker$1.compare`) is ascending by score, and
ties on the same square are broken by `getObjectIndex()`. The last element is
therefore the **highest score**, and on one square the object drawn last.

**Answer to the question: the game picks by per-object alpha mask over every
object that was rendered, not by a square walk.** The square walk is only how the
candidate list is gathered, and the box each candidate is tested against is the
box the renderer really drew it into.

### `getClickObjects` — the box is the renderer's own

`FBORenderObjectPicker.getClickObjects` (`@26-433`) takes every field of the box
off `ObjectRenderInfo`:

| offset | field |
| --- | --- |
| `211-232` | `x = renderInfo.renderX`, `y = renderInfo.renderY` (translucent layers) |
| `288-325` | otherwise `x = chunk.renderX * zoom + renderInfo.renderX`, same for y |
| `341-360` | `width = renderInfo.renderWidth`, `height = renderInfo.renderHeight` |
| `363-384` | `scaleX = (int) renderInfo.renderScaleX`, same for y |

And `ObjectRenderInfo` is filled by
`IsoObject.updateRenderInfoForObjectPicker` (`@0-548`) during rendering:

| offset | what |
| --- | --- |
| `35-126` | a 64×128 texture at `tileScale == 2` is drawn at scale 2; a 128×256 one at scale 1 |
| `216-279` | `sx = IsoUtils.XToScreen(...)`, `sy = IsoUtils.YToScreen(...)` |
| `284-315` | **`sx -= offsetX`**; **`sy -= offsetY + renderYOffset * Core.tileScale`** |
| `358-380` | `renderX = sx - IsoCamera.frameState.offX` (and `renderY` likewise) |
| `496-521` | `renderWidth = texture.getWidthOrig() * scaleX`, `renderHeight = ... * scaleY` |

`IsoObject.<init>` (`@38-57`), and again `IsoObject.reset` (`@201-220`):

```
offsetX = 32 * Core.tileScale
offsetY = 96 * Core.tileScale
```

Both are readable from Lua: `public float getOffsetX();` `public float getOffsetY();`

`getObjectsOnSquare` (`@0-165`) is the filter on what is offered at all: an object
whose `renderInfo.layer` is `None` or whose `targetAlpha` is 0 is dropped unless
its sprite has the `water` flag, and otherwise it needs
`renderWidth > 0 and renderHeight > 0`. **Nothing that was not rendered this frame
can be picked.**

### `getObjectsAt` — the staircase, out of the MOUSE's tile

`FBORenderObjectPicker.getObjectsAt` (`@166-318` for a player at z ≥ 0, `@22-165`
for below): for each `z` in `0..31`,

```
isoX = IsoUtils.XToIso(0, mx, my, z)
isoY = IsoUtils.YToIso(0, mx, my, z)
side = (isoX % 1 > isoY % 1) ? rightSideXy : leftSideXy
for each pair (dx, dy) in side:  getObjectsOnSquare(floor(isoX)+dx, floor(isoY)+dy, z, out)
```

and the two arrays, from the constructor (`@75-216`):

```
leftSideXy  = {0,0} {0,1} {1,1} {1,2} {2,2} {2,3} {3,3}
rightSideXy = {0,0} {1,0} {1,1} {2,1} {2,2} {3,2} {3,3}
```

Three diagonal steps — but three diagonal steps is **six steps of x + y**, and six
steps of x + y is the whole height of a sprite box (§2). The "3-tile diagonal" is
not a narrow budget; it is exactly the right one for an unraised sprite.

### `calculateScore` — why the chair wins

`IsoObjectPicker$ClickObject.calculateScore` (`@0-696`), starting at `1.0`:

| offset | term |
| --- | --- |
| `11-111` | `+ abs(dot(player facing, direction to the square) * 4)` |
| `155-229` | a door, or a thumpable that is a door: `+6`, `+1` more if adjacent |
| `232-264` | a window: `+4` |
| `267-294` | same room as the player: `+1`, **else `-100000`** |
| `295-313` | the player is above the square: `-1000` |
| `314-384` | the local player: `-100000`; a see-through thumpable with no container: `-100000` |
| `385-400` | a curtain: `+3` |
| `401-416` | a light switch: `+20` |
| `417-437` | **the sprite has `IsoFlagType.bed`: `+2`** |
| `438-453` | it has a container: `+10` |
| `454-469` | a generator: `+11` |
| `470-485` | an `IsoWaveSignal`: `+20` |
| `486-506` | a thumpable with a light source: `+3` |
| `507-528` | `waterPiped`: `+3` |
| `529-550` | `solidfloor`: `-100` |
| `551-607` | a west roof: `-100` |
| `608-642` | `cutW` or `cutN`: `-2` |
| `643-655` | an interactive entity (a `UiConfig` with a window class): `+2` |
| `656-693` | **`- IsoUtils.DistanceManhatten(square centre, player) / 2`** |
| `694-696` | cast to `int` |

Everything from the curtain down is exclusive — each one jumps to the end.

A **vanilla computer** is a plain `IsoObject`: no container, no flag on that list,
no `UiConfig`. It gets nothing from the exclusive chain.

A **desk chair** carries `IsoFlagType.bed` — that is the flag `IsoGridSquare.getBed`
collects and the flag `CeroSecReach.chairInFront` already reads — so it gets `+2`.
And it stands on the square the player is standing (or sitting) on, so it pays
almost none of the Manhattan penalty while the desk one square away pays half a
step of it.

> **So: with the cursor on the monitor of a computer on a desk, and a chair pulled
> up in front of that desk, the game considers both, and if both masks are hit the
> chair wins by about two and a half points. `worldobjects` is then `{chair}` — and
> the chair's square is one step SOUTH of the desk's.**

Whether both masks are hit at one pixel depends on how far the chair's back
reaches up the screen into the monitor's band, which is a sprite question and not
a code question: sometimes it does and sometimes it does not, which is exactly the
"often" in the report.

### What vanilla itself does about objects on tables

Nothing special in the picker — a lamp on a table is its own `IsoObject` with its
own `renderYOffset`, its own box and its own mask, and the picker resolves it the
same way it resolves the table. What vanilla's **menus** do, when the device they
are about may be sitting on something, is widen from the picked object to its
square:

* `media/lua/client/ISUI/ISRadioAndTvMenu.lua:16-26` — for each of `worldObjects`, walk `object:getSquare():getObjects()` looking for an `IsoRadio`
* `media/lua/client/ISUI/ISBBQMenu.lua:20` — the same, for a barbecue
* `ISWorldObjectContextMenuLogic.getAllObjects` (`@0-121`) → `getAllObjectOnSquare` (`@0-77`) — the debug menu's own expansion: every object on the square of every picked object

That is the pattern `CeroSecContextMenu.findComputer` now runs **first**.

### And vanilla resolves the mouse to a tile the same way we now do

`media/lua/client/Context/ISMenuContextWorld.lua:74-79`, in the very call chain the
right-click runs down (`ISContextManager.createWorldMenu` → `menuWorld.createMenu`,
the same function that calls `ISWorldObjectContextMenu.createMenu` at `:45`/`:48`):

```lua
contextData.objects = self.getAllObjects(contextData);

if not JoypadState.players[_playerNum+1] then
    local wx,wy = ISCoordConversion.ToWorld( _x*getCore():getZoom(contextData.playerNum), _y*getCore():getZoom(contextData.playerNum), contextData.player:getZ() );
    self.getObjectsSquare( contextData, getCell():getGridSquare(wx, wy, contextData.player:getZ()) );
end
```

Three things, all of them the mod's own pattern and none of them invented here:

* `ISCoordConversion.ToWorld` is called **from client code**, so the `media/lua/server`
  folder it lives in is in the client's Lua state. (`FishingDebugWindow.lua`,
  `ISRemoveItemTool.lua` and `FireBrushUI.lua` call it too.)
* the mouse is multiplied by `getCore():getZoom(playerNum)` before it is converted —
  the same space `ContextPick` puts it in, and the space `CeroSecReach.pickSquares`
  works in.
* the whole of it is behind `not JoypadState.players[_playerNum+1]`, which is the
  guard `CeroSecContextMenu.findComputer` uses for its own mouse pass.

Vanilla takes the one square the mouse lands on; `pickSquares` takes the window of
§2 around it, because a raised sprite is not drawn on its own tile. The level is the
one the game resolved the click to rather than vanilla's `player:getZ()`.

---

## 2. The projection, and which squares can be drawn over a point

`IsoUtils` (all four confirmed as each other's inverses, and benched in
`tests/terminal_test.lua`):

```
XToScreen(x, y, z, n) = 32 * tileScale * (x - y)
YToScreen(x, y, z, n) = 16 * tileScale * (x + y) + (n - z) * 96 * tileScale
XToIso(n, sx, sy, z)  = (sx' + 2 * sy') / (64 * tileScale) + 3 * z
YToIso(n, sx, sy, z)  = (2 * sy' - sx') / (64 * tileScale) + 3 * z
        with sx' = sx + IsoCamera.getOffX(n), sy' = sy + IsoCamera.getOffY(n)
```

`ISCoordConversion.ToScreen` is `XToScreen/YToScreen` less `getCameraOffX/Y`, and
`ISCoordConversion.ToWorld` is `XToIso/YToIso`, so the two are inverses in the
same space — the space the picker puts the mouse in by multiplying it by the zoom.

Writing `s = x + y` and `d = x - y`, a square's anchor is
`(32 * ts * d, 16 * ts * s)` and the box the renderer draws into is

```
left   = anchorX - offsetX                                = anchorX - 32 * ts
top    = anchorY - offsetY - renderYOffset * ts           = anchorY - 96 * ts - raise * ts
width  = 64 * ts          height = 128 * ts
```

The box contains the mouse point when

```
anchorY(s) - 96*ts - raise*ts  <  mouse.y  <=  anchorY(s) + 32*ts - raise*ts
anchorX(d) - 32*ts             <  mouse.x  <=  anchorX(d) + 32*ts
```

which, in steps, is

```
s(mouse) - 2 + raise/16  <=  s  <=  s(mouse) + 6 + raise/16
d(mouse) - 1             <=  d  <=  d(mouse) + 1
```

`raise` is a render offset and a table-top object's never exceeds
`CeroSecReach.SURFACE_MAX` = 64 (`ISMoveableSpriteProps.lua:1620-1622`), so
`raise/16` runs `0..4`:

> **The squares that can be drawn over a screen point are the ones from 2 steps of
> x + y behind the mouse's own position to 10 steps in front of it, and one step of
> x − y either side.**

Six of those ten are the game's own staircase. The other four are the raise —
which is the part the game itself would miss, on a sprite raised the full 64 whose
opaque pixels are high in its sheet. No shipped computer sprite draws that high;
a monitor's pixels are low in the texture, which is why the measured distance for
the screenshot is **2 steps**, nowhere near the edge of anything.

Two more steps are needed on top, because a square is named by integers: the
mouse's tile is `floor(XToIso)`, `floor(YToIso)`, and each floor loses up to a
whole step of its own — up to two off the sum, always forward. Hence

```
CeroSecReach.PICK_BEHIND = 2
CeroSecReach.PICK_AHEAD  = 6 + SURFACE_MAX/16 + 2 = 12
CeroSecReach.PICK_SIDE   = 1
```

A sweep over every raise and every pixel of a box
(`tests/terminal_test.lua`) reaches exactly `-2`, `+11` and `±1`: behind and aside
are tight, ahead carries one step of slack because both bounds it is built from
are strict.

`s` and `d` always have the same parity (`s + d = 2x`), so half the pairs in that
window name no square at all — which is why the game's own candidates read as a
staircase rather than as a block.

---

## 3. The two defects this proved

**The candidate squares were anchored on the wrong square.**
`pickCandidates` walked `(+0..2, +0..2)` out of the square of the object the game
picked. But that object is itself somewhere inside the staircase the game walked
out of the **mouse's** tile, so walking a forward-only staircase again out of it
points away from the start. In the screenshot the picked object is the chair at
`2089,5833`; the desk is at `2089,5832`, i.e. `dy = -1`; the old scan covered
`2089..2091 × 5833..5835` and never looked at the desk once. Nothing was in front
of anything — the search was pointed the wrong way. *"Something invisible in
front" was the search's own blind side.*

**The box was 64 px right and 192 px low.** `drawnBox` took
`ISCoordConversion.ToScreen` as the box's top-left. The renderer subtracts
`offsetX = 32 * tileScale` and `offsetY = 96 * tileScale` from it. At `tileScale`
2 that is 64 and 192 — three quarters of a sprite height — so `isMaskClicked` was
asked about a pixel three quarters of a sprite below the pixel the cursor was
really on, and the only way to hit a monitor's mask was to click most of a tile
under it. *"Sometimes I almost have to click the ground."*

`docs/TEST-rung1.md` had recorded the second one as a doubt — "it leaves out
`IsoObject.offsetX/offsetY`, which are public fields with no getter and are zero
for a static world object". Both halves of that were wrong: there are getters, and
they are never zero.

---

## 4. Settled by a second reading of the jar

An adversarial pass over the fix (2026-09-12) closed three of the things this note
first listed as open:

* **`ISCoordConversion` is in the client's Lua state.** `LuaManager.LoadDirBase()`
  loads only `shared` + `client`, but `GameLoadingState.enter()` calls
  `LoadDirBase("server")` on the straight-line path — the `GameClient.client` test
  at `@21` guards only a port-warning string, not the load — and `GameServer` loads
  all three. Vanilla client callers exist besides
  `ISMenuContextWorld.lua:77,249`: `client/DebugUIs/ISRemoveItemTool.lua` and
  `client/Fishing/FishingDebugWindow.lua`. Singleplayer and multiplayer both.
* **`XToIso`/`YToIso` use the same camera as `getCameraOffX()`.** The 3-arg
  `XToIso(F,F,F)` forwards to `XToIso(IsoPlayer.getPlayerIndex(), …)`, and
  `getCameraOffX()` → `IsoCamera.getOffX()` → `cameras[IsoPlayer.getPlayerIndex()]`.
  Same index, no zoom in either, and the round trip
  `XToIso(XToScreen − offX, YToScreen − offY, z) == x` is exact.
* **The chunk-relative `renderX` reassembles to the world formula.** `isCaching()`
  does replace x, y with `PZMath.coordmodulof(x, 8)` and store
  `renderInfo.renderX = sx + xoff` with `xoff = renderChunk.w / 2`
  (`FBORenderChunkManager.beginRenderChunkLevel` `@36-42`), but the blit sets
  `chunk.renderX = (XToScreen(wx*8, wy*8) − getOffX()) / zoom − w_eff/2 + fixJigglyModelsX`,
  so the `w/2` cancels and `chunk.renderX * zoom + renderInfo.renderX` is
  `XToScreen(world) − camOffX − offsetX`. On Y it cancels too, because
  `PIXELS_PER_LEVEL == 96 * Core.tileScale` is exactly `YToScreen`'s per-level step,
  so the level terms annihilate against `yoff`. The mask index matches as well: the
  engine does `(int)((mouse − x) / scaleX)`, the mod `math.floor((px − x) / scaleX)`.

## 5. What is still only settleable by a click in game

* **`IsoSprite.def.offX/offY/offZ`.** The renderer ADDS them to the tile coordinates
  before `XToScreen` (`@224-276`), and `IsoObject.load` restores them from the save,
  so a sprite carrying a placement offset is drawn away from its square's anchor and
  `drawnBox` does not know it. They are reachable only through `IsoSprite.def`, a
  public **field** whose accessor `getSpriteInstance()` is private, and no vanilla
  Lua anywhere reads a Java instance field — so this is left alone rather than
  guessed at. A computer that answers a whole tile off, and only after being nudged
  or placed with extended placement, is this.
* **`PlayerCamera.fixJigglyModelsX/Y`.** A sub-pixel camera-jitter term
  (`DebugOptions.fboRenderChunk.fixJigglyModels`) that is inside `chunk.renderX` and
  not inside `ISCoordConversion.ToScreen`. At most about a pixel, and a pixel does
  not decide a mask, but it is a difference.
* **The zoom's player index.** `getClickObjects` and `ContextPick` hardcode
  `Core.getZoom(0)`; the mod uses `getZoom(playerIndex)`, matching
  `ISMenuContextWorld.lua:77` and matching `getCameraOffX()`, which is per player
  index. They differ only in split-screen, where the mouse pass does not run anyway
  (the joypad guard).
* **Whether the chair's back really overlaps the monitor's band** on the sprites in
  the screenshot — i.e. whether the chair beat the computer on score or the computer
  was never masked at all. Either way the fix is the same, and the **Log** tab now
  says which.
* **`Core.tileScale` and the whole of it at a zoom other than 1.** Every box term is
  linear in `tileScale` and the mouse is the only thing multiplied by the zoom, so the
  arithmetic should not care. Untested.
* **Which picker path runs.** `PerformanceSettings.fboRenderChunk` decides, and both
  paths mask and score identically, so the conclusion holds either way; only the
  candidate gathering differs.
