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
	hulls = {}, modules = {}, items = {}, enemies = {}, markets = {}, wrecks = {},
	-- definition order, so menus list things the way the data files do
	list = { hulls = {}, modules = {}, items = {}, enemies = {}, wrecks = {} },
}

-- Slot families. primary / secondary are fire groups for guns (left and
-- right mouse button); auxiliary holds a launcher (middle mouse button).
local FAMILIES = { primary = true, secondary = true, auxiliary = true, engine = true, reactor = true, utility = true, thruster = true, computer = true }
-- Module families. A "weapon" (gun, artillery, laser) fits a primary or a
-- secondary slot; every other family fits the slot of the same name.
local MODULE_FAMILIES = { weapon = true, auxiliary = true, engine = true, reactor = true, utility = true, thruster = true, computer = true }
local SIZES = { S = 1, M = 2, L = 3, any = 0 }   -- "any": shared slots every hull class uses alike
local WEAPON_KINDS = { gun = true, artillery = true, laser = true, missile = true, torpedo = true, drone = true }
local MOUNTS = { fixed = true, gimbal = true, turret = true }
data.FAMILIES, data.SIZES = FAMILIES, SIZES

-- Does a module fit a hull slot?
function data.fits(slot, m)
	-- a module sized "any" fits a slot of any size (side jets scale to it)
	if m.size ~= slot.size and m.size ~= "any" then return false end
	if m.family == "weapon" then return slot.family == "primary" or slot.family == "secondary" end
	return m.family == slot.family
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

function api.hull(def)
	register("hulls", "hull", def)
	for _, f in ipairs({ "mass", "armor", "hold", "drag", "slots" }) do need(def, f, "hull") end
	if not def.shape and not def.parts then fail(("hull '%s' needs a shape or parts"):format(def.id)) end
	local LAYERS = { hull = true, detail = true, glow = true }
	for i, part in ipairs(def.parts or {}) do
		local function bad(what) fail(("hull '%s' part %d: %s"):format(def.id, i, what)) end
		if part.layer ~= nil and not LAYERS[part.layer] then bad("unknown layer '" .. tostring(part.layer) .. "' (use hull, detail or glow)") end
		if part.color ~= nil and (type(part.color) ~= "table" or #part.color < 3) then bad("color should be { r, g, b }") end
		if part.tint ~= nil and (type(part.tint) ~= "table" or #part.tint < 3) then bad("tint should be { r, g, b }") end
		if part.armor ~= nil and type(part.armor) ~= "number" then bad("armor should be a number") end
		if part.shade ~= nil and type(part.shade) ~= "number" then bad("shade should be a number") end
		if part.mass ~= nil and type(part.mass) ~= "number" then bad("mass should be a number") end
		if part.lights ~= nil then
			if type(part.lights) ~= "table" then bad("lights should be a list") end
			for j, l in ipairs(part.lights) do
				if type(l.x) ~= "number" or type(l.y) ~= "number" then bad(("light %d needs x and y"):format(j)) end
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
	if def.helm and def.helm ~= "strafe" and def.helm ~= "turn" then fail(("hull '%s' has unknown helm '%s' (use strafe or turn)"):format(def.id, tostring(def.helm))) end
	if not MOUNTS[def.mount] then fail(("hull '%s' has unknown mount '%s' (use fixed, gimbal or turret)"):format(def.id, tostring(def.mount))) end
	for i, slot in ipairs(def.slots) do
		if slot.mount and not MOUNTS[slot.mount] then fail(("hull '%s' slot %d has unknown mount '%s'"):format(def.id, i, tostring(slot.mount))) end
		if not FAMILIES[slot.family] then fail(("hull '%s' slot %d has unknown family '%s'"):format(def.id, i, tostring(slot.family))) end
		if not SIZES[slot.size] then fail(("hull '%s' slot %d has unknown size '%s' (use S, M, L or any)"):format(def.id, i, tostring(slot.size))) end
	end
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

function api.module(def)
	register("modules", "module", def)
	need(def, "family", "module"); need(def, "size", "module"); need(def, "mass", "module")
	if not MODULE_FAMILIES[def.family] then fail(("module '%s' has unknown family '%s'"):format(def.id, tostring(def.family))) end
	if not SIZES[def.size] then fail(("module '%s' has unknown size '%s'"):format(def.id, tostring(def.size))) end
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

-- A station's market: what it sells (data/markets.lua). Keyed by station
-- name; a later one for the same station replaces it.
function api.market(def)
	if type(def) ~= "table" then fail("market expects a table, like market { station = ..., sells = { ... } }") end
	if type(def.station) ~= "string" then fail("market is missing 'station'") end
	if type(def.sells) ~= "table" then fail(("market '%s' is missing 'sells'"):format(def.station)) end
	def.source = currentFile
	data.markets[def.station] = def
end

function api.enemy(def)
	register("enemies", "enemy", def)
	need(def, "hull", "enemy"); need(def, "ai", "enemy")
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

local function loadFolder(folder)
	local files = love.filesystem.getDirectoryItems(folder)
	table.sort(files)
	for _, name in ipairs(files) do
		if name:match("%.lua$") then loadFile(folder .. "/" .. name) end
	end
end

-- Every ammo a weapon module can fire, biggest first: same family as the
-- weapon kind, and the same caliber (guns, artillery) or the same size or
-- smaller (auxiliary launchers: missiles, torpedoes, drones).
function data.ammoOptions(module)
	local w = module.weapon
	local out = {}
	if not w or w.kind == "laser" then return out end
	for _, id in ipairs(data.list.items) do
		local item = data.items[id]
		if item.kind == "ammo" and item.family == w.kind then
			-- a gun's caliber is its size unless it says otherwise (twin mounts)
			local fits = item.size == (w.caliber or module.size)
			if module.family == "auxiliary" then fits = SIZES[item.size] <= SIZES[module.size] end
			if fits then table.insert(out, id) end
		end
	end
	table.sort(out, function(a, b) return SIZES[data.items[a].size] > SIZES[data.items[b].size] end)
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
		for _, e in ipairs(mk.sells) do
			if not data.items[e[1]] then
				error(("%s: market '%s' sells unknown item '%s'"):format(mk.source, name, tostring(e[1])), 0)
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
		for _, c in ipairs(e.containers and { e.containers[1] } or {}) do
			if not data.items[c] or data.items[c].kind ~= "container" then
				error(("enemy '%s' carries unknown container '%s'"):format(id, tostring(c)), 0)
			end
		end
		if not h then error(("enemy '%s' uses unknown hull '%s'"):format(id, e.hull), 0) end
		checkLoadout("enemy '" .. id .. "'", h, e.loadout or h.loadout)
	end
	for id, m in pairs(data.modules) do
		if m.weapon and m.weapon.kind ~= "laser" and not data.ammoFor(m) then
			error(("module '%s' fires %s %s ammo, but no ammo with that family and size exists"):format(
				id, m.weapon.kind, m.size), 0)
		end
	end
end

-- Every ammo type gets a matching crate item: the same rounds boxed up as
-- cargo. Looted ammo arrives as crates, which weapons can't fire from;
-- they're for selling or restocking at a station.
local function addCrates()
	for _, id in ipairs(data.list.items) do
		local a = data.items[id]
		if a.kind == "ammo" and not a.crate then
			local cid = id .. "_crate"
			a.crate = cid
			data.items[cid] = {
				id = cid, kind = "crate", ammo = id, name = a.name .. " (crate)", maker = a.maker,
				volume = a.volume, mass = a.mass, price = a.price,
			}
		end
	end
end

-- Every module is also an item, so spares can sit in a hold, in station
-- storage or in a husk. Its shape comes from its size (S 2 x 1, M 2 x 2,
-- L 3 x 2, any 2 x 1), its volume matches the shape and its mass is the
-- module's own. Module items stay out of data.list.items so they don't
-- show up in ammo lists.
local MODULE_SHAPES = { S = { 2, 1 }, M = { 2, 2 }, L = { 3, 2 }, any = { 2, 1 } }
local function addModuleItems()
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
	addCrates()
	addModuleItems()
	crossCheck()
end

return data
