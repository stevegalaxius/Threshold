--[[
	Debug panel (F1), built with Slab. Swap hulls and modules, tune flight
	feel live, spawn enemies, and read the numbers behind the handling.
	This is a developer tool; the player-facing menus will use Luis.
]]

local Slab = require("lib.Slab")
local data = require("src.data")
local T = require("src.tuning")
local Ship = require("src.ship")
local Render = require("src.render")
local Fields = require("src.fields")

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
	-- Docked: put a new ship in this station's hangar (until there's a market).
	local st = p and p.dockState and p.dockState.done and p.dockState.station
	if st then
		Slab.Text("Park a new ship here (" .. st.name .. ")")
		for _, o in ipairs(opts) do
			if Slab.Button("Park a new " .. data.hulls[o.value].name, { W = 300 }) then game:addToHangar(st, o.value) end
		end
	end
	if Slab.Button("+10,000 credits") then game.universe.credits = game.universe.credits + 10000 end
	Slab.Separator()
	Slab.Text("Save / load (F5 / F9)")
	if Slab.Button("Save") then game:saveTo("quick") end
	Slab.SameLine()
	if Slab.Button("Load") then game:loadFrom("quick") end
	Slab.SameLine()
	if Slab.Button("New game") then game:newGame() end
	Slab.SameLine()
	if Slab.Button("Load autosave") then game:loadFrom("auto") end

	Slab.Text("Paint")
	local paints = {}
	local paintName = "(custom)"
	for _, pt in ipairs(Render.PAINTS) do
		table.insert(paints, { label = pt.name, value = pt.color })
		local c = game.playerColor
		if pt.color[1] == c[1] and pt.color[2] == c[2] and pt.color[3] == c[3] then paintName = pt.name end
	end
	combo("dbg_paint", paintName, paints, function(c)
		game.playerColor = c
		if p then p.color = c end
	end)

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
		for _, ammo in ipairs(w.ammoOptions) do
			if not ammoSeen[ammo] then
				ammoSeen[ammo] = true
				local item = data.items[ammo]
				Slab.Text(("%s: %d"):format(item.name, p.cargo[ammo] or 0))
				Slab.PushID(ammo)
				if Slab.Button("+10") then Ship.addCargo(p, ammo, 10) end
				Slab.SameLine()
				if Slab.Button("+100") then Ship.addCargo(p, ammo, 100) end
				Slab.SameLine()
				if Slab.Button("Fill") then Ship.addCargo(p, ammo, 100000) end
				Slab.PopID()
			end
		end
	end
	if Slab.Button("Empty hold") then
		p.cargo = {}
		Ship.updateMass(p)
	end
	Slab.SameLine()
	if Slab.Button("Repair") then p.armor = p.stats.armor end
	if p.hold and Slab.CheckBox(T.dev.showHold, "Show hold grid") then T.dev.showHold = not T.dev.showHold end
end

local function cheats(game)
	if Slab.CheckBox(T.dev.god, "God mode") then T.dev.god = not T.dev.god end
	if Slab.CheckBox(T.dev.infiniteAmmo, "Infinite ammo") then T.dev.infiniteAmmo = not T.dev.infiniteAmmo end
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

local function flightSection(game)
	for _, s in ipairs(T.flightSpecs) do
		Slab.Text(s.label)
		if Slab.InputNumberSlider("flight_" .. s.key, T[s.key], s.min, s.max, { W = 300, Precision = s.precision }) then
			T[s.key] = Slab.GetInputNumber()
		end
	end
	if Slab.Button("Reset flight and catch") then T.resetFlight() end
	if Fields.orbits[game.fieldId] and game.player and not game.player.dead then
		if Slab.Button("Arrive here again (try the catch)") then
			local Ship = require("src.ship")
			game:loadField(game.fieldId, { player = Ship.record(game.player), at = { catch = true } })
		end
	end
end

local function laneSection(game)
	for _, s in ipairs(T.laneSpecs) do
		Slab.Text(s.label)
		if Slab.InputNumberSlider("lane_" .. s.key, T[s.key], s.min, s.max, { W = 300, Precision = s.precision }) then
			T[s.key] = Slab.GetInputNumber()
		end
	end
	if Slab.Button("Reset lane to defaults") then T.resetLane() end
	if Fields.orbits[game.fieldId] and game.player and not game.player.dead then
		local to = game.fieldId == "mars" and "earth" or "mars"
		if Slab.Button("Straight into a lane to " .. Fields[to].name) then game:launchTrip(to) end
	end
	if Slab.Button(T.travelMode == "lane" and "Drivers send you: highway (switch to warp + catch)" or "Drivers send you: warp + catch (switch to highway)") then
		T.travelMode = T.travelMode == "lane" and "flight" or "lane"
	end
end

local function spawnSection(game)
	Slab.Text("Playing field")
	local fopts = {}
	for _, id in ipairs(Fields.list) do fopts[#fopts + 1] = { label = Fields[id].name, value = id } end
	combo("dbg_field", game.field and game.field.name or "", fopts, function(id) game:loadField(id) end)
	for _, id in ipairs(data.list.enemies) do
		local def = data.enemies[id]
		if Slab.Button(("Spawn %s (%s)"):format(def.name, id), { W = 300 }) then
			local x, y = game:spawnPoint(900, 1300)
			game:spawnEnemy(id, x, y)
		end
	end
	if Slab.Button("Clear enemies") then game:clearEnemies() end
	-- station turrets: make every armed station angry at you (as if you'd
	-- shot it), or forgive you
	if game.player and not game.player.dead then
		if Slab.Button("Stations hate me (30 s)") then
			for _, st in ipairs(game.entities) do
				if st.grudge then st.grudge[game.player] = game.time end
			end
		end
		Slab.SameLine()
		if Slab.Button("Forgive me") then
			for _, st in ipairs(game.entities) do
				if st.grudge then st.grudge[game.player] = nil end
			end
		end
	end
	-- wrecks and props from data/ or the Shipyard (data.wrecks)
	for _, id in ipairs(data.list.wrecks) do
		local def = data.wrecks[id]
		if Slab.Button(("Spawn %s %s"):format(def.kind, def.name), { W = 300 }) then
			local x, y = game:spawnPoint(600, 900)
			game:spawnWreck(id, x, y)
		end
	end
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
		("Thrust           %.0f kN main, %.0f side, %.0f retro"):format(s.thrust, s.sideThrust, s.retroThrust),
		("Armor            %.0f"):format(s.armor),
		("Power            %.0f out, %.0f draw, %.0f stored"):format(s.powerOut, s.powerDraw, s.powerCap),
		("Hold             %.1f / %.0f m3"):format(p.holdUsed, Ship.holdCapacity(p)),
		("Hardest impact   %.0f px/s  (you take damage above %.0f)"):format(game.stats.maxImpactSpeed, (game.player and game.player.hull.ramSpeed or T.ramSpeed) * T.ramSpeedScale),
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
	section("dbg_flight", "Flight and catch", flightSection, game)
	section("dbg_lane", "Transit lane (highway)", laneSection, game)
	section("dbg_spawn", "Spawn and arena", spawnSection, game)
	Slab.EndWindow()
end

function Debug.draw()
	Slab.Draw()
end

return Debug
