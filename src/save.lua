--[[
	Save files. A save is one plain Lua table (see Game:saveState in
	src/world.lua for what's in it) written out as a Lua literal:

	  return { version = 1, field = "planet", ... }

	It's read back in an empty sandbox, so a save file can only hold data,
	never run code. version lets later builds upgrade old saves
	(Save.upgrade) instead of refusing them.

	Files live in LÖVE's save folder (love.filesystem.getSaveDirectory()),
	one per slot: save_<slot>.lua.
]]

local Save = { VERSION = 2 }

local function isIdent(k)
	return type(k) == "string" and k:match("^[%a_][%w_]*$") ~= nil
end

-- A value as Lua source. Tables with keys 1..n are written as lists, the
-- rest with sorted keys so the same state always writes the same file.
local function encode(v, indent, out)
	local t = type(v)
	if t == "number" then
		if v ~= v or v == math.huge or v == -math.huge then out[#out + 1] = "0"
		elseif v % 1 == 0 and math.abs(v) < 2 ^ 53 then out[#out + 1] = string.format("%d", v)
		else out[#out + 1] = string.format("%.17g", v) end
	elseif t == "string" then
		out[#out + 1] = string.format("%q", v)
	elseif t == "boolean" then
		out[#out + 1] = tostring(v)
	elseif t == "table" then
		local n = #v
		local keys = {}
		for k in pairs(v) do
			if not (type(k) == "number" and k >= 1 and k <= n and k % 1 == 0) then table.insert(keys, k) end
		end
		table.sort(keys, function(a, b)
			if type(a) == type(b) then return a < b end
			return type(a) == "number"
		end)
		if n == 0 and #keys == 0 then out[#out + 1] = "{}" return end
		local pad = indent .. "\t"
		out[#out + 1] = "{\n"
		for i = 1, n do
			out[#out + 1] = pad
			encode(v[i], pad, out)
			out[#out + 1] = ",\n"
		end
		for _, k in ipairs(keys) do
			out[#out + 1] = pad
			if isIdent(k) then
				out[#out + 1] = k
			else
				out[#out + 1] = "["
				encode(k, pad, out)
				out[#out + 1] = "]"
			end
			out[#out + 1] = " = "
			encode(v[k], pad, out)
			out[#out + 1] = ",\n"
		end
		out[#out + 1] = indent .. "}"
	else
		error("can't save a " .. t, 0)
	end
end

function Save.encode(v)
	local out = {}
	encode(v, "", out)
	return table.concat(out)
end

function Save.decode(src)
	if not src:match("^%s*return") then src = "return " .. src end
	local chunk, err = loadstring(src, "=save")
	if not chunk then return nil, err end
	setfenv(chunk, {})
	local ok, v = pcall(chunk)
	if not ok then return nil, v end
	if type(v) ~= "table" then return nil, "not a save file" end
	return v
end

-- Bring an older save up to the current version. Each step upgrades one
-- version. Version 2 adds selected world-object snapshots.
function Save.upgrade(state)
	if (state.version or 0) > Save.VERSION then return nil, "made by a newer version of the game" end
	state.areas = state.areas or {}
	state.nextObjectId = state.nextObjectId or 0
	state.version = Save.VERSION
	return state
end

local function fileName(slot) return ("save_%s.lua"):format(slot or "quick") end

function Save.write(slot, state)
	state.version = Save.VERSION
	local ok, err = love.filesystem.write(fileName(slot), "return " .. Save.encode(state) .. "\n")
	return ok, err
end

function Save.read(slot)
	local src = love.filesystem.read(fileName(slot))
	if not src then return nil, "no save in slot " .. tostring(slot or "quick") end
	local state, err = Save.decode(src)
	if not state then return nil, err end
	return Save.upgrade(state)
end

function Save.delete(slot)
	love.filesystem.remove(fileName(slot))
end

function Save.exists(slot)
	return love.filesystem.getInfo(fileName(slot)) ~= nil
end

-- The most recently written of the player's saves (F5's "quick" and the
-- "auto" save), or nil if there are none.
function Save.newest()
	local best, bestT
	for _, slot in ipairs({ "quick", "auto" }) do
		local info = love.filesystem.getInfo(fileName(slot))
		if info and (not bestT or (info.modtime or 0) > bestT) then best, bestT = slot, info.modtime or 0 end
	end
	return best
end

return Save
