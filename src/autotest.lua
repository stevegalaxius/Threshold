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
	local it = { thrust = 0, strafe = 0, firePrimary = false, fireSecondary = false, boost = false, aimX = 0, aimY = 0 }
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
			it.fireSecondary = (math.floor(t * 2) % 7 == 0)
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
				p.armor, p.stats.armor, p.cargo.rounds_s or 0, p.cargo.missile_s or 0, p.holdUsed, p.stats.hold, game.kills, #game.pickups)
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
		log("Bastion shells left: %d (started 30), mass now %.1f t; parked target at 1430 px: %s, armor %.0f/%.0f",
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
		shot("06_lasers")
	end) end
	if t >= 34 then once("quit", function()
		log("done: %d entities, %d projectiles, %d effects", #game.entities, #game.projectiles, #game.effects)
		love.event.quit()
	end) end
end

return A
