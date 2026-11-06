-- Selected world objects survive named-area unloads as plain records.
-- This is not an NPC registry or an offline simulation: unloaded objects
-- follow the orbital current, and generated scenery/ships remain disposable. Empty snapshots
-- are meaningful, so collected containers do not refill on the next visit.
local data = require("src.data")
local Hold = require("src.inventory.hold")
local T=require("src.tuning")
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
	return { x = w.x, y = w.y, radius = w.radius, rate = game:currentSpeed(r) / r }
end

-- Lightweight orbital catch-up without remote physics. Rigid objects keep
-- altitude; loose pickups follow the damped current, retaining all loot.
local function advanced(game, r, elapsed)
	local motion = r.orbit or game and orbit(game, r.x, r.y)
	if not motion or elapsed <= 0 then return r end
	local out = {}
	for k, v in pairs(r) do out[k] = v end
 local flowRadius=motion.radius or game and game.well and game.well.radius
 if not r.kind and (not flowRadius or (r.x-motion.x)^2+(r.y-motion.y)^2>=flowRadius^2) then
  -- Pickups relax toward the turning current instead of receiving the
  -- centripetal support used by rigid debris. Their small outward drift
  -- reduces angular shear over time; holding each initial radius fixed
  -- greatly over-spreads a loot cloud during long trips.
  local dx,dy=r.x-motion.x,r.y-motion.y
  local radius=math.sqrt(dx*dx+dy*dy)
  if radius<1 then return r end
  local drag=T.pickupDrag
  local decay=math.exp(-drag*elapsed)
  local flowX,flowY=-dy*motion.rate,dx*motion.rate
  local driftX,driftY=r.vx-flowX,r.vy-flowY
  local settling=(1-decay)/drag
  dx,dy=dx+driftX*settling,dy+driftY*settling
  local settledRadius=math.sqrt(dx*dx+dy*dy)
  if settledRadius<1 then return r end
  -- current speed scales as radius^-1/2, hence angular speed radius^-3/2.
  local rate=motion.rate*(radius/settledRadius)^1.5
  local ratio=1+3*rate*rate*elapsed/drag
  local root=math.sqrt(ratio)
  local angle=(2*rate*elapsed/(root+1))%(math.pi*2)
  local scale=ratio^(1/3)
  local c,s=math.cos(angle),math.sin(angle)
  local x,y=(dx*c-dy*s)*scale,(dx*s+dy*c)*scale
  out.x,out.y=motion.x+x,motion.y+y
  local angular=rate/root
  local radial=rate*rate/(drag*ratio)
  out.vx=x*radial-y*angular+driftX*decay
  out.vy=y*radial+x*angular+driftY*decay
  return out
 end
	local a = (motion.rate * elapsed) % (math.pi * 2)
	local c, s = math.cos(a), math.sin(a)
	local x, y = r.x - motion.x, r.y - motion.y
	out.x, out.y = motion.x + x * c - y * s, motion.y + x * s + y * c
	out.vx, out.vy = r.vx * c - r.vy * s, r.vx * s + r.vy * c
	return out
end

function P.advanceRecord(record,elapsed) return advanced(nil,record,elapsed) end
function P.orbit(game,x,y) return orbit(game,x,y) end

-- Pure poses for preview rendering; no writes to a retained physics world.
function P.previewPositions(game)
 local result={objects={},pickups={}}
 local area=game.universe.areas and game.universe.areas[game.fieldId]
 if not area then return result end
 local elapsed=math.max(0,game.universe.clock-area.capturedAt)
 for _,r in ipairs(area.objects) do result.objects[r.id]=advanced(game,r,elapsed) end
 local Loose=require('src.loose')
 for id,record in pairs(Loose.records(game.universe)) do
  if record.area==game.fieldId and record.kind=='loot' then
   local x,y,vx,vy=Loose.position(record,game.universe.clock)
   result.pickups[id]={x=x,y=y,vx=vx,vy=vy,item=record.item,count=record.count}
  end
 end
 return result
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
		hold = Hold.serialize(e.hold), historyWreckId=e.historyWreckId, origin = P.copy(e.origin) }
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

function P.install(Game)
	function Game:captureArea()
		if not self.field or self.field.transit then return end
		local snapshot = { version = 1, capturedAt = self.universe.clock, objects = {}, pickups = {} }
		for _, e in ipairs(self.entities) do
			if selected(e) and not e.dead and not e.removed then
				snapshot.objects[#snapshot.objects + 1] = record(self, e)
			end
		end
		-- Loose items are not area state: their records live in src/loose.lua.
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
		local Loose = require("src.loose")
		for _, record in pairs(Loose.records(self.universe)) do
			if record.area == self.fieldId and record.kind == "loot" then
				local rx, ry = Loose.position(record, self.universe.clock)
				if (rx - x) ^ 2 + (ry - y) ^ 2 < (20 + margin) ^ 2 then return false end
			end
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
				self:stepOutOfStations(e)
			end
		end
	end

	-- Saved debris rides the well's current rigidly while the area is
	-- unloaded, but stations follow their own tracks, so a husk can come
	-- back inside one; Box2D then flings it off at speed. Step it out to
	-- the nearest clear spot beside the station instead.
	function Game:stepOutOfStations(e)
		if not e.body or e.body:isDestroyed() then return end
		local x, y = e.body:getPosition()
		local own = e.radius or e.halfLength or 50
		for _ = 1, 4 do
			local moved = false
			for _, o in ipairs(self.entities) do
				if o.kind == "station" and o ~= e and not o.removed and o.body and not o.body:isDestroyed() then
					local ox, oy = o.body:getPosition()
					local need = (o.radius or 300) + own + 40
					local dx, dy = x - ox, y - oy
					local d = math.sqrt(dx * dx + dy * dy)
					if d < need then
						if d < 1 then dx, dy, d = 1, 0, 1 end
						x, y = ox + dx / d * need, oy + dy / d * need
						moved = true
					end
				end
			end
			if not moved then break end
		end
		e.body:setPosition(x, y)
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
				e.historyWreckId=r.historyWreckId
				local b = e.body
				b:setMassData(unpack(r.mass))
				b:setPosition(r.x, r.y)
				b:setAngle(r.angle)
				b:setLinearVelocity(r.vx, r.vy)
				b:setAngularVelocity(r.spin)
				b:setLinearDamping(r.linearDamping)
				b:setAngularDamping(r.angularDamping)
				self:stepOutOfStations(e)
			end
		end
	end
end

return P
