--[[
	Scripted smoke test:  love . --autotest

	Flies the player through a fixed script, logs handling numbers, and saves
	screenshots to the save folder, then quits. Useful after changing data
	or flight code to check nothing broke and the numbers are still sane.
]]

local data = require("src.data")
local T = require("src.tuning")
local Ship = require("src.ship")
local Debug = require("src.debugui")
local events = require("src.events")

local A = { shots = {}, logged = {} }

local function log(fmt, ...)
	print(("[autotest t=%5.2f] " .. fmt):format(A.game and A.game.time or 0, ...))
end

local function speed(e)
	local vx, vy = e.body:getLinearVelocity()
	return math.sqrt(vx * vx + vy * vy)
end

local function once(key, fn)
	if not A.logged[key] then A.logged[key] = true; fn() end
end

function A.start(game)
	A.game = game
	A.taken, A.dealt = {}, {}
	events.on("hit", function(e, amount, source, cause)
		cause = cause or "?"
		if e.isPlayer then A.taken[cause] = (A.taken[cause] or 0) + amount
		elseif source and source.isPlayer then A.dealt[cause] = (A.dealt[cause] or 0) + amount end
	end)
	game.wavesOn = false
	-- clear a lane to the right so the acceleration test doesn't hit a rock
	for i = #game.entities, 1, -1 do
		local e = game.entities[i]
		if e.kind == "asteroid" then
			local x, y = e.body:getPosition()
			if x > -200 and math.abs(y) < 400 then game:remove(e) end
		end
	end
	game.player.body:setAngle(0)
	log("loaded %d hulls, %d modules, %d items, %d enemies", #data.list.hulls, #data.list.modules, #data.list.items, #data.list.enemies)
	local perf = Ship.performance(game.player)
	log("Wisp: mass %.1f t, accel %.0f px/s2 (side %.0f), top speed %.0f px/s, turn accel %.1f rad/s2", perf.mass, perf.accel, perf.sideAccel, perf.topSpeed, perf.turnAccel)
end

local function nearestEnemy(game)
	local p = game.player
	local px, py = p.body:getPosition()
	local best, bd
	for _, e in ipairs(game.entities) do
		if e.kind == "ship" and e.team == 2 and not e.dead then
			local x, y = e.body:getPosition()
			local d = (x - px) ^ 2 + (y - py) ^ 2
			if not bd or d < bd then best, bd = e, d end
		end
	end
	return best
end

function A.intent(game, dt)
	local t = game.time
	local p = game.player
	local it = { thrust = 0, strafe = 0, firePrimary = false, fireSecondary = false, fireAux = false, boost = false, aimX = 0, aimY = 0 }
	if not p or p.dead then return it end
	local px, py = p.body:getPosition()
	it.aimX, it.aimY = px + 300, py

	if t < 2 then
		it.thrust = 1                          -- main engine, nose pointing right
	elseif t < 4 then
		-- coast: measure drift
	elseif t < 20 then
		local e = nearestEnemy(game)
		if e then
			local ex, ey = e.body:getPosition()
			local evx, evy = e.body:getLinearVelocity()
			it.aimX, it.aimY = ex + evx * 0.3, ey + evy * 0.3
			local dx, dy = ex - px, ey - py
			local d = math.sqrt(dx * dx + dy * dy)
			-- circle at ~600 px using the side thrusters, guns on target
			local err = math.max(-1, math.min(1, (d - 600) / 200))
			it.thrust, it.strafe = Ship.toLocal(p, -dy / d * 0.8 + dx / d * err, dx / d * 0.8 + dy / d * err)
			it.firePrimary = d < 950
			it.fireAux = (math.floor(t * 2) % 7 == 0)
			it.boost = (math.floor(t) % 5 == 0)
		end
	elseif t < 27 then
		-- Bastion: artillery at a drone parked 1400 px away
		local e = nearestEnemy(game)
		if e then it.aimX, it.aimY = e.body:getPosition() else it.aimX, it.aimY = px + 1400, py - 300 end
		it.firePrimary = true
	elseif t < 31 then
		-- sit still and let a drone ram us
		it.aimX, it.aimY = px - 300, py
	elseif t < 33 then
		-- lasers at the drone straight "up"
		it.aimX, it.aimY = px, py - 220
		it.firePrimary = t > 31.4
	end
	return it
end

local function shot(name)
	love.graphics.captureScreenshot(function(img)
		img:encode("png", name .. ".png")
		log("screenshot %s/%s.png", love.filesystem.getSaveDirectory(), name)
	end)
end

function A.update(game, dt)
	local t = game.time
	local p = game.player

	if t >= 1 then once("v1", function() log("speed after 1 s full thrust: %.0f px/s", speed(p)) end) end
	if t >= 2 then once("v2", function() log("speed after 2 s full thrust: %.0f px/s", speed(p)) end) end
	if t >= 1.5 then once("shot_flight", function() shot("01_flight") end) end
	if t >= 4 then once("v4", function()
		log("speed after 2 s coasting: %.0f px/s", speed(p))
		local x, y = p.body:getPosition()
		for _ = 1, 2 do
			game:spawnEnemy("swarmer", x + 1000 + love.math.random() * 300, y + (love.math.random() - 0.5) * 700)
		end
		log("phase A (like wave 1): 2 scrap drones")
	end) end
	if t >= 7 then once("shot_fight", function() shot("02_fight") end) end
	if t >= 12 then once("phaseB", function()
		local function total(tbl) local s = 0 for _, v in pairs(tbl) do s = s + v end return s end
		log("phase A result: kills %d, enemies left %d, player armor %.0f/%.0f, damage taken %.0f",
			game.kills, game:enemyCount(), p.armor, p.stats.armor, total(A.taken))
		game:clearEnemies()
		local x, y = p.body:getPosition()
		game:spawnEnemy("gunner", x + 1100, y - 300)
		game:spawnEnemy("interceptor", x + 1100, y + 300)
		A.killsAtB = game.kills
		log("phase B: gunner + interceptor")
	end) end
	if t >= 13 then once("debug_on", function() Debug.visible = true end) end
	if t >= 13.5 then once("shot_debug", function() shot("03_debug_panel") end) end
	if t >= 14 then once("debug_off", function() Debug.visible = false end) end

	if t >= 20 then once("fight_summary", function()
		local function fmt(tbl) local out = {} for k, v in pairs(tbl) do table.insert(out, ("%s %.0f"):format(k, v)) end return table.concat(out, ", ") end
		log("damage taken by player: %s", fmt(A.taken))
		log("damage dealt by player: %s", fmt(A.dealt))
		if p and not p.dead then
			log("phase B kills %d", game.kills - (A.killsAtB or 0))
			log("after fight: armor %.0f/%.0f, rounds %d, missiles %d, hold %.1f/%.0f, kills %d, pickups on field %d",
				p.armor, p.stats.armor, p.cargo.rounds_s or 0, p.cargo.missile_s or 0, p.holdUsed, Ship.holdCapacity(p), game.kills, #game.pickups)
			for id, n in pairs(p.cargo) do log("  hold: %s x%d", id, n) end
		else
			log("player died during the fight (kills %d)", game.kills)
		end
		game:clearEnemies()
		T.dev.god = true
		game:spawnPlayer("ferrous_bastion")
		local bx, by = game.player.body:getPosition()
		A.artyTarget = game:spawnEnemy("brawler", bx + 1400, by - 300)
		A.artyTarget.def = nil          -- parked target, no AI
		local perf = Ship.performance(game.player)
		log("Bastion: mass %.1f t, accel %.0f px/s2 (side %.0f), top speed %.0f px/s, turn accel %.1f rad/s2", perf.mass, perf.accel, perf.sideAccel, perf.topSpeed, perf.turnAccel)
	end) end
	if t >= 24 then once("shot_arty", function() shot("04_artillery") end) end
	if t >= 27 then once("ram_setup", function()
		local b = game.player
		log("Bastion shells left: %d (started 60), mass now %.1f t; parked target at 1430 px: %s, armor %.0f/%.0f",
			b.cargo.shell_l or 0, b.body:getMass(), A.artyTarget.dead and "destroyed" or "alive", A.artyTarget.armor, A.artyTarget.stats.armor)
		if not A.artyTarget.dead then game:remove(A.artyTarget) end
		local x, y = b.body:getPosition()
		local d = game:spawnEnemy("swarmer", x - 500, y)
		d.body:setLinearVelocity(500, 0)
		game.stats.maxImpulse, game.stats.maxImpactSpeed = 0, 0
	end) end
	if t >= 30 then once("ram_result", function()
		log("ram test: hardest impact %.0f px/s (impulse %.0f), Bastion armor %.0f/%.0f", game.stats.maxImpactSpeed, game.stats.maxImpulse, game.player.armor, game.player.stats.armor)
		shot("05_ram")
	end) end
	if t >= 31 then once("laser_setup", function()
		T.dev.god = false
		local w = game:spawnPlayer("halcyon_wisp")
		w.loadout[1], w.loadout[2] = "glint_laser", "glint_laser"
		Ship.refit(w)
		local x, y = w.body:getPosition()
		A.laserTarget = game:spawnEnemy("swarmer", x, y - 220)
		A.laserTarget.def = nil          -- hold still: no AI
		A.powerBefore = w.power
		-- loot drops right on top of us
		game:spawnPickup(x, y, "scrap", 1)
		game:spawnPickup(x, y, "rounds_s", 40)
		A.holdBefore = w.holdUsed
	end) end
	if t >= 33 then once("laser_result", function()
		local w = game.player
		local d = A.laserTarget
		log("lasers: target %s (armor %.0f/%.0f), power %.0f -> %.0f",
			d.dead and "destroyed" or "alive", d.armor, d.stats.armor, A.powerBefore, w.power)
		log("pickups: hold %.2f -> %.2f m3, scrap %d, light rounds %d", A.holdBefore, w.holdUsed, w.cargo.scrap or 0, w.cargo.rounds_s or 0)
		-- Grid hold: layout, adding until it's full, and husk holds.
		for _, g in ipairs(w.hold.grids) do log("grid: %s %d x %d, %d stacks", g.name, g.w, g.h, #g.stacks) end
		local got = Ship.addCargo(w, "scrap", 3)
		log("grid: +%d scrap, hold %d / %d m3", got, w.holdUsed, Ship.holdCapacity(w))
		got = Ship.addCargo(w, "rounds_s", 100000)
		log("grid: filled with %d light rounds, hold %d / %d m3, missiles %d, mass %.1f t", got, w.holdUsed, Ship.holdCapacity(w), w.cargo.missile_s or 0, w.body:getMass())
		log("grid: room for %d more scrap", Ship.canFit(w, "scrap"))
		for _, e in ipairs(game.entities) do
			if e.kind == "husk" then
				local n, parts = 0, {}
				for id, c in pairs(e.loot) do n = n + 1; table.insert(parts, id .. " x" .. c) end
				log("husk: %s, %d x %d grid, %s", e.hold.grids[1].name, e.hold.grids[1].w, e.hold.grids[1].h, table.concat(parts, ", "))
			end
		end
		T.dev.showHold = true
		shot("06_lasers")
	end) end
	-- Cargo screen: eject, split, drag out, then a (pretend) station.
	if t >= 33.3 then once("cargo_space", function()
		local Cargo = require("src.ui.cargo")
		local Grid = require("src.inventory.grid")
		local w = game.player
		T.dev.showHold = false
		Cargo.toggle(game)
		local L = Cargo.layout(game)
		local cs = L.cs
		local function at(r, cx, cy) return r.x + (cx + 0.5) * cs, r.y + (cy + 0.5) * cs end
		local main = L.grids[1]
		local g = main.g
		local pickups = #game.pickups
		local s = Grid.at(g, g.w - 1, g.h - 1)
		local mx, my = at(main, g.w - 1, g.h - 1)
		Cargo.mousepressed(game, mx, my, 2)
		log("cargo: right-click ejected %s x%d, pickups %d -> %d, hold %d / %d", s.id, s.n, pickups, #game.pickups, w.holdUsed, Ship.holdCapacity(w))
		local src = Grid.at(g, g.w - 1, g.h - 2)
		local before = src.n
		local sx, sy = at(main, g.w - 1, g.h - 2)
		Cargo.mousepressed(game, sx, sy, 1, { shift = true })
		Cargo.mousereleased(game, mx, my, 1)
		local moved = Grid.at(g, g.w - 1, g.h - 1)
		log("cargo: shift-drag split %s %d -> %d + %d, hold %d / %d, light rounds %d", src.id, before, src.n, moved and moved.n or 0, w.holdUsed, Ship.holdCapacity(w), w.cargo.rounds_s or 0)
		Cargo.mousepressed(game, mx, my, 1)
		Cargo.mousereleased(game, 4, 4, 1)
		log("cargo: dragged out to eject, pickups %d, light rounds %d, hold %d / %d", #game.pickups, w.cargo.rounds_s or 0, w.holdUsed, Ship.holdCapacity(w))
		shot("07_cargo_space")
	end) end
	if t >= 33.6 then once("cargo_station", function()
		local Cargo = require("src.ui.cargo")
		local Grid = require("src.inventory.grid")
		local Hold = require("src.inventory.hold")
		Cargo.toggle(game)
		-- A real wheel station (planet field), with the Wisp parked inside.
		game:loadField("planet")
		local w = game.player
		local st
		for _, e in ipairs(game.entities) do if e.kind == "station" and e.dock then st = e end end
		w.dockState = { done = true, phase = "done", t = 0, station = st }
		game.state = "docked"
		local storage = game:stationStorage(st)
		Hold.add(storage, "rounds_s_crate", 120)
		local L = Cargo.layout(game)
		local cs = L.cs
		local function at(r, s) return r.x + (s.x + 0.5) * cs, r.y + (s.y + 0.5) * cs end
		local function find(side, id)
			for _, r in ipairs(Cargo.layout(game).grids) do
				if (side == "ship") == (r.side.ship ~= nil) then
					for _, s in ipairs(r.g.stacks) do if s.id == id then return r, s end end
				end
			end
		end
		local r, s = find("ship", "rounds_s")
		local x, y = at(r, s)
		Cargo.mousepressed(game, x, y, 1, { ctrl = true })
		log("cargo: ctrl-click moved light rounds to storage, storage has %d, ship has %d, hold %d / %d", Hold.count(storage, "rounds_s"), w.cargo.rounds_s or 0, w.holdUsed, Ship.holdCapacity(w))
		r, s = find("storage", "rounds_s_crate")
		x, y = at(r, s)
		Cargo.mousepressed(game, x, y, 1, { ctrl = true })
		log("cargo: crate to hold: hold crates %d, storage crates %d", w.cargo.rounds_s_crate or 0, Hold.count(storage, "rounds_s_crate"))
		local before = w.cargo.rounds_s or 0
		r, s = find("ship", "rounds_s_crate")
		if r then
			x, y = at(r, s)
			Cargo.mousepressed(game, x, y, 2)
		end
		log("cargo: unboxed, light rounds %d -> %d, crates left %d, hold %d / %d", before, w.cargo.rounds_s or 0, w.cargo.rounds_s_crate or 0, w.holdUsed, Ship.holdCapacity(w))
		r, s = find("ship", "missile_s")
		x, y = at(r, s)
		local tx, ty
		for _, gr in ipairs(Cargo.layout(game).grids) do
			if gr.side.ship and gr.g.key ~= "hull" then tx, ty = gr.x + 0.5 * cs, gr.y + 0.5 * cs end
		end
		Cargo.mousepressed(game, x, y, 1)
		Cargo.keypressed(game, "r")
		Cargo.mousereleased(game, tx, ty, 1)
		local pod = w.hold.grids[2]
		local ps = Grid.at(pod, 0, 0)
		log("cargo: dragged + rotated a missile stack into the pod: %s %d x %d, missiles %d", ps and ps.id or "nothing", ps and ps.w or 0, ps and ps.h or 0, w.cargo.missile_s or 0)
		-- Equipment: unfit the engine into the hold, try to launch, refit it
		-- with a double-click, and check a full Cargo Pod can't come out.
		L = Cargo.layout(game)
		local function slotRow(family)
			for _, er in ipairs(L.equip.slots) do if er.slot.family == family then return er end end
		end
		local function freeSpot()
			local main = Cargo.layout(game).grids[1]
			for cy = 0, main.g.h - 1 do
				for cx = 0, main.g.w - 2 do
					if Grid.isFree(main.g, cx, cy, 2, 1) then return main.x + (cx + 0.5) * cs, main.y + (cy + 0.5) * cs end
				end
			end
		end
		local eng, thr = slotRow("engine"), slotRow("thruster")
		local engineId, thrusterId = w.loadout[eng.i], w.loadout[thr.i]
		local ex, ey = freeSpot()
		Cargo.mousepressed(game, eng.x + 10, eng.y + 10, 1)
		Cargo.mousereleased(game, ex, ey, 1)
		log("equip: unfitted %s, slot now %s, in hold %d, thrust %.0f, launch problem: %s (thrusters count)", engineId, tostring(w.loadout[eng.i]),
			w.cargo[engineId] or 0, w.stats.thrust, tostring(Ship.launchProblem(w)))
		local tx, ty = freeSpot()
		Cargo.mousepressed(game, thr.x + 10, thr.y + 10, 1)
		Cargo.mousereleased(game, tx, ty, 1)
		game:undock()
		log("equip: thrusters out too: launch problem %s, undock -> state %s", tostring(Ship.launchProblem(w)), game.state)
		Cargo.quickFit(game, ex, ey)
		Cargo.quickFit(game, tx, ty)
		log("equip: double-click refit, engine %s, thruster %s, thrust %.0f, launch problem: %s", tostring(w.loadout[eng.i]),
			tostring(w.loadout[thr.i]), w.stats.thrust, tostring(Ship.launchProblem(w)))
		local util = slotRow("utility")
		Hold.add(w.hold, "scrap", 1)
		local podGrid = w.hold.grids[2]
		local podHas = #podGrid.stacks
		Cargo.mousepressed(game, util.x + 10, util.y + 10, 1)
		log("equip: tried to pull a Cargo Pod holding %d stacks -> slot %s, hand %s", podHas, tostring(w.loadout[util.i]), tostring(Cargo.hand and Cargo.hand.id))
		-- grab a spare module from storage and drag it over the slot it fits
		Hold.add(storage, "glint_laser", 1)
		L = Cargo.layout(game)
		r, s = find("storage", "glint_laser")
		x, y = at(r, s)
		Cargo.mousepressed(game, x, y, 1)
		local prim = slotRow("primary")
		Cargo.mousereleased(game, prim.x + 10, prim.y + 10, 1)
		log("equip: dragged glint_laser from storage onto slot %d -> %s, old module now in hold %d / storage %d",
			prim.i, tostring(w.loadout[prim.i]), w.cargo.px2_autogun or 0, Hold.count(storage, "px2_autogun"))
		shot("08_cargo_station")
	end) end
	if t >= 33.9 then once("cargo_done", function() game:undock() end) end
	if t >= 34 then once("quit", function()
		log("done: %d entities, %d projectiles, %d effects", #game.entities, #game.projectiles, #game.effects)
		love.event.quit()
	end) end
end

return A
