--[[
	Surface shuttles: what a planet's or moon's surface industry makes,
	carried up to its station while the player is there to see it.

	A facility flagged surface=true (src/world_layout.lua) normally puts its
	output straight into its station's stock (src/industry_outputs.lua).
	While the player is in that station's area, the output is held back
	instead as a load waiting on the surface (u.shuttles.waiting[key]).
	Every so often a shuttle lifts off with that load, flies up to the
	station and docks; the cargo goes into stock when it does. Then it
	launches again, flies back down and lands.

	Kill one on the way up and the station never gets that cargo: it's in
	the wreck. Shuttles are the area's own protected traffic, so shooting one
	costs standing with the faction that owns the area and raises heat at its
	station (src/reputation.lua).

	Nothing is lost or made twice: a load in flight is recorded in
	u.shuttles.flights until it docks or the shuttle dies, and anything held
	back for an area the player isn't in (left, saved and loaded, died) is
	delivered at once. Offline, the economy runs exactly as before.
]]
local T = require("src.tuning")
local L = require("src.locations")

local S = { game = nil }
local live = setmetatable({}, { __mode = "v" })   -- flight id -> its ship
local cos, sin, pi, sqrt, max, min, random = math.cos, math.sin, math.pi, math.sqrt, math.max, math.min, love.math.random

local function state(u)
	u.shuttles = u.shuttles or { waiting = {}, flights = {}, next = {}, n = 0 }
	return u.shuttles
end

local function addTo(t, cargo) for id, n in pairs(cargo) do if n > 0 then t[id] = (t[id] or 0) + n end end end
local function total(cargo) local n = 0; for _, v in pairs(cargo) do n = n + v end; return n end

-- Into the station's stock, as the facility would have put it.
local function deliver(u, key, cargo)
	local Stock = require("src.stockpile")
	for id, n in pairs(cargo) do
		if n > 0 then Stock.add(u, key, id, n); require("src.economy").stat(u, "made", id, n) end
	end
end

-- Is recipe c at station key made by one of its surface facilities?
function S.surfaceRecipe(key, c)
	local I = require("src.industry")
	for id, inst in pairs(I.installations(key)) do
		if inst.surface then
			for _, r in ipairs(I.definition(id, inst).recipes) do if r == c.id then return true end end
		end
	end
	return false
end

-- From src/industry_outputs.lua: hold a surface facility's output back for
-- a shuttle while the player is in its area. True if it took the goods.
function S.divert(u, key, item, n, c)
	local g = S.game
	if not g or g.universe ~= u or not c or n <= 0 or not g.well or g.flight then return false end
	local place = L.byId[key]
	if not place or place.area ~= g.fieldId or not S.surfaceRecipe(key, c) then return false end
	local w = state(u).waiting
	w[key] = w[key] or {}
	w[key][item] = (w[key][item] or 0) + n
	return true
end

-- How much of item is on its way to key (waiting or in flight), so the
-- facility doesn't overfill the station's shelf while it's being carried.
function S.pending(u, key, item)
	local st = u.shuttles
	if not st then return 0 end
	local n = st.waiting[key] and st.waiting[key][item] or 0
	for _, f in pairs(st.flights) do if f.key == key and f.cargo[item] then n = n + f.cargo[item] end end
	return n
end

-- The surface's distance from the planet's centre along bearing a (a rocky
-- world's outline isn't a circle).
local function surfaceR(game, a)
	local w = game.well
	local rock = w.planet and w.planet.rock
	if rock then
		local nx, ny = cos(a), sin(a)
		local o = rock.outline
		for i = 1, #o, 2 do
			local j = (i + 1) % #o + 1
			local ax, ay = o[i], o[i + 1]
			local ex, ey = o[j] - ax, o[j + 1] - ay
			local cross = nx * ey - ny * ex
			if math.abs(cross) > 1e-6 then
				local d = (ax * ey - ay * ex) / cross
				local along = (ax * ny - ay * nx) / cross
				if d > 0 and along >= 0 and along <= 1 then return d end
			end
		end
	end
	return w.radius
end
-- The altitude ships hold above the gravity band (src/ai.lua flies no lower).
local function cruiseR(game)
	local w = game.well
	return w.radius + min(T.surfacePullRange, w.radius * 0.5) + 500
end

local function setGhost(e, on)
	for _, f in ipairs(e.body:getFixtures()) do f:setSensor(on) end
	e.body:setType(on and "kinematic" or "dynamic")
	e.driverProtected = on or nil   -- nothing fires from a shuttle mid-climb
end

-- A landing pad a little way round from the station's bearing.
local function padBearing(game, st)
	local w = game.well
	local x, y = st.body:getPosition()
	return math.atan2(y - w.y, x - w.x) + (random() - 0.5) * T.shuttleSpread
end

-- Lift off from the surface with a load for station key.
local function launch(game, key, cargo)
	local st = game:locationEntity(key)
	if not st then return false end
	local u, w = game.universe, game.well
	local def = require("src.data").enemies.surface_shuttle
	local a = padBearing(game, st)
	local r0 = surfaceR(game, a) - 20
	local Ship = require("src.ship")
	local e = Ship.new(game, { hull = def.hull, loadout = def.loadout, cargo = cargo, team = def.team or 3,
		x = w.x + cos(a) * r0, y = w.y + sin(a) * r0, angle = a, enemy = def })
	-- whatever didn't fit stays on the ground for the next one
	local back = {}
	for id, n in pairs(e.holdOverflow or {}) do back[id] = n end
	e.holdOverflow = {}
	local carried = {}
	for id, n in pairs(cargo) do carried[id] = n - (back[id] or 0) end
	if total(carried) <= 0 then return false end
	local s = state(u)
	for id, n in pairs(back) do s.waiting[key][id] = (s.waiting[key][id] or 0) + n end
	s.n = s.n + 1
	local flight = { id = "shuttle/" .. s.n, key = key, cargo = carried }
	s.flights[flight.id] = flight
	table.insert(game.entities, e)
	e.name = def.name
	e.route, e.routeIndex = { st }, 1
	e.shuttle = { flight = flight.id, key = key, phase = "launch", t = 0, a = a, r0 = r0, r1 = cruiseR(game) }
	live[flight.id] = e
	setGhost(e, true)
	e.drawScale = T.shuttleGroundScale
	game:spark(e.body:getX(), e.body:getY(), 18, { 0.75, 0.68, 0.55 })
	return true
end

-- The scripted climb from the pad and descent onto it: the shuttle grows
-- from a speck on the ground to full size as it rises (and shrinks as it
-- comes down), engine lit, with a burn through the air on a world that
-- has an atmosphere, riding round with the planet's current.
function S.animate(game, e, dt)
	local sh, w = e.shuttle, game.well
	if not w then sh.phase = nil; setGhost(e, false); return end
	sh.t = sh.t + dt
	local up = sh.phase == "launch"
	local f = min(1, sh.t / (up and T.shuttleLaunchTime or T.shuttleLandTime))
	-- climbing: slow off the pad, then quicker; landing: braking to touch down
	local k = up and f * f * (3 - 2 * f) or 1 - (1 - f) * (1 - f)
	local r = up and sh.r0 + (sh.r1 - sh.r0) * k or sh.r1 + (sh.r0 - sh.r1) * k
	-- carried round by the current like everything else at that height
	sh.a = sh.a + game:currentSpeed(r) / max(r, 1) * dt
	local tx, ty = w.x + cos(sh.a) * r, w.y + sin(sh.a) * r
	local x, y = e.body:getPosition()
	e.body:setLinearVelocity((tx - x) / dt, (ty - y) / dt)
	-- nose out going up; going down, nose up too, braking on the main engine
	e.body:setAngle(sh.a)
	e.body:setAngularVelocity(0)
	local height = up and k or 1 - k
	e.drawScale = T.shuttleGroundScale + (1 - T.shuttleGroundScale) * height
	e.mainBurn = up and 1 or (0.4 + 0.6 * (1 - height))
	e.retroBurn, e.sideBurn, e.foreBurn, e.turnBurn = 0, 0, 0, 0
	e.intent.thrust, e.intent.strafe, e.intent.boost = 0, 0, false
	if w.atmo and height < 0.45 then
		-- through the air: the sheath on the side it's moving toward
		e.reentry = (0.45 - height) / 0.45 * 0.7
		e.reentryX, e.reentryY = (up and 1 or -1) * cos(sh.a), (up and 1 or -1) * sin(sh.a)
	else e.reentry = nil end
	if f >= 1 then
		e.reentry, e.drawScale = nil, nil
		if up then
			sh.phase = nil
			setGhost(e, false)
			local fx, fy = game:flowAt(tx, ty)
			e.body:setLinearVelocity(fx + cos(sh.a) * 60, fy + sin(sh.a) * 60)
		else
			-- down: a puff of dust and it's gone
			game:spark(tx, ty, 18, { 0.75, 0.68, 0.55 })
			sh.gone = true   -- removed in S.update, outside the step's entity loop
		end
	end
end

-- Docked at its station (from Game:finishDocking): the load goes into stock,
-- and after a short stop it will head back down to a pad.
function S.docked(game, e, ds, st)
	local sh = e.shuttle
	local s = state(game.universe)
	local flight = s.flights[sh.flight]
	if flight then deliver(game.universe, flight.key, flight.cargo); s.flights[sh.flight] = nil end
	e.cargo = {}
	if e.hold then require("src.inventory.hold").sync(e.hold, {}) end
	ds.stay = T.shuttleStay * (0.7 + random() * 0.6)
	sh.down = true
	local a = padBearing(game, st)
	sh.padA = a
	local w = game.well
	local R = cruiseR(game)
	local pad = { kind = "waypoint", removed = false, body = {
		getPosition = function() return w.x + cos(a) * R, w.y + sin(a) * R end,
		getLinearVelocityFromWorldPoint = function() return game:flowAt(w.x + cos(a) * R, w.y + sin(a) * R) end,
	} }
	e.route = { st, pad }
end

-- The player hit or killed one: the area's faction takes it personally.
function S.hit(u, e)
	local Rep = require("src.reputation")
	local key = e.shuttle.key
	Rep.addStanding(u, Rep.ofNode(key), T.shuttleStandingPerHit)
	Rep.addHeat(u, key, Rep.T.heatPerHit)
end
function S.killed(u, e)
	local Rep = require("src.reputation")
	Rep.addStanding(u, Rep.ofNode(e.shuttle.key), Rep.T.standingPerKill)
end

-- Every step: settle finished flights, deliver what's held back for areas
-- the player isn't in, start descents and launch new shuttles.
function S.update(game, dt)
	S.game = game
	local u = game.universe
	if not u then return end
	local s = state(u)
	local clock = u.clock
	local here = not game.flight and game.well and game.fieldId
	for id, f in pairs(s.flights) do
		local e = live[id]
		if e and e.dead then
			s.flights[id] = nil                         -- the cargo is in its wreck
		elseif not e or e.removed then
			deliver(u, f.key, f.cargo); s.flights[id] = nil
		end
	end
	local flying = 0
	for _ in pairs(s.flights) do flying = flying + 1 end
	for key, cargo in pairs(s.waiting) do
		local place = L.byId[key]
		if not place or place.area ~= here then
			deliver(u, key, cargo); s.waiting[key] = nil
		elseif total(cargo) > 0 then
			s.next[key] = s.next[key] or clock + T.shuttleFirst * random()
			if flying < T.shuttleMax and (total(cargo) >= T.shuttleLoad or clock >= s.next[key]) then
				-- one load at a time, the waiting goods shared out by kind
				local load, room = {}, T.shuttleLoad
				for id, n in pairs(cargo) do
					local take = min(n, room); if take > 0 then load[id] = take; cargo[id] = n - take; room = room - take end
				end
				if launch(game, key, load) then
					flying = flying + 1
					s.next[key] = clock + T.shuttleInterval[1] + random() * (T.shuttleInterval[2] - T.shuttleInterval[1])
				else addTo(cargo, load); s.next[key] = clock + 10 end
			end
		end
	end
	-- back down: close over its pad, it lands
	for i = #game.entities, 1, -1 do
		local e = game.entities[i]
		if e.shuttle and e.shuttle.gone and not e.removed then game:remove(e) end
	end
	if game.well then
		for _, e in ipairs(game.entities) do
			local sh = e.shuttle
			if sh and sh.down and not sh.phase and not e.dockState and not e.dockExit and not e.dead and not e.removed then
				local w = game.well
				local R = cruiseR(game)
				local px, py = w.x + cos(sh.padA) * R, w.y + sin(sh.padA) * R
				local x, y = e.body:getPosition()
				if (x - px) ^ 2 + (y - py) ^ 2 < 600 ^ 2 then
					sh.phase, sh.t = "land", 0
					sh.a = math.atan2(y - w.y, x - w.x)
					sh.r1 = sqrt((x - w.x) ^ 2 + (y - w.y) ^ 2)
					sh.r0 = surfaceR(game, sh.a) - 20
					setGhost(e, true)
				end
			end
		end
	end
end

return S
