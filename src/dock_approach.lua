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
function G.waitPoint(game, e, st, side, d, ry)
	local mx = markerX(game, e, st, side, d)
	local lateral = (d.hw or 100) + (e.halfLength or 100) + 250
	return mx + 200, (ry or 0) >= 0 and lateral or -lateral
end

-- A berth's pose in the dock's frame: position, the outward heading, and an
-- approach point straight out from the pad, clear of the hull.
local function berthGoal(game, e, st, side, d, bd)
	local sb = st.body
	local wx, wy = sb:getWorldPoint(bd.x, bd.y)
	local bx, by = game.dockLocal(st, side, wx, wy, d)
	local h = math.rad(bd.heading or 0) - (d.a or 0) + (side < 0 and pi or 0)
	local cx, cy, R = hullCircle(game, e, st, side, d)
	local reach = (e.halfLength or 100) + 350
	local ax, ay = bx + cos(h) * reach, by + sin(h) * reach
	local r = sqrt((ax - cx) ^ 2 + (ay - cy) ^ 2)
	if r < R then
		-- the pad faces in toward the hull: come at it from straight out
		local ux, uy = (ax - cx) / max(1, r), (ay - cy) / max(1, r)
		ax, ay = cx + ux * R, cy + uy * R
	end
	return { mx = ax, my = ay, ex = bx, ey = by, ea = h }
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
	local front0 = door and sx > goal.mx - 50 and math.abs(sy) < max(d.hw * 2, (sx - d.x2) * 0.4)
	if r0 < R and not front0 then
		-- inside the hull's circle (in a bay, beside a wing): straight out first
		pts[#pts + 1] = { cx + cos(a0) * R, cy + sin(a0) * R }
		r0 = R
	end
	local rm = sqrt((mx - cx) ^ 2 + (my - cy) ^ 2)
	local am = atan2(my - cy, mx - cx)
	local gap = wrap(am - a0)
	-- Already out in front of the door: straight onto the axis.
	local front = door and sx > mx - 50 and math.abs(sy) < max(d.hw * 2, (sx - d.x2) * 0.4)
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
	if door then pts[#pts + 1] = { goal.ex, goal.ey } end
	local s = 0
	pts[1].s = 0
	for i = 2, #pts do
		s = s + sqrt((pts[i][1] - pts[i - 1][1]) ^ 2 + (pts[i][2] - pts[i - 1][2]) ^ 2)
		pts[i].s = s
	end
	pts.final, pts.ea = door and pts[#pts - 1].s or max(0, s - 400), goal.ea
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
	return wx, wy, want, nx, ny, remaining, ap
end

-- A berth-bound ship at its pad and slow enough: the station settles it on.
function G.tryBerth(game, e, stop)
	local ap = e.dockApproach
	if not ap or ap.stop ~= stop or not ap.berth or not ap.pose then return end
	local sb = stop.body
	local x, y = e.body:getPosition()
	-- at the point straight out from the pad, and nearly stopped: the
	-- ship itself never flies in among the station's structure
	local gx, gy = game.dockWorld(stop, ap.side, ap.goal.mx, ap.goal.my, ap.dock)
	if (x - gx) ^ 2 + (y - gy) ^ 2 > 140 ^ 2 then return end
	local vx, vy = e.body:getLinearVelocity()
	local fx, fy = sb:getLinearVelocityFromWorldPoint(x, y)
	if (vx - fx) ^ 2 + (vy - fy) ^ 2 > 90 ^ 2 then return end
	if not game:mooringFits(stop, ap.berth, e.hull.id, e) then e.dockApproach = nil; return end
	game:beginDocking(e, stop, ap.side, ap.dock)
	local ds = e.dockState
	ds.phase, ds.t, ds.berth, ds.mooring = "taxi", 0, ap.berth, game:berthPose(stop, ap.berth, e.hull.id)
	ds.lx, ds.ly = sb:getLocalPoint(x, y)
	ds.la = e.body:getAngle() - sb:getAngle()
	local turn = math.abs(wrap(math.rad(ap.pose.heading or 0) - ds.la))
	ds.dur = max(1.5, sqrt((ap.pose.x - ds.lx) ^ 2 + (ap.pose.y - ds.ly) ^ 2) / 110, turn / 0.8)
	e.bay, e.bayStation = nil, stop.locationId or stop.key
	e.body:setActive(false)
	e.dockApproach = nil
end

return G
