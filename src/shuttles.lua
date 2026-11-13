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

	Kill one on the way up and the station never gets that cargo; every
	whole unit's worth of pods shot down drops that unit for the taking. Shuttles are the area's own protected traffic, so shooting one
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

-- Into the station's stock, as the facility would have put it. Each unit
-- made is shared out over T.shuttlePodsPerUnit pods (the facilities make a
-- unit every few minutes; one pod a unit was hardly any traffic), so a pod
-- carries a share; shares add up in u.shuttles.credit and whole units go on
-- the shelf.
local function deliver(u, key, cargo)
	local Stock = require("src.stockpile")
	local s = state(u)
	s.credit = s.credit or {}
	local c = s.credit[key] or {}
	s.credit[key] = c
	for id, n in pairs(cargo) do
		if n > 0 then
			c[id] = (c[id] or 0) + n
			local whole = math.floor(c[id] + 1e-6)
			if whole > 0 then
				c[id] = max(0, c[id] - whole)
				Stock.add(u, key, id, whole); require("src.economy").stat(u, "made", id, whole)
			end
		end
	end
end
-- A pod shot down: its share is lost to the station, and once the shares
-- lost add up to a whole unit, that unit falls out of the wreck.
local function lose(game, e, key, cargo)
	local s = state(game.universe)
	s.lost = s.lost or {}
	local c = s.lost[key] or {}
	s.lost[key] = c
	local x, y = e.body:getPosition()
	for id, n in pairs(cargo) do
		c[id] = (c[id] or 0) + n
		local whole = math.floor(c[id] + 1e-6)
		if whole > 0 then c[id] = max(0, c[id] - whole); game:spawnPickup(x, y, id, whole) end
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

-- Pods are cosmetic traffic: always sensors, so nothing bumps them or is
-- bumped by them (shots still find them, Game:raycast sees sensors), and
-- kinematic while a script flies them.
local function setGhost(e, on)
	for _, f in ipairs(e.body:getFixtures()) do f:setSensor(true) end
	e.body:setType(on and "kinematic" or "dynamic")
end

-- A station dock's door and runway point, in the world, for the dock nearest x, y.
local function dockPoints(game, st, x, y)
	local best, bestD
	for _, d in ipairs(st.docks or { st.dock }) do
		local px, py = game.dockWorld(st, 1, d.x2 + d.runway * 0.6, 0, d)
		local dd = (px - x) ^ 2 + (py - y) ^ 2
		if not best or dd < bestD then best, bestD = d, dd end
	end
	local d = best
	local dx, dy = game.dockWorld(st, 1, d.x2 - 20, 0, d)
	local rx, ry = game.dockWorld(st, 1, d.x2 + d.runway * 0.6, 0, d)
	return dx, dy, rx, ry, game.dockAngle(st, 1, d)
end

-- Into the station's door and straight back out: no tractor, no dock
-- booked, nothing a real ship waits on. The load is stocked at the door.
local function animateDock(game, e, dt)
	local sh = e.shuttle
	local st = sh.station
	if not st or st.removed then sh.gone = true; return end
	sh.t = sh.t + dt
	if sh.phase == "inside" then
		-- out of sight in the station a while, riding along at its door
		local x, y = e.body:getPosition()
		local dx, dy = dockPoints(game, st, x, y)
		e.body:setLinearVelocity((dx - x) / dt, (dy - y) / dt)
		e.mainBurn = 0
		if sh.t >= sh.stay then sh.phase, sh.t, e.podHidden = "leave", 0, nil end
		return
	end
	local f = min(1, sh.t / T.shuttleDockTime)
	local x, y = e.body:getPosition()
	local dx, dy, rx, ry, a = dockPoints(game, st, sh.fromX or x, sh.fromY or y)
	sh.fromX, sh.fromY = sh.fromX or x, sh.fromY or y
	local inward = sh.phase == "enter"
	local k = f * f * (3 - 2 * f)
	local from_x, from_y = inward and sh.fromX or dx, inward and sh.fromY or dy
	local to_x, to_y = inward and dx or rx, inward and dy or ry
	local tx, ty = from_x + (to_x - from_x) * k, from_y + (to_y - from_y) * k
	e.body:setLinearVelocity((tx - x) / dt, (ty - y) / dt)
	e.body:setAngle(inward and a + pi or a)
	e.body:setAngularVelocity(0)
	e.drawScale = inward and 1 - 0.4 * k or 0.6 + 0.4 * k
	e.mainBurn = inward and 0.2 or 0.6
	e.retroBurn, e.sideBurn, e.foreBurn, e.turnBurn = 0, 0, 0, 0
	if f >= 1 then
		sh.t, sh.fromX, sh.fromY = 0, nil, nil
		if inward then
			S.docked(game, e, st)
			sh.phase, sh.stay, e.podHidden = "inside", T.shuttleStay[1] + random() * (T.shuttleStay[2] - T.shuttleStay[1]), true
		else
			sh.phase, e.drawScale = nil, nil
			setGhost(e, false)
			local vx, vy = st.body:getLinearVelocityFromWorldPoint(tx, ty)
			e.body:setLinearVelocity(vx + cos(a) * 80, vy + sin(a) * 80)
		end
	end
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
	-- its share of a unit rides in the flight record, not the hold
	local e = Ship.new(game, { hull = def.hull, loadout = def.loadout, cargo = {}, team = def.team or 3,
		x = w.x + cos(a) * r0, y = w.y + sin(a) * r0, angle = a, enemy = def })
	local s = state(u)
	s.n = s.n + 1
	local flight = { id = "shuttle/" .. s.n, key = key, cargo = cargo }
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
-- comes down), engine lit, riding round with the planet's current.
function S.animate(game, e, dt)
	local ph = e.shuttle.phase
	if ph == "enter" or ph == "inside" or ph == "leave" then return animateDock(game, e, dt) end
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
	e.reentry = nil
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

-- At its station's door: the load goes into stock, and it heads back down
-- to a pad.
function S.docked(game, e, st)
	local sh = e.shuttle
	local s = state(game.universe)
	local flight = s.flights[sh.flight]
	if flight then deliver(game.universe, flight.key, flight.cargo); s.flights[sh.flight] = nil end
	sh.down = true
	local a = padBearing(game, st)
	sh.padA = a
	local w = game.well
	local R = cruiseR(game)
	local pad = { kind = "waypoint", removed = false, body = {
		getPosition = function() return w.x + cos(a) * R, w.y + sin(a) * R end,
		getLinearVelocityFromWorldPoint = function() return game:flowAt(w.x + cos(a) * R, w.y + sin(a) * R) end,
	} }
	e.route, e.routeIndex = { pad }, 1
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
			if not e.removed then lose(game, e, f.key, f.cargo) end
			s.flights[id] = nil
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
			local share = 1 / T.shuttlePodsPerUnit
			if flying < T.shuttleMax and clock >= s.next[key] and total(cargo) >= share - 1e-6 then
				-- one pod's share at a time, the waiting goods taken by kind
				local load, room = {}, share
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
	-- up: on its station's runway, it slips in at the door
	for _, e in ipairs(game.entities) do
		local sh = e.shuttle
		if sh and not sh.down and not sh.phase and not e.dead and not e.removed then
			local st = e.route and e.route[1]
			if st and not st.removed and st.body then
				local x, y = e.body:getPosition()
				local _, _, rx, ry = dockPoints(game, st, x, y)
				if (x - rx) ^ 2 + (y - ry) ^ 2 < 350 ^ 2 then
					sh.phase, sh.t, sh.station = "enter", 0, st
					setGhost(e, true)
				end
			end
		end
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
