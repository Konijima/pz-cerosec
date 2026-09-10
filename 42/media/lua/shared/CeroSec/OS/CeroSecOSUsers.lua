--
-- CeroSec OS core: users and login.
--
-- Passwords are plain strings: this is game data on a 1993 machine, not a
-- credential store, and the game serializes the state anyway. The comparison
-- lives in checkPassword alone, so swapping it for something else later is a
-- one-function change.
--

CeroSecOS = CeroSecOS or {}

function CeroSecOS.getUser(state, name)
	if state == nil or state.users == nil or type(name) ~= "string" then return nil end
	return state.users[name]
end

function CeroSecOS.newUser(name, password, home, admin)
	return { name = name, password = password or "", home = home or "/", admin = admin and true or false }
end

-- The single place a password is judged. An empty stored password means the
-- account is open, which is how a fresh machine ships.
function CeroSecOS.checkPassword(user, password)
	if user == nil then return false end
	local stored = user.password or ""
	if password == nil then password = "" end
	return stored == password
end

-- session, reason. A session is a runtime object: the terminal window owns it
-- and it is never written into the state.
function CeroSecOS.login(state, name, password)
	local user = CeroSecOS.getUser(state, name)
	if user == nil then return nil, "no such user" end
	if not CeroSecOS.checkPassword(user, password) then return nil, "wrong password" end
	return { user = user.name, cwd = user.home or "/" }, nil
end
