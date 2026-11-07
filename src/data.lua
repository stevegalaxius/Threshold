--[[
	Content loader.

	Every hull, module, ammo type, salvage item and enemy is defined in a
	plain Lua file under data/, or under mods/<modname>/data/. Those files
	run in a sandbox: all they can do is call the registration functions
	below (hull, module, ammo, salvage, container, enemy, market) and use basic math, string
	and table helpers. They cannot touch files, globals or game state.

	The base game loads its own content through exactly the same path a mod
	would, and anything a mod defines with an existing id replaces the base
	definition. So "modding support" is just this file.
]]

local data = {
	hulls = {}, modules = {}, items = {}, enemies = {}, markets = {}, wrecks = {}, stations = {},
	-- definition order, so menus list things the way the data files do
	list = { hulls = {}, modules = {}, items = {}, enemies = {}, wrecks = {}, stations = {} },
}

-- Slot families. A hardpoint takes a gun, artillery piece or laser; a bay
-- takes a launcher (missiles, torpedoes, drones). Which trigger fires each
-- is set per slot (see Ship.triggerFor).
local FAMILIES = { hardpoint = true, bay = true, engine = true, reactor = true, utility = true, computer = true }
-- Module families. A "weapon" (gun, artillery, laser) fits a hardpoint;
-- every other family fits the slot of the same name.
local MODULE_FAMILIES = { weapon = true, bay = true, engine = true, reactor = true, utility = true, computer = true }
local SIZES = { S = 1, M = 2, L = 3, any = 0 }   -- "any": shared slots every hull class uses alike
local WEAPON_KINDS = { cannon = true, laser = true, drill = true, missile = true, drone = true }
-- The ammo families a weapon chambers when it doesn't list its own
-- (weapon.chambers = { "artillery" }, { "shotgun", "gun" }). A cannon is any
-- hardpoint weapon that fires ammo: what it chambers makes it an autocannon,
-- a mortar or a shotgun. Lasers and drills take none.
data.CHAMBERS = { cannon = { "gun" }, missile = { "missile", "torpedo" }, drone = { "drone" } }
-- Older weapon kinds: a gun, artillery piece or shotgun is a cannon that
-- chambers that ammo; a torpedo tube is a missile rack.
-- One laser kind with two ways to fire: a pulse (per-shot damage and
-- power, fireRate shots a second) or, with beam = true, a beam (per-second
-- damage and power while held). They fire down separate paths in Weapons.fire.
data.LASERS = { laser = true }
local OLD_KINDS = { gun = { "cannon", "gun" }, artillery = { "cannon", "artillery" }, shotgun = { "cannon", "shotgun" }, torpedo = { "missile" } }
local MOUNTS = { fixed = true, gimbal = true, turret = true }
data.FAMILIES, data.SIZES = FAMILIES, SIZES

-- Slots saved before hardpoints and bays (editor designs) used primary,
-- secondary and auxiliary; read them as the new families.
function data.migrateSlot(slot)
	if slot.family == "primary" then slot.family = "hardpoint"
	elseif slot.family == "secondary" then slot.family, slot.trigger = "hardpoint", slot.trigger or "secondary"
	elseif slot.family == "auxiliary" then slot.family = "bay" end
	return slot
end

-- Does a module fit a hull slot?
function data.fits(slot, m)
	-- a module sized "any" fits a slot of any size (computers and utilities)
	if m.size ~= slot.size and m.size ~= "any" then return false end
	if m.family == "weapon" then return slot.family == "hardpoint" end
	return m.family == slot.family
end

-- A loadout made to fit the hull's slots. A module in a slot it doesn't fit
-- (the hull's slot layout changed, as with the Shipyard redesigns) moves to
-- the first empty slot it does fit instead of being dropped; unknown ids and
-- modules with no room go.
function data.fitLoadout(hull, loadout)
	local out, misfits = {}, {}
	local n = #hull.slots
	for i, id in pairs(loadout or {}) do
		local m = id and data.modules[id]
		if type(i) == "number" and m then
			if i <= n and data.fits(hull.slots[i], m) then out[i] = id else misfits[#misfits + 1] = { i = i, id = id } end
		end
	end
	table.sort(misfits, function(a, b) return a.i < b.i end)
	for _, f in ipairs(misfits) do
		for i, slot in ipairs(hull.slots) do
			if not out[i] and data.fits(slot, data.modules[f.id]) then out[i] = f.id; break end
		end
	end
	for i = 1, n do out[i] = out[i] or false end
	return out
end

local currentFile = "?"

local function fail(msg)
	error(("%s: %s"):format(currentFile, msg), 0)
end

local function need(def, field, kind)
	if def[field] == nil then fail(("%s '%s' is missing '%s'"):format(kind, tostring(def.id), field)) end
end

local function register(category, kind, def)
	if type(def) ~= "table" then fail(kind .. " expects a table, like " .. kind .. " { id = ... }") end
	need(def, "id", kind)
	need(def, "name", kind)
	if not data[category][def.id] then table.insert(data.list[category], def.id) end
	def.source = currentFile
	data[category][def.id] = def
	return def
end

-- The functions data files are allowed to call ---------------------------

local HullShape = require("src.hullshape")

local api = {}

local function prepareHull(def)
	if type(def) ~= "table" then fail("hull expects a table") end
	need(def, "id", "hull"); need(def, "name", "hull")
	for _, f in ipairs({ "mass", "armor", "hold", "drag", "slots" }) do need(def, f, "hull") end
	if not def.shape and not def.parts then fail(("hull '%s' needs a shape or parts"):format(def.id)) end
	local LAYERS = { hull = true, detail = true, glow = true }
	for i, part in ipairs(def.parts or {}) do
		local function bad(what) fail(("hull '%s' part %d: %s"):format(def.id, i, what)) end
		if part.layer ~= nil and not LAYERS[part.layer] then bad("unknown layer '" .. tostring(part.layer) .. "' (use hull, detail or glow)") end
		if part.color ~= nil and (type(part.color) ~= "table" or #part.color < 3) then bad("color should be { r, g, b }") end
		if part.tint ~= nil and (type(part.tint) ~= "table" or #part.tint < 3) then bad("tint should be { r, g, b }") end
		if part.paint ~= nil and part.paint ~= "primary" and part.paint ~= "secondary" then bad("paint should be primary or secondary (leave it out for bare metal)") end
		if part.armor ~= nil and type(part.armor) ~= "number" then bad("armor should be a number") end
		if part.shade ~= nil and type(part.shade) ~= "number" then bad("shade should be a number") end
		if part.mass ~= nil and type(part.mass) ~= "number" then bad("mass should be a number") end
		if part.lights ~= nil then
			if type(part.lights) ~= "table" then bad("lights should be a list") end
			for j, l in ipairs(part.lights) do
				if type(l.x) ~= "number" or type(l.y) ~= "number" then bad(("light %d needs x and y"):format(j)) end
				if (l.w ~= nil and type(l.w) ~= "number") or (l.h ~= nil and type(l.h) ~= "number") then bad(("light %d: w and h should be numbers"):format(j)) end
				if l.kind ~= nil and l.kind ~= "window" and l.kind ~= "nav" and l.kind ~= "strobe" then bad(("light %d has unknown kind '%s' (use window, nav or strobe)"):format(j, tostring(l.kind))) end
			end
		end
	end
	local ok, err = pcall(HullShape.prepare, def)
	if not ok then fail(err) end
	-- radius: half the hull's width, unless it says. Ships collide in their
	-- drawn shape; radius is for the spine, distances and thruster size.
	if not def.radius then
		local w = 0
		for k = 2, #def.shape, 2 do w = math.max(w, math.abs(def.shape[k])) end
		def.radius = math.max(4, math.floor(w + 0.5))
	end
	def.turn = def.turn or 0
	def.bonuses = def.bonuses or {}
	def.mount = def.mount or "gimbal"
	if def.paints ~= nil then
		if type(def.paints) ~= "table" then fail(("hull '%s': paints should be a list of preset names"):format(def.id)) end
		for _, n in ipairs(def.paints) do
			if not require("src.paint").find(n) then fail(("hull '%s' has unknown paint '%s' (see src/paint.lua)"):format(def.id, tostring(n))) end
		end
	end
	if def.helm and def.helm ~= "strafe" and def.helm ~= "turn" then fail(("hull '%s' has unknown helm '%s' (use strafe or turn)"):format(def.id, tostring(def.helm))) end
	if not MOUNTS[def.mount] then fail(("hull '%s' has unknown mount '%s' (use fixed, gimbal or turret)"):format(def.id, tostring(def.mount))) end
	for i, slot in ipairs(def.slots) do
		data.migrateSlot(slot)
		if slot.mount and not MOUNTS[slot.mount] then fail(("hull '%s' slot %d has unknown mount '%s'"):format(def.id, i, tostring(slot.mount))) end
		if not FAMILIES[slot.family] then fail(("hull '%s' slot %d has unknown family '%s'"):format(def.id, i, tostring(slot.family))) end
		if slot.trigger and slot.trigger ~= "primary" and slot.trigger ~= "secondary" and slot.trigger ~= "tertiary" then fail(("hull '%s' slot %d has unknown trigger '%s' (use primary, secondary or tertiary)"):format(def.id, i, tostring(slot.trigger))) end
		if not SIZES[slot.size] then fail(("hull '%s' slot %d has unknown size '%s' (use S, M, L or any)"):format(def.id, i, tostring(slot.size))) end
	end
end

function api.hull(def)
	prepareHull(def)
	return register("hulls", "hull", def)
end

-- Validate and prepare an isolated preview without replacing a catalogue hull.
function data.prepareHull(def)
	local ok, err = pcall(prepareHull, def)
	if not ok then return nil, err end
	return def
end

-- A wreck: a derelict built from parts, placed in the world rather than
-- left by a ship. It drifts, can be looted, and breaks apart part by part
-- like a ship's wreck (src/game.lua, Game:spawnWreck).
--   parts   as for hulls (src/hullshape.lua)
--   armor   toughness (default 200)    hold  m3 for its loot (default 20)
--   mass    tonnes (default 100)
--   loot    what it can turn up: { { item, min, max, chance }, ... }
-- A prop is the same with no loot: debris, beacons, scenery.
local function wreckLike(kind, def)
	register("wrecks", kind, def)
	if not def.parts then fail(("%s '%s' needs parts"):format(kind, def.id)) end
	local ok, err = pcall(HullShape.prepare, def)
	if not ok then fail(err) end
	def.kind = kind
	def.armor, def.hold, def.mass = def.armor or 200, def.hold or 20, def.mass or 100
	def.loot = def.loot or {}
	def.slots = {}
	for i, l in ipairs(def.loot) do
		if type(l) ~= "table" or type(l[1]) ~= "string" then fail(("%s '%s' loot %d should be { item, min, max, chance }"):format(kind, def.id, i)) end
	end
	-- radius: half its width, as for hulls
	local w = 0
	for k = 2, #def.shape, 2 do w = math.max(w, math.abs(def.shape[k])) end
	def.radius = def.radius or math.max(4, math.floor(w + 0.5))
end

function api.wreck(def) wreckLike("wreck", def) end
function api.prop(def) def.loot = {}; wreckLike("prop", def) end

-- A wreck or prop made at runtime (the Shipyard's test spawn).
function data.defineWreck(def)
	local was = currentFile
	currentFile = "shipyard"
	local ok, err = pcall(def.kind == "prop" and api.prop or api.wreck, def)
	currentFile = was
	if not ok then return nil, err end
	return def
end

-- A station layout (src/stations.lua has the format and the generated
-- wheels). One part says dock = true: its box is the docking module, door
-- at its +x end.
local STATION_ROLES = { habitat = true, shipyard = true, customs = true, mine = true }
function api.station(def)
	if not def.name then def.name = def.id end
	register("stations", "station", def)
	if not def.parts then fail(("station '%s' needs parts"):format(def.id)) end
	-- role: which A-Life smart terrain the station is (habitat, shipyard,
	-- customs, mine). Left out, it's a plain station.
	if def.role ~= nil and not STATION_ROLES[def.role] then
		fail(("station '%s' has unknown role '%s' (use habitat, shipyard, customs or mine)"):format(def.id, tostring(def.role)))
	end
	local ok, err = pcall(HullShape.prepare, def)
	if not ok then fail(err) end
	-- every part tagged dock is a docking module. Its frame points from the
	-- station's centre out through the part by default; authored heading,
	-- entrance and dimensions override that geometry for any station shape.
	-- dockBoth opens both ends of the same frame.
	def.docks = {}
	for _, part in ipairs(def.parts) do
		if part.dock then
			local ok,d=pcall(require("src.dock_geometry").build,part)
			if not ok then fail(("station '%s': %s"):format(def.id,d)) end
			table.insert(def.docks, d)
		end
	end
	if #def.docks == 0 then fail(("station '%s' needs a part with dock = true"):format(def.id)) end
	-- berths: parking spots outside, { x, y, heading (degrees, the way the
	-- parked ship faces), size (the longest ship half-length that fits) }.
	-- Arriving ships take a free one that fits; the rest go inside.
	if def.berths ~= nil and type(def.berths) ~= "table" then fail(("station '%s': berths should be a list"):format(def.id)) end
	-- rotors: parts that turn on their own, apart from the station's core
	-- (where the docks and berths are). rotors = { name = { x, y (the
	-- pivot, default 0, 0), spin (radians a second; left out, the
	-- location's spin), over (drawn on top of the core instead of under
	-- it) } }, and each turning part says rotor = "name".
	-- Every part without a rotor is the core, which holds still.
	if def.rotors ~= nil and type(def.rotors) ~= "table" then fail(("station '%s': rotors should be a table"):format(def.id)) end
	def.staticParts, def.rotorParts = nil, nil
	if def.rotors and next(def.rotors) then
		def.staticParts, def.rotorParts = {}, {}
		for name, r in pairs(def.rotors) do
			if type(r) ~= "table" then fail(("station '%s': rotor '%s' should be a table"):format(def.id, tostring(name))) end
			if r.over ~= nil and type(r.over) ~= "boolean" then fail(("station '%s': rotor '%s' over should be true or false"):format(def.id, tostring(name))) end
			for _, f in ipairs({ "x", "y", "spin" }) do
				if r[f] ~= nil and type(r[f]) ~= "number" then fail(("station '%s': rotor '%s' %s should be a number"):format(def.id, tostring(name), f)) end
			end
			def.rotorParts[name] = {}
		end
		for _, part in ipairs(def.parts) do
			if part.rotor ~= nil then
				local list = def.rotorParts[part.rotor]
				if not list then fail(("station '%s': part '%s' names unknown rotor '%s'"):format(def.id, tostring(part.name), tostring(part.rotor))) end
				if part.dock then fail(("station '%s': dock part '%s' can't be on a rotor"):format(def.id, tostring(part.name))) end
				table.insert(list, part)
			else
				table.insert(def.staticParts, part)
			end
		end
	end
	-- turrets: { x, y, module (a weapon module id), turn
	-- (degrees a second, default 90) }. They fire the module's weapon with
	-- endless ammo at whatever Game:stationHostile picks.
	if def.turrets ~= nil and type(def.turrets) ~= "table" then fail(("station '%s': turrets should be a list"):format(def.id)) end
	for j, t in ipairs(def.turrets or {}) do
		if type(t.x) ~= "number" or type(t.y) ~= "number" then fail(("station '%s': turret %d needs x and y"):format(def.id, j)) end
		local m = data.modules[t.module]
		if not (m and m.weapon) then
			fail(("station '%s': turret %d: '%s' isn't a weapon module"):format(def.id, j, tostring(t.module)))
		end
		t.turn = t.turn or 90
		if t.heading ~= nil and type(t.heading) ~= "number" then fail(("station '%s': turret %d heading should be a number"):format(def.id, j)) end
	end
	for j, b in ipairs(def.berths or {}) do
		if type(b.x) ~= "number" or type(b.y) ~= "number" then fail(("station '%s': berth %d needs x and y"):format(def.id, j)) end
		b.heading = b.heading or 0
		b.size = b.size or 80
		if type(b.heading) ~= "number" or type(b.size) ~= "number" then fail(("station '%s': berth %d heading and size should be numbers"):format(def.id, j)) end
	end
	def.dock = def.docks[1]
	local reach = 0
	for k = 1, #def.shape, 2 do reach = math.max(reach, math.sqrt(def.shape[k] ^ 2 + def.shape[k + 1] ^ 2)) end
	def.radius = reach
	def.slots = {}
end

function data.defineStation(def)
	local was = currentFile
	currentFile = "stations"
	local ok, err = pcall(api.station, def)
	currentFile = was
	if not ok then return nil, err end
	return def
end

function api.module(def)
	register("modules", "module", def)
	need(def, "family", "module"); need(def, "size", "module"); need(def, "mass", "module")
	if not MODULE_FAMILIES[def.family] then fail(("module '%s' has unknown family '%s'"):format(def.id, tostring(def.family))) end
	if not SIZES[def.size] then fail(("module '%s' has unknown size '%s'"):format(def.id, tostring(def.size))) end
	if def.family=="computer" then
		for _,field in ipairs({"radarRange","uplinkRange","lookahead","predictionTime","lockCone","controlLimit"}) do
			local value=def[field]
			if value~=nil and (type(value)~="number" or value~=value or value<=0 or value==math.huge) then
				fail(("computer '%s': %s must be a positive finite number"):format(def.id,field))
			end
		end
		if def.lockCone and def.lockCone>180 then fail(("computer '%s': lockCone must be at most 180 degrees"):format(def.id)) end
		if def.controlLimit and def.controlLimit%1~=0 then fail(("computer '%s': controlLimit must be an integer"):format(def.id)) end
	end
	-- pulse / beam kinds (briefly separate) are lasers
	if def.weapon and (def.weapon.kind == "pulse" or def.weapon.kind == "beam") then
		def.weapon.beam = def.weapon.kind == "beam" or nil
		def.weapon.kind = "laser"
	end
	local old = def.weapon and OLD_KINDS[def.weapon.kind]
	if old then
		def.weapon.kind = old[1]
		if old[2] and not def.weapon.chambers then def.weapon.chambers = { old[2] } end
	end
	if def.weapon and def.weapon.chambers ~= nil and type(def.weapon.chambers) ~= "table" then
		fail(("module '%s': chambers should be a list of ammo families, like { \"gun\", \"shotgun\" }"):format(def.id))
	end
	if def.weapon and not WEAPON_KINDS[def.weapon.kind] then
		fail(("module '%s' has unknown weapon kind '%s'"):format(def.id, tostring(def.weapon.kind)))
	end
end

function api.ammo(def)
	register("items", "ammo", def)
	need(def, "family", "ammo"); need(def, "size", "ammo"); need(def, "volume", "ammo"); need(def, "mass", "ammo")
	need(def, "shot", "ammo")
	def.kind = "ammo"
end

function api.salvage(def)
	register("items", "salvage", def)
	need(def, "volume", "salvage"); need(def, "mass", "salvage"); need(def, "price", "salvage")
	def.kind = "salvage"
end

-- A container: an item you can stow in a hold when it's empty, and a
-- floating box with a grid of its own (grid = { w, h }) when it isn't.
-- fill lists what a loaded one can turn up: { item, min, max, chance }.
function api.container(def)
	register("items", "container", def)
	for _, f in ipairs({ "volume", "mass", "price", "w", "h", "grid", "hp", "body" }) do need(def, f, "container") end
	def.kind, def.stack = "container", 1
	def.fill = def.fill or {}
end

-- Market profiles have their own identity; station placements reference them explicitly.
function api.market(def)
	if type(def) ~= "table" then fail("market expects a table, like market { station = ..., sells = { ... } }") end
	if type(def.id or def.location) ~= "string" then fail("market needs an explicit id") end
 def.station=def.station or def.id or def.location
	if def.location ~= nil and type(def.location) ~= "string" then fail("market location must be an ID string") end
	if def.shops ~= nil then
		if type(def.shops) ~= "table" or #def.shops == 0 then fail(("market '%s': shops must be a list"):format(def.station)) end
		for i, shop in ipairs(def.shops) do
			if type(shop.name) ~= "string" then fail(("market '%s' shop %d is missing 'name'"):format(def.station, i)) end
			if type(shop.sells) ~= "table" then fail(("market '%s' shop '%s' is missing 'sells'"):format(def.station, shop.name)) end
		end
	elseif type(def.sells) ~= "table" then fail(("market '%s' is missing 'sells' (or 'shops')"):format(def.station)) end
	def.source = currentFile
	data.markets[def.id or def.location] = def
end

function api.enemy(def)
	register("enemies", "enemy", def)
	need(def, "hull", "enemy"); need(def, "ai", "enemy")
	if def.livery ~= nil and (type(def.livery) ~= "table" or type(def.livery.primary) ~= "table") then
		error(("enemy '%s': livery should be { primary = { r, g, b }, secondary = { r, g, b }? }"):format(tostring(def.id)), 0)
	end
end

-- A hull made at runtime (the F2 editor's test flight). Errors come back
-- as nil, message instead of being thrown.
function data.defineHull(def)
	local was = currentFile
	currentFile = "shipyard"
	local ok, err = pcall(api.hull, def)
	currentFile = was
	if not ok then return nil, err end
	return def
end

local addModuleItems
-- A weapon module made at runtime (the Shipyard's Weapons tab). Errors
-- come back as nil, message instead of being thrown.
function data.defineModule(def)
	local was = currentFile
	currentFile = "shipyard"
	local ok, err = pcall(api.module, def)
	currentFile = was
	if not ok then return nil, err end
	addModuleItems()
	return def
end

-- Loading ------------------------------------------------------------------

local function sandbox()
	local env = {
		math = math, string = string, table = table,
		pairs = pairs, ipairs = ipairs, tostring = tostring, tonumber = tonumber,
		type = type, unpack = unpack, select = select, print = print,
	}
	for k, fn in pairs(api) do env[k] = fn end
	return env
end

local function loadFile(path)
	currentFile = path
	local source = love.filesystem.read(path)
	local chunk, err = loadstring(source, "@" .. path)
	if not chunk then error(err, 0) end
	setfenv(chunk, sandbox())
	chunk()
end

local loadFolder
function loadFolder(folder)
	local files = love.filesystem.getDirectoryItems(folder)
	table.sort(files)
	-- files first, then subfolders (the Shipyard lets you sort designs into folders)
	local n = 0
	for _, name in ipairs(files) do
		if name:match("%.lua$") then loadFile(folder .. "/" .. name); n = n + 1 end
	end
	if folder:sub(1, 5) == "mods/" then print(("[data] %s: %d file%s"):format(folder, n, n == 1 and "" or "s")) end
	for _, name in ipairs(files) do
		local sub = folder .. "/" .. name
		if love.filesystem.getInfo(sub, "directory") then loadFolder(sub) end
	end
end

-- The ammo families a weapon chambers (see data.CHAMBERS).
function data.chambers(w)
	return w and (w.chambers or data.CHAMBERS[w.kind]) or {}
end

-- Every ammo a weapon module can load: a family it chambers, in its exact
-- caliber (hardpoint weapons) or its size or smaller (bay launchers). Its
-- first chambered family comes first, then biggest first.
function data.ammoOptions(module)
	local w = module.weapon
	local out = {}
	local rank = {}
	for i, fam in ipairs(data.chambers(w)) do rank[fam] = i end
	for _, id in ipairs(data.list.items) do
		local item = data.items[id]
		if item.kind == "ammo" and rank[item.family] then
			-- a gun's caliber is its size unless it says otherwise (twin mounts)
			local fits = item.size == (w.caliber or module.size)
			if module.family == "bay" then fits = SIZES[item.size] <= SIZES[module.size] end
			if fits then table.insert(out, id) end
		end
	end
	table.sort(out, function(a, b)
		local ia, ib = data.items[a], data.items[b]
		if ia.family ~= ib.family then return rank[ia.family] < rank[ib.family] end
		if ia.size ~= ib.size then return SIZES[ia.size] > SIZES[ib.size] end
		if (ia.price or 0) ~= (ib.price or 0) then return (ia.price or 0) < (ib.price or 0) end   -- cheapest is the default
		return a < b
	end)
	return out
end

-- The ammo a weapon fires by default (its biggest option).
function data.ammoFor(module)
	return data.ammoOptions(module)[1]
end

-- Modules that fit a slot (size matching is strict).
function data.modulesFor(slot)
	local out = {}
	for _, id in ipairs(data.list.modules) do
		local m = data.modules[id]
		if data.fits(slot, m) then table.insert(out, id) end
	end
	return out
end

local function crossCheck()
	for name, mk in pairs(data.markets) do
		for _, id in ipairs(mk.ships or {}) do
			if not data.hulls[id] or data.hulls[id].playable == false then
				error(("%s: market '%s' sells unknown or unplayable ship '%s'"):format(mk.source, name, tostring(id)), 0)
			end
		end
		for _, shop in ipairs(mk.shops or { { sells = mk.sells } }) do
			for _, e in ipairs(shop.sells) do
				if not data.items[e[1]] then
					error(("%s: market '%s' sells unknown item '%s'"):format(mk.source, name, tostring(e[1])), 0)
				end
			end
		end
	end
	local function checkLoadout(owner, hull, loadout)
		for i, slot in ipairs(hull.slots) do
			local id = loadout and loadout[i]
			if id and id ~= false then
				local m = data.modules[id]
				if not m then error(("%s: loadout slot %d uses unknown module '%s'"):format(owner, i, id), 0) end
				if not data.fits(slot, m) then
					error(("%s: module '%s' (%s %s) doesn't fit slot %d (%s %s)"):format(
						owner, id, m.family, m.size, i, slot.family, slot.size), 0)
				end
			end
		end
	end
	for id, h in pairs(data.hulls) do checkLoadout("hull '" .. id .. "'", h, h.loadout) end
	-- Grid shapes: whole cells, and a stack can't hold more than its cells.
	for id, item in pairs(data.items) do
		if item.w or item.h or item.stack then
			local w, h, stack = item.w or 0, item.h or 0, item.stack or 1
			for _, v in ipairs({ w, h, stack }) do
				if v < 1 or v % 1 ~= 0 then
					error(("item '%s': w, h and stack must be whole numbers of 1 or more"):format(id), 0)
				end
			end
			if w * h < item.volume * stack - 1e-6 then
				error(("item '%s': a stack of %d is %.2f m3 but its %d x %d cells only hold %d"):format(
					id, stack, item.volume * stack, w, h, w * h), 0)
			end
		end
	end
	for id, item in pairs(data.items) do
		if item.kind == "container" then
			for _, f in ipairs(item.fill) do
				if not data.items[f[1]] then error(("container '%s' fills with unknown item '%s'"):format(id, tostring(f[1])), 0) end
			end
		end
	end
	for id, e in pairs(data.enemies) do
		local h = data.hulls[e.hull]
		if not h then error(("enemy '%s' uses unknown hull '%s'"):format(id, e.hull), 0) end
		checkLoadout("enemy '" .. id .. "'", h, e.loadout or h.loadout)
	end
	for id, m in pairs(data.modules) do
		if m.weapon and not data.LASERS[m.weapon.kind] and m.weapon.kind ~= "drill" and not data.ammoFor(m) then
			error(("module '%s' fires %s %s ammo, but no ammo with that family and size exists"):format(
				id, m.weapon.kind, m.size), 0)
		end
	end
end

-- Every module is also an item, so spares can sit in a hold, in station
-- storage or in a husk. Its shape comes from its size (S 2 x 1, M 2 x 2,
-- L 3 x 2, any 2 x 1), its volume matches the shape and its mass is the
-- module's own. Module items stay out of data.list.items so they don't
-- show up in ammo lists.
local MODULE_SHAPES = { S = { 2, 1 }, M = { 2, 2 }, L = { 3, 2 }, any = { 2, 1 } }
function addModuleItems()
	for _, id in ipairs(data.list.modules) do
		local m = data.modules[id]
		local existing = data.items[id]
		if existing and existing.kind ~= "module" then
			error(("module '%s' has the same id as an item"):format(id), 0)
		end
		local shape = MODULE_SHAPES[m.size]
		data.items[id] = {
			id = id, kind = "module", module = id, name = m.name, maker = m.maker, size = m.size,
			w = shape[1], h = shape[2], stack = 1, volume = shape[1] * shape[2], mass = m.mass, price = m.price or 0,
		}
	end
end

data.renamedModules = {
	px2_autogun = "gun_s_base", rk7_autocannon = "gun_m_base", rk14_twin = "gun_l_base",
	pip_mortar = "artillery_s_base", thumper_m = "artillery_m_base", long_tom = "artillery_l_base",
	sparrow_rack = "missile_s_base", hornet_pod = "missile_m_base", trident_bay = "missile_l_base",
	artilllery_S_base = "artillery_s_base",
	thread_beam = "beam_s_base", searing_ray = "beam_m_base", furnace_beam = "beam_l_base",
	bore_drill = "drill_s_base", rockbiter = "drill_m_base", deep_core_drill = "drill_l_base",
	wasp_bay = "drone_s_base", hive_bay = "drone_m_base", carrier_deck = "drone_l_base",
	glint_laser = "pulse_s_base", lumen_lance = "pulse_m_base", sunder_beam = "pulse_l_base",
	-- torpedo tubes are gone: torpedoes are missile-rack ammo now
	maul_tube = "missile_s_base", breaker_tube = "missile_m_base", leviathan_tube = "missile_l_base",
}
-- the first _base ids had upper-case sizes (gun_S_base)
for _, kind in ipairs({ "gun", "artillery", "missile", "pulse", "beam", "drill", "drone" }) do
	for _, size in ipairs({ "S", "M", "L" }) do
		data.renamedModules[kind .. "_" .. size .. "_base"] = kind .. "_" .. size:lower() .. "_base"
	end
end

-- Hulls that took new ids (lower case, or a new maker), so saves still load.
data.renamedHulls = {
	halcyon_wisp = "intaki_wisp", ferrous_bastion = "estates_bastion", brute_praetor = "intaki_praetor",
	Intaki_Archangel = "intaki_archangel", Intaki_wisp = "intaki_wisp", ferrous_Bison = "ferrous_bison",
}

function data.load()
	loadFolder("data")
	if love.filesystem.getInfo("mods", "directory") then
		local mods = love.filesystem.getDirectoryItems("mods")
		table.sort(mods)
		for _, mod in ipairs(mods) do
			local folder = "mods/" .. mod .. "/data"
			if love.filesystem.getInfo(folder, "directory") then loadFolder(folder) end
		end
	end
	addModuleItems()
	-- Old weapon ids (before the Shipyard <kind>_<size>_base designs) still
	-- resolve, so saves holding them load. Lookup only: not in the lists.
	for old, new in pairs(data.renamedModules) do
		if data.modules[new] and not data.modules[old] then
			data.modules[old], data.items[old] = data.modules[new], data.items[new]
		end
	end
	for old, new in pairs(data.renamedHulls) do
		if data.hulls[new] and not data.hulls[old] then data.hulls[old] = data.hulls[new] end
	end
	crossCheck()
end

return data
