-- ===========================================================================
-- test_cell.lua  ·  the one pure function in the position recorder that can
-- void a whole dungeon run without saying anything.
--
--     lua tools/test_cell.lua        (from the DodoProbe folder)
--
-- cell() turns one client value into one field of a sample line. If it ever
-- touches a secret -- string.format, comparison, tostring, anything -- it
-- throws, the throw happens inside a C_Timer ticker, and the recorder stops.
-- On disk that looks exactly like "he only walked twenty steps".
--
-- 🔴 It slices the REAL function out of DodoProbe.lua rather than keeping a
-- copy here. A hand-copied duplicate would be a fixture built from the same
-- misunderstanding as the bug, and it would drift the first time anyone edits
-- the original -- silently, and in the direction that reads like "still fine".
-- ===========================================================================

local SRC = "DodoProbe.lua"

local function slice(src, header)
	local i = src:find(header, 1, true)
	assert(i, "could not find " .. header .. " -- has it been renamed?")
	local j = src:find("\nend\n", i, true)
	assert(j, "no terminating end for " .. header)
	return src:sub(i, j + 4)
end

local f = assert(io.open(SRC, "rb"))
local src = f:read("*a")
f:close()
-- Read as bytes so nothing is reinterpreted, then normalise the line endings:
-- this file is CRLF on disk, and a slicer looking for "\nend\n" finds nothing
-- in it -- which reads like "that function is gone", not "wrong line endings".
src = src:gsub("\r\n", "\n")

local pass, fail = 0, 0
local function check(name, got, want)
	if got == want then
		pass = pass + 1
	else
		fail = fail + 1
		io.write(("  FAIL  %s\n         got %s, want %s\n")
			:format(name, tostring(got), tostring(want)))
	end
end

-- Build a sandbox where a chosen set of values is secret, exactly the way the
-- client behaves: a secret still reports as the number it stands in for, and
-- only goes off when something uses it.
local function build(text, secrets)
	local env = {
		string = string, type = type, tostring = tostring, math = math,
		issecretvalue = function(v) return secrets[v] == true end,
	}
	local chunk = assert(load(text .. "\nreturn cell, num", "=cell", "t", env))
	return chunk()
end

local SECRET_N = 7000001
local cell, num = build(slice(src, "local function cell(ok, v)")
	.. slice(src, "local function num(ok, v)"), { [SECRET_N] = true })

io.write("cell(): the three-state formatter\n")
check("a real number is formatted for arithmetic", cell(true, 1234.5678), "1234.5678")
check("negatives keep their sign",                 cell(true, -987.6543), "-987.6543")
check("a refused call says ERR",                   cell(false, nil), "ERR")
check("no value says nil",                         cell(true, nil), "nil")
check("a secret says SECRET and is never printed", cell(true, SECRET_N), "SECRET")
check("a non-number is called out, not formatted", cell(true, "hello"), "T:string")

-- The point of the whole exercise: the secret must never reach string.format.
-- If it did, the number it stands in for would land in the file looking like a
-- perfectly good coordinate -- and every calculation downstream would be built
-- on it.
check("a secret does NOT leak the value it stands in for",
	cell(true, SECRET_N):find("7000001"), nil)

io.write("num(): what may be used in arithmetic\n")
check("a real number comes through", num(true, 12.5), 12.5)
check("a secret does NOT",           num(true, SECRET_N), nil)
check("nil does not",                num(true, nil), nil)
check("a refused call does not",     num(false, 5), nil)
check("a string does not",           num(true, "5"), nil)

-- ---------------------------------------------------------------------------
-- A/B, inline: strip the secrecy guard out of the sliced source and prove both
-- functions change their answer. Green here without this would mean the guard
-- is decorative -- which is the failure mode this whole file exists for.
-- ---------------------------------------------------------------------------
local stripped = (slice(src, "local function cell(ok, v)") .. slice(src, "local function num(ok, v)"))
	:gsub('if issecretvalue and issecretvalue%(v%) then return "SECRET" end', "")
	:gsub("if issecretvalue and issecretvalue%(v%) then return nil end", "")
local cellNo, numNo = build(stripped, { [SECRET_N] = true })

check("A/B: without the guard, cell WOULD print the stand-in value",
	cellNo(true, SECRET_N), "7000001.0000")
check("A/B: without the guard, num WOULD hand it to arithmetic",
	numNo(true, SECRET_N), SECRET_N)

io.write(("\n%d passed, %d failed\n"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
