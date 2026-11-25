-- NPC docking and launching under station control.
--
-- The player flies onto the runway and the tractor beam (Game:updateDockedShip,
-- phase "tractor") helps them in. NPCs don't: once one is near the station it
-- is going to, its dock is free and it has somewhere to park, the station
-- takes the ship over completely. The ship stops colliding and glides along a
-- path that rides with the station: round the hull at a safe radius to a
-- marker out on the dock's axis, then straight in to the door, slowing as it
-- goes and turning smoothly to face the door. From there the usual "pull"
-- (into the hangar) or "taxi" (onto an exterior berth) finishes the job.
--
-- Leaving is the mirror: a ship launched from the door glides out along the
-- axis past the hull and is let go there, already moving away.
--
-- NPCs used to fly the whole runway themselves, switching to the beam only
-- once their centre entered a narrow strip over the runway, after the physics
-- step. Long haulers swung their tails into the hull, fast ones hit before
-- the beam caught them, and wrecks left on the approach caused more crashes.
local T = require("src.tuning")

local G = {}
local sqrt, cos, sin, atan2, pi, max, min = math.sqrt, math.cos, math.sin, math.atan2, math.pi, math.max, math.min

G.captureMargin = 900   -- capture ring: this far beyond hull radius + ship half length
G.orbitMargin = 260     -- the path circles the hull this far beyond hull radius + half length
G.cruise = 320          -- top glide speed (px/s, relative to the station)
G.doorSpeed = 60        -- speed arriving at the door
G.accel = 140           -- glide acceleration and braking (px/s^2)
G.turnRate = 1.1        -- how fast the station turns the ship (rad/s)
G.launchSpeed = 260     -- launch glide speed out of the door

local function wrap(a) return (a + pi) % (2 * pi) - pi end

-- Ship width from the hull outline (half width).
local function halfWidth(e)
	local w = 0
	local s = e.hull and e.hull.shape
	if s then for i = 2, #s, 2 do w = max(w, math.abs(s[i])) end end
	return w
end

-- Which way a ship would come at a dock: the far end of a two-way tunnel
-- when it is on that side.
local function dockSide(game, st, d, x, y)
	if not d.both then return 1 end
	local lx = game.dockLocal(st, 1, x, y, d)
	return lx < 0 and -1 or 1
end

-- The station's centre and safe radius, in the dock's frame.
local function hullCircle(game, e, st, side, d)
	local AI = require("src.ai")
	local cx, cy = game.dockLocal(st, side, st.body:getX(), st.body:getY(), d)
	local R = AI.hullRadius(st) + (e.halfLength or 100) + G.orbitMargin
	return cx, cy, R
end

-- Where on the dock's axis (+x out of the door) the hull circle is cleared.
local function markerX(game, e, st, side, d)
	local cx, cy, R = hullCircle(game, e, st, side, d)
	local mx = cx + sqrt(max(0, R * R - cy * cy))
	return max(mx, d.x2 + d.runway * 0.6 + (e.halfLength or 100)), cx, cy, R
end
G.markerX = markerX

-- A path, in the dock's frame, from (sx, sy) round the hull to the marker and
-- straight in to the door. Points are {x, y}; s is cumulative length.
local function buildPath(game, e, st, side, d, sx, sy)
	local mx, cx, cy, R = markerX(game, e, st, side, d)
	local door = d.x2 + (e.halfLength or 100) + 40
	local pts = { { sx, sy } }
	local r0 = sqrt((sx - cx) ^ 2 + (sy - cy) ^ 2)
	local a0 = atan2(sy - cy, sx - cx)
	local rm = sqrt((mx - cx) ^ 2 + cy * cy)
	local am = atan2(-cy, mx - cx)
	local gap = wrap(am - a0)
	-- Already out in front of the door: straight onto the axis.
	local front = sx > mx - 50 and math.abs(sy) < max(d.hw * 2, (sx - d.x2) * 0.4)
	if not front and math.abs(gap) > 0.05 then
		local n = max(4, math.ceil(math.abs(gap) / 0.12))
		for i = 1, n do
			local f = i / n
			local fs = f * f * (3 - 2 * f)
			-- never in closer than the safe radius while going round
			local r = max(min(R, r0), r0 + (rm - r0) * fs)
			if i < n then r = max(r, R) end
			local a = a0 + gap * f
			pts[#pts + 1] = { cx + cos(a) * r, cy + sin(a) * r }
		end
	elseif not front then
		pts[#pts + 1] = { mx, 0 }
	end
	-- out in front: ease onto the axis a little way out before the final run
	local last = pts[#pts]
	if last[1] > door + 200 then
		pts[#pts + 1] = { max(door + 100, min(last[1] - 150, mx)), 0 }
	end
	pts[#pts + 1] = { door, 0 }
	local s = 0
	pts[1].s = 0
	for i = 2, #pts do
		s = s + sqrt((pts[i][1] - pts[i - 1][1]) ^ 2 + (pts[i][2] - pts[i - 1][2]) ^ 2)
		pts[i].s = s
	end
	return pts, s
end

-- Point and direction along a path at distance s.
local function sample(pts, s)
	for i = 2, #pts do
		local a, b = pts[i - 1], pts[i]
		if s <= b.s or i == #pts then
			local len = max(1e-6, b.s - a.s)
			local f = max(0, min(1, (s - a.s) / len))
			return a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f, (b[1] - a[1]) / len, (b[2] - a[2]) / len
		end
	end
	local p = pts[#pts]
	return p[1], p[2], -1, 0
end

-- Where the ship will go once it reaches the door: inside (fits the doorway
-- and the hangar), an exterior berth, or nowhere (refused).
local function parking(game, e, st, d)
	local interior = game:fitsDock(e, d) and game:hangarFit(st, e.hull.id, e)
	if interior then return interior end
	local berth = game:freeBerth(st, e)
	return nil, berth
end

-- Does this NPC hand over to the station now? Called each frame for an NPC
-- whose route stop is st and who isn't queued behind someone.
function G.tryCapture(game, e, st)
	if st.city or st.sat or not st.dock or not st.body then return false end
	local Q = require("src.queue")
	local AI = require("src.ai")
	local d = AI.approachDock(e, st)
	if not d then return false end
	local x, y = e.body:getPosition()
	local ring = AI.hullRadius(st) + (e.halfLength or 100) + G.captureMargin
	do
		-- always reach out past the marker the AI waits at (src/ai.lua)
		local side = dockSide(game, st, d, x, y)
		local mx, cx, cy = markerX(game, e, st, side, d)
		ring = max(ring, sqrt((mx + 200 - cx) ^ 2 + cy * cy) + 300)
	end
	if (x - st.body:getX()) ^ 2 + (y - st.body:getY()) ^ 2 > ring * ring then return false end
	if Q.dockBusy(game, st, d, e) then return false end
	if (e.glideCheckAt or 0) > game.time then return false end
	e.glideCheckAt = game.time + 0.5
	local interior, berth = parking(game, e, st, d)
	if not interior and not berth then
		e.dockCooldown = 4
		if e.alifeId then require("src.upkeep").rejected(game, e, st) end
		return false
	end
	local side = dockSide(game, st, d, x, y)
	game:beginDocking(e, st, side, d)
	local ds = e.dockState
	ds.phase = "glide"
	local lx, ly = game.dockLocal(st, side, x, y, d)
	ds.path, ds.len = buildPath(game, e, st, side, d, lx, ly)
	ds.s = 0
	local vx, vy = e.body:getLinearVelocity()
	local fx, fy = st.body:getLinearVelocityFromWorldPoint(x, y)
	ds.v = max(80, min(G.cruise * 1.4, sqrt((vx - fx) ^ 2 + (vy - fy) ^ 2)))
	-- heading kept relative to the dock frame, so it rides the station's spin
	ds.ga = e.body:getAngle() - game.dockAngle(st, side, d)
	e.bay = interior or nil
	e.bayStation = st.locationId or st.key
	ds.glideBerth = berth
	e.body:setActive(false)
	e.intent.thrust, e.intent.strafe, e.intent.boost = 0, 0, false
	return true
end

-- One step of the arrival glide. At the door it hands on to "pull" or "taxi".
function G.updateArrival(game, e, ds, dt)
	local st, d = ds.station, ds.dock or ds.station.dock
	local side = ds.side or 1
	local b, sb = e.body, st.body
	if not ds.path then
		-- restored from a save made mid-glide: plan again from where it is
		local x, y = b:getPosition()
		local lx, ly = game.dockLocal(st, side, x, y, d)
		ds.path, ds.len = buildPath(game, e, st, side, d, lx, ly)
		ds.s, ds.v = 0, G.doorSpeed
		ds.ga = ds.ga or (b:getAngle() - game.dockAngle(st, side, d))
	end
	b:setActive(false)
	local remaining = max(0, ds.len - ds.s)
	local want = min(G.cruise, sqrt(G.doorSpeed ^ 2 + 2 * G.accel * remaining))
	if ds.v > want then ds.v = max(want, ds.v - G.accel * 1.6 * dt)
	else ds.v = min(want, ds.v + G.accel * dt) end
	ds.s = min(ds.len, ds.s + ds.v * dt)
	local lx, ly, tx, ty = sample(ds.path, ds.s)
	-- turn toward the direction of travel; on the last straight that is
	-- nose to the door
	local want_a = atan2(ty, tx)
	local da = wrap(want_a - ds.ga)
	local step = G.turnRate * dt
	ds.ga = ds.ga + max(-step, min(step, da))
	local wx, wy = game.dockWorld(st, side, lx, ly, d)
	b:setPosition(wx, wy)
	b:setAngle(game.dockAngle(st, side, d) + ds.ga)
	local svx, svy = sb:getLinearVelocityFromWorldPoint(wx, wy)
	-- report a believable velocity (rendering, AI reading other ships)
	local a = d.a or 0
	local c, s = cos(a), sin(a)
	local ox, oy = sb:getWorldVector(tx * side * c - ty * side * s, tx * side * s + ty * side * c)
	b:setLinearVelocity(svx + ox * ds.v, svy + oy * ds.v)
	b:setAngularVelocity(0)
	if ds.s >= ds.len and math.abs(wrap(pi - ds.ga)) < 0.08 then
		ds.ga = pi
		b:setAngle(game.dockAngle(st, side, d) + pi)
		if ds.glideBerth and not e.bay then
			local berth = ds.glideBerth
			if not game:mooringFits(st, berth, e.hull.id, e) then berth = game:freeBerth(st, e) end
			if not berth then
				return G.refuse(game, e, ds)
			end
			local bd = game:berthPose(st, berth, e.hull.id) or st.def.berths[berth]
			ds.phase, ds.t, ds.berth, ds.mooring = "taxi", 0, berth, game:berthPose(st, berth, e.hull.id)
			ds.lx, ds.ly = sb:getLocalPoint(wx, wy)
			ds.la = b:getAngle() - sb:getAngle()
			ds.dur = max(1.5, min(8, sqrt((bd.x - ds.lx) ^ 2 + (bd.y - ds.ly) ^ 2) / 220))
		else
			ds.phase, ds.t = "pull", 0
			ds.lx, ds.ly, ds.la = lx, ly, pi
		end
		ds.path = nil
	end
end

-- No room after all (a berth went while it glided in): launch it back out.
function G.refuse(game, e, ds)
	local st = ds.station
	e.bay, e.bayStation = nil, nil
	if e.alifeId then require("src.upkeep").rejected(game, e, st) end
	G.beginLaunch(game, e, st, ds.dock or st.dock, ds.side or 1)
	e.dockState, e.dockCooldown = nil, 4
end

-- A ship leaving glides out under station control, along points in the
-- station's own frame (so it rides the station's spin): from the door out
-- along the dock's axis past the hull, or from an exterior berth forward
-- off the pad and then straight out from the station.
function G.beginLaunch(game, e, st, d, side, berth)
	if st.city or st.sat then return false end
	local AI = require("src.ai")
	local sb = st.body
	local x, y = e.body:getPosition()
	local pts = {}
	local function add(wx, wy) local lx, ly = sb:getLocalPoint(wx, wy); pts[#pts + 1] = { lx, ly } end
	add(x, y)
	if berth then
		local R = AI.hullRadius(st) + (e.halfLength or 100) + G.orbitMargin
		local a = math.rad(berth.heading or 0)
		local px, py = berth.x + cos(a) * ((e.halfLength or 100) + 250), berth.y + sin(a) * ((e.halfLength or 100) + 250)
		pts[#pts + 1] = { px, py }
		local r = sqrt(px * px + py * py)
		if r < R then
			if r < 1 then px, py, r = cos(a), sin(a), 1 end
			pts[#pts + 1] = { px / r * R, py / r * R }
		end
	else
		local mx = markerX(game, e, st, side, d)
		add(game.dockWorld(st, side, mx + 120, 0, d))
	end
	local len = 0
	pts[1].s = 0
	for i = 2, #pts do
		len = len + sqrt((pts[i][1] - pts[i - 1][1]) ^ 2 + (pts[i][2] - pts[i - 1][2]) ^ 2)
		pts[i].s = len
	end
	e.launchGlide = { station = st, dock = d, side = side, berth = berth and true or nil, path = pts, len = len, s = 0, v = 100,
		a = e.body:getAngle() - sb:getAngle() }
	e.body:setActive(false)
	return true
end

function G.updateLaunch(game, e, dt)
	local g = e.launchGlide
	local st = g.station
	local b, sb = e.body, st.body
	if e.dead or e.removed or st.removed or not sb or sb:isDestroyed() or not g.path then
		e.launchGlide = nil
		if b and not b:isDestroyed() then b:setActive(true) end
		return
	end
	g.v = min(G.launchSpeed, g.v + G.accel * 1.5 * dt)
	g.s = min(g.len, g.s + g.v * dt)
	local lx, ly, tx, ty = sample(g.path, g.s)
	local da = wrap(atan2(ty, tx) - g.a)
	local step = G.turnRate * dt
	g.a = g.a + max(-step, min(step, da))
	local wx, wy = sb:getWorldPoint(lx, ly)
	local ox, oy = sb:getWorldVector(tx, ty)
	local svx, svy = sb:getLinearVelocityFromWorldPoint(wx, wy)
	b:setPosition(wx, wy)
	b:setAngle(sb:getAngle() + g.a)
	b:setLinearVelocity(svx + ox * g.v, svy + oy * g.v)
	b:setAngularVelocity(sb:getAngularVelocity())
	e.intent.thrust, e.intent.strafe, e.intent.boost = 0, 0, false
	e.intent.firePrimary, e.intent.fireSecondary, e.intent.fireTertiary = false, false, false
	if g.s >= g.len then
		e.launchGlide = nil
		b:setActive(true)
		e.dockCooldown = max(e.dockCooldown or 0, 4)
	end
end

G.halfWidth = halfWidth
return G
