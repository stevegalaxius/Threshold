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
Export.PART_FIELDS = { "name", "shape", "shade", "tint", "color", "paint", "mirror", "layer", "collide", "cargo", "core", "breakable", "armor", "mass", "explode", "lights", "dock", "dockBoth", "dockRunway", "dockHeading", "dockX", "dockY", "dockWidth", "dockDepth", "dockCapture", "dockWall", "role", "rotor", "barrel" }
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
	if not out.dock then
  out.dockBoth=nil
  for _,field in ipairs(require("src.dock_geometry").fields) do out[field]=nil end
 end
	if out.dockBoth == false then out.dockBoth = nil end
	if out.layer == "hull" then out.layer = nil end
	if out.collide == true then out.collide = nil end
	if out.breakable == true then out.breakable = nil end
	if out.mirror == false then out.mirror = nil end
	if out.cargo == false then out.cargo = nil end
	if out.core == false then out.core = nil end
	if out.role == "" then out.role = nil end
	if out.name == "" then out.name = nil end
	if out.barrel == false then out.barrel = nil end
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
	def.paint = nil   -- the old single factory paint; hulls use the paints pool now
	def.cargo = nil   -- hulls carry no starting cargo; a ship's hold starts empty
	if design.slots then
		def.slots = copy(design.slots)
		for _, slot in ipairs(def.slots) do data.migrateSlot(slot) end
		-- Explicit defaults win, including intentionally empty slots. Older designs
		-- inherit the base loadout until they are edited.
		local loadout = {}
		for i, slot in ipairs(def.slots) do
			local source = design.loadout or def.loadout
			local id = source and source[i]
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
	local def = { id = design.id, name = design.name, kind = "station", parts = {},
		color = design.color and copy(design.color), haze = design.haze, role = design.role, rotors = design.rotors and copy(design.rotors),
  hangar=design.hangar and copy(design.hangar), services=design.services and copy(design.services), repairRate=design.repairRate }
	if design.turrets and #design.turrets > 0 then
		def.turrets = {}
		for _, t in ipairs(design.turrets) do
			table.insert(def.turrets, { x = t.x, y = t.y, module = t.module, turn = (t.turn or 90) ~= 90 and t.turn or nil, heading = t.heading })
		end
	end
	if design.berths and #design.berths > 0 then
		def.berths = {}
		for _, b in ipairs(design.berths) do
			table.insert(def.berths, { x = b.x, y = b.y, heading = (b.heading or 0) ~= 0 and b.heading or nil, size = (b.size or 80) ~= 80 and b.size or nil,maxLength=b.maxLength,maxWidth=b.maxWidth })
		end
	end
	for _, part in ipairs(design.parts) do table.insert(def.parts, Export.cleanPart(part)) end
	return def
end

-- A weapon module (the Weapons tab): its stats plus the drawn art.
function Export.weaponDef(design)
	local def = copy(design.module or {})
	def.id, def.name = design.id, design.name
	def.family = def.family or "weapon"
	def.source, def.art = nil, nil
	local parts = {}
	for _, part in ipairs(design.parts) do table.insert(parts, Export.cleanPart(part)) end
	if #parts > 0 then
		def.art = { parts = parts }
		if design.muzzles and #design.muzzles > 0 then def.art.muzzles = copy(design.muzzles) end
	end
	return def
end

-- The definition for whatever kind the design is.
function Export.def(design)
	if design.kind == "weapon" then return Export.weaponDef(design) end
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
local function weaponSource(design)
	local def = Export.weaponDef(design)
	local keys = {}
	for k in pairs(def) do if k ~= "id" and k ~= "name" and k ~= "art" and k ~= "weapon" then table.insert(keys, k) end end
	table.sort(keys)
	local out = { "-- Made in the Shipyard (F2), Weapons tab.", "module {", ("\tid = %q, name = %q,"):format(def.id, def.name) }
	for _, k in ipairs(keys) do table.insert(out, "\t" .. k .. " = " .. serialize(def[k], "\t") .. ",") end
	if def.weapon then table.insert(out, "\tweapon = " .. serialize(def.weapon, "\t") .. ",") end
	if def.art then
		table.insert(out, "\tart = {")
		if def.art.muzzles then table.insert(out, "\t\tmuzzles = " .. serialize(def.art.muzzles, "\t\t") .. ",") end
		table.insert(out, "\t\tparts = {")
		for _, part in ipairs(design.parts) do
			local line = partLine(part, "\t\t\t")
			table.insert(out, line)
		end
		table.insert(out, "\t\t},")
		table.insert(out, "\t},")
	end
	table.insert(out, "}")
	return table.concat(out, "\n") .. "\n"
end

function Export.source(design)
	if design.kind == "weapon" then return weaponSource(design) end
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

-- Folders inside the export folder: "" is the top, "ships/fighters" a
-- subfolder. Names keep letters, digits, _ and -; empty parts drop out.
function Export.cleanFolder(folder)
	local parts = {}
	for seg in tostring(folder or ""):gmatch("[^/\\]+") do
		if seg ~= "." and seg ~= ".." then table.insert(parts, (seg:gsub("[^%w_%-%.]", "_"))) end
	end
	return table.concat(parts, "/")
end

local function full(rel)
	rel = Export.cleanFolder(rel)
	return rel == "" and Export.FOLDER or (Export.FOLDER .. "/" .. rel)
end

-- Every folder and design file under the export folder, in tree order:
-- { rel = "ships/x.lua", name = "x.lua", dir = false, depth = 1, folder = "ships", id = "x" }.
-- Cached: the panel asks every frame; anything that changes the files clears it.
local listCache
function Export.refresh() listCache = nil end
function Export.list()
	if listCache then return listCache end
	local out = {}
	local function walk(rel, depth)
		local items = love.filesystem.getDirectoryItems(full(rel))
		table.sort(items, function(a, b) return a:lower() < b:lower() end)
		local dirs, files = {}, {}
		for _, name in ipairs(items) do
			local r = rel == "" and name or (rel .. "/" .. name)
			local info = love.filesystem.getInfo(full(rel) .. "/" .. name)
			if info and info.type == "directory" then table.insert(dirs, { rel = r, name = name })
			elseif name:match("%.lua$") then table.insert(files, { rel = r, name = name, id = name:gsub("%.lua$", "") }) end
		end
		for _, d in ipairs(dirs) do
			table.insert(out, { rel = d.rel, name = d.name, dir = true, depth = depth, folder = rel })
			walk(d.rel, depth + 1)
		end
		for _, f in ipairs(files) do
			table.insert(out, { rel = f.rel, name = f.name, id = f.id, dir = false, depth = depth, folder = rel })
		end
	end
	if love.filesystem.getInfo(Export.FOLDER, "directory") then walk("", 0) end
	listCache = out
	return out
end

-- Just the folders, top first: { "", "ships", "ships/fighters", ... }.
function Export.folders()
	local out = { "" }
	for _, e in ipairs(Export.list()) do if e.dir then table.insert(out, e.rel) end end
	return out
end

-- The folder an exported design with this id lives in, or nil.
function Export.folderOf(id)
	for _, e in ipairs(Export.list()) do
		if not e.dir and e.id == id then return e.folder end
	end
	return nil
end

function Export.makeFolder(rel)
	rel = Export.cleanFolder(rel)
	if rel == "" then return nil, "no folder name" end
	Export.refresh()
	if not love.filesystem.createDirectory(full(rel)) then return nil, "couldn't create " .. rel end
	return rel
end

-- Delete a design file, or a folder if it's empty.
function Export.remove(rel)
	rel = Export.cleanFolder(rel)
	if rel == "" then return nil, "can't delete the export folder itself" end
	local path = full(rel)
	local info = love.filesystem.getInfo(path)
	if not info then return nil, rel .. " is already gone" end
	if info.type == "directory" and #love.filesystem.getDirectoryItems(path) > 0 then
		return nil, rel .. " isn't empty"
	end
	Export.refresh()
	if not love.filesystem.remove(path) then return nil, "couldn't delete " .. rel end
	return true
end

-- Writes into design.folder (default: wherever this id was exported
-- before, else the top). Exporting into a different folder moves it, so
-- there's never two files with the same id.
function Export.write(design)
	local old = Export.folderOf(design.id)
	local folder = Export.cleanFolder(design.folder or old or "")
	love.filesystem.createDirectory(full(folder))
	local path = full(folder) .. "/" .. design.id .. ".lua"
	local ok, err = love.filesystem.write(path, Export.source(design))
	Export.refresh()
	if not ok then return nil, err end
	if old and old ~= folder then love.filesystem.remove(full(old) .. "/" .. design.id .. ".lua") end
	design.folder = folder
	return love.filesystem.getSaveDirectory() .. "/" .. path
end

-- A design from a loaded hull: its parts minus mirror twins (the part
-- they mirror keeps mirror = true) and minus everything prepare added.
function Export.fromHull(id)
	local hull = data.hulls[id]
	local design = { id = id, name = hull.name, base = id, parts = {}, stats = {}, slots = copy(hull.slots), loadout = copy(hull.loadout) }
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
	local design = { id = id, name = st.name, kind = "station", base = data.list.hulls[1], parts = {}, slots = {}, stats = {},
		color = st.color and copy(st.color), haze = st.haze, role = st.role, rotors = st.rotors and copy(st.rotors), berths = st.berths and copy(st.berths),hangar=st.hangar and copy(st.hangar),
		services = st.services and copy(st.services), repairRate = st.repairRate,
		turrets = st.turrets and copy(st.turrets) }
	for _, part in ipairs(st.parts) do
		if not part.twin then table.insert(design.parts, Export.cleanPart(part)) end
	end
	return design
end

-- A design from a loaded weapon module: its art parts become the parts.
function Export.fromModule(id)
	local m = data.modules[id]
	local module = copy(m)
	module.id, module.name, module.source, module.art = nil, nil, nil, nil
	local design = { id = id, name = m.name, kind = "weapon", base = data.list.hulls[1], parts = {}, slots = {}, stats = {},
		module = module, muzzles = m.art and m.art.muzzles and copy(m.art.muzzles) or {} }
	for _, part in ipairs(m.art and m.art.parts or {}) do table.insert(design.parts, Export.cleanPart(part)) end
	return design
end

function Export.autosave(design)
	love.filesystem.createDirectory("shipyard")
	local d = { id = design.id, name = design.name, base = design.base, parts = {}, stats = design.stats, slots = design.slots, loadout = design.loadout,
		kind = design.kind, folder = design.folder, loot = design.loot, color = design.color, haze = design.haze, role = design.role, rotors = design.rotors, berths = design.berths, turrets = design.turrets,hangar=design.hangar, services = design.services, repairRate = design.repairRate,
		module = design.module, muzzles = design.muzzles }
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
