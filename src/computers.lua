--[[
	Ship computers: modules in the "computer" slot every playable hull has.
	A module's `computer` field says which one it is:

	  nav       warns of a collision: when your course (velocity relative
	            to it) runs you into something within T.navLookahead seconds,
	            the dashed line along your velocity fades in, bright orange.
	  ordnance  puts a lead pip on the target (your radar lock, or the
	            hostile nearest the cursor): shoot the pip and your primary
	            rounds meet the target.
	  radar     radarRange px. T locks the hostile nearest the cursor and
	            your missiles fly at the lock instead of picking their own
	            target; T on empty space clears it. G takes the controls of
	            your nearest drone (your ship holds still), G again hands
	            them back.

	Game:computer(e, kind) is the fitted module of that kind, or nil.
]]

local data = require("src.data")
local T = require("src.tuning")
local Weapons = require("src.weapons")

local sqrt, max, cos, sin = math.sqrt, math.max, math.cos, math.sin

return function(Game)

function Game:computer(e, kind)
	if not e or not e.loadout then return nil end
	for i in ipairs(e.hull.slots) do
		local m = e.loadout[i] and data.modules[e.loadout[i]]
		if m and m.computer == kind then return m end
	end
end

local function hostileNear(game, e, x, y, within, from, range)
	local best, bd = nil, within * within
	local fx, fy = from.body:getPosition()
	for _, o in ipairs(game.entities) do
		if o.kind == "ship" and not o.dead and o.team ~= e.team then
			local ox, oy = o.body:getPosition()
			local d = (ox - x) ^ 2 + (oy - y) ^ 2
			if d < bd and (not range or (ox - fx) ^ 2 + (oy - fy) ^ 2 <= range * range) then best, bd = o, d end
		end
	end
	return best
end

-- The ship your inputs fly: the drone you've taken over, or your own.
function Game:pilotedShip()
	local d = self.piloting
	if d and (d.dead or not d.body or self.player.dead) then
		d.piloted, self.piloting, d = nil, nil, nil
	end
	return d or self.player
end

-- T: lock the hostile nearest the cursor, or clear the lock.
function Game:radarLock(aimX, aimY)
	local p = self.player
	if not p or p.dead then return end
	local radar = self:computer(p, "radar")
	if not radar then self:toast("No radar computer fitted") return end
	local t = hostileNear(self, p, aimX, aimY, 400, p, radar.radarRange)
	p.lock = t
	if t then self:toast("Locked: " .. (t.def and t.def.name or "contact")) end
end

-- G: take over the nearest of your drones, or hand the controls back.
function Game:toggleDroneControl()
	local p = self.player
	if not p or p.dead then return end
	if self.piloting then
		self.piloting.piloted, self.piloting = nil, nil
		return
	end
	local radar = self:computer(p, "radar")
	if not radar then self:toast("No radar computer fitted") return end
	local x, y = p.body:getPosition()
	local best, bd
	for _, o in ipairs(self.entities) do
		if o.drone and o.owner == p and not o.dead then
			local ox, oy = o.body:getPosition()
			local d = (ox - x) ^ 2 + (oy - y) ^ 2
			if d <= radar.radarRange ^ 2 and (not bd or d < bd) then best, bd = o, d end
		end
	end
	if not best then self:toast("No drone in radar range") return end
	best.piloted, self.piloting = true, best
end

-- Is ship e on course to hit something within `ahead` seconds?
local SOLID = { asteroid = true, planet = true, station = true, structure = true, ship = true, husk = true, container = true }
local function collisionCourse(game, e, ahead)
	local x, y = e.body:getPosition()
	local vx, vy = e.body:getLinearVelocity()
	local me = (e.halfLength or 20) * 0.8
	for _, o in ipairs(game.entities) do
		if o ~= e and SOLID[o.kind] and not o.dead and not o.removed and not o.gas
			and not (o.drone and o.owner == e) and o.body then
			local ox, oy = o.body:getPosition()
			local ovx, ovy = o.body:getLinearVelocity()
			local rx, ry, rvx, rvy = ox - x, oy - y, ovx - vx, ovy - vy
			local reach = (o.radius or o.halfLength or 20) + me
			local closing = -(rx * rvx + ry * rvy)
			if closing > 0 then
				local v2 = rvx * rvx + rvy * rvy
				local t = math.min(closing / v2, ahead)
				local cx, cy = rx + rvx * t, ry + rvy * t
				if cx * cx + cy * cy < reach * reach then return true end
			end
		end
	end
	return false
end

-- Each frame: the nav warning, and drop a lock that's dead or out of
-- radar range.
function Game:updateComputers(dt)
	local p = self.player
	if not p or p.dead then return end
	local ship = self:pilotedShip()
	local want = (self:computer(p, "nav") and not ship.catching and not ship.dockState
		and collisionCourse(self, ship, T.navLookahead)) and 1 or 0
	local warn = p.navWarn or 0
	p.navWarn = warn + math.max(-dt * 2, math.min(dt * 5, want - warn))
	local t, radar = p.lock, self:computer(p, "radar")
	if t and (t.dead or not radar) then p.lock = nil
	elseif t then
		local x, y = p.body:getPosition()
		local tx, ty = t.body:getPosition()
		if (tx - x) ^ 2 + (ty - y) ^ 2 > (radar.radarRange * 1.1) ^ 2 then p.lock = nil end
	end
	if self.piloting and (not radar or self.piloting.dead) then
		if self.piloting.piloted then self.piloting.piloted = nil end
		self.piloting = nil
	end
end

-- Where to shoot so a round at shotSpeed meets target t.
local function leadPoint(e, t, shotSpeed)
	local x, y = e.body:getPosition()
	local vx, vy = e.body:getLinearVelocity()
	local tx, ty = t.body:getPosition()
	local tvx, tvy = t.body:getLinearVelocity()
	local rvx, rvy = tvx - vx, tvy - vy
	local px, py = tx, ty
	for _ = 1, 4 do
		local time = sqrt((px - x) ^ 2 + (py - y) ^ 2) / shotSpeed
		px, py = tx + rvx * time, ty + rvy * time
	end
	return px, py
end

local function primarySpeed(e)
	for _, slot in ipairs(e.weapons or {}) do
		if slot.group == "primary" and slot.ammo then return data.items[slot.ammo].shot.speed end
	end
end

-- Drawn in world space (inside the camera), under the HUD.
function Game:drawComputers(px)
	local lg = love.graphics
	local p = self.player
	if not p or p.dead or p.dockState then return end
	local ship = self:pilotedShip()
	local x, y = ship.body:getPosition()

	-- nav: the mass driver's dashed course line, only while a collision's coming
	local warn = p.navWarn or 0
	if warn > 0.01 then
		local vx, vy = ship.body:getLinearVelocity()
		local ahead = T.navLookahead
		lg.setColor(1, 0.55, 0.1, 0.85 * warn)
		lg.setLineWidth(max(2, 2 * px))
		local n = 20
		for i = 0, n - 1, 2 do
			local t1, t2 = i / n * ahead, (i + 1) / n * ahead
			lg.line(x + vx * t1, y + vy * t1, x + vx * t2, y + vy * t2)
		end
	end

	local radar = self:computer(p, "radar")
	if radar and self.piloting == nil then
		lg.setColor(0.4, 0.9, 0.65, 0.07)
		lg.setLineWidth(max(1, px))
		lg.circle("line", x, y, radar.radarRange, 128)
	end

	local lock = p.lock
	if lock and not lock.dead then
		local tx, ty = lock.body:getPosition()
		local r = (lock.halfLength or 30) + 14 * px
		local c = 10 * px
		lg.setColor(1, 0.35, 0.3, 0.9)
		lg.setLineWidth(max(2, 2 * px))
		for _, s in ipairs({ { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } }) do
			local cx, cy = tx + s[1] * r, ty + s[2] * r
			lg.line(cx, cy, cx - s[1] * c, cy)
			lg.line(cx, cy, cx, cy - s[2] * c)
		end
	end

	if self:computer(p, "ordnance") then
		local speed = primarySpeed(ship)
		local aimX, aimY = ship.intent.aimX, ship.intent.aimY
		local t = (lock and not lock.dead) and lock
			or (aimX and hostileNear(self, ship, aimX, aimY, 900 * px, ship))
		if speed and t then
			local lx, ly = leadPoint(ship, t, speed)
			local tx, ty = t.body:getPosition()
			lg.setColor(1, 0.85, 0.35, 0.35)
			lg.setLineWidth(max(1, px))
			lg.line(tx, ty, lx, ly)
			lg.setColor(1, 0.85, 0.35, 0.95)
			lg.setLineWidth(max(2, 2 * px))
			lg.circle("line", lx, ly, 9 * px)
			lg.circle("fill", lx, ly, 2.5 * px)
		end
	end

	if self.piloting then
		local d = self.piloting
		local dx, dy = d.body:getPosition()
		lg.setColor(0.8, 0.55, 1, 0.8)
		lg.setLineWidth(max(1.5, 1.5 * px))
		lg.circle("line", dx, dy, (d.halfLength or 14) + 10 * px)
	end
end

end
