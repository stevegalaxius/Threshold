--[[
	Debug panel (F1), built with Slab. Swap hulls and modules, tune flight
	feel live, spawn enemies, and read the numbers behind the handling.
	This is a developer tool; the player-facing menus will use Luis.
]]

local Slab = require("lib.Slab")
local data = require("src.data")
local T = require("src.tuning")
local Ship = require("src.ship")

local Debug = { visible = false }

function Debug.init()
	Slab.Initialize({ "nodocks", "nomessages" })
end

function Debug.toggle()
	Debug.visible = not Debug.visible
end

-- True while the mouse is over the panel, so clicks don't fire weapons.
function Debug.blocksMouse()
	return Debug.visible and not Slab.IsVoidHovered()
end

function Debug.blocksKeyboard()
	return Debug.visible and Slab.IsAnyInputFocused()
end

local function combo(id, selected, options, onPick)
	if Slab.BeginComboBox(id, { Selected = selected, W = 300 }) then
		for _, opt in ipairs(options) do
			if Slab.TextSelectable(opt.label) then onPick(opt.value) end
		end
		Slab.EndComboBox()
	end
end

local function shipSection(game)
	local p = game.player
	Slab.Text("Hull (launches a fresh ship)")
	local opts = {}
	for _, id in ipairs(data.list.hulls) do
		local h = data.hulls[id]
		if h.playable ~= false then
			table.insert(opts, { label = ("%s  -  %s, %s"):format(h.name, h.maker, h.class), value = id })
		end
	end
	local current = data.hulls[game.playerHull]
	combo("dbg_hull", current.name, opts, function(id) game:spawnPlayer(id) end)
	if Slab.Button("Relaunch ship") then game:spawnPlayer() end

	if not p or p.dead then return end
	Slab.Separator()
	Slab.Text("Modules (strict size matching)")
	for i, slot in ipairs(p.hull.slots) do
		local mopts = { { label = "(empty)", value = false } }
		for _, id in ipairs(data.modulesFor(slot)) do
			table.insert(mopts, { label = data.modules[id].name, value = id })
		end
		local cur = p.loadout[i] and data.modules[p.loadout[i]].name or "(empty)"
		Slab.Text(("%d. %s %s"):format(i, slot.family, slot.size))
		combo("dbg_slot" .. i, cur, mopts, function(id)
			p.loadout[i] = id
			Ship.refit(p)
		end)
	end

	Slab.Separator()
	Slab.Text("Hold")
	local ammoSeen = {}
	for _, w in ipairs(p.weapons) do
		if w.ammo and not ammoSeen[w.ammo] then
			ammoSeen[w.ammo] = true
			local item = data.items[w.ammo]
			Slab.Text(("%s: %d"):format(item.name, p.cargo[w.ammo] or 0))
			Slab.PushID(w.ammo)
			if Slab.Button("+10") then Ship.addCargo(p, w.ammo, 10) end
			Slab.SameLine()
			if Slab.Button("+100") then Ship.addCargo(p, w.ammo, 100) end
			Slab.SameLine()
			if Slab.Button("Fill") then Ship.addCargo(p, w.ammo, 100000) end
			Slab.PopID()
		end
	end
	if Slab.Button("Empty hold") then
		p.cargo = {}
		Ship.updateMass(p)
	end
	Slab.SameLine()
	if Slab.Button("Repair") then p.armor = p.stats.armor end
end

local function cheats(game)
	if Slab.CheckBox(T.dev.god, "God mode") then T.dev.god = not T.dev.god end
	if Slab.CheckBox(T.dev.infiniteAmmo, "Infinite ammo") then T.dev.infiniteAmmo = not T.dev.infiniteAmmo end
	if Slab.CheckBox(game.wavesOn, "Waves") then game.wavesOn = not game.wavesOn end
end

local function tuningSection()
	for _, s in ipairs(T.specs) do
		Slab.Text(s.label)
		if Slab.InputNumberSlider("tune_" .. s.key, T[s.key], s.min, s.max, { W = 300, Precision = s.precision }) then
			T[s.key] = Slab.GetInputNumber()
		end
	end
	if Slab.Button("Reset to defaults") then T.reset() end
end

local function spawnSection(game)
	for _, id in ipairs(data.list.enemies) do
		local def = data.enemies[id]
		if Slab.Button(("Spawn %s (%s)"):format(def.name, id), { W = 300 }) then
			local x, y = game:spawnPoint(900, 1300)
			game:spawnEnemy(id, x, y)
		end
	end
	if Slab.Button("Next wave now") then
		game.wave = game.wave + 1
		game:spawnWave(game.wave)
	end
	Slab.SameLine()
	if Slab.Button("Clear enemies") then game:clearEnemies() end
	if Slab.Button("Spawn 5 asteroids") then
		for _ = 1, 5 do
			local x, y = game:spawnPoint(300, 700)
			game:spawnAsteroid(x, y, 30 + love.math.random() * 70)
		end
	end
end

local function readout(game)
	local p = game.player
	if not p or p.dead then Slab.Text("(no ship)") return end
	local perf = Ship.performance(p)
	local s = p.stats
	local lines = {
		("Mass             %.0f t  (dry %.0f + hold %.0f)"):format(perf.mass, s.mass * T.massScale, p.cargoMass * T.massScale),
		("Acceleration     %.0f px/s2"):format(perf.accel),
		("Top speed        %.0f px/s"):format(perf.topSpeed),
		("Turn accel       %.1f rad/s2"):format(perf.turnAccel),
		("Max turn speed   %.0f deg/s"):format(perf.turnSpeed),
		("Side accel       %.0f px/s2  (maneuvering thrusters)"):format(perf.sideAccel),
		("Thrust           %.0f kN main, %.0f kN side/retro"):format(s.thrust, s.sideThrust),
		("Armor            %.0f"):format(s.armor),
		("Power            %.0f out, %.0f draw, %.0f stored"):format(s.powerOut, s.powerDraw, s.powerCap),
		("Hold             %.1f / %.0f m3"):format(p.holdUsed, s.hold),
		("Hardest impact   %.0f px/s  (ram above %.0f)"):format(game.stats.maxImpactSpeed, T.ramSpeed),
	}
	for _, l in ipairs(lines) do Slab.Text(l) end
	if Slab.Button("Reset impact meter") then game.stats.maxImpulse, game.stats.maxImpactSpeed = 0, 0 end
end

local function section(id, label, fn, ...)
	if Slab.BeginTree(id, { Label = label }) then
		fn(...)
		Slab.EndTree()
	end
end

function Debug.update(dt, game)
	Slab.Update(dt)
	if not Debug.visible then return end
	local h = love.graphics.getHeight()
	Slab.BeginWindow("dbg_window", {
		Title = "Debug  (F1 hides)", X = love.graphics.getWidth() - 380, Y = 140,
		W = 360, H = h - 160, AutoSizeWindow = false, AllowResize = true,
	})
	Slab.Text(("FPS %d    ships+rocks %d    shots %d"):format(love.timer.getFPS(), #game.entities, #game.projectiles))
	cheats(game)
	Slab.Separator()
	section("dbg_ship", "Ship, modules and hold", shipSection, game)
	section("dbg_readout", "Handling readout", readout, game)
	section("dbg_tuning", "Flight tuning", tuningSection)
	section("dbg_spawn", "Spawn and arena", spawnSection, game)
	Slab.EndWindow()
end

function Debug.draw()
	Slab.Draw()
end

return Debug
