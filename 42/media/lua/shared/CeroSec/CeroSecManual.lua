-- The shelf's root table, and nothing else any more.
--
-- This file WAS the manual: one volume, correct, written for somebody who had
-- used a bigger Unix before, and it carried the whole machine on its own until
-- the documentation SET was written. The set is three volumes --
-- CeroSecManualUser.lua, CeroSecManualAdmin.lua, CeroSecManualProgrammer.lua --
-- and between them they cover every command the shell has and every refusal the
-- machine can print (tests/manual_test.lua holds them to it, volume by volume
-- and over the union of the three). So the single book has been retired: two
-- books describing one machine is one book too many, and the one that goes is
-- the one nobody is meant to read.
--
-- What is left is the table the three volumes hang themselves on. Each of them
-- opens with the same two defensive lines this file does, so none of them cares
-- which file the game loads first, and this one is not needed for the shelf to
-- stand up -- it is kept because the shelf's contract is worth having written
-- down in the file the contract is named after. There is no text here, no
-- version literal, and nothing that reads CeroSecOS at load time.
--
-- The reader (CeroSecManualUI), the loot tables (CeroSecManualLoot) and the
-- inventory menu (CeroSecManualMenu) all resolve a volume by id and nothing
-- else. `CeroSec.Manual`, the item the first book shipped as, is still defined
-- because it is in saves, and it opens volume one -- the volume it became.

CeroSecManual = CeroSecManual or {}
CeroSecManual.volumes = CeroSecManual.volumes or {}
