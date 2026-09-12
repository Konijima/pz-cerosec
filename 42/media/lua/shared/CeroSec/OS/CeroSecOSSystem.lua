--
-- CeroSec OS core: the system files, the boot check and the BIOS repair.
--
-- A machine is a filesystem and nothing else. What makes it a machine that can
-- be used is what is IN that filesystem: the commands in /bin and the accounts
-- in /etc/passwd. Take either away and the computer is a box with a disk in it,
-- which is exactly what `rm -r /bin` as root is meant to leave behind.
--
-- The way back is the BIOS, not a guard rail on the command: root keeps full
-- power, and the protection is that root has a password. So nothing below
-- refuses a destruction; what is here is the check that says the machine is no
-- longer bootable, and the repair a player answers "y" to.
--

CeroSecOS = CeroSecOS or {}

--
-- /bin
--
-- The commands are files. The shell resolves a name by looking /bin/<name> up
-- and testing x on it for the user who typed it, so `rm /bin/ls` really does
-- take ls away and `chmod 644 /bin/ls` really does put it out of reach of
-- everybody but root -- who bypasses the bits the way root bypasses everything.
--
-- Only /bin. There is no PATH and no ./thing: copying /bin/ls into a home
-- directory and running it from there is not supported, and the copy is an
-- ordinary file that no shell will look at.
--

-- Every command in one deterministic order, from the descriptions rather than
-- from the command table: a command with no description does not get a file,
-- which is what keeps `help` from ever having a blank line in it.
--
-- Minus the words that are the shell itself. `cd` cannot be a file in Unix and
-- must not be one here: a program cannot move the shell that ran it, so there is
-- nothing an executable of that name could have contained. Same for exit, and
-- for jobs and wait, which own what the shell started. They keep their
-- description and their usage line -- `help` lists them under the table of
-- files and `man` prints them -- and they have no executable.
function CeroSecOS.binNames()
	local names = {}
	for name, _ in pairs(CeroSecOS.COMMAND_INFO or {}) do
		if not CeroSecOS.isShellWord(name) then names[#names + 1] = name end
	end
	table.sort(names)
	return names
end

-- Put the standard set into a directory, one file each, owner root and mode
-- 755. Authoritative for the commands: an executable that is there is reset to
-- the standard owner, mode and description, so a machine repaired from the BIOS
-- comes back from `chmod 000 /bin/ls` too. Anything else in /bin is left
-- exactly where it is -- it is not ours to take away.
function CeroSecOS.fillBin(bin)
	if type(bin) ~= "table" or bin.type ~= "dir" or type(bin.children) ~= "table" then
		return nil
	end
	local names = CeroSecOS.binNames()
	for i = 1, #names do
		bin.children[names[i]] = CeroSecOS.newFile("root", 755, CeroSecOS.commandDesc(names[i]))
	end
	return bin
end

-- A top level directory of the machine's own, made or replaced. Used by the
-- repair and by the migration, and by nothing a player can reach.
function CeroSecOS.ensureSystemDir(state, name)
	if type(state) ~= "table" then return nil end
	if type(state.fs) ~= "table" or state.fs.type ~= "dir" or type(state.fs.children) ~= "table" then
		state.fs = CeroSecOS.newDir("root", 755)
	end
	local node = state.fs.children[name]
	if type(node) ~= "table" or node.type ~= "dir" or type(node.children) ~= "table" then
		node = CeroSecOS.newDir("root", 755)
		state.fs.children[name] = node
	end
	return node
end

-- /mnt, the one directory a disk is mounted on. Root's at 755 and shipped empty,
-- which is what /mnt has been on every Unix that had one: it is a PLACE and not a
-- drawer, and a machine that kept files in it would be a machine whose files
-- disappear the moment somebody mounts something.
--
-- Made only where the name is free, like everything else the machine seeds: a
-- /mnt root deleted stays deleted, and anything else at that name is somebody's
-- own work.
function CeroSecOS.ensureMnt(state)
	if type(state) ~= "table" then return nil end
	if type(state.fs) ~= "table" or type(state.fs.children) ~= "table" then return nil end
	local node = state.fs.children[CeroSecOS.MNT_NAME]
	if node ~= nil then return node end
	if CeroSecOS.countEntries(state.fs) >= CeroSecOS.MAX_DIR_ENTRIES then return nil end
	node = CeroSecOS.newDir("root", CeroSecOS.MNT_MODE)
	state.fs.children[CeroSecOS.MNT_NAME] = node
	return node
end

-- The `wheel` group and the /etc/sudoers line that grants it, added to whatever
-- the two files already hold. Each is written only where its own line is
-- missing, and each write goes through the ordinary filesystem gate, so a full
-- disk leaves both files byte for byte as they were.
--
-- true when it changed something. Used by the top-up and by nothing a player can
-- reach: a fresh machine ships with both lines already (defaultGroup,
-- defaultSudoers) and this finds nothing to do on one.
function CeroSecOS.ensureWheel(state)
	local changed = false
	local root = CeroSecOS.rootSession()

	local group = CeroSecOS.systemNode(state, CeroSecOS.GROUP_PATH)
	if type(group) == "table" and group.type == "file" then
		local groups, order = CeroSecOS.parseGroup(group.data or "")
		-- A file that parses to no group at all is the BIOS' business, exactly as
		-- an unparseable sudoers is: the repair writes the shipped groups back and
		-- wheel is one of them. A line added here would make that file parse to one
		-- group and so make the repair keep it for ever.
		if #order > 0 and groups[CeroSecOS.WHEEL_GROUP] == nil then
			local text = group.data or ""
			if text ~= "" then text = text .. "\n" end
			text = text .. CeroSecOS.groupLine({ name = CeroSecOS.WHEEL_GROUP, members = {} })
			if CeroSecOS.setData(state, root, CeroSecOS.GROUP_PATH, text) ~= nil then
				changed = true
			end
		end
	end

	local sudoers = CeroSecOS.systemNode(state, CeroSecOS.SUDOERS_PATH)
	if type(sudoers) == "table" and sudoers.type == "file" then
		local entries, order = CeroSecOS.parseSudoers(sudoers.data or "")
		-- A file that parses to NOBODY is not a list, and it is the BIOS' business
		-- and not this one's: the repair writes the shipped list back, and that one
		-- carries the wheel line already. Adding a line to a rubbish file here
		-- would make it parse to somebody and so make the repair keep it for ever.
		if #order > 0 and entries["%" .. CeroSecOS.WHEEL_GROUP] == nil then
			local text = sudoers.data or ""
			if text ~= "" then text = text .. "\n" end
			text = text .. "%" .. CeroSecOS.WHEEL_GROUP
			if CeroSecOS.setData(state, root, CeroSecOS.SUDOERS_PATH, text) ~= nil then
				changed = true
			end
		end
	end
	return changed
end

--
-- Topping an older machine up
--
-- A wave that adds a command adds a file to /bin, and a machine that was saved
-- before it has neither. That is not damage -- the BIOS is for damage -- and it
-- is not something to seed on every load either, because root deleting
-- /bin/ls is root's right and must stay deleted.
--
-- So the state carries the contents it was built with (state.sysv), and this
-- runs once, when that number is behind: it puts in the standard executables
-- that are MISSING and nothing else, writes /etc/sudoers only when there is
-- nothing at all at that name, and then moves the number up. At the current
-- number it does nothing at all, which is what keeps `rm /bin/ls` a deletion
-- and not a suggestion.
--
-- A name in /bin that is taken -- by a file of your own, by a directory -- is
-- left exactly where it is: this fills gaps, it does not replace.
--
-- true when it changed something.
function CeroSecOS.upgradeSystem(state)
	if type(state) ~= "table" then return false end
	local sysv = state.sysv
	if type(sysv) == "number" and sysv >= CeroSecOS.SYSTEM_VERSION then return false end

	-- The ceilings are the disk's and are not suspended for this: a machine
	-- filled to the node limit is topped up as far as it goes and no further,
	-- because the alternative is a state validate then refuses -- a working
	-- machine made unbootable by an upgrade it never asked for.
	local nodes, bytes = CeroSecOS.usage(state)

	local bin = CeroSecOS.systemNode(state, CeroSecOS.BIN_PATH)
	if type(bin) == "table" and bin.type == "dir" and type(bin.children) == "table" then
		-- The other direction, and the only thing here that takes anything away.
		-- Two kinds of name reach it and both are the same deed:
		--
		--   * a word that is the shell ITSELF (cd, exit, jobs, wait). Earlier
		--     versions shipped an executable for each, and a machine saved before
		--     that change has files that never had anything behind them;
		--   * a name this build RETIRED (CeroSecOS.RETIRED_BIN) -- adduser,
		--     deluser, gpasswd, hash -- which are names no Unix of 1993 had. The
		--     command is gone from the engine, so the file left in /bin would be a
		--     name `help` offers and the shell refuses.
		--
		-- They go -- but only where the file is exactly what was shipped: owner
		-- root, mode 755, and the very description that was seeded. Anything else
		-- at that name is a player's own work and is left where it is; nothing here
		-- is allowed to be a deletion somebody did not ask for.
		local function drop(name, desc)
			local node = bin.children[name]
			if type(node) ~= "table" or node.type ~= "file" then return end
			if node.owner ~= "root" or node.mode ~= 755 or node.data ~= desc then return end
			bin.children[name] = nil
			nodes = nodes - 1
			bytes = bytes - #(node.data or "")
		end
		local info = CeroSecOS.COMMAND_INFO or {}
		for name, entry in pairs(info) do
			if entry.shell == true then drop(name, CeroSecOS.commandDesc(name)) end
		end
		for name, desc in pairs(CeroSecOS.RETIRED_BIN or {}) do drop(name, desc) end

		local names = CeroSecOS.binNames()
		for i = 1, #names do
			local name = names[i]
			local info = CeroSecOS.commandDesc(name)
			if bin.children[name] == nil
					and nodes + 1 <= CeroSecOS.MAX_NODES
					and bytes + #info <= CeroSecOS.MAX_TOTAL_BYTES
					and CeroSecOS.countEntries(bin) < CeroSecOS.MAX_DIR_ENTRIES then
				bin.children[name] = CeroSecOS.newFile("root", 755, info)
				nodes = nodes + 1
				bytes = bytes + #info
			end
		end
	end

	local etc = CeroSecOS.systemNode(state, CeroSecOS.ETC_PATH)
	if type(etc) == "table" and etc.type == "dir" and type(etc.children) == "table" then
		if etc.children.sudoers == nil then
			local text = CeroSecOS.defaultSudoers()
			if nodes + 1 <= CeroSecOS.MAX_NODES and bytes + #text <= CeroSecOS.MAX_TOTAL_BYTES
					and CeroSecOS.countEntries(etc) < CeroSecOS.MAX_DIR_ENTRIES then
				etc.children.sudoers = CeroSecOS.newFile("root", CeroSecOS.SUDOERS_MODE, text)
				nodes = nodes + 1
				bytes = bytes + #text
			end
		end
		-- /etc/group, on the same terms: only when there is nothing at all at
		-- that name. A machine that has been running without one has every node
		-- on it in a group of its owner's own name, which is what a missing file
		-- means and not something to rewrite.
		if etc.children.group == nil then
			local text = CeroSecOS.defaultGroup()
			if nodes + 1 <= CeroSecOS.MAX_NODES and bytes + #text <= CeroSecOS.MAX_TOTAL_BYTES
					and CeroSecOS.countEntries(etc) < CeroSecOS.MAX_DIR_ENTRIES then
				etc.children.group = CeroSecOS.newFile("root", CeroSecOS.GROUP_MODE, text)
			end
		end

		-- The one thing here that adds a LINE to a file a player may have edited,
		-- and it is the pair of lines `wheel` is: a group with nobody in it, and the
		-- /etc/sudoers line that grants it. Neither gives anybody anything -- the
		-- group ships empty on a new machine for the same reason -- and without both
		-- of them `useradd -G wheel bob` on a machine off an older save would put bob
		-- in a group nothing reads, which is what the manual says wheel is NOT.
		--
		-- Once, at this version bump, and only where the line is not there at all: a
		-- line a player takes out AFTER the top-up stays out, because the number has
		-- moved and this never runs again.
		--
		-- What is deliberately NOT done is putting the accounts whose /etc/passwd
		-- line says "admin" into wheel. That flag never granted anything -- no
		-- command consulted it -- so an account carrying one is owed nothing, and a
		-- top-up that handed it root would be this build giving away a power the
		-- machine never had.
		CeroSecOS.ensureWheel(state)
	end

	-- /var, for a machine saved before there was a cron on it. Made only where
	-- it is missing, like everything else here.
	CeroSecOS.ensureVar(state)
	-- And the two network files, on the same terms: a machine saved before there
	-- was a wire in it has neither, and neither is damage.
	CeroSecOS.ensureNet(state)
	-- And /dev/null, for a machine saved before there was a hole in its disk.
	CeroSecOS.ensureDev(state)
	-- And /mnt, for a machine saved before there was a slot on the front of it.
	CeroSecOS.ensureMnt(state)

	state.sysv = CeroSecOS.SYSTEM_VERSION
	return true
end

--
-- /etc/hostname
--
-- The file is the name. `hostname` reads it, root may write it, and the server
-- reads it for the window title -- so a machine renamed by hand in the editor
-- is renamed everywhere the next time somebody looks.
--

function CeroSecOS.isValidHostname(name)
	if type(name) ~= "string" then return false end
	if #name < 1 or #name > CeroSecOS.HOSTNAME_MAX then return false end
	-- Never a leading "-": the name is written into the state as well, where
	-- validate tests it with isValidName, which refuses one.
	if string.find(name, "^[a-z0-9]") == nil then return false end
	return string.find(name, "[^a-z0-9%-]") == nil
end

-- Same one-slot, content-keyed cache the passwd parser has: the file is the
-- truth, and what makes the answer stale is the file changing.
CeroSecOS.hostnameCache = { node = nil, text = nil, name = nil }

-- The machine's name. The file when it holds one, the name on the state when it
-- does not -- a machine whose /etc/hostname was deleted still has to be called
-- something on a title bar and in a prompt.
function CeroSecOS.hostname(state)
	local fallback = CeroSecOS.DEFAULT_HOSTNAME
	if type(state) == "table" and CeroSecOS.isValidHostname(state.hostname) then
		fallback = state.hostname
	end
	local node = CeroSecOS.systemNode(state, CeroSecOS.HOSTNAME_PATH)
	if node == nil or node.type ~= "file" then return fallback end

	local cache = CeroSecOS.hostnameCache
	if cache.node ~= node or cache.text ~= node.data then
		local name = nil
		local lines = CeroSecOS.splitLines(node.data or "")
		if #lines > 0 then
			-- Greedy captures around one run of non-blanks: a first line with a
			-- space inside it does not match at all, which is the right answer
			-- for "ksp 1" rather than silently reading it as "ksp".
			local word = string.match(lines[1], "^[ \t]*([^ \t]*)[ \t]*$")
			if CeroSecOS.isValidHostname(word) then name = word end
		end
		cache.node = node
		cache.text = node.data
		cache.name = name
	end
	if cache.name == nil then return fallback end
	return cache.name
end

-- true, or nil plus a reason. Writes through writeFile, so /etc has to be there
-- and the ceilings apply; the state's own copy of the name is only moved once
-- the file has actually taken it.
function CeroSecOS.setHostname(state, name, now)
	if not CeroSecOS.isValidHostname(name) then return nil, "invalid name" end
	local done, reason = CeroSecOS.writeFile(state, CeroSecOS.rootSession(),
		CeroSecOS.HOSTNAME_PATH, name, false, now)
	if done == nil then return nil, reason end
	state.hostname = name
	return true, nil
end

--
-- /etc/motd
--

-- What is put on the screen after a login: the file, capped at MOTD_MAX_LINES.
-- A missing or empty file greets nobody -- root emptied it on purpose, and a
-- silent machine is a valid choice (the built-in line only seeds a new disk).
function CeroSecOS.motdLines(state)
	local node = CeroSecOS.systemNode(state, CeroSecOS.MOTD_PATH)
	if node == nil or node.type ~= "file" or (node.data or "") == "" then
		return {}
	end
	local lines = CeroSecOS.splitLines(node.data)
	local out = {}
	for i = 1, #lines do
		if i > CeroSecOS.MOTD_MAX_LINES then return out end
		out[i] = lines[i]
	end
	return out
end

--
-- The boot check
--
-- What the BIOS looks at before it hands the machine over. Deliberately not the
-- same question as validate's: validate asks whether the state is something the
-- core can run ON at all, this asks whether what is on the disk is still an
-- operating system. A state validate refuses never reaches here -- the server
-- has nothing to hand in -- and that counts as "no operating system" too.
--
-- true, or false plus the reason.
function CeroSecOS.systemOk(state)
	if type(state) ~= "table" or type(state.fs) ~= "table" then return false, "no filesystem" end

	local bin = CeroSecOS.systemNode(state, CeroSecOS.BIN_PATH)
	if bin == nil then return false, "no " .. CeroSecOS.BIN_PATH end
	if bin.type ~= "dir" then return false, CeroSecOS.BIN_PATH .. " is not a directory" end
	if CeroSecOS.countEntries(bin) == 0 then return false, CeroSecOS.BIN_PATH .. " is empty" end

	local passwd = CeroSecOS.systemNode(state, CeroSecOS.PASSWD_PATH)
	if passwd == nil then return false, "no " .. CeroSecOS.PASSWD_PATH end
	if passwd.type ~= "file" then return false, CeroSecOS.PASSWD_PATH .. " is not a file" end
	if not CeroSecOS.hasUsers(state) then return false, CeroSecOS.PASSWD_PATH .. " has no accounts" end

	return true
end

--
-- The repair
--
-- What "y" at the BIOS prompt does. It puts the system files back and touches
-- nothing else: /home, /root, /dev and anything a player made are not the
-- BIOS's business, and a machine repaired here keeps every file that was on it.
-- The homes explicitly included: an account's ~/.sh_history and its ~/.profile
-- are its own work, and a repair that swept them away would be a repair that
-- cost the player the thing he would least expect to lose.
--
-- Idempotent by construction: running it on a healthy machine rewrites the
-- executables to the very same contents and leaves everything else alone.
--
-- A /etc/passwd that still parses is KEPT, hashes and all, and so are a
-- /etc/sudoers that still names somebody and a /etc/group that still holds a
-- group. Losing the accounts is not part of
-- repairing the commands, and a root password somebody set is not something a
-- repair may quietly drop.
function CeroSecOS.restoreSystem(state)
	if type(state) ~= "table" then return nil, "no state" end

	local etc = CeroSecOS.ensureSystemDir(state, "etc")
	if etc.children.hostname == nil then
		local name = CeroSecOS.DEFAULT_HOSTNAME
		if CeroSecOS.isValidHostname(state.hostname) then name = state.hostname end
		etc.children.hostname = CeroSecOS.newFile("root", 644, name)
	end
	if etc.children.motd == nil then
		etc.children.motd = CeroSecOS.newFile("root", 644, CeroSecOS.MOTD)
	end
	local passwd = etc.children.passwd
	local keep = false
	if type(passwd) == "table" and passwd.type == "file" then
		local _, order = CeroSecOS.parsePasswd(passwd.data or "")
		keep = #order > 0
	end
	if not keep then
		etc.children.passwd =
			CeroSecOS.newFile("root", CeroSecOS.PASSWD_MODE, CeroSecOS.defaultPasswd())
	end

	-- /etc/sudoers, on the same terms as the accounts: a file that still names
	-- somebody is kept exactly as it is -- a name added to it is not damage --
	-- and one that is missing, is not a file, or parses to nobody at all is
	-- written back to the shipped list.
	local sudoers = etc.children.sudoers
	local keepSudoers = false
	if type(sudoers) == "table" and sudoers.type == "file" then
		local _, order = CeroSecOS.parseSudoers(sudoers.data or "")
		keepSudoers = #order > 0
	end
	if not keepSudoers then
		etc.children.sudoers =
			CeroSecOS.newFile("root", CeroSecOS.SUDOERS_MODE, CeroSecOS.defaultSudoers())
	end

	-- /etc/group, on the same terms again: a file that still holds one group is
	-- kept exactly as it is -- a group somebody made is not damage -- and one
	-- that is missing, is not a file, or parses to nothing at all is written
	-- back to the shipped three.
	local group = etc.children.group
	local keepGroup = false
	if type(group) == "table" and group.type == "file" then
		local _, order = CeroSecOS.parseGroup(group.data or "")
		keepGroup = #order > 0
	end
	if not keepGroup then
		etc.children.group =
			CeroSecOS.newFile("root", CeroSecOS.GROUP_MODE, CeroSecOS.defaultGroup())
	end

	-- And the wheel pair, on the terms ensureWheel sets: each line added only
	-- where it is missing. A repair that put the group back and not the sudoers
	-- line would leave a machine where `useradd -G wheel` means nothing.
	CeroSecOS.ensureWheel(state)

	CeroSecOS.fillBin(CeroSecOS.ensureSystemDir(state, "bin"))
	-- And /var, which is the machine's own tree exactly as /bin and /etc are. The
	-- crontabs, the log and the mail in it are left where they are: a repair puts
	-- the directories back, it does not throw away what a player asked for.
	CeroSecOS.ensureVar(state)
	-- /etc/hosts and /etc/hosts.equiv, on the same terms as the rest of /etc:
	-- made where they are missing, and one that is there is left exactly as it
	-- lies -- a name a survivor wrote down is not damage.
	CeroSecOS.ensureNet(state)
	-- And /dev, with the hole in the disk in it. The world's devices are not the
	-- BIOS's business -- they are not on the disk at all -- so this puts back
	-- exactly one node.
	CeroSecOS.ensureDev(state)
	-- And /mnt. What is IN the drive is not the BIOS's business either: a disk is a
	-- thing in the world, and repairing a machine has never meant reaching into it.
	CeroSecOS.ensureMnt(state)

	-- A repaired machine has everything this build ships, so there is nothing
	-- left for the upgrade to top up.
	state.sysv = CeroSecOS.SYSTEM_VERSION
	return true
end
