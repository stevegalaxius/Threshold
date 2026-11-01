--[[
	Shipyard files: turning a design into a data file the game loads, and
	a loaded hull back into a design.

	A design is { id, name, base, parts }. base is the hull whose stats,
	slots and loadout the design flies with (phase 1 edits shape only);
	parts are the editor's own copies, with only the fields a data file
	holds (no tris, area or centre: HullShape.prepare adds those).

	Exports go to the save folder, mods/shipyard/data/<id>.lua, which
	src/data.lua already loads after the base game (reusing an id
	replaces that hull). The working design autosaves to
	shipyard/_autosave.lua there too.
]]

local data = require("src.data")

local Export = {}

Export.FOLDER = "mods/shipyard/data"
Export.AUTOSAVE = "shipyard/_autosave.lua"

-- The fields a part can carry in a data file, in the order they're written.
Export.PART_FIELDS = { "name", "shape", "shade", "tint", "color", "mirror", "layer", "collide", "cargo", "core", "breakable", "armor", "mass", "explode", "lights", "dock", "dockBoth", "dockRunway", "role" }
-- Editor-only fields (kept in the autosave, never in an export).
local EDITOR_FIELDS = { "hidden", "locked" }

-- Hull fields that come from the shape, not the base hull.
local SHAPE_KEYS = { parts = true, shape = true, source = true, id = true, name = true }

local function round(v)
	if math.abs(v - math.floor(v + 0.5)) < 1e-6 then return tostring(math.floor(v + 0.5)) end
	return (("%.3f"):format(v):gsub("0+$", ""):gsub("%.$", ""))
end

local function isArray(t)
	local n = #t
	for k in pairs(t) do
		if type(k) ~= "number" or k < 1 or k > n or k % 1 ~= 0 then return false end
	end
	return true
end

local IDENT = "^[%a_][%w_]*$"

-- Any plain value as Lua source. Short arrays stay on one line.
local function serialize(v, indent)
	indent = indent or ""
	local t = type(v)
	if t == "number" then return round(v)
	elseif t == "string" then return ("%q"):format(v)
	elseif t == "boolean" then return tostring(v)
	elseif t ~= "table" then return "nil" end
	if isArray(v) then
		local simple = true
		for _, x in ipairs(v) do if type(x) == "table" then simple = false end end
		local items = {}
		for _, x in ipairs(v) do table.insert(items, serialize(x, indent .. "\t")) end
		if #items == 0 then return "{}" end
		if simple then return "{ " .. table.concat(items, ", ") .. " }" end
		return "{\n" .. indent .. "\t" .. table.concat(items, ",\n" .. indent .. "\t") .. ",\n" .. indent .. "}"
	end
	local keys = {}
	for k in pairs(v) do table.insert(keys, k) end
	table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
	local items = {}
	for _, k in ipairs(keys) do
		local key = (type(k) == "string" and k:match(IDENT)) and k or ("[" .. serialize(k) .. "]")
		table.insert(items, key .. " = " .. serialize(v[k], indent .. "\t"))
	end
	local one = "{ " .. table.concat(items, ", ") .. " }"
	if #one < 100 and not one:find("\n") then return one end
	return "{\n" .. indent .. "\t" .. table.concat(items, ",\n" .. indent .. "\t") .. ",\n" .. indent .. "}"
end
Export.serialize = serialize

local function copy(v)
	if type(v) ~= "table" then return v end
	local out = {}
	for k, x in pairs(v) do out[k] = copy(x) end
	return out
end
Export.copy = copy

-- One part, with only the fields a data file holds (and the editor's own
-- when `editor` is set).
function Export.cleanPart(part, editor)
	local out = {}
	for _, f in ipairs(Export.PART_FIELDS) do
		if part[f] ~= nil then out[f] = copy(part[f]) end
	end
	if editor then
		for _, f in ipairs(EDITOR_FIELDS) do out[f] = part[f] end
	end
	-- defaults stay out of the file
	if out.shade == 1 then out.shade = nil end
	if out.armor == 1 then out.armor = nil end
	if out.mass == 1 then out.mass = nil end
	if out.explode == false then out.explode = nil end
	if out.dock == false then out.dock = nil end
	if not out.dock then out.dockBoth, out.dockRunway = nil, nil end
	if out.dockBoth == false then out.dockBoth = nil end
	if out.layer == "hull" then out.layer = nil end
	if out.collide == true then out.collide = nil end
	if out.breakable == true then out.breakable = nil end
	if out.mirror == false then out.mirror = nil end
	if out.cargo == false then out.cargo = nil end
	if out.core == false then out.core = nil end
	if out.role == "" then out.role = nil end
	if out.name == "" then out.name = nil end
	return out
end

-- A hull definition (not yet prepared) for a design: the base hull's
-- stats with the design's id, name and parts.
function Export.hullDef(design)
	local base = data.hulls[design.base]
	local def = {}
	if base then
		for k, v in pairs(base) do
			if not SHAPE_KEYS[k] then def[k] = copy(v) end
		end
	end
	def.id, def.name = design.id, design.name
	def.radius = nil   -- worked out from the shape (src/data.lua)
	-- the design's own stats and slots win over the base hull's
	for k, v in pairs(design.stats or {}) do def[k] = copy(v) end
	if design.slots then
		def.slots = copy(design.slots)
		-- keep the base loadout only where it still fits the slot
		local loadout = {}
		for i, slot in ipairs(def.slots) do
			local id = def.loadout and def.loadout[i]
			local m = id and data.modules[id]
			loadout[i] = (m and data.fits(slot, m)) and id or false
		end
		def.loadout = loadout
	end
	def.parts = {}
	for _, part in ipairs(design.parts) do table.insert(def.parts, Export.cleanPart(part)) end
	return def
end

-- A wreck or prop definition for a design (design.kind "wreck" / "prop").
function Export.wreckDef(design)
	local st = design.stats or {}
	local def = { id = design.id, name = design.name, kind = design.kind,
		armor = st.armor or 200, hold = st.hold or 20, mass = st.mass or 100 }
	if design.kind == "wreck" then def.loot = copy(design.loot or {}) end
	def.parts = {}
	for _, part in ipairs(design.parts) do table.insert(def.parts, Export.cleanPart(part)) end
	return def
end

-- A station layout for a design (design.kind "station").
function Export.stationDef(design)
	local def = { id = design.id, name = design.name, kind = "station", parts = {} }
	for _, part in ipairs(design.parts) do table.insert(def.parts, Export.cleanPart(part)) end
	return def
end

-- The definition for whatever kind the design is.
function Export.def(design)
	if design.kind == "station" then return Export.stationDef(design) end
	if design.kind == "wreck" or design.kind == "prop" then return Export.wreckDef(design) end
	return Export.hullDef(design)
end

local function partLine(part, indent)
	local p = Export.cleanPart(part)
	local items = {}
	for _, f in ipairs(Export.PART_FIELDS) do
		if p[f] ~= nil then table.insert(items, f .. " = " .. serialize(p[f], indent)) end
	end
	return indent .. "{ " .. table.concat(items, ", ") .. " },"
end

-- The design as a data file: hull { ... } with one part per line and the
-- part's name first, so it survives a re-import.
function Export.source(design)
	local def = Export.def(design)
	local kind = (design.kind == "wreck" or design.kind == "prop" or design.kind == "station") and design.kind or "hull"
	local keys = {}
	for k in pairs(def) do if k ~= "parts" and k ~= "id" and k ~= "name" and k ~= "kind" then table.insert(keys, k) end end
	table.sort(keys)
	local out = {
		kind == "hull" and ("-- Made in the Shipyard (F2). Base hull: " .. tostring(design.base)) or "-- Made in the Shipyard (F2).",
		kind .. " {",
		("\tid = %q, name = %q,"):format(def.id, def.name),
	}
	for _, k in ipairs(keys) do
		table.insert(out, "\t" .. k .. " = " .. serialize(def[k], "\t") .. ",")
	end
	table.insert(out, "\tparts = {")
	for _, part in ipairs(design.parts) do
		table.insert(out, (partLine(part, "\t\t")))
	end
	table.insert(out, "\t},")
	table.insert(out, "}")
	return table.concat(out, "\n") .. "\n"
end

function Export.write(design)
	love.filesystem.createDirectory(Export.FOLDER)
	local path = Export.FOLDER .. "/" .. design.id .. ".lua"
	local ok, err = love.filesystem.write(path, Export.source(design))
	if not ok then return nil, err end
	return love.filesystem.getSaveDirectory() .. "/" .. path
end

-- A design from a loaded hull: its parts minus mirror twins (the part
-- they mirror keeps mirror = true) and minus everything prepare added.
function Export.fromHull(id)
	local hull = data.hulls[id]
	local design = { id = id, name = hull.name, base = id, parts = {}, stats = {}, slots = copy(hull.slots) }
	for _, part in ipairs(hull.parts) do
		if not part.twin then table.insert(design.parts, Export.cleanPart(part)) end
	end
	return design
end

-- Autosave: the design (with editor-only fields) as a plain Lua table.
-- A design from a loaded wreck or prop.
function Export.fromWreck(id)
	local w = data.wrecks[id]
	local design = { id = id, name = w.name, kind = w.kind, base = data.list.hulls[1], parts = {}, slots = {},
		stats = { armor = w.armor, hold = w.hold, mass = w.mass }, loot = copy(w.loot or {}) }
	for _, part in ipairs(w.parts) do
		if not part.twin then table.insert(design.parts, Export.cleanPart(part)) end
	end
	return design
end

-- A design from a loaded station layout.
function Export.fromStation(id)
	local st = data.stations[id]
	local design = { id = id, name = st.name, kind = "station", base = data.list.hulls[1], parts = {}, slots = {}, stats = {} }
	for _, part in ipairs(st.parts) do
		if not part.twin then table.insert(design.parts, Export.cleanPart(part)) end
	end
	return design
end

function Export.autosave(design)
	love.filesystem.createDirectory("shipyard")
	local d = { id = design.id, name = design.name, base = design.base, parts = {}, stats = design.stats, slots = design.slots,
		kind = design.kind, loot = design.loot }
	for _, part in ipairs(design.parts) do table.insert(d.parts, Export.cleanPart(part, true)) end
	love.filesystem.write(Export.AUTOSAVE, "return " .. serialize(d) .. "\n")
end

function Export.loadAutosave()
	if not love.filesystem.getInfo(Export.AUTOSAVE) then return nil end
	local src = love.filesystem.read(Export.AUTOSAVE)
	local chunk = src and loadstring(src)
	if not chunk then return nil end
	setfenv(chunk, {})
	local ok, d = pcall(chunk)
	if ok and type(d) == "table" and type(d.parts) == "table" and d.id then return d end
	return nil
end

return Export
