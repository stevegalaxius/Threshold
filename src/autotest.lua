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
	game:clearEnemies()                -- the level's own enemies; the test brings its own
	game.autosaveOff = true
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
	elseif A.tow and not A.tow.removed then
		-- hold the tractor on a container and fly away with it
		it.aimX, it.aimY = A.tow.body:getPosition()
		if game.time > A.towFrom + 0.3 then it.aimX, it.aimY = px + math.cos(p.body:getAngle()) * 300, py + math.sin(p.body:getAngle()) * 300 end
		it.tractor = true
		it.thrust = game.time > A.towFrom + 0.3 and 1 or 0
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
		-- A real wheel station (Mars), with the Wisp parked inside.
		game:loadField("mars")
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
		Cargo.mousepressed(game, x, y, 2)
		log("cargo: right-click moved light rounds to storage, storage has %d, ship has %d, hold %d / %d", Hold.count(storage, "rounds_s"), w.cargo.rounds_s or 0, w.holdUsed, Ship.holdCapacity(w))
		r, s = find("storage", "rounds_s_crate")
		x, y = at(r, s)
		Cargo.mousepressed(game, x, y, 1, { ctrl = true })
		log("cargo: crate to hold: hold crates %d, storage crates %d", w.cargo.rounds_s_crate or 0, Hold.count(storage, "rounds_s_crate"))
		local before = w.cargo.rounds_s or 0
		r, s = find("ship", "rounds_s_crate")
		if r then
			x, y = at(r, s)
			Cargo.lastClick = nil
			Cargo.mousepressed(game, x, y, 1)      -- double-click
			Cargo.mousereleased(game, x, y, 1)
			Cargo.mousepressed(game, x, y, 1)
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
		local function dbl(x, y)                   -- a real double-click: press, release, press
			Cargo.mousepressed(game, x, y, 1); Cargo.mousereleased(game, x, y, 1)
			Cargo.mousepressed(game, x, y, 1); Cargo.mousereleased(game, x, y, 1)
		end
		dbl(ex, ey)
		dbl(tx, ty)
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
	-- Looting: tap E on a container, Take All, tow one, shoot one, sink a Hauler.
	if t >= 33.95 then once("loot_open", function()
		local Cargo = require("src.ui.cargo")
		local w = game.player
		local px, py = w.body:getPosition()
		local a = w.body:getAngle()
		local c = game:spawnContainer(px + math.cos(a) * 110, py + math.sin(a) * 110, nil, true)
		c.body:setLinearVelocity(w.body:getLinearVelocity())
		A.lootBox = c
		local n, parts = 0, {}
		for id, k in pairs(c.loot) do n = n + 1; table.insert(parts, id .. " x" .. k) end
		local cx, cy = c.body:getPosition()
		w.intent.aimX, w.intent.aimY = cx, cy
		w.intent.tractor = true
		game:updatePickups(0)
		w.intent.tractor = false
		game:updatePickups(0)
		Cargo.update(game)
		local L = Cargo.layout(game)
		log("loot: tapped E on a container (%s) -> window %s, %d sides, loot side %s",
			table.concat(parts, ", "), tostring(Cargo.isOpen(game)), L and #L.sides or 0, L and L.sides[2] and L.sides[2].title or "none")
		shot("09_loot")
		-- shove it away: the beam should hold it in reach while the window's open
		local vx, vy = w.body:getLinearVelocity()
		c.body:setLinearVelocity(vx + math.cos(a) * 400, vy + math.sin(a) * 400)
		local t0 = game.time
		for _ = 1, 240 do game:step(1 / 120); Cargo.update(game) end
		game.time = t0      -- keep the rest of the script on schedule
		local cx2, cy2 = c.body:getPosition()
		log("loot: shoved it off at 400 px/s -> 2 s later %.0f px from the hull (beam range %d), window open %s",
			Ship.distanceTo(w, cx2, cy2) - c.radius, Ship.tractorRange(w), tostring(Cargo.isOpen(game)))
	end) end
	if t >= 34.05 then once("loot_take", function()
		local Cargo = require("src.ui.cargo")
		local w = game.player
		local L = Cargo.layout(game)
		local side = L.sides[2]
		local before = w.holdUsed
		Cargo.mousepressed(game, side.take.x + 4, side.take.y + 4, 1)
		local left = 0
		for _, k in pairs(A.lootBox.loot) do left = left + k end
		log("loot: Take All, hold %d -> %d / %d m3, left in the container %d items, container mass %.1f t",
			before, w.holdUsed, Ship.holdCapacity(w), left, A.lootBox.body:getMass())
		Cargo.close(game)
		-- Wisp can't stow a container; an Anvil-sized hold (10 x 5) can.
		local Hold = require("src.inventory.hold")
		log("loot: room for a container: Wisp %d, 10 x 5 hold %d", Ship.canFit(w, "cargo_container", 1),
			Hold.room(Hold.new({ { key = "hull", name = "x", w = 10, h = 5 } }), "cargo_container", 1))
		-- reopen it, then fly out of range: it should close itself
		game.openLoot = A.lootBox
		Cargo.update(game)
		local x, y = A.lootBox.body:getPosition()
		A.lootBox.body:setPosition(x + 5000, y)
		Cargo.update(game)
		log("loot: moved the container away -> window open %s", tostring(Cargo.isOpen(game)))
		-- tow a loaded one
		local px, py = w.body:getPosition()
		local a = w.body:getAngle()
		A.tow = game:spawnContainer(px - math.cos(a) * 120, py - math.sin(a) * 120, nil, true)
		A.tow.body:setLinearVelocity(w.body:getLinearVelocity())
		A.towFrom = game.time
	end) end
	if t >= 35.3 then once("tow", function()
		local w = game.player
		local cx, cy = A.tow.body:getPosition()
		local vx, vy = w.body:getLinearVelocity()
		log("tow: towing %s, line %.0f px from the hull (slack %d), ship speed %.0f px/s (tow limit %d), container mass %.1f t",
			tostring(w.towTarget == A.tow), Ship.distanceTo(w, cx, cy) - A.tow.radius, T.towLength, math.sqrt(vx * vx + vy * vy), T.towSpeed, A.tow.body:getMass())
		shot("10_tow")
		A.tow, A.towFrom = nil, nil
		-- shoot it apart, eject a container, sink a Hauler
		A.pickupsBefore = #game.pickups
		local px, py = w.body:getPosition()
		local box = game:spawnContainer(px + 400, py + 400, nil, true)
		A.boxStacks = 0
		for _, g in ipairs(box.hold.grids) do A.boxStacks = A.boxStacks + #g.stacks end
		game:damage(box, 1e6)
		local boxes = 0
		for _, e in ipairs(game.entities) do if e.kind == "container" then boxes = boxes + 1 end end
		A.boxesBefore = boxes
		game:eject(w, "cargo_container", 1)
		for _, e in ipairs(game.entities) do
			if e.kind == "ship" and e.def and e.def.id == "freighter" then
				game:damage(e, 1e9)
				break
			end
		end
	end) end
	if t >= 35.4 then once("spill", function()
		local Cargo = require("src.ui.cargo")
		local Hold = require("src.inventory.hold")
		local boxes = 0
		for _, e in ipairs(game.entities) do if e.kind == "container" then boxes = boxes + 1 end end
		log("loot: shot a loaded container with %d stacks -> pickups %d -> %d; containers %d -> %d after one ejected and the shot one gone",
			A.boxStacks, A.pickupsBefore, #game.pickups, A.boxesBefore, boxes)
		-- The Hauler's wreck: its cargo is packed in containers.
		local husk
		for _, e in ipairs(game.entities) do
			if e.kind == "husk" and e.hull.id == "ferrous_freighter" then husk = e end
		end
		local packed, loose, inside = 0, 0, 0
		for _, g in ipairs(husk.hold.grids) do
			for _, st in ipairs(g.stacks) do
				if st.inner then
					packed = packed + 1
					for _, n in pairs(Hold.totals(st.inner)) do inside = inside + n end
				else
					loose = loose + 1
				end
			end
		end
		log("hauler: wreck holds %d loaded containers (%d items inside) and %d loose stacks", packed, inside, loose)
		-- bring the wreck alongside, open it, double-click a container, take a stack out of it
		local w = game.player
		local px, py = w.body:getPosition()
		husk.body:setPosition(px + 260, py + 120)
		husk.body:setLinearVelocity(w.body:getLinearVelocity())
		Cargo.openLoot(game, husk)
		local L = Cargo.layout(game)
		local cs = L.cs
		local box
		for _, r in ipairs(L.grids) do
			if r.side.entity == husk then
				for _, st in ipairs(r.g.stacks) do if st.inner and not box then box = { r = r, s = st } end end
			end
		end
		local bx, by = box.r.x + (box.s.x + 0.5) * cs, box.r.y + (box.s.y + 0.5) * cs
		for _ = 1, 2 do Cargo.mousepressed(game, bx, by, 1); Cargo.mousereleased(game, bx, by, 1) end
		L = Cargo.layout(game)
		log("hauler: double-clicked a container -> %d panels, last %s, equipment %s", #L.sides, L.sides[#L.sides].title,
			L.equip.hidden and "hidden" or "shown")
		local inner = L.sides[#L.sides]
		local before = w.holdUsed
		local r
		for _, gr in ipairs(L.grids) do if gr.side == inner then r = gr end end
		local st = r.g.stacks[1]
		for _, x in ipairs(r.g.stacks) do if x.w * x.h < st.w * st.h then st = x end end
		local id, n = st.id, st.n
		Cargo.mousepressed(game, r.x + (st.x + 0.5) * cs, r.y + (st.y + 0.5) * cs, 2)
		log("hauler: right-clicked %s x%d out of the container -> hold %d -> %d m3, ship mass %.1f t", id, n, before, w.holdUsed, w.body:getMass())
		shot("11_hauler_wreck")
		-- a bigger ship scoops the whole container, cargo and all
		local big = Hold.new({ { key = "hull", name = "Main hold", w = 10, h = 5 } })
		local copy = { id = box.s.id, n = 1, inner = box.s.inner }
		local ok = Hold.placeStack(big, copy)
		local sorted = Hold.sort(big)
		local s2 = big.grids[1].stacks[1]
		log("hauler: 10 x 5 hold took the loaded container %s, sort kept its cargo %s, contents %.1f t",
			tostring(ok), tostring(sorted and s2 and s2.inner == box.s.inner), Hold.innerMass(big, require("src.data").items))
	end) end
	if t >= 35.5 then once("hauler_close", function() require("src.ui.cargo").close(game) end) end
	-- Hangar, parked cargo, swapping ships, save/load, travel, respawn.
	if t >= 35.65 then once("hangar", function()
		local Cargo = require("src.ui.cargo")
		local w = game.player
		local st
		for _, e in ipairs(game.entities) do if e.kind == "station" and e.dock and not st then st = e end end
		A.st = st
		game:dockInstantly(w, st)
		game:playerDocked(st)
		-- the ship market: buy a Wisp (credits topped up), then sell it back
		local orig = game:credits()
		game.universe.credits = 20000
		local c0 = game:credits()
		local bought, why = game:buyShip(st, "halcyon_wisp")
		local c1 = game:credits()
		local i = #game:hangar(st)
		local paid = game:sellShip(st, i)
		log("shipmarket: bought Wisp %s (%s) %d -> %d cr; sold for %s -> %d cr; hangar %d; shipyard here: %s",
			tostring(bought ~= nil), tostring(why), c0, c1, tostring(paid), game:credits(), #game:hangar(st),
			table.concat(game.shipyard(st), ","))
		game.universe.credits = 0
		log("shipmarket: broke buy refused: %s", tostring(game:shipBuyProblem(st, "halcyon_wisp")))
		game.universe.credits = orig
		game:addToHangar(st, "brute_anvil")
		Cargo.tab = "hangar"
		log("hangar: docked at %s (%s), home %s, hangar has %d ship(s): %s", st.name, st.key, game:homeStation().key,
			#game:hangar(st), game:hangar(st)[1].hull)
		game:addToHangar(st, "ferrous_bastion")
		shot("12_hangar")
	end) end
	if t >= 35.75 then once("hangar_cargo", function()
		local Cargo = require("src.ui.cargo")
		local Hangar = require("src.ui.hangar")
		local Hold = require("src.inventory.hold")
		local w = game.player
		local H = Hangar.layout(game)
		local rec = game:hangar(A.st)[1]
		local ship
		for _, s in ipairs(H.ships) do if s.owner == rec then ship = s end end
		-- drag the Anvil onto the Bastion (refused), then down 6 rows; then the Cargo button
		local x0, y0 = ship.x + 4, ship.y + 4
		local bx, by = rec.bay.x, rec.bay.y
		Cargo.mousepressed(game, x0, y0, 1)
		Cargo.mousereleased(game, x0 + 4 * H.cs, y0, 1)
		local blocked = rec.bay.x == bx
		Hangar.lastClick = nil                   -- (two quick clicks would be a double-click: fly)
		Cargo.mousepressed(game, x0, y0, 1)
		Cargo.mousereleased(game, x0, y0 + 6 * H.cs, 1)
		local T = require("src.tuning")
		local aw, ah = game.hangarFootprint("brute_anvil")
		local ww, wh = game.hangarFootprint("halcyon_wisp")
		local bw, bh = game.hangarFootprint("ferrous_bastion")
		log("hangar: bay %d x %d; footprints Wisp %d x %d, Anvil %d x %d, Bastion %d x %d; Wisp (flying) at %d,%d",
			T.hangarW, T.hangarH, ww, wh, aw, ah, bw, bh, game.player.bay.x, game.player.bay.y)
		log("hangar: dragging the Anvil onto the Bastion refused %s; dragged down from %d,%d to %d,%d",
			tostring(blocked), bx, by, rec.bay.x, rec.bay.y)
		shot("12b_hangar_moved")
		H = Hangar.layout(game)
		Hangar.sel = rec
		Cargo.mousepressed(game, H.cargo.x + 4, H.cargo.y + 4, 1)
		local L = Cargo.layout(game)
		local right = L.sides[#L.sides]
		local before = Hold.cells(rec.hold)
		local r, st
		for _, gr in ipairs(L.grids) do
			if gr.side.ship and not st then r, st = gr, gr.g.stacks[1] end
		end
		Cargo.mousepressed(game, r.x + (st.x + 0.5) * L.cs, r.y + (st.y + 0.5) * L.cs, 1, { ctrl = true })
		local titles = {}
		for _, sd in ipairs(L.sides) do table.insert(titles, sd.title) end
		log("hangar: Cargo on the parked Anvil -> tab %s, panels: %s; ctrl-click moved %s: Anvil hold %d -> %d m3",
			Cargo.tab, table.concat(titles, " | "), st.id, before, (Hold.cells(rec.hold)))
		A.parkedCells = Hold.cells(rec.hold)
		-- switch the right-click target to storage
		L = Cargo.layout(game)
		local storageSide
		for _, sd in ipairs(L.sides) do if sd.storage then storageSide = sd end end
		Cargo.mousepressed(game, storageSide.target.x + 4, storageSide.target.y + 4, 1)
		local storage = game:stationStorage(A.st)
		local s0 = Hold.cells(storage)
		r, st = nil, nil
		for _, gr in ipairs(L.grids) do
			if gr.side.ship and not st then r, st = gr, gr.g.stacks[1] end
		end
		Cargo.mousepressed(game, r.x + (st.x + 0.5) * L.cs, r.y + (st.y + 0.5) * L.cs, 2)
		local s1, a1 = Hold.cells(storage), Hold.cells(rec.hold)
		log("hangar: target -> %s; right-click from your hold: storage %d -> %d m3, Anvil hold %d -> %d m3",
			tostring(Cargo.target), s0, s1, A.parkedCells, a1)
		shot("13_parked_cargo")
	end) end
	if t >= 35.85 then once("hangar_fly", function()
		local Cargo = require("src.ui.cargo")
		local Hangar = require("src.ui.hangar")
		local Hold = require("src.inventory.hold")
		local Save = require("src.save")
		Cargo.tab = "hangar"
		local wispCells = Hold.cells(game.player.hold)
		local H = Hangar.layout(game)
		Cargo.mousepressed(game, H.fly.x + 4, H.fly.y + 4, 1)
		local p = game.player
		local parked = game:hangar(A.st)[1]
		log("hangar: Fly -> flying %s (hold %d m3, docked %s), parked now %s (hold %d m3, was %d)", p.hull.name, (Hold.cells(p.hold)),
			tostring(p.dockState ~= nil), parked.hull, (Hold.cells(parked.hold)), wispCells)
		-- save, mess things up, load
		local state = game:saveState()
		local text = Save.encode(state)
		local back = Save.decode(text)
		log("save: %d bytes, round trip %s", #text, tostring(back and Save.encode(back) == text))
		Save.write("autotest", state)
		Hold.add(game:stationStorage(A.st), "scrap", 2)
		game:spawnPlayer("ferrous_bastion")
		game:loadFrom("autotest")
		p = game.player
		local st = p.dockState and p.dockState.station
		log("save: loaded -> field %s, flying %s (hold %d m3), docked at %s, hangar %d (%s, hold %d m3), storage scrap %d",
			game.fieldId, p.hull.name, (Hold.cells(p.hold)), st and st.name or "-", #game:hangar(st), game:hangar(st)[1].hull,
			(Hold.cells(game:hangar(st)[1].hold)), Hold.count(game:stationStorage(st), "scrap"))
	end) end
	if t >= 35.89 then once("market", function()
		local Cargo = require("src.ui.cargo")
		local Hold = require("src.inventory.hold")
		local p = game.player
		Cargo.tab = "market"
		Cargo.update(game)
		Hold.add(p.hold, "salvage_kit", 1)
		local L = Cargo.layout(game)
		local mine, trade, shelf
		for _, gr in ipairs(L.grids) do
			if gr.side.ship and not mine then mine = gr end
			if gr.side.trade then trade = gr end
			if gr.side.market then shelf = gr end
		end
		local kit
		for _, s in ipairs(mine.g.stacks) do if s.id == "salvage_kit" then kit = s end end
		local function at(gr, cx, cy) return gr.x + (cx + 0.5) * L.cs, gr.y + (cy + 0.5) * L.cs end
		local kx, ky = at(mine, kit.x, kit.y)
		Cargo.mousepressed(game, kx, ky, 2)       -- right-click: onto the trade grid
		-- drag the shelf's first stack onto the trade grid
		local want = shelf.g.stacks[1]
		A.boughtId, A.credits0 = want.id, game.universe.credits
		local wx, wy = at(shelf, want.x, want.y)
		Cargo.mousepressed(game, wx, wy, 1)
		local hx, hy = at(trade, 4, 3)
		Cargo.mousereleased(game, hx, hy, 1)
		local owners = {}
		for _, s in ipairs(trade.g.stacks) do table.insert(owners, s.id .. ":" .. tostring(s.owner)) end
		local get, pay = game.tradeTotals(Cargo.trade)
		-- a station stack can't go into your hold
		local back = trade.g.stacks[#trade.g.stacks]
		local bx, by = at(trade, back.x, back.y)
		Cargo.mousepressed(game, bx, by, 1)
		local mx, my = at(mine, mine.g.w - 1, mine.g.h - 1)
		Cargo.mousereleased(game, mx, my, 1)
		local still = 0
		for _, s in ipairs(trade.g.stacks) do if s.owner == "station" then still = still + 1 end end
		log("market: %s at %s, %s; trade grid %s; you get %d, you pay %d, problem %s; station goods kept off your hold %s",
			game.player.dockState.station.name, game.fieldId, require("src.hud").credits(A.credits0), table.concat(owners, ", "),
			get, pay, tostring(game:tradeProblem(A.st, Cargo.trade)), tostring(still == 1))
		local sx, sy = at(shelf, shelf.g.stacks[1].x, shelf.g.stacks[1].y)
		love.mouse.setPosition(sx, sy)            -- (hover for the tooltip)
		shot("15_market")
	end) end
	if t >= 35.91 then once("market_trade", function()
		local Cargo = require("src.ui.cargo")
		local Hold = require("src.inventory.hold")
		local p = game.player
		local L = Cargo.layout(game)
		local tside
		for _, sd in ipairs(L.sides) do if sd.trade then tside = sd end end
		local c = tside.complete
		Cargo.mousepressed(game, c.x + 4, c.y + 4, 1)
		local u = game.universe
		local mk = game:stationMarket(A.st)
		local resale
		for _, s in ipairs(mk.hold.grids[1].stacks) do if s.resale then resale = s end end
		local function stock(id)
			local n = 0
			for _, s in ipairs(mk.hold.grids[1].stacks) do if s.id == id and not s.resale then n = n + s.n end end
			return n
		end
		local stockAfter = stock(A.boughtId)
		log("market: completed -> credits %d -> %d, hold has %s x%d, trade grid empty %s, shelf resale %s (sold on in %.0f s)",
			A.credits0, u.credits, A.boughtId, Hold.count(p.hold, A.boughtId) + Hold.count(game:stationStorage(A.st), A.boughtId),
			tostring(#Cargo.trade.grids[1].stacks == 0), resale and resale.id or "none", resale and (resale.resale - u.clock) or 0)
		Cargo.update(game)                       -- (the restock timer starts)
		u.clock = u.clock + 2000
		Cargo.update(game)
		resale = nil
		for _, s in ipairs(mk.hold.grids[1].stacks) do if s.resale then resale = s end end
		log("market: 2000 s later -> %s stock %d -> %d, resale %s", A.boughtId, stockAfter, stock(A.boughtId), resale and "still there" or "sold on")
		-- a loaded container sells with what's in it; Clear sends it home.
		-- (storage is behind the left panel's Storage tab)
		L = Cargo.layout(game)
		local pk = L.sides[1].picks[2]
		Cargo.mousepressed(game, pk.x + 4, pk.y + 4, 1)
		L = Cargo.layout(game)
		log("market: left panel tabs -> showing %s (%d panels)", L.sides[1].title, #L.sides)
		local storage = game:stationStorage(A.st)
		local inner = Hold.new({ { key = "main", name = "Container", w = 8, h = 4 } })
		Hold.add(inner, "rounds_s_crate", 50)
		Hold.placeStack(storage, { id = "cargo_container", n = 1, inner = inner })
		L = Cargo.layout(game)
		for _, gr in ipairs(L.grids) do
			if gr.side.storage then
				for _, s in ipairs(gr.g.stacks) do
					if s.id == "cargo_container" then
						Cargo.mousepressed(game, gr.x + (s.x + 0.5) * L.cs, gr.y + (s.y + 0.5) * L.cs, 1, { ctrl = true })
					end
				end
			end
		end
		local get = game.tradeTotals(Cargo.trade)
		Cargo.clearTrade(game)
		local home = false
		for _, s in ipairs(storage.grids[1].stacks) do if s.inner == inner then home = true end end
		log("market: loaded container (50 light rounds) sells for %d; Clear sent it home with its cargo %s", get, tostring(home))
		-- leaving the tab sends goods home too
		L = Cargo.layout(game)
		for _, gr in ipairs(L.grids) do
			if gr.side.storage then
				local s = gr.g.stacks[1]
				Cargo.mousepressed(game, gr.x + (s.x + 0.5) * L.cs, gr.y + (s.y + 0.5) * L.cs, 1, { ctrl = true })
			end
		end
		local onTable = #Cargo.trade.grids[1].stacks
		shot("16_market_storage")
		Cargo.marketLeft = "hold"
		Cargo.tab = "cargo"
		Cargo.update(game)
		local state = game:saveState()
		local sk = state.stations[A.st.key]
		log("market: left the tab with %d stack(s) on the grid -> %d left; save has credits %d, clock %.0f, shelf %s",
			onTable, #Cargo.trade.grids[1].stacks, state.credits, state.clock, tostring(sk.market ~= nil))
		game:undock()
		A.holdBefore = Hold.cells(p.hold)
	end) end
	if t >= 35.95 then once("travel", function()
		-- Earth, into the capture ring of the driver to Mars.
		local Ship = require("src.ship")
		game:loadField("earth", { player = Ship.record(game.player) })
		local p = game.player
		A.credits1 = game.universe.credits
		local g = game:findDriver()
		local gx, gy = game:driverBreech(g)
		local dx, dy = math.cos(g.angle), math.sin(g.angle)
		-- come up the approach at a given speed and see what the beam does
		local function approach(speed)
			p.driverTractor, p.driverCooldown, game.driverMenu = nil, 0, nil
			-- the driver rides a track round the planet: come at it where it is now,
			-- moving with it
			gx, gy = g.body:getPosition()
			dx, dy = math.cos(g.angle), math.sin(g.angle)
			local gvx, gvy = g.body:getLinearVelocity()
			p.body:setPosition(gx - dx * 3000, gy - dy * 3000)
			p.body:setAngle(g.angle)
			p.body:setLinearVelocity(gvx + dx * speed, gvy + dy * speed)
			p.body:setAngularVelocity(0)
			local t0, got, overshot = game.time, nil, false
			for i = 1, 120 * 20 do
				p.intent.thrust = 0
				game:step(1 / 120)
				if game.driverMenu then got = i / 120 break end
				if p.driverCooldown and p.driverCooldown > 0 then overshot = true break end
			end
			game.time = t0
			return got, overshot
		end
		local got, over = approach(2400)
		log("travel: up the approach at 2400 px/s -> locked %s, overshot %s", tostring(got ~= nil), tostring(over))
		got, over = approach(500)
		log("travel: up the approach at 500 px/s -> locked after %.1f s, overshot %s", got or -1, tostring(over))
		game.camera.x, game.camera.y = p.body:getPosition()
		game.camera.zoom = 0.25
	end) end
	if t >= 36.1 then once("travel_pick", function()
		log("travel: driver window open %s; fares venus %d, mars %d, jupiter %d cr", tostring(game.driverMenu ~= nil),
			game:driverFare("venus"), game:driverFare("mars"), game:driverFare("jupiter"))
		shot("13b_orrery")
	end) end
	if t >= 36.2 then once("travel_fire", function()
		game:fireDriver("mars")
		-- the barrel swings round to Mars's bearing before it fires: run
		-- the launch through here
		local Fields = require("src.fields")
		local g, p = game:findDriver(), game.player
		local c = game.universe.clock
		local ax, ay = Fields.orbitPos("earth", c)
		local bx, by = Fields.orbitPos("mars", c)
		local want = math.atan2(by - ay, bx - ax)
		local t0, steps, err = game.time, 0, nil
		while p.launch and steps < 120 * 12 do
			game:step(1 / 120)
			steps = steps + 1
			if p.launch and p.launch.t > T.driverAlign and not err then
				err = math.abs((g.angle - want + math.pi) % (2 * math.pi) - math.pi)
			end
		end
		game.time = t0
		log("travel: barrel off Mars's bearing by %.3f rad when it fired, launch took %.1f s", err or -1, steps / 120)
	end) end
	if t >= 38.9 then once("travel_flight", function()
		local f = game.flight or game.lastFlight
		log("travel: fired by the driver -> now in %s (%s)", game.fieldId, game.trip and ("lane to " .. game.trip.to) or "no lane")
		log("travel: flying now %s, clock %.0f; in flight %s (or done), %s -> %s, %.2f AU, %.1f s of trip view", tostring(game.flight ~= nil), game.universe.clock, tostring(f ~= nil), f and f.from or "-", f and f.to or "-", f and f.au or 0, f and f.dur or 0)
		shot("14_flight")
		A.clock0 = game.universe.clock
	end) end
	if t >= 42.45 then once("flight_view", function()
		-- hold a trip view open for a frame to see it drawn
		-- (it ends a step later and lands you at Mars's catcher again)
		game.flight = { from = "earth", to = "mars", au = 0.96, t = 2, dur = 2.01, ship = require("src.ship").record(game.player) }
		shot("14_flight")
	end) end
	if t >= 42.5 then once("catch_arrive", function()
		local p = game.player
		local g = game:findDriver()
		local px, py = p.body:getPosition()
		local gx, gy = game:driverBreech(g)
		local vx, vy = p.body:getLinearVelocity()
		local rings = 0
		for _, e in ipairs(game.entities) do if e.kind == "catchring" then rings = rings + 1 end end
		log("catch: arrived in %s, catching %s, %.0f px from the driver at %.0f px/s, %d rings, clock +%.0f",
			game.fieldId, tostring(p.catching), math.sqrt((px - gx) ^ 2 + (py - gy) ^ 2), math.sqrt(vx * vx + vy * vy), rings, game.universe.clock - (A.clock0 or 0))
		shot("15_catch")
		-- thread every ring: put the ship just short of each in turn
		A.ringQueue = {}
		for _, e in ipairs(game.entities) do if e.kind == "catchring" then table.insert(A.ringQueue, e) end end
		table.sort(A.ringQueue, function(a, b) return a.index > b.index end)
	end) end
	for k = 1, 8 do
		if t >= 42.55 + k * 0.05 then once("catch_ring" .. k, function()
			local e = A.ringQueue and A.ringQueue[k]
			if not e then return end
			local p = game.player
			p.body:setPosition(e.body:getPosition())
		end) end
	end
	if t >= 43.0 then once("catch_bay", function()
		local p = game.player
		local vx, vy = p.body:getLinearVelocity()
		A.bayIn = math.sqrt(vx * vx + vy * vy)
		local g = game:findDriver()
		-- into the bay mouth (not on top of the driver's own hull)
		local gx, gy = game:driverBreech(g)
		local r = g.radius + 60
		p.body:setPosition(gx + math.cos(g.angle) * r, gy + math.sin(g.angle) * r)
	end) end
	if t >= 43.1 then once("catch_done", function()
		local p = game.player
		local vx, vy = p.body:getLinearVelocity()
		vx, vy = vx - (p.flowX or 0), vy - (p.flowY or 0)
		log("catch: through every ring at %.0f px/s into the bay -> catching %s, now %.0f px/s against the current, %d of %d rings passed",
			A.bayIn or 0, tostring(p.catching), math.sqrt(vx * vx + vy * vy), (function()
				local n = 0
				for _, e in ipairs(game.entities) do if e.kind == "catchring" and e.passed then n = n + 1 end end
				return n
			end)(), A.ringQueue and #A.ringQueue or 0)
		local Ship = require("src.ship")
		game:loadField("jupiter", { player = Ship.record(p) })
		local q = game.player
		q.body:setPosition(0, game.well.radius - (game.well.crushStart or T.crushStart) - 4000)
		A.armor0 = q.armor
	end) end
	if t >= 43.6 then once("crush", function()
		local q = game.player
		log("crush: jupiter radius %.0f, armor %.1f -> %.1f after 0.5 s inside", game.well.radius, A.armor0 or -1, q.dead and 0 or q.armor)
		shot("16_jupiter")
		game:damage(q, 1e9)
	end) end
	if t >= 43.7 then once("respawn", function()
		local state = game.state
		game:respawn()
		local p = game.player
		local st = p.dockState and p.dockState.station
		log("respawn: state %s -> %s, field %s, docked at %s, flying %s", state, game.state, game.fieldId, st and st.name or "-", p.hull.name)
	end) end
	if t >= 43.75 then once("pause", function()
		local Pause = require("src.ui.pause")
		love.keypressed("escape")
		A.pauseAt, A.pauseWall = game.time, love.timer.getTime()
		log("pause: Esc -> paused %s", tostring(Pause.isOpen()))
		shot("17_pause")
	end) end
	if A.pauseWall and love.timer.getTime() > A.pauseWall + 0.3 then once("unpause", function()
		local Pause = require("src.ui.pause")
		log("pause: 0.3 s later game time moved %.3f s", game.time - A.pauseAt)
		love.keypressed("escape")
		log("pause: Esc again -> paused %s", tostring(Pause.isOpen()))
	end) end
	-- Moons: out through each planet's gate, across, into the moon's map,
	-- dock if it has a station, and back out through its gate home.
	if t >= 43.78 then once("moons", function()
		local Fields = require("src.fields")
		local function stepN(n) for _ = 1, n do game:step(1 / 60) end end
		-- off the map's edge through the on-ramp toward `to`, then fly the
		-- highway to its far end
		local function through(to)
			local p = game.player
			for _, g in ipairs(game.moonGates or {}) do
				if g.to == to then
					local d = game.arenaRadius - 100
					p.body:setPosition(math.cos(g.a) * d, math.sin(g.a) * d)
					p.body:setLinearVelocity(math.cos(g.a) * 800, math.sin(g.a) * 800)
					stepN(os.getenv("MOONSHOT") == "depart" and 90 or math.ceil(T.departTime * 60) + 4)
					return game.lane ~= nil
				end
			end
		end
		local function across()
			local lane = game.lane
			if not lane then return end
			local p = game.player
			p.runup, p.laneCarry = nil, nil
			local x, y = game:fromLane(lane.half - 300, -T.laneWidth / 2)
			local h = game:laneHeading(lane.half)
			p.body:setPosition(x, y)
			p.body:setLinearVelocity(math.cos(h) * 900, math.sin(h) * 900)
			stepN(10)
		end
		local ids = {}
		for id in pairs(Fields.moons) do table.insert(ids, id) end
		table.sort(ids)
		for _, id in ipairs(ids) do
			local m = Fields.moons[id]
			game:respawn()
			game:loadField(m.parent, { player = Ship.record(game.player) })
			game.state = "playing"
			local ok1 = through(id)
			local mid = game.fieldId .. (game.lane and (" " .. math.floor(game.lane.half * 2) .. " px") or "")
			across()
			local inMoon = game.fieldId
			local st
			for _, e in ipairs(game.entities) do if e.kind == "station" and e.dock then st = e break end end
			local docked = "no station"
			if st then
				game:dockInstantly(game.player, st)
				docked = st.name .. (game.player.dockState and " (docked)" or " (FAILED)")
				game:undock()
				stepN(30)
			end
			game.state = "playing"
			through(m.parent)
			local back = game.fieldId
			across()
			log("moon %s: on-ramp %s -> %s -> %s, station %s, back out -> %s -> %s",
				id, tostring(ok1), mid, inMoon, docked, back, game.fieldId)
		end
		-- the handoff: off Earth's edge onto the highway to Luna, a moment in
		game:respawn()
		game:loadField("earth", { player = Ship.record(game.player) })
		game.state = "playing"
		through("luna")
		local p = game.player
		game.camera.x, game.camera.y = p.body:getPosition()
		if os.getenv("MOONSHOT") ~= "depart" then game.camera.zoom = os.getenv("MOONSHOT") == "luna" and 0.03 or 0.05 end
		if os.getenv("MOONSHOT") == "luna" then
			game:loadField("luna", { player = Ship.record(p) })
			game.camera.x, game.camera.y = 0, 0
		end
		do
			local q = game.player
			local vx, vy = q.body:getLinearVelocity()
			if game.lane then
				local ps, pn, ph = game:toLane(q.body:getPosition())
				log("handoff: in transit in %s, %.0f px/s, %.0f px along (mouth at %.0f), %.0f off the median, lane heading %.2f, flying %.2f",
					game.fieldId, speed(q), ps, -game.lane.half, pn, ph, math.atan2(vy, vx))
			else
				log("departure: still in %s at %.0f px/s, zoom %.3f", game.fieldId, speed(q), game.camera.zoom)
			end
		end
		shot("18_moon_handoff")
	end) end
	if t >= 43.8 then once("quit", function()
		log("done: %d entities, %d projectiles, %d effects", #game.entities, #game.projectiles, #game.effects)
		love.event.quit()
	end) end
end

return A
