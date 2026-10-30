--[[
	Content loader.

	Every hull, module, ammo type, salvage item and enemy is defined in a
	plain Lua file under data/, or under mods/<modname>/data/. Those files
	run in a sandbox: all they can do is call the registration functions
	below (hull, module, ammo, salvage, enemy) and use basic math, string
	and table helpers. They cannot touch files, globals or game state.

	The base game loads its own content through exactly the same path a mod
	would, and anything a mod defines with an existing id replaces the base
	definition. So "modding support" is just this file.
]]

local data = {
	hulls = {}, modules = {}, items = {}, enemies = {},
	-- definition order, so menus list things the way the data files do
	list = { hulls = {}, modules = {}, items = {}, enemies = {} },
}

local FAMILIES = { primary = true, secondary = true, engine = true, reactor = true, armor = true, utility = true, thruster = true }
local SIZES = { S = 1, M = 2, L = 3, any = 0 }   -- "any": shared slots every hull class uses alike
local WEAPON_KINDS = { gun = true, artillery = true, laser = true, missile = true }
local MOUNTS = { fixed = true, gimbal = true, turret = true }
data.FAMILIES, data.SIZES = FAMILIES, SIZES

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

local api = {}

function api.hull(def)
	register("hulls", "hull", def)
	for _, f in ipairs({ "mass", "armor", "hold", "drag", "radius", "slots", "shape" }) do need(def, f, "hull") end
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

function api.module(def)
	register("modules", "module", def)
	need(def, "family", "module"); need(def, "size", "module"); need(def, "mass", "module")
	if not FAMILIES[def.family] then fail(("module '%s' has unknown family '%s'"):format(def.id, tostring(def.family))) end
	if not SIZES[def.size] then fail(("module '%s' has unknown size '%s'"):format(def.id, tostring(def.size))) end
	if def.weapon and not WEAPON_KINDS[def.weapon.kind] then
		fail(("module '%s' has unknown weapon kind '%s'"):format(def.id, tostring(def.weapon.kind)))
	end
end

function api.ammo(def)
	register("items", "ammo", def)
	need(def, "family", "ammo"); need(def, "size", "ammo"); need(def, "volume", "ammo"); need(def, "mass", "ammo")
	def.kind = "ammo"
end

function api.salvage(def)
	register("items", "salvage", def)
	need(def, "volume", "salvage"); need(def, "mass", "salvage"); need(def, "price", "salvage")
	def.kind = "salvage"
end

function api.enemy(def)
	register("enemies", "enemy", def)
	need(def, "hull", "enemy"); need(def, "ai", "enemy")
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

-- Find the ammo a weapon module fires: same family as the weapon kind, same size.
function data.ammoFor(module)
	local w = module.weapon
	if not w or w.kind == "laser" then return nil end
	for _, id in ipairs(data.list.items) do
		local item = data.items[id]
		if item.kind == "ammo" and item.family == w.kind and item.size == module.size then return id end
	end
	return nil
end

-- Modules that fit a slot: same family, same size (size matching is strict).
function data.modulesFor(slot)
	local out = {}
	for _, id in ipairs(data.list.modules) do
		local m = data.modules[id]
		if m.family == slot.family and m.size == slot.size then table.insert(out, id) end
	end
	return out
end

local function crossCheck()
	local function checkLoadout(owner, hull, loadout)
		for i, slot in ipairs(hull.slots) do
			local id = loadout and loadout[i]
			if id and id ~= false then
				local m = data.modules[id]
				if not m then error(("%s: loadout slot %d uses unknown module '%s'"):format(owner, i, id), 0) end
				if m.family ~= slot.family or m.size ~= slot.size then
					error(("%s: module '%s' (%s %s) doesn't fit slot %d (%s %s)"):format(
						owner, id, m.family, m.size, i, slot.family, slot.size), 0)
				end
			end
		end
	end
	for id, h in pairs(data.hulls) do checkLoadout("hull '" .. id .. "'", h, h.loadout) end
	for id, e in pairs(data.enemies) do
		local h = data.hulls[e.hull]
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
	crossCheck()
end

return data
