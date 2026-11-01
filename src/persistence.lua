-- Selected world objects survive named-area unloads as plain records.
-- This is not an NPC registry or an offline simulation: unloaded objects
-- follow the orbital current, and generated scenery/ships remain disposable. Empty snapshots
-- are meaningful, so collected containers do not refill on the next visit.
local data = require("src.data")
local Hold = require("src.inventory.hold")
local P = {}

function P.copy(value)
	if type(value) ~= "table" then return value end
	local out = {}
	for k, v in pairs(value) do out[k] = P.copy(v) end
	return out
end

local function known(id) return data.items[id] ~= nil end
local function selected(e) return e.kind == "husk" or e.kind == "container" end
local function partIndex(hull, part)
	for i, p in ipairs(hull.parts) do if p == part then return i end end
end

local function identify(game, object)
	if not object.persistenceId then
		game.universe.nextObjectId = (game.universe.nextObjectId or 0) + 1
		object.persistenceId = game.universe.nextObjectId
	end
	return object.persistenceId
end

local function orbit(game, x, y)
	local w = game.well
	if not w then return end
	local r = math.sqrt((x - w.x) ^ 2 + (y - w.y) ^ 2)
	if r < 1 then return end
	return { x = w.x, y = w.y, rate = game:currentSpeed(r) / r }
end

-- Lightweight orbital catch-up, not an offline physics simulation. Keep
-- altitude constant, rotate drift velocity with the orbit, and retain loot.
local function advanced(game, r, elapsed)
	local motion = r.orbit or orbit(game, r.x, r.y)
	if not motion or elapsed <= 0 then return r end
	local out = {}
	for k, v in pairs(r) do out[k] = v end
	local a = (motion.rate * elapsed) % (math.pi * 2)
	local c, s = math.cos(a), math.sin(a)
	local x, y = r.x - motion.x, r.y - motion.y
	out.x, out.y = motion.x + x * c - y * s, motion.y + x * s + y * c
	out.vx, out.vy = r.vx * c - r.vy * s, r.vx * s + r.vy * c
	return out
end

local function record(game, e)
	local body = e.body
	local x, y = body:getPosition()
	local vx, vy = body:getLinearVelocity()
	local mx, my, mass, inertia = body:getMassData()
	local r = { kind = e.kind, id = identify(game, e), x = x, y = y, vx = vx, vy = vy,
		angle = body:getAngle(), spin = body:getAngularVelocity(), orbit = orbit(game, x, y),
		mass = { mx, my, mass, inertia }, linearDamping = body:getLinearDamping(),
		angularDamping = body:getAngularDamping(), hp = e.hp, radius = e.radius,
		hold = Hold.serialize(e.hold) }
	if e.kind == "container" then
		r.item = e.item
	else
		r.hull, r.source = e.hull.id, data.wrecks[e.hull.id] == e.hull and "wreck" or "hull"
		r.color, r.spine = P.copy(e.color), P.copy(e.spine)
		r.noseX, r.tailX, r.halfLength = e.noseX, e.tailX, e.halfLength
		r.flicker, r.placed, r.armorBase = e.flicker, e.placed, e.armorBase
		r.part = e.part and partIndex(e.hull, e.part)
		if e.pieces then
			r.pieces = {}
			for _, pc in ipairs(e.pieces) do
				r.pieces[#r.pieces + 1] = { part = partIndex(e.hull, pc.part), core = pc.core,
					hp = pc.hp, frac = pc.frac, massFrac = pc.massFrac, share = P.copy(pc.share) }
			end
		end
	end
	return r
end

local function pickupRecord(game, p)
	return { id = identify(game, p), item = p.item, count = p.count,
		x = p.x, y = p.y, vx = p.vx, vy = p.vy, spin = p.spin, orbit = orbit(game, p.x, p.y) }
end

function P.install(Game)
	function Game:captureArea()
		if not self.field or self.field.transit then return end
		local snapshot = { version = 1, capturedAt = self.universe.clock, objects = {}, pickups = {} }
		for _, e in ipairs(self.entities) do
			if selected(e) and not e.dead and not e.removed then
				snapshot.objects[#snapshot.objects + 1] = record(self, e)
			end
		end
		for _, p in ipairs(self.pickups) do
			if p.count > 0 then snapshot.pickups[#snapshot.pickups + 1] = pickupRecord(self, p) end
		end
		self.universe.areas = self.universe.areas or {}
		self.universe.areas[self.fieldId] = snapshot
		return snapshot
	end

	-- Reserve saved object positions while regenerating disposable scenery.
	function Game:areaObjectClear(x, y, margin)
		local area = self.restoringArea
		if not area then return true end
		for _, saved in ipairs(area.objects) do
			local r = advanced(self, saved, math.max(0, self.universe.clock - area.capturedAt))
			if (r.x - x) ^ 2 + (r.y - y) ^ 2 < ((r.radius or 100) + margin) ^ 2 then return false end
		end
		for _, saved in ipairs(area.pickups) do
			local r = advanced(self, saved, math.max(0, self.universe.clock - area.capturedAt))
			if (r.x - x) ^ 2 + (r.y - y) ^ 2 < (20 + margin) ^ 2 then return false end
		end
		return true
	end

	-- Highway views retain a frozen physics scene. Catch up its selected
	-- objects too, so turning back does not restore yesterday's positions.
	function Game:syncAreaMotion()
		local area = self.universe.areas and self.universe.areas[self.fieldId]
		if not area then return end
		local records = {}
		for _, r in ipairs(area.objects) do records[r.id] = r end
		local elapsed = math.max(0, self.universe.clock - area.capturedAt)
		for _, e in ipairs(self.entities) do
			local saved = records[e.persistenceId]
			if saved and not e.dead and not e.removed then
				local r = advanced(self, saved, elapsed)
				e.body:setPosition(r.x, r.y)
				e.body:setLinearVelocity(r.vx, r.vy)
			end
		end
		records = {}
		for _, r in ipairs(area.pickups) do records[r.id] = r end
		for _, p in ipairs(self.pickups) do
			local saved = records[p.persistenceId]
			if saved then
				local r = advanced(self, saved, elapsed)
				p.x, p.y, p.vx, p.vy = r.x, r.y, r.vx, r.vy
			end
		end
	end

	function Game:restoreArea(snapshot)
		if not snapshot then return end
		-- Replace the generated baseline, even when the saved list is empty.
		for i = #self.entities, 1, -1 do
			if selected(self.entities[i]) then self:remove(self.entities[i]) end
		end
		self.pickups = {}
		for _, saved in ipairs(snapshot.objects or {}) do
			local r = advanced(self, saved, math.max(0, self.universe.clock - snapshot.capturedAt))
			local e
			local hold = Hold.deserialize(r.hold, known)
			if r.kind == "container" and known(r.item) then
				e = self:spawnContainer(r.x, r.y, r.item, false, hold)
			elseif r.kind == "husk" then
				local hull = (r.source == "wreck" and data.wrecks or data.hulls)[r.hull]
				if hull then e = self:restoreHusk(r, hull, hold) end
			end
			if e then
				e.persistenceId, e.hp = r.id, r.hp
				local b = e.body
				b:setMassData(unpack(r.mass))
				b:setPosition(r.x, r.y)
				b:setAngle(r.angle)
				b:setLinearVelocity(r.vx, r.vy)
				b:setAngularVelocity(r.spin)
				b:setLinearDamping(r.linearDamping)
				b:setAngularDamping(r.angularDamping)
			end
		end
		for _, saved in ipairs(snapshot.pickups or {}) do
			local r = advanced(self, saved, math.max(0, self.universe.clock - snapshot.capturedAt))
			if known(r.item) and r.count > 0 then
				self.pickups[#self.pickups + 1] = { persistenceId = r.id, item = r.item, count = r.count,
					x = r.x, y = r.y, vx = r.vx, vy = r.vy, spin = r.spin }
			end
		end
	end
end

return P
