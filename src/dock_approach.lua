-- How an NPC flies in to dock: its own engines, its own physics, along a
-- planned route. Old code flew it straight at the runway once it was in a
-- broad cone in front of the door; a ship coming from the side or behind,
-- or a long hull swinging its tail, hit the station before the tractor
-- beam (which only takes over on the runway) could catch it.
--
-- The route, worked out in the dock's own frame so it rides the station:
-- round the hull at a safe radius (hull radius + the ship's half length +
-- a margin) to a point out on the dock's axis, then straight in. The AI
-- follows it like any other leg (src/ai.lua), slowing as it closes, and
-- the beam catches it on the runway as before. A ship bound for an
-- exterior berth flies to a point straight out from the pad instead, then
-- in onto it, and the station settles it on the pad (Game:updateDockedShip
-- "taxi") once it's there and slow.
local T = require("src.tuning")

local G = {}
local sqrt, cos, sin, atan2, pi, max, min = math.sqrt, math.cos, math.sin, math.atan2, math.pi, math.max, math.min

G.orbitMargin = 260     -- the path circles the hull this far beyond hull radius + half length
G.arcSpeed = 450        -- most it flies round the hull (px/s, relative to the station)
G.finalSpeed = 200      -- most on the last straight in
G.endSpeed = 50         -- arriving at the door or the pad

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

-- Where a ship waits for its turn: out past the marker and off to the side
-- of the runway, so it isn't parked in the way of the player's approach.
-- spread: this ship's own spot in a patch further out and to the side.
-- Every inbound ship used to make for one of the same two points, so a
-- busy station gathered its traffic into two knots that bumped and
-- scorched each other while they waited.
function G.waitPoint(game, e, st, side, d, ry, spread)
	local mx = markerX(game, e, st, side, d)
	local lateral = (d.hw or 100) + (e.halfLength or 100) + 250
	local out = 200
	if spread then
		local a, b = require("src.queue").spreadOf(e.alifeId or e.id or tostring(e))
		out = out + (a * 0.5 + 0.5) * T.dockWaitSpread
		lateral = lateral + (b * 0.5 + 0.5) * T.dockWaitSpread
	end
	return mx + out, (ry or 0) >= 0 and lateral or -lateral
end

-- Hold beside the runway in the station's frame. The slot nearest the
-- runway is open for the next arrival while the leader is still flying in.
function G.stagingPoint(game, e, st, side, dock, lateral, slot)
	local mx, my = G.waitPoint(game, e, st, side, dock, lateral)
	mx = max(mx, dock.x2 + dock.runway * 1.8 + e.halfLength)
	mx = mx + (slot - 1) * max(T.queueGap, 2 * e.halfLength + 100)
	local Nav = require("src.local_navigation")
	local radius = max(e.halfLength, e.hull.radius) + T.aiClearance
	for _, y in ipairs({my, -my}) do
		local xw, yw = game.dockWorld(st, side, mx, y, dock)
		if Nav.stagingClear(game, e, xw, yw, radius) then return xw, yw end
	end
end

-- A berth's pose in the dock's frame: position, the outward heading, and an
-- approach point straight out from the pad, clear of the hull.
local function berthGoal(game, e, st, side, d, bd)
	local sb = st.body
	local wx, wy = sb:getWorldPoint(bd.x, bd.y)
	local bx, by = game.dockLocal(st, side, wx, wy, d)
	local h = math.rad(bd.heading or 0) - (d.a or 0) + (side < 0 and pi or 0)
	local cx, cy, R = hullCircle(game, e, st, side, d)
	local ux, uy = cos(h), sin(h)
	local dx, dy = bx - cx, by - cy
	local dot = dx*ux + dy*uy
	local outward = -dot + sqrt(max(0, dot*dot + R*R - dx*dx - dy*dy))
	local reach = max((e.halfLength or 100) + 350, outward)
	return { mx = bx + ux*reach, my = by + uy*reach,
		ex = bx + ux*130, ey = by + uy*130, ea = h }

end

-- A path, in the dock's frame, from (sx, sy) round the hull to an approach
-- point and then straight to the end point: the door (nose in) by default,
-- or an exterior berth (goal from berthGoal). Points are {x, y}; s is
-- cumulative length; .final is where the last straight starts.
local function buildPath(game, e, st, side, d, sx, sy, goal)
	local mx0, cx, cy, R = markerX(game, e, st, side, d)
	local door = not goal
	goal = goal or { mx = mx0, my = 0, ex = d.x2 + (e.halfLength or 100) + 40, ey = 0, ea = pi }
	local mx, my = goal.mx, goal.my
	local pts = { { sx, sy } }
	local r0 = sqrt((sx - cx) ^ 2 + (sy - cy) ^ 2)
	local a0 = atan2(sy - cy, sx - cx)
	local front
	if door then
		front = sx > mx - 50 and math.abs(sy) < max(d.hw * 2, (sx - d.x2) * 0.4)
	else
		-- Replanning midway down the pad's approach must keep flying in.
		-- The pad is inside the broad hull circle, so orbiting it again
		-- would pull the ship back out before it reached the local beam.
		local ox, oy = cos(goal.ea), sin(goal.ea)
		local dx, dy = sx - goal.ex, sy - goal.ey
		local ahead, across = dx*ox + dy*oy, math.abs(dx*oy - dy*ox)
		front = ahead >= -85 and across < (e.halfLength or 100) + 300
		if front and across > 125 then
			local intercept = max(380, ahead)
			pts[#pts + 1] = { goal.ex + ox*intercept, goal.ey + oy*intercept }
		end
	end
	if r0 < R and not front then
		-- inside the hull's circle (in a bay, beside a wing): straight out first
		pts[#pts + 1] = { cx + cos(a0) * R, cy + sin(a0) * R }
		r0 = R
	end
	local rm = sqrt((mx - cx) ^ 2 + (my - cy) ^ 2)
	local am = atan2(my - cy, mx - cx)
	local gap = wrap(am - a0)
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
		pts[#pts + 1] = { mx, my }
	end
	if door then
		-- out in front: ease onto the axis a little way out before the final run
		local last = pts[#pts]
		if last[1] > goal.ex + 200 then
			pts[#pts + 1] = { max(goal.ex + 100, min(last[1] - 150, mx)), 0 }
		end
	end
	pts[#pts + 1] = { goal.ex, goal.ey }
	local s = 0
	pts[1].s = 0
	for i = 2, #pts do
		s = s + sqrt((pts[i][1] - pts[i - 1][1]) ^ 2 + (pts[i][2] - pts[i - 1][2]) ^ 2)
		pts[i].s = s
	end
	pts.final, pts.ea = door and pts[#pts - 1].s or (front and 0 or max(0, s - 400)), goal.ea
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


-- Nearest distance along the path to (x, y), in the dock's frame.
local function along(pts, x, y)
	local best, bs = math.huge, 0
	for i = 2, #pts do
		local a, b = pts[i - 1], pts[i]
		local dx, dy = b[1] - a[1], b[2] - a[2]
		local l2 = max(1e-6, dx * dx + dy * dy)
		local f = max(0, min(1, ((x - a[1]) * dx + (y - a[2]) * dy) / l2))
		local px, py = a[1] + dx * f, a[2] + dy * f
		local dd = (x - px) ^ 2 + (y - py) ^ 2
		if dd < best then best, bs = dd, a.s + (b.s - a.s) * f end
	end
	return bs, sqrt(best)
end

-- Where this ship parks: inside (fits the doorway and the hangar) or on a
-- free exterior berth that fits it (nil: the door anyway, and the station
-- turns it away at the door as it always has).
local function parking(game, e, st, d)
	if game:fitsDock(e, d) and game:hangarFit(st, e.hull.id, e) then return nil end
	return game:freeBerth(st, e)
end

-- Plan (or keep) the route for e to its stop's dock. Rebuilt from where the
-- ship is every couple of seconds, so a push or a detour just re-plans.
function G.plan(game, e, stop, d)
	local ap = e.dockApproach
	local x, y = e.body:getPosition()
	if ap and ap.stop == stop and ap.dock == d and game.time < ap.refresh then return ap end
	local side = dockSide(game, stop, d, x, y)
	local berth = ap and ap.stop == stop and ap.berth
	if berth and not game:mooringFits(stop, berth, e.hull.id, e) then berth = nil end
	if not berth or not ap then berth = parking(game, e, stop, d) end
	local bd = berth and (game:berthPose(stop, berth, e.hull.id) or stop.def.berths[berth])
	local lx, ly = game.dockLocal(stop, side, x, y, d)
	local goal = bd and berthGoal(game, e, stop, side, d, bd) or nil
	local pts, len = buildPath(game, e, stop, side, d, lx, ly, goal)
	ap = { stop = stop, dock = d, side = side, pts = pts, len = len, berth = bd and berth or nil,
		pose = bd, goal = goal, refresh = game.time + 2 }
	e.dockApproach = ap
	return ap
end

-- Steering for one frame: the point to head for (world), the speed it
-- wants relative to the station, and the heading to hold on the last
-- straight (nil: face the way it's going).
function G.steer(game, e, stop, d, brake)
	local ap = G.plan(game, e, stop, d)
	local st, side = stop, ap.side
	local x, y = e.body:getPosition()
	local lx, ly = game.dockLocal(st, side, x, y, d)
	local s, off = along(ap.pts, lx, ly)
	local vx, vy = e.body:getLinearVelocity()
	local fx, fy = st.body:getLinearVelocityFromWorldPoint(x, y)
	local speed = sqrt((vx - fx) ^ 2 + (vy - fy) ^ 2)
	local look = max(220, min(700, speed * 0.9)) + off * 0.5
	local tx, ty = sample(ap.pts, min(ap.len, s + look))
	local remaining = max(0, ap.len - s)
	local final = s >= ap.pts.final - 50
	local want = sqrt(G.endSpeed ^ 2 + 2 * brake * 0.45 * remaining)
	want = min(want, final and G.finalSpeed or G.arcSpeed)
	-- well off the line: slow so it can get back on it
	if off > 300 then want = min(want, max(120, G.arcSpeed * 300 / off)) end
	local wx, wy = game.dockWorld(st, side, tx, ty, d)
	local nx, ny
	if final then
		local h = ap.pts.ea
		-- a hull that steers with side thrust backs onto a berth facing out;
		-- one that can only turn keeps its nose on the way in
		if ap.berth and e.hull.helm == "turn" then h = h + pi end
		local a = (d.a or 0) + (side < 0 and pi or 0)
		nx, ny = st.body:getWorldVector(cos(h + a), sin(h + a))
	end
	ap.s, ap.off, ap.want, ap.final = s, off, want, final
	ap.crossing = nil
	if s + look >= ap.pts.final then
		-- Check the join and the lane ahead before aiming into crossing traffic.
		local goal = final and ap.pts[#ap.pts] or {tx, ty}
		local gx, gy = game.dockWorld(st, side, goal[1], goal[2], d)
		ap.crossing = require("src.queue").crossing(game, e, st, gx, gy, max(want, G.finalSpeed))
	end
	return wx, wy, want, nx, ny, remaining, ap
end

function G.tryBerth(game, e, stop)
	local ap = e.dockApproach
	if ap and ap.stop == stop and ap.berth and ap.pose then
		return game:tryBerthTractor(e, stop, ap.dock, ap.berth, ap.pose)
	end
end

function G.playerBerth(game, p)
	if (p.berthCheckAt or 0) > game.time then return false end
	p.berthCheckAt = game.time + .15
	local x, y = p.body:getPosition()
	for _, st in ipairs(game.entities) do
		if st.kind == "station" and not st.removed and not st.city and st.dock then
			local sx, sy = st.body:getPosition()
			local radius = require("src.ai").hullRadius(st) + 750
			if (x-sx)^2 + (y-sy)^2 < radius^2 then
				local berth = game:freeBerth(st, p)
				local pose = berth and game:berthPose(st, berth, p.hull.id)
				if pose and game:tryBerthTractor(p, st, st.dock, berth, pose) then return true end
			end
		end
	end
	return false
end

return G
