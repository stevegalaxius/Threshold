return function(game)
	local T = require("src.tuning")
	local Fields = require("src.fields")
	local Ship = require("src.ship")
	local checks = 0
	local function check(ok, message) assert(ok, message); checks = checks + 1 end
	local function strength(x, y)
		local ax, ay = game:surfacePullAt(x, y)
		return math.sqrt(ax * ax + ay * ay)
	end
	-- Every destination with a surface has the same altitude-based response;
	-- radius sets the reach, rather than multiplying tiny-world acceleration.
	for _, id in ipairs(Fields.list) do
		local F = Fields[id]
		if F.planetR then
			local R = F.planetR
			game.well = { x = 0, y = 0, radius = R, gas = F.gas }
			local reach = math.min(T.surfacePullRange, R * 0.5)
			check(strength(R + reach + 1, 0) == 0, id .. ": pull extends beyond its band")
			check(strength(R + reach * 0.25, 0) > strength(R + reach * 0.75, 0), id .. ": pull does not build with proximity")
			check(strength(R, 0) > 0, id .. ": no surface pull at rest")
			check(strength(0, R) == strength(R, 0), id .. ": pull depends on approach direction")
		end
	end
	game.well = nil
	check(strength(0, 100) == 0, "open space has surface gravity")

	-- Real physics: a stationary ship starts sinking, outward thrust can
	-- recover it, and fully docked cloud-city ships remain held safely.
	for _, id in ipairs({ "earth", "deimos", "jupiter", "uranus" }) do
		game:loadField(id)
		local p, w = game.player, game.well
		local height = w.gas and -300 or (id == "deimos" and 250 or 1000)
		p.body:setPosition(w.radius + height, 0)
		p.body:setLinearVelocity(0, 0)
		game:applySurfacePull()
		game.world:update(1 / 120)
		local vx = p.body:getLinearVelocity()
		check(vx < 0, id .. ": stationary ship did not start sinking")
		p.body:setAngle(0)
		p.spool = 1
		p.intent.thrust, p.intent.strafe = 1, 0
		p.intent.aimX, p.intent.aimY = p.body:getX() + 10000, 0
		Ship.fly(p, 1 / 120)
		game:applySurfacePull()
		game.world:update(1 / 120)
		check(p.body:getLinearVelocity() > 0, id .. ": starter ship cannot thrust away from the surface")
		if w.gas then
			local city
			for _, e in ipairs(game.entities) do if e.city then city = e break end end
			check(city ~= nil, "cloud city missing")
			-- Discard contacts from the isolated physics probes above before
			-- resuming the full simulation (which can put distant rocks to sleep).
			game.contacts = {}
			game:clearEnemies()
			local d = city.dock
			local x, y = game.dockWorld(city, 1, d.x2 + p.halfLength + 180, 0)
			p.body:setPosition(x, y)
			p.body:setLinearVelocity(city.body:getLinearVelocity())
			p.intent.thrust, p.intent.strafe, p.intent.boost = 0, 0, false
			game:updateDocking(1 / 120)
			check(p.dockState and p.dockState.phase == "tractor", "cloud-city approach did not capture")
			for _ = 1, 1800 do
				game:step(1 / 120)
				if p.dead or (p.dockState and p.dockState.done) then break end
			end
			check(not p.dead and p.dockState and p.dockState.done,
				"surface pull prevents a controlled cloud-city docking")
			game:dockInstantly(p, city)
			p.body:setLinearVelocity(0, 0)
			game:applySurfacePull()
			game.world:update(1 / 120)
			check(p.body:getLinearVelocity() == 0, "docked cloud-city ship is falling")
		end
	end
	-- An irregular outline's local surface, rather than the nominal radius,
	-- controls the pull onset. This simple long rock has its end at x=1600.
	game.well = { x = 0, y = 0, radius = 1000,
		planet = { rock = { outline = { -1600, -600, 1600, -600, 1600, 600, -1600, 600 } } } }
	check(strength(1750, 0) > 0, "rocky surface pull ignores protruding terrain")
	check(strength(2150, 0) == 0, "rocky surface band has incorrect reach")
	local saved = T.surfacePull
	T.surfacePull = 0
	check(strength(1600, 0) == 0, "surface pull tuning cannot disable the force")
	T.surfacePull = saved
	game.well = nil
	print(("surface pull: %d checks passed"):format(checks))
end
