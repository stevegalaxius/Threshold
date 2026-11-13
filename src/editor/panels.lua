--[[
	The Shipyard's Slab windows: the design panel on the left (file,
	tools, view, parts list) and the part inspector on the right.
]]

local Slab = require("lib.Slab")
local data = require("src.data")
local Canvas = require("src.editor.canvas")
local Export = require("src.editor.export")
local HullShape = require("src.hullshape")

local Panels = {}

local LAYERS = { "hull", "detail", "glow" }
local GRIDS = { 1, 2, 4, 8, 16 }
local PREVIEWS = { normal = "Normal", wreck = "Wreck", collision = "Collision", ["break"] = "Break apart" }

-- Hull stats the design can set over its base hull (see data/hulls.lua and data/ships/).
local STATS = {
	{ "mass", "mass (t)", "Dry weight in tonnes. Heavier = slower to accelerate and turn.", 1, 5000, 5, 0 },
	{ "armor", "armor", "Hit points of the hull itself.", 10, 5000, 10, 0 },
	{ "hold", "hold (m3)", "Cargo space in cubic metres.", 0, 1000, 1, 0 },
	{ "drag", "drag", "Quadratic drag. Top speed = sqrt(thrust x 100 / drag), so lower drag = faster.", 0.01, 5, 0.01, 2 },
	{ "turn", "turn torque", "How hard it rotates. Bigger = snappier.", 0, 20000, 50, 0 },
	{ "turnSpeed", "turn cap (deg/s)", "Optional top spin speed, so a heavy hull comes about slowly even with lots of torque.", 10, 720, 5, 0 },
	{ "sideThrust", "maneuvering (kN)", "Built-in side thrust; turn-mode hulls use it for turning.", 0, 5000, 10, 0 },
	{ "spoolTime", "spool (s)", "Seconds for the main engine to reach full thrust. A slight ramp makes heavy hulls feel heavy. 0 = instant.", 0, 3, 0.05, 2 },
	{ "toughness", "toughness", "Crash damage is divided by this (default 1; 2 = half). Light ships already take the most, since their speed changes most.", 0.1, 10, 0.05, 2 },
	{ "turretTurn", "turret (deg/s)", "How fast turret-mounted guns swing round. Only matters when mount is turret.", 10, 720, 5, 0 },
	{ "price", "price", "Credits to buy it.", 0, 1000000, 500, 0 },
}
local FAMILIES = { "hardpoint", "bay", "engine", "reactor", "computer" }   -- utility is deprecated (reads as computer)
local SIZES = { "S", "M", "L" }
-- Families with no sizes: their slots are always "any" (data/hulls.lua).
local SIZELESS = { utility = true, computer = true }

local function combo(id, selected, options, onPick, w)
	if Slab.BeginComboBox(id, { Selected = selected, W = w or 200 }) then
		for _, opt in ipairs(options) do
			if Slab.TextSelectable(opt.label) then onPick(opt.value) end
		end
		Slab.EndComboBox()
	end
end

local function textField(E, id, value, onChange, w)
	if Slab.Input(id, { Text = value or "", W = w or 200, ReturnOnText = true }) then
		E.pushUndoCoalesced(id)
		onChange(Slab.GetInputText())
	end
end

local function slider(E, id, value, lo, hi, onChange, precision)
	if Slab.InputNumberSlider(id, value, lo, hi, { W = 200, Precision = precision or 2 }) then
		E.pushUndoCoalesced(id)
		onChange(Slab.GetInputNumber())
	end
end

local function check(E, value, label, onChange)
	if Slab.CheckBox(value, label) then
		E.pushUndo()
		onChange(not value)
	end
end

local CATEGORIES = {
	{ "hull", "Ships", "Hulls you can fly" },
	{ "wreck", "Containers", "Containers and props placed in the world" },
	{ "station", "Stations", "Station layouts" },
	{ "weapon", "Weapons", "Guns, launchers and bays: stats and art" },
}

-- Weapon stats by kind: key, label, lo, hi, step, precision, tooltip.
local WSTAT = {
	fireRate = { "fire rate (/s)", 0.05, 30, 0.05, 2, "Shots per second." },
	spread = { "spread (deg)", 0, 20, 0.1, 1, "Random wobble on each shot." },
	gimbal = { "gimbal (deg)", 0, 45, 1, 0, "How far a gimballed mount can swing to aim." },
	recoil = { "recoil", 0, 20000, 10, 0, "Push back on the ship per launch." },
	recoilPct = { "recoil (%)", 0, 200, 1, 1, "Push back on the ship per shot, as a percentage of the round's knockback." },
	damage = { "damage", 0, 1000, 1, 0, "Per pulse, or per second for beams and drills." },
	range = { "range (px)", 100, 10000, 50, 0, "How far the beam reaches." },
	powerPerShot = { "power / shot", 0, 500, 1, 0, "Power each pulse takes." },
	powerPerSecond = { "power / s", 0, 500, 1, 0, "Power while it's held." },
	pulse = { "pulse (s)", 0.02, 1, 0.01, 2, "How long the flash lingers." },
	barrels = { "barrels", 1, 6, 1, 0, "Shots take turns between barrels (ignored when the art has muzzle points)." },
	barrelGap = { "barrel gap (px)", 0, 40, 1, 0, "Distance between barrels (ignored with muzzle points)." },
	rockDamage = { "rock damage", 0, 100, 1, 0, "Damage to asteroids." },
	extendTime = { "extend (s)", 0.05, 2, 0.05, 2, "Time to reach full length." },
	length = { "length (px)", 10, 2000, 5, 0, "How far it reaches fully out. Unset: as long as the ship." },
	width = { "shaft width (px)", 1, 40, 0.5, 1, "Thickness of the shaft. Unset: 6." },
	bitSize = { "bit size (px)", 2, 60, 0.5, 1, "Radius of the spinning bit at the tip. Unset: 9 / 13 / 17 by size." },
	control = { "control", 1, 8, 1, 0, "Drone control budget." },
	beams = { "beams", 1, 12, 1, 0, "Lines it fires at once, each doing the full damage (several = a multi-beam laser)." },
	beamSpread = { "beam spread (deg)", 0, 90, 0.5, 1, "How wide the beams fan out, edge to edge." },
	beamWidth = { "beam width", 0.2, 4, 0.05, 2, "Thickness of the drawn beam (1 = normal)." },
	capacity = { "tube capacity", 1, 32, 1, 0, "How much its tubes hold, in S rounds: an M round takes 2, an L round 4. It fires only what's armed, and re-arms one round at a time (each ammo's arm time)." },
}
local WFIELDS = {
	cannon = { "fireRate", "spread", "gimbal", "recoilPct", "barrels", "barrelGap" },
	laser = { "fireRate", "damage", "range", "powerPerShot", "pulse", "gimbal", "beams", "beamSpread", "beamWidth" },
	beam = { "damage", "range", "powerPerSecond", "gimbal", "beams", "beamSpread", "beamWidth" },
	drill = { "damage", "rockDamage", "powerPerSecond", "extendTime", "length", "width", "bitSize" },
	missile = { "fireRate", "capacity", "recoil" },
	drone = { "fireRate", "recoil", "control" },
}
local WKINDS = { "cannon", "laser", "drill", "missile", "drone" }
local BAY_KINDS = { missile = true, drone = true }

-- Wreck and prop settings, in place of hull stats and slots.
local WRECK_STATS = {
	{ "armor", "armor", 10, 20000, 10, 0, "How much damage it soaks before it bursts (its parts share it)." },
	{ "hold", "hold (m3)", 1, 1000, 1, 0, "Room for its loot." },
	{ "mass", "mass (t)", 1, 100000, 10, 0, "How hard it is to push around." },
}

-- A combo of the weapon modules a station turret can mount.
local function turretCombo(id, current, pick)
	local opts = {}
	for _, mid in ipairs(data.list.modules) do
		local m = data.modules[mid]
		if m.weapon then
			local kind = m.weapon.kind == "missile" and "missile rack"
				or m.weapon.kind == "drone" and "drone bay" or m.weapon.kind
			table.insert(opts, { label = ("%s (%s %s)"):format(m.name, m.size, kind), value = mid })
		end
	end
	local m = data.modules[current]
	combo(id, m and m.name or tostring(current), opts, pick, 200)
end

-- Window fill: lights a whole part in one go. Patterns:
--   rooms      groups of windows share a colour; some rooms dark
--   scattered  every window its own colour; whole rows go dark
--   rows       unbroken lit rows, like a deck's promenade
--   checker    every other window, a lattice
--   grid       every window lit
local WINDOW_PALETTES = Canvas.WINDOW_PALETTES or {
	warm = { { 1, 0.82, 0.5 }, { 1, 0.82, 0.5 }, { 1, 0.6, 0.35 }, { 1, 0.9, 0.7 } },
	mixed = { { 1, 0.82, 0.5 }, { 1, 0.82, 0.5 }, { 1, 0.6, 0.35 }, { 0.6, 0.9, 1 }, { 0.75, 1, 0.65 } },
	cool = { { 0.6, 0.9, 1 }, { 0.6, 0.9, 1 }, { 0.85, 0.95, 1 }, { 0.75, 1, 0.65 } },
	amber = { { 1, 0.7, 0.35 }, { 1, 0.6, 0.35 } },
	white = { { 1, 0.95, 0.85 } },
	auto = false,   -- no colour: the game's default window colour
}
Canvas.WINDOW_PALETTES = WINDOW_PALETTES
local WINDOW_PATTERNS = { "rooms", "scattered", "rows", "checker", "grid" }
local function fillWindows(E, p)
	local sx, sy = E.windowSpacing or (ship and 6 or 40), E.windowRowSpacing or (ship and 6 or 48)
	local density, pattern = E.windowDensity or 0.6, E.windowPattern or "rooms"
	local pal = WINDOW_PALETTES[E.windowPalette or "auto"]
	local pw, ph = Canvas.paneSize(E)
	local rnd = love.math.random
	local function colour() if pal then local c = pal[rnd(#pal)]; return { c[1], c[2], c[3] } end end
	local x0, x1, y0, y1 = math.huge, -math.huge, math.huge, -math.huge
	for k = 1, #p.shape, 2 do
		x0, x1 = math.min(x0, p.shape[k]), math.max(x1, p.shape[k])
		y0, y1 = math.min(y0, p.shape[k + 1]), math.max(y1, p.shape[k + 1])
	end
	local rooms, row = {}, 0
	p.lights = {}
	for y = y0 + sy * 0.75, y1 - sy * 0.4, sy do
		row = row + 1
		local rowLit, rowColour = rnd() >= 0.25, colour()
		local col = 0
		for x = x0 + sx * 0.75, x1 - sx * 0.4, sx do
			col = col + 1
			if Canvas.inside(p.shape, x, y) then
				local lit, c = false, nil
				if pattern == "rooms" then
					local key = math.floor(col / 3) .. ":" .. math.floor(row / 2)
					rooms[key] = rooms[key] or { lit = rnd() < density, c = colour() }
					lit, c = rooms[key].lit and rnd() < 0.9, rooms[key].c
				elseif pattern == "scattered" then
					lit, c = rowLit and rnd() < density, colour()
				elseif pattern == "rows" then
					lit, c = rnd() < 0.15 + density * 0.85 and row % 2 == 1, rowColour
				elseif pattern == "checker" then
					lit, c = (row + col) % 2 == 0 and rnd() < 0.3 + density * 0.7, colour()
				else
					lit, c = rnd() < 0.3 + density * 0.7, colour()
				end
				if lit then
					table.insert(p.lights, { kind = "window", x = math.floor(x + 0.5), y = math.floor(y + 0.5), w = pw, h = ph, color = c })
				end
			end
		end
	end
	if #p.lights == 0 then p.lights = nil end
end

local function placedSections(E, d)
	d.stats = d.stats or {}
	if d.kind == "station" then
		local docks = 0
		for _, p in ipairs(d.parts) do if p.dock then docks = docks + 1 end end
		Slab.Text("Station layout", { Color = { 0.8, 0.85, 1 } })
		Slab.Text("Mark one or more parts as docking modules;", { Color = { 0.6, 0.6, 0.6 } })
		Slab.Text("each door faces out from the centre.", { Color = { 0.6, 0.6, 0.6 } })
		Slab.Text(docks >= 1 and ("Docks: %d"):format(docks) or "No dock yet (needs at least 1)", { Color = docks >= 1 and { 0.5, 1, 0.6 } or { 1, 0.5, 0.4 } })
		Slab.Text("Role (A-Life smart terrain):")
		Slab.SameLine()
		combo("yard_station_role", d.role or "none", {
			{ label = "none", value = false }, { label = "habitat", value = "habitat" },
			{ label = "shipyard", value = "shipyard" }, { label = "customs", value = "customs" }, { label = "mine", value = "mine" },
		}, function(v) E.pushUndo(); d.role = v or nil end, 120)
		Slab.Separator()
		-- Station services: which tabs a docked player gets here.
		Slab.Text("Services (tabs when docked; Storage is always there):")
		local Game = require("src.game")
		local have = {}
		for _, id in ipairs(d.services or { "market", "shipyard", "hangar" }) do have[id] = true end
		for _, id in ipairs(Game.SERVICES) do
			check(E, have[id] == true, id, function(on)
				have[id] = on or nil
				d.services = {}
				for _, sid in ipairs(Game.SERVICES) do if have[sid] then table.insert(d.services, sid) end end
			end)
		end
		if have.repair then
			Slab.Text("repair cost per armor point"); Slab.SameLine({ Pad = 4 })
			if Slab.InputNumberDrag("yard_repairrate", d.repairRate or require("src.tuning").repairRate, 0, 200, 1, { W = 60, Precision = 0 }) then
				E.pushUndoCoalesced("yard_repairrate"); d.repairRate = math.floor(Slab.GetInputNumber())
			end
		end
		Slab.Separator()
		local nr = 0
		for _ in pairs(d.rotors or {}) do nr = nr + 1 end
		local shown = E.showRotors
		if shown == nil then shown = nr > 0 end
		check(E, shown, ("Rotors window (%d rotors)"):format(nr), function(on) E.showRotors = on end)
		Slab.Separator()
		Slab.Text("Use it: layout = \"<id>\" on a station entry", { Color = { 0.6, 0.6, 0.6 } })
		Slab.Text("in src/fields.lua, or export as ring_<R>_<tube>", { Color = { 0.6, 0.6, 0.6 } })
		Slab.Text("or city_<k> to replace that one.", { Color = { 0.6, 0.6, 0.6 } })
		Slab.Separator()
		local turrets = d.turrets or {}
		Slab.Button("?", { W = 18, H = 18, Tooltip = "Turrets fire any weapon module (guns, artillery, lasers, missiles, torpedoes, drones)\nwith endless ammo and power. For now they shoot hostile ships and anyone\nwho shoots the station (for 30 s); reputation will decide this later.\nTurn: how fast the turret swings, degrees a second.\nMissile, torpedo and drone launchers are fixed bays with a heading instead." })
		Slab.SameLine()
		Slab.Text(#turrets > 0 and ("Turrets: %d"):format(#turrets) or "Turrets: none")
		local t = E.tsel and turrets[E.tsel]
		if t then
			Slab.Text(("Turret %d"):format(E.tsel), { Color = { 0.6, 0.85, 1 } })
			turretCombo("yard_turretmod", t.module, function(id) E.pushUndo(); t.module = id end)
			local m = data.modules[t.module]
			if m and m.family == "bay" then
				Slab.Text("fixed bay: missiles curve to the target,", { Color = { 0.6, 0.6, 0.6 } })
				Slab.Text("drones fly off to it, torpedoes only", { Color = { 0.6, 0.6, 0.6 } })
				Slab.Text("fire down its line", { Color = { 0.6, 0.6, 0.6 } })
				Slab.Text("heading"); Slab.SameLine({ Pad = 4 })
				local out = (t.x == 0 and t.y == 0) and 0 or math.floor(math.deg(math.atan2(t.y, t.x)) + 0.5) % 360
				if Slab.InputNumberDrag("yard_turrethead", t.heading or out, 0, 359, 1, { W = 70 }) then
					E.pushUndoCoalesced("yard_turrethead"); t.heading = Slab.GetInputNumber()
				end
			else
				Slab.Text("turn"); Slab.SameLine({ Pad = 4 })
				if Slab.InputNumberDrag("yard_turretturn", t.turn or 90, 5, 360, 1, { W = 70 }) then
					E.pushUndoCoalesced("yard_turretturn"); t.turn = Slab.GetInputNumber()
				end
			end
			if Slab.Button("Remove turret") then E.deleteSelected() end
		end
		Slab.Separator()
		local berths = d.berths or {}
		Slab.Button("?", { W = 18, H = 18, Tooltip = "Berths are parking spots outside the station.\nA ship that docks takes a free berth it fits on and parks there, in view.\nWhen berths are full, ships that fit use the dock; oversized ships moor outside.\nSize controls the pad marker. Ship capacity is scaled separately." })
		Slab.SameLine()
		Slab.Text(#berths > 0 and ("Berths: %d"):format(#berths) or "Berths: none (every ship goes inside)")
		local b = E.bsel and berths[E.bsel]
		if b then
			Slab.Text(("Berth %d"):format(E.bsel), { Color = { 0.95, 0.75, 0.25 } })
			Slab.Text("heading"); Slab.SameLine({ Pad = 4 })
			if Slab.InputNumberDrag("yard_berthheading", b.heading or 0, 0, 359, 1, { W = 70 }) then
				E.pushUndoCoalesced("yard_berthheading"); b.heading = Slab.GetInputNumber()
			end
			Slab.SameLine()
			Slab.Text("size"); Slab.SameLine({ Pad = 4 })
			if Slab.InputNumberDrag("yard_berthsz", b.size or 80, 20, 400, 2, { W = 70 }) then
				E.pushUndoCoalesced("yard_berthsz"); b.size = Slab.GetInputNumber()
			end
			if Slab.Button("Remove berth") then E.deleteSelected() end
		elseif #berths > 0 then
			Slab.Text("Select tool: click a berth to edit or move it", { Color = { 0.6, 0.6, 0.6 } })
		else
			Slab.Text("Use the Berths tool to place some", { Color = { 0.6, 0.6, 0.6 } })
		end
		Slab.Separator()
		local T = require("src.tuning")
		local bay = d.hangar or {}
		Slab.Button("?", { W = 18, H = 18, Tooltip = ("Interior bay: the hangar grid docked ships park in, in cells of %d px.\nA ship takes its hull length x width in cells. Default %d x %d."):format(T.hangarCell, T.hangarW, T.hangarH) })
		Slab.SameLine()
		Slab.Text("Interior bay  w"); Slab.SameLine({ Pad = 4 })
		if Slab.InputNumberDrag("yard_hangarw", bay.w or T.hangarW, 1, 80, 1, { W = 60, Precision = 0 }) then
			E.pushUndoCoalesced("yard_hangarw")
			d.hangar = d.hangar or { w = T.hangarW, h = T.hangarH }
			d.hangar.w = math.floor(Slab.GetInputNumber())
		end
		Slab.SameLine()
		Slab.Text("h"); Slab.SameLine({ Pad = 4 })
		if Slab.InputNumberDrag("yard_hangarh", bay.h or T.hangarH, 1, 60, 1, { W = 60, Precision = 0 }) then
			E.pushUndoCoalesced("yard_hangarh")
			d.hangar = d.hangar or { w = T.hangarW, h = T.hangarH }
			d.hangar.h = math.floor(Slab.GetInputNumber())
		end
		Slab.Text(("= %d x %d px"):format((bay.w or T.hangarW) * T.hangarCell, (bay.h or T.hangarH) * T.hangarCell), { Color = { 0.6, 0.6, 0.6 } })
		return
	end
	if Slab.BeginTree("yard_wstats", { Label = (d.kind == "prop" and "Prop" or "Wreck") .. " stats" }) then
		for _, st in ipairs(WRECK_STATS) do
			local key, label, lo, hi, step, prec, help = unpack(st)
			Slab.Button("?", { W = 18, H = 18, Tooltip = help })
			Slab.SameLine()
			Slab.Text(label)
			Slab.SameLine({ Pad = 4 })
			local def = key == "armor" and 200 or key == "hold" and 20 or 100
			if Slab.InputNumberDrag("yard_w_" .. key, d.stats[key] or def, lo, hi, step, { W = 90, Precision = prec }) then
				E.pushUndoCoalesced("yard_w_" .. key)
				d.stats[key] = Slab.GetInputNumber()
			end
		end
		Slab.EndTree()
	end
	if d.kind ~= "container" and d.kind ~= "wreck" then return end
	d.loot = d.loot or {}
	-- a named loot table (data/loot_tables.lua), else the list below
	local tables = { { label = "(own list below)", value = false } }
	for _, id in ipairs(data.list.lootTables) do table.insert(tables, { label = id, value = id }) end
	Slab.Text("Loot table")
	Slab.SameLine()
	combo("yard_loottable", d.lootTable or "(own list below)", tables, function(id) E.pushUndo(); d.lootTable = id or nil end, 170)
	if Slab.Button("Roll preview", { Tooltip = "Roll this container's loot once, as it would spawn here" }) then
		local LT = require("src.loot_tables")
		local got = LT.fill({ lootTable = d.lootTable, loot = d.loot }, { area = E.game and E.game.fieldId })
		local parts = {}
		for id, n in pairs(got) do parts[#parts + 1] = ("%d %s"):format(n, data.items[id] and data.items[id].name or id) end
		table.sort(parts)
		E.lootPreview = #parts > 0 and table.concat(parts, ", ") or "nothing"
	end
	if E.lootPreview then Slab.Text(E.lootPreview, { Color = { 0.7, 0.8, 0.7 } }) end
	if not d.lootTable and Slab.BeginTree("yard_loot", { Label = ("Own loot list (%d)"):format(#d.loot) }) then
		Slab.Text("item, min, max, chance (0-1) per spawn", { Color = { 0.6, 0.6, 0.6 } })
		local items = {}
		for _, id in ipairs(data.list.items) do table.insert(items, { label = data.items[id].name, value = id }) end
		local remove
		for i, l in ipairs(d.loot) do
			Slab.PushID("yard_loot" .. i)
			local it = data.items[l[1]]
			combo("yard_lootitem" .. i, it and it.name or tostring(l[1]), items, function(id) E.pushUndo(); l[1] = id end, 130)
			Slab.SameLine()
			if Slab.InputNumberDrag("yard_lootmin" .. i, l[2] or 1, 0, 999, 1, { W = 34 }) then E.pushUndoCoalesced("lmin" .. i); l[2] = Slab.GetInputNumber() end
			Slab.SameLine()
			if Slab.InputNumberDrag("yard_lootmax" .. i, l[3] or l[2] or 1, 0, 999, 1, { W = 34 }) then E.pushUndoCoalesced("lmax" .. i); l[3] = Slab.GetInputNumber() end
			Slab.SameLine()
			if Slab.InputNumberDrag("yard_lootch" .. i, l[4] or 1, 0, 1, 0.05, { W = 40, Precision = 2 }) then E.pushUndoCoalesced("lch" .. i); l[4] = Slab.GetInputNumber() end
			Slab.SameLine()
			if Slab.Button("x", { W = 18, H = 18 }) then remove = i end
			Slab.PopID()
		end
		if remove then E.pushUndo(); table.remove(d.loot, remove) end
		if Slab.Button("Add loot") then
			E.pushUndo()
			table.insert(d.loot, { data.list.items[1], 1, 3, 1 })
		end
		Slab.EndTree()
	end
end

-- Left: the design ------------------------------------------------------

local fileBrowser

local GREY = { 0.6, 0.6, 0.6 }

-- Which category an exported id belongs to, from what's loaded (nil: not loaded yet).
local function categoryOf(id)
	if data.stations[id] and not data.hulls[id] then return "station" end
	if data.wrecks[id] and not data.hulls[id] then return "wreck" end
	if data.hulls[id] then return "hull" end
	if data.modules[id] then return "weapon" end
end

-- The Files section: new / save, then a browser of the export folder that
-- you move around in. Where you're browsing is where Save writes.
function fileBrowser(E, cat, builtIn)
	local d = E.design
	E.browseDir = E.browseDir or ""
	local dir = E.browseDir
	if dir ~= "" and not Export.isFolder(dir) then E.browseDir, dir = "", "" end

	Slab.Text("Files")
	if cat == "hull" then
		if Slab.Button("New hull", { Tooltip = "A ship you can fly" }) then E.newDesign("hull") end
	elseif cat == "wreck" then
		if Slab.Button("New container", { Tooltip = "An object that holds loot, filled from a loot table" }) then E.newDesign("container") end
		Slab.SameLine()
		if Slab.Button("New prop", { Tooltip = "Debris or scenery: like a container, no loot" }) then E.newDesign("prop") end
	elseif cat == "weapon" then
		if Slab.Button("New weapon", { Tooltip = "A gun or launcher module" }) then E.newDesign("weapon") end
	else
		if Slab.Button("New station", { Tooltip = "A station layout: needs one part marked as the docking module" }) then E.newDesign("station") end
	end
	Slab.SameLine()
	if Slab.Button("Save", { Tooltip = "Writes " .. d.id .. ".lua into the folder below.\nSaving over the same id replaces it; saving into another folder moves it." }) then
		E.pushUndo(); d.folder = dir; E.export()
	end
	Slab.Text("Saves to " .. Export.path(dir) .. "/" .. d.id .. ".lua", { Color = GREY })

	-- where you are, and the way up
	Slab.Text("Folder: " .. (dir == "" and "shipyard" or dir:match("^@") and dir:gsub("^@([^/]+)", "mod %1") or "shipyard/" .. dir))
	if dir ~= "" then
		Slab.SameLine()
		if Slab.Button("Up", { H = 18 }) then E.browseDir = dir:match("^(.*)/[^/]*$") or "" ; E.confirmDelete = nil end
	end
	if Slab.Button("New folder", { Tooltip = "Makes a folder here; type its name, then Enter or Make" }) then
		E.namingFolder = true; E.newFolderName = ""
	end
	Slab.SameLine()
	if Slab.Button("Refresh", { Tooltip = "Re-read the folders (it also does this every second)" }) then Export.refresh() end
	if E.namingFolder then
		Slab.Text("Name"); Slab.SameLine()
		local entered = Slab.Input("yard_newfolder", { Text = E.newFolderName or "", W = 140, ReturnOnText = false })
		if entered then E.newFolderName = Slab.GetInputText() end
		Slab.SameLine()
		local make = Slab.Button("Make", { H = 18 })
		Slab.SameLine()
		if Slab.Button("Cancel", { H = 18 }) then E.namingFolder = false end
		if (make or entered) and (E.newFolderName or "") ~= "" then
			local rel = E.makeFolder((dir == "" and "" or dir .. "/") .. E.newFolderName)
			if rel then E.browseDir = rel end
			E.namingFolder, E.newFolderName = false, ""
		end
	end

	-- this folder's contents: subfolders, then this tab's designs
	local shown = 0
	for _, e in ipairs(Export.list()) do
		local c = not e.dir and categoryOf(e.id)
		-- folders always; designs only on their own tab (not-yet-loaded files on every tab)
		if e.folder == dir and (e.dir or c == cat or not c) then
			shown = shown + 1
			local label
			if e.dir then label = "[" .. e.name .. "]"
			else
				local def = data.hulls[e.id] or data.wrecks[e.id] or data.stations[e.id] or data.modules[e.id]
				label = def and (def.name .. "  (" .. e.id .. ")") or (e.id .. "  (loads on restart)")
				-- two files with one id: the later-loaded one is the one in the game
				if def and def.source and def.source ~= e.path then label = label .. "  (duplicate id: " .. def.source:gsub("^mods/", ""):gsub("/data/", "/") .. " is the one in use)" end
				if e.id == d.id then label = "> " .. label end
			end
			if E.confirmDelete == e.rel then
				Slab.Text("Delete " .. e.name .. "?"); Slab.SameLine()
				if Slab.Button("Yes", { H = 18 }) then E.deleteSaved(e.rel) end
				Slab.SameLine()
				if Slab.Button("No", { H = 18 }) then E.confirmDelete = nil end
			else
				if e.mod then Slab.Text("   ") elseif Slab.Button("x", { W = 18, H = 18, Tooltip = e.dir and "Delete this folder (must be empty)" or "Delete this saved design" }) then E.confirmDelete = e.rel end
				Slab.SameLine()
				if Slab.TextSelectable(label) then
					if e.dir then E.browseDir = e.rel; E.confirmDelete = nil
					elseif c then E.openHull(e.id) end
				end
			end
		end
	end
	if shown == 0 then Slab.Text(dir == "" and "Nothing saved yet." or "Empty folder.", { Color = GREY }) end

	-- the game's own designs, to start from
	combo("yard_open_" .. cat, "Open a built-in design...", builtIn, function(id) E.openHull(id) end, 280)
end

-- The Weapons tab: the module's stats, then the art tools.
local function restackControls(E, id)
	local sel = E.selectedParts()
	local n = #E.design.parts
	if #sel == 0 then
		Slab.Text("Select a part to change its layer", { Color = { 0.6, 0.6, 0.6 } })
		return
	end
	local function btn(label, how, tip)
		if Slab.Button(label, { W = 64, H = 20, Tooltip = tip }) then E.restack(how) end
	end
	btn("To back", "back", "Draw first, under everything (Shift+[)")
	Slab.SameLine()
	btn("Back", "backward", "One step further back ([)")
	Slab.SameLine()
	btn("Forward", "forward", "One step further forward (])")
	Slab.SameLine()
	btn("To front", "front", "Draw last, over everything (Shift+])")
	Slab.Text(#sel > 1 and ("%d parts, layer"):format(#sel) or "layer"); Slab.SameLine()
	if Slab.InputNumberDrag(id, sel[1], 1, n, 1, { W = 60, Precision = 0, Tooltip = "Position in the list: 1 is the back, " .. n .. " the front" }) then
		E.restack(math.floor(Slab.GetInputNumber() + 0.5))
	end
	Slab.SameLine()
	Slab.Text(("of %d"):format(n), { Color = { 0.6, 0.6, 0.6 } })
end

local function weaponSections(E, d)
	local m = d.module
	m.weapon = m.weapon or { kind = "cannon" }
	local w = m.weapon
	local function num(id, label, value, lo, hi, step, prec, tip, set)
		Slab.Text(label); Slab.SameLine({ Pad = 4 })
		if Slab.InputNumberDrag(id, value or lo, lo, hi, step, { W = 90, Precision = prec }) then
			E.pushUndoCoalesced(id); set(Slab.GetInputNumber())
		end
		if tip then Slab.SameLine(); Slab.Button("?", { W = 18, H = 18, Tooltip = tip }) end
	end
	Slab.Text("maker"); Slab.SameLine()
	textField(E, "yard_wmaker", m.maker, function(t) m.maker = t ~= "" and t or nil end, 200)
	Slab.Text("kind"); Slab.SameLine()
	local kopts = {}
	for _, k in ipairs(WKINDS) do table.insert(kopts, { label = k, value = k }) end
	combo("yard_wkind", w.kind, kopts, function(k)
		E.pushUndo(); w.kind = k
		if k ~= "laser" then w.beam = nil end
		m.family = BAY_KINDS[k] and "bay" or "weapon"
	end, 120)
	Slab.Text("size"); Slab.SameLine()
	local sopts = {}
	for _, z in ipairs(SIZES) do table.insert(sopts, { label = z, value = z }) end
	combo("yard_wsize", m.size, sopts, function(z) E.pushUndo(); m.size = z end, 60)
	if w.kind == "cannon" then
		Slab.SameLine(); Slab.Text("caliber"); Slab.SameLine()
		local copts = { { label = "same as size", value = false } }
		for _, z in ipairs(SIZES) do table.insert(copts, { label = z, value = z }) end
		combo("yard_wcal", w.caliber or "same as size", copts, function(z) E.pushUndo(); w.caliber = z or nil end, 80)
	end
	-- which ammo families it chambers, in the order ticked (first = default)
	local FAMS = { cannon = { "gun", "artillery" }, missile = { "missile", "torpedo" } }
	if FAMS[w.kind] then
		local list = {}
		for _, f in ipairs(data.chambers(w)) do table.insert(list, f) end
		Slab.Text("chambers")
		for _, f in ipairs(FAMS[w.kind]) do
			local at
			for i, g in ipairs(list) do if g == f then at = i end end
			Slab.SameLine()
			check(E, at ~= nil, f, function(on)
				if on then table.insert(list, f) elseif #list > 1 then table.remove(list, at) end
				w.chambers = list
			end)
		end
	end
	Slab.Text(("Fits %s %s slots"):format(m.size, m.family == "bay" and "bay" or "hardpoint"), { Color = GREY })
	Slab.Separator()
	Slab.Text("Module")
	num("yard_wmass", "mass (t)", m.mass, 0.1, 500, 0.5, 1, nil, function(v) m.mass = v end)
	num("yard_wpow", "power draw", m.powerDraw or 0, 0, 100, 0.5, 1, "Reactor output it needs just to be fitted.", function(v) m.powerDraw = v end)
	num("yard_wprice", "price", m.price or 0, 0, 1000000, 100, 0, nil, function(v) m.price = v end)
	Slab.Separator()
	Slab.Text("Weapon")
	if w.kind == "laser" then
		check(E, w.beam == true, "Beam (held, per second) instead of pulse (per shot)", function(on) w.beam = on or nil end)
	end
	for _, key in ipairs(WFIELDS[(w.kind == "laser" and w.beam) and "beam" or w.kind] or {}) do
		local f = WSTAT[key]
		if key == "fireRate" and E.rpm then
			num("yard_w_rpm", "fire rate (rpm)", (w.fireRate or 0) * 60, 1, 1800, 1, 0, nil, function(v) w.fireRate = v / 60 end)
			Slab.SameLine()
			if Slab.Button("rpm", { W = 36, H = 18, Tooltip = "Showing rounds per minute: click for shots per second" }) then E.rpm = false end
		elseif key == "fireRate" then
			num("yard_w_" .. key, f[1], w[key], f[2], f[3], f[4], f[5], f[6], function(v) w[key] = v end)
			Slab.SameLine()
			if Slab.Button("/s", { W = 36, H = 18, Tooltip = "Showing shots per second: click for rounds per minute" }) then E.rpm = true end
		else
		num("yard_w_" .. key, f[1], w[key], f[2], f[3], f[4], f[5], f[6], function(v)
			if f[5] == 0 then v = math.floor(v + 0.5) end
			w[key] = v
		end)
		end
	end
	-- laser color, 0..1 per channel
	if w.kind == "laser" then
		check(E, w.beamRandom == true, "Random spread (scatter beams across the spread, across a fan)", function(on) w.beamRandom = on or nil end)
		local c = w.color or require("src.weapons").LASER_COLOR
		for ch, label in ipairs({ "red", "green", "blue" }) do
			num("yard_wcol" .. ch, "beam " .. label, c[ch], 0, 1, 0.02, 2, "Beam color (0..1).", function(v)
				local nc = { c[1], c[2], c[3] }
				nc[ch] = v
				w.color = nc
			end)
		end
	end
	Slab.Text("description")
	if Slab.Input("yard_wdesc", { Text = m.description or "", W = 260, H = 60, MultiLine = true, MultiLineW = 250, ReturnOnText = true }) then
		E.pushUndoCoalesced("yard_wdesc")
		local t = Slab.GetInputText()
		m.description = t ~= "" and t or nil
	end
	if Slab.Button("Test fire", { Tooltip = "Fits it to every matching slot on your ship and puts you in flight" }) then E.testFly() end
	Slab.SameLine()
	if Slab.Button("Copy source") then E.copySource() end
	if Slab.Button("Undo") then E.undoStep() end
	Slab.SameLine()
	if Slab.Button("Redo") then E.redoStep() end

	Slab.Separator()
	Slab.Text("Art (optional; none = plain barrels)")
	Slab.Text("+x is the line of fire, 0,0 the pivot.", { Color = GREY })
	Slab.Text("Tick Barrel on a part to make it recoil.", { Color = GREY })
	local tools = { { "select", "Select (V)" }, { "draw", "Polygon (P)" }, { "rect", "Primitive (B)" }, { "muzzle", "Muzzle points" } }
	local current = 1
	for i, t in ipairs(tools) do if E.tool == t[1] then current = i end end
	if E.tool == "light" then E.tool = "select" end
	for i, t in ipairs(tools) do
		if Slab.RadioButton(t[2], { Index = i, SelectedIndex = current }) then
			E.tool = t[1]
			if t[1] ~= "draw" then E.drawing = nil end
		end
	end
	if E.tool == "muzzle" then
		Slab.Text("Click to add one, right click removes.", { Color = GREY })
		Slab.Text("Shots take turns between them.", { Color = GREY })
	end
	Slab.Text(("%d part%s, %d muzzle%s"):format(#d.parts, #d.parts == 1 and "" or "s", #(d.muzzles or {}), #(d.muzzles or {}) == 1 and "" or "s"), { Color = GREY })
	if Slab.CheckBox(E.snap, "Snap to grid (G, Alt places freely)") then E.snap = not E.snap end
	Slab.Text("grid"); Slab.SameLine()
	local gopts = {}
	for _, g in ipairs({ 0.5, 1, 2, 4 }) do table.insert(gopts, { label = tostring(g), value = g }) end
	combo("yard_wgrid", tostring(E.grid), gopts, function(g) E.grid = g end, 60)
	if Slab.Button("Centre view") then E.view.x, E.view.y = 0, 0 end
	Slab.Text("Parts (lower in the list draws on top)", { Color = GREY })
	restackControls(E, "yard_wlayer")
	for i, p in ipairs(d.parts) do
		Slab.Text(("%2d"):format(i), { Color = { 0.5, 0.5, 0.5 } })
		Slab.SameLine()
		local tags = (p.barrel and "  (barrel)" or "") .. ((p.layer and p.layer ~= "hull") and ("  [" .. p.layer .. "]") or "")
		if Slab.TextSelectable(((E.sel == i) and "> " or "  ") .. (p.name or ("part " .. i)) .. tags) then E.sel, E.vsel, E.multi = i, nil, {} end
	end
end

local function designWindow(E, Editor)
	local h = love.graphics.getHeight()
	Slab.BeginWindow("yard_design", {
		Title = "Shipyard  (F2 closes)", X = 10, Y = 10, W = 310, H = h - 20,
		AutoSizeWindow = false, AllowResize = true,
	})
	local d = E.design

	local opts = {}
	for _, id in ipairs(data.list.hulls) do
		table.insert(opts, { label = data.hulls[id].name .. "  (" .. id .. ")", value = id })
	end
	-- one tab per category, each with its own design, list and new buttons
	local cat = E.category()
	for i, t in ipairs(CATEGORIES) do
		if i > 1 then Slab.SameLine() end
		local on = cat == t[1]
		if Slab.Button(on and ("[" .. t[2] .. "]") or t[2], { W = 72, Tooltip = t[3] }) and not on then E.switchCategory(t[1]) end
	end
	Slab.Separator()
	local openOpts = {}
	if cat == "hull" then
		openOpts = opts
	elseif cat == "weapon" then
		for _, id in ipairs(data.list.modules) do
			local m = data.modules[id]
			if m.weapon then table.insert(openOpts, { label = ("%s  (%s %s, %s)"):format(m.name, m.size, m.weapon.kind, id), value = id }) end
		end
	elseif cat == "wreck" then
		for _, id in ipairs(data.list.wrecks) do
			local w = data.wrecks[id]
			table.insert(openOpts, { label = ("%s  (%s, %s)"):format(w.name, w.kind, id), value = id })
		end
	else
		for _, id in ipairs(data.list.stations) do
			table.insert(openOpts, { label = ("%s  (%s)"):format(data.stations[id].name, id), value = id })
		end
	end
	fileBrowser(E, cat, openOpts)
	Slab.Separator()
	Slab.Text(("This design: a %s"):format(d.kind or "hull"))
	Slab.Text("id"); Slab.SameLine()
	textField(E, "yard_id", d.id, function(t) d.id = t:gsub("[^%w_]", "_") end, 220)
	Slab.Text("name"); Slab.SameLine()
	textField(E, "yard_name", d.name, function(t) d.name = t end, 220)
	d.stats = d.stats or {}
	if cat == "weapon" then weaponSections(E, d) Slab.EndWindow() return end
	if (d.kind or "hull") == "hull" then
		Slab.Text("class"); Slab.SameLine()
		textField(E, "yard_class", E.stat("class"), function(t) d.stats.class = t end, 150)
		Slab.SameLine()
		Slab.Button("?", { W = 18, H = 18, Tooltip = "Just a label, shown in the hangar as 'maker, class'." })
		Slab.Text("maker"); Slab.SameLine()
		textField(E, "yard_maker", E.stat("maker"), function(t) d.stats.maker = t end, 150)
		local Paint = require("src.paint")
		local pool = E.stat("paints") or {}
		Slab.Text("paint jobs: " .. (#pool > 0 and table.concat(pool, ", ") or Paint.DEFAULT .. " (none ticked)"), { Color = { 0.75, 0.75, 0.75 } })
		if Slab.Button(E.showPaints and "Close paint jobs" or "Paint jobs...") then E.showPaints = not E.showPaints end
	end
	Slab.Text("description")
	if Slab.Input("yard_desc", { Text = ((d.kind or "hull") == "hull" and E.stat("description") or d.stats.description) or "", W = 260, H = 70, MultiLine = true, MultiLineW = 250, ReturnOnText = true }) then
		E.pushUndoCoalesced("yard_desc")
		local t = Slab.GetInputText()
		d.stats.description = t ~= "" and t or nil
	end
	if Slab.Button(E.isPlaced() and "Spawn ahead of me" or "Test fly") then E.testFly() end
	Slab.SameLine()
	if Slab.Button("Copy source", { Tooltip = "Copies the data file text to the clipboard" }) then E.copySource() end
	if Slab.Button("Undo") then E.undoStep() end
	Slab.SameLine()
	if Slab.Button("Redo") then E.redoStep() end
	if not E.isPlaced() and Slab.Button("Compare ships") then
		local comparison=require("src.editor.comparison")
		comparison.open=not comparison.open
		if not comparison.open then comparison.clear() end
	end

	Slab.Separator()
	Slab.Text("Tool")
	local tools = { { "select", "Select (V)" }, { "draw", "Polygon (P)" }, { "rect", "Primitive (B)" }, { "light", "Lights (L)" } }
	if E.design.kind == "station" then
		table.insert(tools, { "berth", "Berths" })
		table.insert(tools, { "turret", "Turrets" })
		table.insert(tools, { "pivot", "Rotor pivots" })
	end
	local current = 1
	for i, t in ipairs(tools) do if E.tool == t[1] then current = i end end
	for i, t in ipairs(tools) do
		if Slab.RadioButton(t[2], { Index = i, SelectedIndex = current }) then
			E.tool = t[1]
			if t[1] ~= "draw" then E.drawing = nil end
		end
	end
	if E.tool == "light" then
		-- one set of light settings: clicks, dragged rows and Fill all use it
		local ship = E.design.kind ~= "station"
		local names = { window = "window", nav = "nav (red/green)", strobe = "strobe (white flash)" }
		local kopts = {}
		for _, k in ipairs({ "window", "nav", "strobe" }) do table.insert(kopts, { label = names[k], value = k }) end
		Slab.Text("Light"); Slab.SameLine()
		combo("yard_lightkind", names[E.lightKind], kopts, function(k) E.lightKind = k end, 160)
		local copts = {}
		for _, k in ipairs({ "auto", "mixed", "warm", "cool", "amber", "white" }) do table.insert(copts, { label = k, value = k }) end
		Slab.Text("colours"); Slab.SameLine()
		combo("yard_wpalette", E.windowPalette or "auto", copts, function(v) E.windowPalette = v end, 120)
		if E.lightKind == "window" then
			local pw, ph = Canvas.paneSize(E)
			Slab.Text("pane width / height (px)")
			if Slab.InputNumberDrag("yard_panew", pw, 0.5, 400, 0.5, { W = 70 }) then E.paneW = Slab.GetInputNumber() end
			Slab.SameLine()
			if Slab.InputNumberDrag("yard_paneh", ph, 0.5, 400, 0.5, { W = 70 }) then E.paneH = Slab.GetInputNumber() end
		else
			Slab.Text("size (px)"); Slab.SameLine()
			if Slab.InputNumberDrag("yard_lsizenew", E.lightSize or (E.lightKind == "nav" and 3 or 1.2), 0.5, 24, 0.5, { W = 70 }) then E.lightSize = Slab.GetInputNumber() end
		end
		Slab.Separator()
		Slab.Text("Place", { Color = { 0.8, 0.85, 1 } })
		Slab.Text("Click a part for one light, drag for a row", { Color = { 0.6, 0.6, 0.6 } })
		Slab.Text("Right drag erases; Select (V) edits one", { Color = { 0.6, 0.6, 0.6 } })
		Slab.Text(E.lightKind == "window" and "gap between panes (px)" or "row spacing (px)"); Slab.SameLine()
		if Slab.InputNumberDrag("yard_lightspacing", E.lightSpacing, 2, 200, 1, { W = 70 }) then E.lightSpacing = Slab.GetInputNumber() end
		Slab.Separator()
		Slab.Text("Fill a whole part (windows)", { Color = { 0.8, 0.85, 1 } })
		local p = E.sel and E.design.parts[E.sel]
		Slab.Text(p and ("on: " .. (p.name or ("part " .. E.sel))) or "Select a part first (V)", { Color = { 0.6, 0.6, 0.6 } })
		local popts = {}
		for _, k in ipairs(WINDOW_PATTERNS) do table.insert(popts, { label = k, value = k }) end
		Slab.Text("pattern"); Slab.SameLine()
		combo("yard_wpattern", E.windowPattern or "rooms", popts, function(v) E.windowPattern = v end, 120)
		Slab.Text("across / down (px)")
		if Slab.InputNumberDrag("yard_wsx", E.windowSpacing or (ship and 6 or 40), 2, 200, 1, { W = 70 }) then E.windowSpacing = Slab.GetInputNumber() end
		Slab.SameLine()
		if Slab.InputNumberDrag("yard_wsy", E.windowRowSpacing or (ship and 6 or 48), 2, 200, 1, { W = 70 }) then E.windowRowSpacing = Slab.GetInputNumber() end
		Slab.Text("lit share"); Slab.SameLine()
		if Slab.InputNumberDrag("yard_wden", E.windowDensity or 0.6, 0.05, 1, 0.01, { W = 70 }) then E.windowDensity = Slab.GetInputNumber() end
		if p and Slab.Button("Fill (replaces its lights; again to reroll)") then E.pushUndo(); fillWindows(E, p) end
	end
	if E.tool == "rect" then
		Slab.Text("Drag a box; shift makes an ellipse a circle", { Color = { 0.6, 0.6, 0.6 } })
		local popts = { { label = "rectangle", value = "rect" }, { label = "ellipse / circle", value = "ellipse" }, { label = "chamfered box", value = "chamfer" } }
		local names = { rect = "rectangle", ellipse = "ellipse / circle", chamfer = "chamfered box" }
		combo("yard_prim", names[E.primitive or "rect"], popts, function(k) E.primitive = k end, 160)
		if E.primitive == "ellipse" then
			Slab.Text("sides")
			if Slab.InputNumberDrag("yard_primsides", E.primSides or 24, 6, 64, 1, { W = 90 }) then E.primSides = math.floor(Slab.GetInputNumber()) end
		elseif E.primitive == "chamfer" then
			Slab.Text("corner cut")
			if Slab.InputNumberDrag("yard_primcham", E.primChamfer or 16, 1, 256, 1, { W = 90 }) then E.primChamfer = Slab.GetInputNumber() end
		end
	end
	if E.tool == "select" then
		Slab.Text("Shift-click adds to the selection", { Color = { 0.6, 0.6, 0.6 } })
		Slab.Text("Drag on empty space to box select:")
		combo("yard_boxmode", E.boxMode or "parts", {
			{ label = "parts", value = "parts" }, { label = "lights", value = "lights" },
			{ label = "points of the selected part", value = "points" },
		}, function(v) E.boxMode = v end)
	end
	if E.tool == "turret" then
		Slab.Text("Click to place a turret; right click removes", { Color = { 0.6, 0.6, 0.6 } })
		Slab.Text("Select tool (V) picks one to move or change", { Color = { 0.6, 0.6, 0.6 } })
		Slab.Text("weapon for new turrets")
		turretCombo("yard_turretnew", E.turretModule, function(id) E.turretModule = id end)
	end
	if E.tool == "pivot" then
		Slab.Text("Click to set the pivot of the rotor", { Color = { 0.6, 0.6, 0.6 } })
		Slab.Text("picked in the Rotors window", { Color = { 0.6, 0.6, 0.6 } })
	end
	if E.tool == "berth" then
		Slab.Text("Click to place a berth; drag to aim its nose", { Color = { 0.6, 0.6, 0.6 } })
		Slab.Text("(no drag: it faces out from the centre)", { Color = { 0.6, 0.6, 0.6 } })
		Slab.Text("Right click a berth to remove it", { Color = { 0.6, 0.6, 0.6 } })
		Slab.Text("size for new berths")
		if Slab.InputNumberDrag("yard_berthsize", E.berthSize, 20, 400, 2, { W = 90 }) then E.berthSize = Slab.GetInputNumber() end
	end
	if Slab.CheckBox(E.mirrorNew, "Mirror new parts (default for the M box)") then E.mirrorNew = not E.mirrorNew end
	if Slab.CheckBox(E.snap, "Snap to grid (G, Alt places freely)") then E.snap = not E.snap end
	local gopts = {}
	for _, g in ipairs(GRIDS) do table.insert(gopts, { label = g .. " px", value = g }) end
	combo("yard_grid", E.grid .. " px", gopts, function(g) E.grid = g end, 120)

	Slab.Separator()
	if Slab.BeginTree("yard_previewtree", { Label = "Preview" }) then
	Slab.Text("How the canvas shows the design")
	Slab.Text("view"); Slab.SameLine()
	local popts = {}
	for _, k in ipairs({ "normal", "wreck", "collision", "break" }) do table.insert(popts, { label = PREVIEWS[k], value = k }) end
	combo("yard_preview", PREVIEWS[E.preview], popts, function(k) E.preview = k end, 140)
	local paints, current = {}, "(custom)"
	for _, pt in ipairs(Editor.PAINTS) do
		table.insert(paints, { label = pt.name, value = pt.color })
		if pt.color == E.paint then current = pt.name end
	end
	if (d.kind or "hull") ~= "hull" then
		Slab.Text("paint"); Slab.SameLine()
		combo("yard_paint", current, paints, function(c) E.paint = c end, 140)
	end
	Slab.Text("Pretend damage (windows go out)")
	if Slab.InputNumberSlider("yard_pdamage", E.previewDamage, 0, 1, { W = 160, Precision = 2 }) then E.previewDamage = Slab.GetInputNumber() end
	Slab.SameLine()
	if Slab.Button("Hit") then E.previewFlash = 0.35 end
	if Slab.Button("Centre view") then E.view.x, E.view.y = 0, 0 end
	Slab.EndTree()
	end

	Slab.Separator()
	if not E.isPlaced() then
	if Slab.BeginTree("yard_stats", { Label = "Hull stats" }) then
		local base = data.hulls[d.base]
		Slab.Text("Unchanged stats come from")
		combo("yard_base", base and base.name or "?", opts, function(id) E.pushUndo(); E.setBase(id) end, 200)
		Slab.Text("Picking one resets stats and slots, keeps the shape.", { Color = { 0.6, 0.6, 0.6 } })
		for _, st in ipairs(STATS) do
			local key, label, help = st[1], st[2], st[3]
			Slab.Button("?", { W = 18, H = 18, Tooltip = help })
			Slab.SameLine()
			local own = d.stats[key]
			local v = E.stat(key)
			Slab.Text(label .. (own ~= nil and " *" or ""))
			Slab.SameLine({ Pad = 4 })
			-- drag sideways or type; each stat has a sensible range and step
			local lo, hi, step, prec = st[4], st[5], st[6], st[7]
			if Slab.InputNumberDrag("yard_stat_" .. key, v or lo, lo, hi, step, { W = 90, Precision = prec }) then
				E.pushUndo()
				d.stats[key] = Slab.GetInputNumber()
			end
			if own ~= nil then
				Slab.SameLine()
				if Slab.Button("x", { W = 18, H = 18, Tooltip = "Back to the base hull's value" }) then E.pushUndo(); d.stats[key] = nil end
			end
		end
		local mopts = {}
		for _, m in ipairs({ "fixed", "gimbal", "turret" }) do table.insert(mopts, { label = m, value = m }) end
		Slab.Button("?", { W = 18, H = 18, Tooltip = "fixed: guns point down the nose, you aim with the ship.\ngimbal: guns swing a few degrees toward the cursor.\nturret: guns rotate all the way round at the turret speed.\nThis is the default; each weapon slot can set its own in the Slots list." })
		Slab.SameLine()
		Slab.Text("default mount"); Slab.SameLine()
		combo("yard_mount", E.stat("mount") or "gimbal", mopts, function(m) E.pushUndo(); d.stats.mount = m end, 120)
		local hopts = { { label = "strafe", value = "strafe" }, { label = "turn", value = "turn" } }
		Slab.Button("?", { W = 18, H = 18, Tooltip = "strafe: A/D slide sideways on the side thrusters.\nturn: A/D rotate the hull and the mouse only aims the guns (battleships).\nTurn-helm hulls also keep their boost on trade lanes." })
		Slab.SameLine()
		Slab.Text("helm"); Slab.SameLine()
		combo("yard_helm", E.stat("helm") or "strafe", hopts, function(m) E.pushUndo(); d.stats.helm = m end, 120)
		Slab.EndTree()
	end
	if Slab.BeginTree("yard_slots", { Label = ("Slots (%d), drag markers on the canvas"):format(#d.slots) }) then
		local remove
		local defaults = E.ensureLoadout()
		for i, slot in ipairs(d.slots) do
			Slab.PushID("yard_slot" .. i)
			local selected = E.slotSel == i
			local c = Canvas.SLOT_COLORS[slot.family]
			if Slab.TextSelectable(("%s%d."):format(selected and ">" or " ", i), { IsSelectableTextOnly = true, Color = c }) then E.slotSel = i end
			Slab.SameLine()
			local fopts = {}
			for _, f in ipairs(FAMILIES) do table.insert(fopts, { label = f, value = f }) end
			combo("yard_slotfam" .. i, slot.family, fopts, function(f)
				E.pushUndo()
				slot.family = f
				if SIZELESS[f] then slot.size = "any" elseif slot.size == "any" then slot.size = "S" end
				if f ~= "hardpoint" and f ~= "bay" then slot.mount, slot.trigger = nil, nil end
				E.validateSlotDefault(i)
				E.sortSlots()
			end, 95)
			if not SIZELESS[slot.family] then
				Slab.SameLine()
				local sopts = {}
				for _, s in ipairs(SIZES) do table.insert(sopts, { label = s, value = s }) end
				combo("yard_slotsize" .. i, slot.size, sopts, function(s) E.pushUndo(); slot.size = s; E.validateSlotDefault(i) end, 50)
			end
			if slot.family == "hardpoint" or slot.family == "bay" then
				-- weapon slots can mount differently from the hull's default
				Slab.SameLine()
				local mo = { { label = "(hull)", value = false } }
				for _, m in ipairs({ "fixed", "gimbal", "turret" }) do table.insert(mo, { label = m, value = m }) end
				combo("yard_slotmount" .. i, slot.mount or "(hull)", mo, function(m) E.pushUndo(); slot.mount = m or nil end, 70)
				-- default trigger (the player can change it in the hold)
				Slab.SameLine()
				local dflt = slot.family == "bay" and "tertiary" or "primary"
				local TAG = { primary = "PRI", secondary = "SEC", tertiary = "TER" }
				local to = { { label = "PRI", value = "primary" }, { label = "SEC", value = "secondary" }, { label = "TER", value = "tertiary" } }
				combo("yard_slottrig" .. i, TAG[slot.trigger or dflt], to, function(t)
					E.pushUndo(); slot.trigger = (t ~= dflt) and t or nil
				end, 50)
				-- which way it faces, degrees off the nose (180 = out the back)
				Slab.SameLine()
				if Slab.InputNumberDrag("yard_slotface" .. i, slot.heading or 0, -180, 180, 5,
					{ W = 50, Precision = 0, Tooltip = "Facing: degrees off the nose (180 = backwards). Fixed mounts fire this way; gimbals swing around it." }) then
					E.pushUndoCoalesced("yard_slotface" .. i)
					local v = math.floor(Slab.GetInputNumber() + 0.5)
					slot.heading = v ~= 0 and v or nil
				end
			end
			-- weapon slots always sit on the hull; internal ones (engine
			-- exhausts and the like) can be placed or left off
			if slot.family ~= "hardpoint" and slot.family ~= "bay" then
				Slab.SameLine()
				if Slab.Button(slot.x and "on hull" or "place", { W = 58, H = 18, Tooltip = slot.x and "Click to take it off the hull" or "Put it on the hull at the origin" }) then
					E.pushUndo()
					if slot.x then slot.x, slot.y = nil, nil else slot.x, slot.y = 0, 0 end
				end
			elseif not slot.x then slot.x, slot.y = 0, 0 end
			Slab.SameLine()
			if Slab.Button("x", { W = 18, H = 18, Tooltip = "Remove this slot" }) then remove = i end
			Slab.Text("Default item"); Slab.SameLine()
			local items = { { label = "Empty", value = false } }
			for _, id in ipairs(data.list.modules) do
				local m = data.modules[id]
				if data.fits(slot, m) then table.insert(items, { label = m.name, value = id }) end
			end
			local current = defaults[i] and data.modules[defaults[i]]
			combo("yard_slotdefault" .. i, current and current.name or "Empty", items, function(id)
				E.pushUndo(); E.ensureLoadout()[i] = id
			end, 230)
			Slab.PopID()
		end
		if remove then E.pushUndo(); table.remove(d.slots, remove); table.remove(defaults, remove); E.slotSel = nil end
		if Slab.Button("Add slot") then
			E.pushUndo()
			table.insert(d.slots, { family = "hardpoint", size = "S", x = 0, y = 0 })
			defaults[#d.slots] = false
			E.slotSel = #d.slots
			E.sortSlots()
		end
		Slab.Text("Modules that no longer fit a slot are", { Color = { 0.6, 0.6, 0.6 } })
		Slab.Text("left empty when you test fly.", { Color = { 0.6, 0.6, 0.6 } })
		Slab.EndTree()
	end
	else
		placedSections(E, d)
	end

	Slab.Separator()
	-- the wreck's numbers: share of the area, and which part is the core
	local total, biggest, tagged = 0, nil, nil
	local function areaOf(p) return Canvas.area(p.shape) * (p.mirror and 2 or 1) end
	for i, p in ipairs(d.parts) do
		if not p.hidden then
			total = total + areaOf(p)
			if p.core then tagged = tagged or i end
			if p.collide ~= false and (not biggest or Canvas.area(p.shape) > Canvas.area(d.parts[biggest].shape)) then biggest = i end
		end
	end
	E.coreIndex = tagged or biggest
	E.totalArea = total
	Slab.Text(("Parts (%d), drawn top to bottom"):format(#d.parts))
	Slab.Text("click a name to select it, shift-click for more", { Color = { 0.6, 0.6, 0.6 } })
	restackControls(E, "yard_layer")
	for i, p in ipairs(d.parts) do
		Slab.PushID("yard_part" .. i)
		local selected = E.sel == i or (E.multi and E.multi[i]) or false
		-- one row per part: layer number, visibility and lock as small toggles,
		-- then the name, highlighted when selected
		Slab.Text(("%2d"):format(i), { Color = { 0.5, 0.5, 0.5 } })
		Slab.SameLine()
		if Slab.Button(p.hidden and "-" or "o", { W = 18, H = 18, Tooltip = p.hidden and "Hidden: click to show" or "Visible: click to hide" }) then
			p.hidden = not p.hidden or nil
		end
		Slab.SameLine()
		if Slab.Button(p.locked and "L" or " ", { W = 18, H = 18, Tooltip = p.locked and "Locked: click to unlock" or "Click to lock (can't be picked on the canvas)" }) then
			p.locked = not p.locked or nil
		end
		Slab.SameLine()
		local tags = (p.mirror and " [mirror]" or "") .. (i == E.coreIndex and " [core]" or "") .. (E.errors[i] and " [!]" or "")
		local label = (selected and "> " or "  ") .. (p.name or ("part " .. i)) .. tags
		local color = E.errors[i] and { 1, 0.45, 0.45 } or selected and { 1, 0.85, 0.3 } or (p.hidden and { 0.5, 0.5, 0.5 } or nil)
		if Slab.TextSelectable(label, { IsSelectableTextOnly = true, IsSelected = selected, Color = color }) then
			if love.keyboard.isDown("lshift", "rshift") and E.sel and E.sel ~= i then
				E.multi = E.multi or {}
				E.multi[i] = (not E.multi[i]) or nil
			else
				E.sel, E.vsel, E.lsel, E.multi = i, nil, nil, {}
			end
		end
		Slab.PopID()
	end
	Slab.EndWindow()
end

-- Floating: a hull's pool of factory paint jobs ---------------------------
local function paintWindow(E)
	local d = E.design
	if (d.kind or "hull") ~= "hull" or not E.showPaints then return end
	local Paint = require("src.paint")
	local pool = E.stat("paints") or {}
	local on = {}
	for _, n in ipairs(pool) do on[n] = true end
	Slab.BeginWindow("yard_paintwin", { Title = "Factory paint jobs", X = 340, Y = 10, W = 290, H = math.min(love.graphics.getHeight() - 20, 110 + #Paint.PRESETS * 20),
		AutoSizeWindow = false, AllowResize = true, IsOpen = true })
	Slab.Text("Each hull leaves the yard in one of the", { Color = { 0.6, 0.6, 0.6 } })
	Slab.Text("ticked jobs, at random. None: " .. Paint.DEFAULT, { Color = { 0.6, 0.6, 0.6 } })
	Slab.Text("Canvas shows the first ticked.", { Color = { 0.6, 0.6, 0.6 } })
	Slab.Separator()
	for _, pt in ipairs(Paint.PRESETS) do
		local c, s2 = pt.color, Paint.shadeOf(pt.color)
		Slab.Rectangle({ W = 22, H = 18, Color = { c[1], c[2], c[3], 1 } })
		Slab.SameLine({ Pad = 0 })
		Slab.Rectangle({ W = 10, H = 18, Color = { s2[1], s2[2], s2[3], 1 } })
		Slab.SameLine()
		if Slab.CheckBox(on[pt.name] == true, pt.name, { Id = "yard_pj_" .. pt.name }) then
			E.pushUndo()
			local out = {}
			for _, q in ipairs(Paint.PRESETS) do
				local want = on[q.name]
				if q.name == pt.name then want = not want end
				if want then out[#out + 1] = q.name end
			end
			d.stats.paints = #out > 0 and out or nil
		end
	end
	if Slab.Button("Done") then E.showPaints = false end
	Slab.EndWindow()
end

-- Floating: the station's rotors -------------------------------------------
-- Everything about rotors in one place: which rotor the selected part
-- turns with, each rotor's pivot and spin, and picking pivots on the canvas.
local function rotorWindow(E)
	local d = E.design
	if d.kind ~= "station" then return end
	-- shown when the station has rotors, unless hidden; the checkbox in
	-- the station section turns it on for one without
	local show = E.showRotors
	if show == nil then show = d.rotors ~= nil end
	if not show then return end
	local h = love.graphics.getHeight()
	Slab.BeginWindow("yard_rotorwin", { Title = "Rotors", X = 340, Y = h - 330, W = 300, H = 300, AutoSizeWindow = false, AllowResize = true })
	local p = E.sel and d.parts[E.sel]
	if p then
		Slab.Text("Selected part: " .. (p.name or ("part " .. E.sel)), { Color = { 0.8, 0.85, 1 } })
		if p.dock then
			Slab.Text("Docks stay on the still core", { Color = { 0.6, 0.6, 0.6 } })
		else
			if not p.dock then
				local ropts = { { label = "none (still core)", value = false } }
				local names = {}
				for name in pairs(E.design.rotors or {}) do table.insert(names, name) end
				table.sort(names)
				for _, name in ipairs(names) do table.insert(ropts, { label = name, value = name }) end
				table.insert(ropts, { label = "+ new rotor here", value = true })
				Slab.Text("Rotor")
				Slab.SameLine()
				combo("yard_rotor" .. E.sel, p.rotor or "none (still core)", ropts, function(v)
					E.pushUndo()
					if v == true then
						-- a new rotor pivoting on this part's centre
						E.design.rotors = E.design.rotors or {}
						local n = 1
						while E.design.rotors["rotor" .. n] do n = n + 1 end
						local sx, sy, k = 0, 0, 0
						for j = 1, #p.shape, 2 do sx, sy, k = sx + p.shape[j], sy + p.shape[j + 1], k + 1 end
						E.design.rotors["rotor" .. n] = { x = math.floor(sx / k + 0.5), y = math.floor(sy / k + 0.5), spin = 0.5 }
						p.rotor = "rotor" .. n
						E.rotorSel = p.rotor
					else
						p.rotor = v or nil
					end
				end, 160)
			end

		end
	else
		Slab.Text("Select a part (V) to put it on a rotor", { Color = { 0.6, 0.6, 0.6 } })
	end
	Slab.Separator()
	if not (E.rotorSel and d.rotors and d.rotors[E.rotorSel]) then E.rotorSel = d.rotors and next(d.rotors) or nil end
	if E.rotorSel then
		Slab.Text("Pivot tool sets: " .. E.rotorSel, { Color = { 0.6, 0.6, 0.6 } })
	end
	-- each rotor: a group of parts turning about a pivot, apart from the core
		local rnames = {}
		for name in pairs(d.rotors or {}) do table.insert(rnames, name) end
		table.sort(rnames)
		if #rnames == 0 then Slab.Text("No rotors yet: pick \"+ new rotor here\" above", { Color = { 0.6, 0.6, 0.6 } }) end
		for _, name in ipairs(rnames) do
			local r = d.rotors[name]
			local count = 0
			for _, p in ipairs(d.parts) do if p.rotor == name then count = count + 1 end end
			if Slab.BeginTree("yard_rotor_" .. name, { Label = ("%s (%d parts)"):format(name, count) }) then
			check(E, r.spin ~= nil, "Own spin (else the location's)", function(on) r.spin = on and 0.5 or nil end)
			if r.spin ~= nil then
				Slab.Text("Spin (radians a second)")
				slider(E, "yard_rspin" .. name, r.spin, -3, 3, function(v) r.spin = v end, 2)
			end
			Slab.Text(("Pivot %d, %d"):format(r.x or 0, r.y or 0))
			if Slab.Button("Place on canvas##" .. name) then E.tool, E.rotorSel, E.drawing = "pivot", name, nil end
			Slab.SameLine()
			if Slab.Button("Centre of its parts##" .. name) then
				-- the middle of the box round every part on this rotor
				local x1, y1, x2, y2 = math.huge, math.huge, -math.huge, -math.huge
				for _, p in ipairs(d.parts) do
					if p.rotor == name then
						for j = 1, #p.shape, 2 do
							x1, x2 = math.min(x1, p.shape[j]), math.max(x2, p.shape[j])
							y1, y2 = math.min(y1, p.shape[j + 1]), math.max(y2, p.shape[j + 1])
						end
					end
				end
				if x1 < math.huge then
					E.pushUndo()
					r.x, r.y = math.floor((x1 + x2) / 2 + 0.5), math.floor((y1 + y2) / 2 + 0.5)
				end
			end
			Slab.SameLine()
			if Slab.Button("Station centre##" .. name) then E.pushUndo(); r.x, r.y = 0, 0 end
			Slab.Text("Fine tune X / Y")
			slider(E, "yard_rx" .. name, r.x or 0, -20000, 20000, function(v) r.x = math.floor(v + 0.5) end, 0)
			slider(E, "yard_ry" .. name, r.y or 0, -20000, 20000, function(v) r.y = math.floor(v + 0.5) end, 0)
			check(E, r.over == true, "Draw over the core", function(on) r.over = on or nil end)
			if Slab.Button("Remove " .. name) then
				E.pushUndo()
				for _, p in ipairs(d.parts) do if p.rotor == name then p.rotor = nil end end
				d.rotors[name] = nil
				if not next(d.rotors) then d.rotors = nil end
			end
			Slab.EndTree()
			end
		end

	Slab.EndWindow()
end

-- Right: the selected part -------------------------------------------------

local function partWindow(E)
	local p = E.sel and E.design.parts[E.sel]
	if not p then return end
	local w, h = love.graphics.getWidth(), love.graphics.getHeight()
	Slab.BeginWindow("yard_part", {
		Title = "Part", X = w - 300, Y = 10, W = 290, H = h - 20,
		AutoSizeWindow = false, AllowResize = true,
	})
	local i = E.sel
	local light = E.lsel and p.lights and p.lights[E.lsel]
	if light then
		local group = Canvas.lightSelection(E)
		local LFIELDS = { "kind", "color", "size", "w", "h", "rate", "phase" }
		local function key(v) return type(v) == "table" and table.concat(v, ",") or tostring(v) end
		local before = {}
		for _, f in ipairs(LFIELDS) do before[f] = key(light[f]) end
		Slab.Text(("Light %d of %d on this part"):format(E.lsel, #p.lights))
		if #group > 1 then
			Slab.Text(("%d lights selected: edits apply to all"):format(#group), { Color = { 0.5, 0.9, 1 } })
		end
		local kopts = { { label = "nav", value = "nav" }, { label = "strobe", value = "strobe" } }
		table.insert(kopts, 1, { label = "window", value = "window" })
		combo("yard_lkind" .. i, light.kind or "window", kopts, function(k)
			E.pushUndo()
			light.kind = k
			if k == "strobe" then light.rate = light.rate or 1 end
		end, 120)
		local auto = light.color == nil
		check(E, auto, light.kind == "nav" and "Auto colour (red port, green starboard)" or "Auto colour", function(on)
			if on then light.color = nil else
				local c = HullShape.lightColor(light)
				light.color = { c[1], c[2], c[3] }
			end
		end)
		if light.color then
			for ci, name in ipairs({ "r", "g", "b" }) do
				Slab.Text(name); Slab.SameLine()
				slider(E, "yard_lc" .. name .. i, light.color[ci], 0, 1, function(v) light.color[ci] = v end)
			end
		end
		if light.kind == "window" and (light.w or light.h) then
			Slab.Text("pane width / height (px)")
			slider(E, "yard_lw" .. i, light.w or light.size or 1.2, 0.5, 400, function(v) light.w = v end, 1)
			slider(E, "yard_lh" .. i, light.h or light.size or 1.2, 0.5, 400, function(v) light.h = v end, 1)
		else
			Slab.Text("size (px)")
			slider(E, "yard_lsize" .. i, light.size or (light.kind == "nav" and 3 or 1.2), 0.5, 24, function(v) light.size = v end, 1)
			if light.kind == "window" and Slab.Button("Make it a pane") then
				E.pushUndo(); local s0 = (light.size or 1.2) * 1.2; light.w, light.h, light.size = s0, s0, nil
			end
		end
		if light.kind == "strobe" then
			Slab.Text("flashes per second")
			slider(E, "yard_lrate" .. i, light.rate or 1, 0.1, 4, function(v) light.rate = v end)
			Slab.Text("phase (offset between strobes)")
			slider(E, "yard_lphase" .. i, light.phase or 0, 0, 1, function(v) light.phase = v end)
		end
		if Slab.Button("Delete light") then E.deleteSelected() end
		Slab.SameLine()
		if Slab.Button("Back to the part") then E.lsel = nil end
		if Slab.Button("Remove all lights on this part") then E.pushUndo(); p.lights = nil; E.lsel = nil end
		for _, f in ipairs(LFIELDS) do
			if key(light[f]) ~= before[f] then
				for k = 2, #group do
					local v = light[f]
					if type(v) == "table" then v = { unpack(v) } end
					group[k][f] = v
				end
			end
		end
		Slab.Separator()
	end
	if E.errors[i] then Slab.Text("! " .. E.errors[i], { Color = { 1, 0.4, 0.4 } }) end
	local a = Canvas.area(p.shape) * (p.mirror and 2 or 1)
	Slab.Text(("%d points   area %d px2"):format(#p.shape / 2, a))
	if E.totalArea and E.totalArea > 0 then
		Slab.Text(("%.0f%% of the wreck%s"):format(a / E.totalArea * 100, i == E.coreIndex and ", the core" or ""))
	end

	Slab.Text("name"); Slab.SameLine()
	textField(E, "yard_pname" .. i, p.name, function(t) p.name = t end, 200)

	Slab.Separator()
	Slab.Text("Look")
	if E.design.kind == "weapon" then
		check(E, p.barrel == true, "Barrel (recoils when it fires)", function(on) p.barrel = on or nil end)
	end
	if ((E.design.kind or "hull") == "hull" or E.design.kind == "weapon") and not p.color then
		Slab.Text("paint"); Slab.SameLine()
		combo("yard_ppaint" .. i, p.paint or "metal", {
			{ label = "metal", value = "metal" }, { label = "primary", value = "primary" }, { label = "secondary", value = "secondary" },
		}, function(v)
			E.pushUndo()
			local v2 = v ~= "metal" and v or nil
			for _, k in ipairs(Canvas.selection(E)) do E.design.parts[k].paint = v2 end
		end, 120)
	end
	slider(E, "yard_shade" .. i, p.shade or 1, 0, 1.5, function(v) p.shade = v end)
	Slab.Text("Tint (added to the paint)")
	local tint = p.tint or { 0, 0, 0 }
	for c, name in ipairs({ "r", "g", "b" }) do
		Slab.Text(name); Slab.SameLine()
		slider(E, "yard_tint" .. name .. i, tint[c], -1, 1, function(v)
			local t = p.tint or { 0, 0, 0 }
			t[c] = v
			p.tint = (t[1] == 0 and t[2] == 0 and t[3] == 0) and nil or t
		end)
	end
	check(E, p.color ~= nil, "Fixed colour (ignores the paint)", function(on)
		local c = E.previewPaint(); p.color = on and { c[1], c[2], c[3] } or nil
	end)
	if p.color then
		for c, name in ipairs({ "r", "g", "b" }) do
			Slab.Text(name); Slab.SameLine()
			slider(E, "yard_col" .. name .. i, p.color[c], 0, 1, function(v) p.color[c] = v end)
		end
	end
	do
	Slab.Text("Layer")
	local lopts = {}
	for _, l in ipairs(LAYERS) do table.insert(lopts, { label = l, value = l }) end
	combo("yard_layer" .. i, p.layer or "hull", lopts, function(l) E.pushUndo(); p.layer = l ~= "hull" and l or nil end, 140)
	end

	if E.design.kind == "station" then
		Slab.Separator()
		if not p.dock and p.rotor then Slab.Text("Rotor: " .. p.rotor .. " (see the Rotors window)") end

		check(E, p.dock == true, "Docking module", function(on) p.dock = on or nil end)
		if p.dock then
			local ok,d=pcall(require("src.dock_geometry").build,p)
			if not ok then Slab.Text(tostring(d));d={a=0,x2=0,yc=0,hw=100,x1=-200,runway=600,capture=260,wall=24} end
			check(E,p.dockHeading==nil,"Auto direction from station center",function(on)
			 p.dockHeading=not on and math.deg(d.a) or nil
			end)
			if p.dockHeading~=nil then
			 Slab.Text("Entrance heading (degrees)")
			 slider(E,"yard_dheading"..i,p.dockHeading,-180,180,function(v)p.dockHeading=v end,1)
			end
			check(E,p.dockX~=nil,"Custom entrance position",function(on)
			 if on then p.dockX,p.dockY=require("src.dock_geometry").point(d,d.x2,0)
			 else p.dockX,p.dockY=nil,nil end
			end)
			if p.dockX~=nil then
			 Slab.Text("Entrance X / Y (station coordinates)")
			 slider(E,"yard_dx"..i,p.dockX,-20000,20000,function(v)p.dockX=v end,0)
			 slider(E,"yard_dy"..i,p.dockY,-20000,20000,function(v)p.dockY=v end,0)
			end
			check(E,p.dockWidth~=nil,"Custom opening width",function(on)p.dockWidth=on and d.hw*2 or nil end)
			if p.dockWidth then slider(E,"yard_dwidth"..i,p.dockWidth,20,5000,function(v)p.dockWidth=v end,0) end
			check(E,p.dockDepth~=nil,"Custom interior depth",function(on)p.dockDepth=on and d.x2-d.x1 or nil end)
			if p.dockDepth then slider(E,"yard_ddepth"..i,p.dockDepth,20,5000,function(v)p.dockDepth=v end,0) end
			check(E, p.dockBoth == true, "Tunnel (open at both ends)", function(on) p.dockBoth = on or nil end)
			Slab.Text("Runway length (px)")
			slider(E, "yard_drun" .. i, p.dockRunway or 600, 100, 5000, function(v) p.dockRunway = math.floor(v + 0.5) end, 0)
			check(E,p.dockCapture~=nil,"Custom tractor half-width",function(on)p.dockCapture=on and d.capture or nil end)
			if p.dockCapture then slider(E,"yard_dcapture"..i,p.dockCapture,20,5000,function(v)p.dockCapture=v end,0) end
			Slab.Text("Door frame thickness (px)")
			slider(E,"yard_dwall"..i,p.dockWall or 24,1,200,function(v)p.dockWall=v end,0)

		end
	end
	if E.design.kind ~= "station" and E.design.kind ~= "weapon" then
		Slab.Separator()
		Slab.Text("Wreck")
		check(E, p.cargo == true, "Carries cargo", function(on) p.cargo = on or nil end)
		Slab.Text("  (no part tagged: every part carries)", { Color = { 0.6, 0.6, 0.6 } })
		check(E, p.core == true, "Core (stays when the rest is shot off)", function(on) p.core = on or nil end)
		check(E, p.breakable ~= false, "Can be shot off", function(on) if on then p.breakable = nil else p.breakable = false end end)
		check(E, p.explode == true, "Bursts into loot when shot off", function(on) p.explode = on or nil end)
		Slab.Text("Mass multiplier (when it breaks away)")
		slider(E, "yard_mass" .. i, p.mass or 1, 0.1, 5, function(v) p.mass = v end)
		Slab.Text("Armour multiplier")
		slider(E, "yard_armor" .. i, p.armor or 1, 0.1, 5, function(v) p.armor = v end)
	end

	Slab.Separator()
	Slab.Text("Shape")
	check(E, p.mirror == true, "Mirrored: drawn again flipped across the centre line (M)", function(on) p.mirror = on or nil end)
	if E.design.kind ~= "weapon" then check(E, p.collide ~= false, "Collides (off: drawn only)", function(on) if on then p.collide = nil else p.collide = false end end) end
	if Slab.Button("Flip nose-tail") then E.transformSelected(function(x, y) return -x, y end, true) end
	Slab.SameLine()
	if Slab.Button("Flip sides") then E.transformSelected(function(x, y) return x, -y end, true) end
	if Slab.Button("Rotate 90") then E.transformSelected(function(x, y) return -y, x end) end
	Slab.SameLine()
	if Slab.Button("Rotate 15") then
		local c, s = math.cos(math.pi / 12), math.sin(math.pi / 12)
		local cx, cy = Canvas.centre(p.shape)
		E.transformSelected(function(x, y) return cx + (x - cx) * c - (y - cy) * s, cy + (x - cx) * s + (y - cy) * c end)
	end
	if Slab.Button("Scale -10%") then
		local cx, cy = Canvas.centre(p.shape)
		E.transformSelected(function(x, y) return cx + (x - cx) * 0.9, cy + (y - cy) * 0.9 end)
	end
	Slab.SameLine()
	if Slab.Button("Scale +10%") then
		local cx, cy = Canvas.centre(p.shape)
		E.transformSelected(function(x, y) return cx + (x - cx) * 1.1, cy + (y - cy) * 1.1 end)
	end
	if Slab.Button("Symmetrize about the spine") then E.symmetrizeSelected() end
	if Slab.Button("Duplicate (Ctrl+D)") then E.duplicateSelected() end
	Slab.SameLine()
	if Slab.Button("Delete") then E.vsel = nil; E.deleteSelected() end
	Slab.EndWindow()
end

function Panels.update(E, Editor)
	designWindow(E, Editor)
	partWindow(E)
	rotorWindow(E)
	paintWindow(E)
	require("src.editor.comparison").update(E)
end

Panels.fillWindows = fillWindows
return Panels
