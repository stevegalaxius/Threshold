--[[
	Satellites: owned, persistent props in a planet's orbit (data/satellites.lua).

	Each is a prop design from data/wrecks/ spawned as a husk, so it flies,
	takes hits and is saved with its area like any placed wreck
	(src/persistence.lua). On top of that it carries:

	  e.sat = id    stable id, <field>_sat_<n>, for quests to name

	and the universe keeps one record per satellite (universe.satellites):

	  { id, field, kind, name, owner, dock, actions, vend, lost }

	The record is the truth for what the satellite is and what it allows; the
	husk is only where it is. Two levers, read through Sat.levers:

	  dock     who may lock on: "none" | "owner" | "rep" | "anyone" | "player"
	  actions  what you can do while locked: { "vend", "quest", ... }

	Kinds set the defaults; quests override them per satellite with
	Sat.allow / Sat.revoke, and the override is saved with the record.
]]

local data = require("src.data")

local Sat = {}

Sat.kinds = {
	passive = { design = "sat_passive", dock = "none", actions = {} },
	fuel = { design = "sat_fuel_buoy", dock = "anyone", actions = { "vend" }, vend = { "deuterium_canister" } },
	vendor = { design = "sat_vendor", dock = "anyone", actions = { "vend" },
		vend = { "rounds_s", "rounds_m", "shell_s", "patch_kit", "deuterium_canister" } },
}

local function copy(t)
	if type(t) ~= "table" then return t end
	local o = {}
	for k, v in pairs(t) do o[k] = copy(v) end
	return o
end

local function store(universe)
	universe.satellites = universe.satellites or {}
	return universe.satellites
end

-- A rolled, seeded list of { id, kind, alt, angle } for a field: the same
-- every time, so a field always has the same satellites.
function Sat.layout(fieldId, field)
	local def = data.satellites[fieldId]
	if not def or not field or not field.planetR then return {} end
	local seed = 0
	for i = 1, #fieldId do seed = seed * 31 + fieldId:byte(i) end
	local rng = love.math.newRandomGenerator(seed % 2147483647 + 1)
	local count = def.count or 12
	if type(count) == "table" then count = rng:random(count[1], count[2]) end
	local kinds, total = {}, 0
	for k, w in pairs(def.mix or { passive = 1 }) do
		if Sat.kinds[k] then kinds[#kinds + 1] = { k, w }; total = total + w end
	end
	table.sort(kinds, function(a, b) return a[1] < b[1] end)
	local band = def.band or { 0.08, 0.85 }
	local R, edge = field.planetR, field.radius or field.planetR * 3
	local out = {}
	for n = 1, count do
		local r, kind = rng:random() * total, kinds[1] and kinds[1][1] or "passive"
		for _, kw in ipairs(kinds) do
			if r < kw[2] then kind = kw[1]; break end
			r = r - kw[2]
		end
		local f = band[1] + rng:random() * (band[2] - band[1])
		out[n] = { id = ("%s_sat_%02d"):format(fieldId, n), n = n, kind = kind,
			alt = R + (edge - R) * f, angle = rng:random() * math.pi * 2, owner = def.owner,
			name = ("%s sat %02d"):format(def.names or field.name or fieldId, n) }
	end
	return out
end

-- The record for a satellite, made from its layout slot the first time.
function Sat.record(universe, slot, fieldId)
	local all = store(universe)
	local r = all[slot.id]
	if not r then
		local K = Sat.kinds[slot.kind]
		r = { id = slot.id, field = fieldId, kind = slot.kind, name = slot.name, owner = slot.owner }
		all[slot.id] = r
		r.design = K.design
	end
	return r
end

function Sat.get(universe, id) return universe and universe.satellites and universe.satellites[id] end

-- What it allows right now: the quest override if there is one, else its kind's.
function Sat.levers(r)
	local K = Sat.kinds[r.kind] or Sat.kinds.passive
	return {
		dock = r.dock or K.dock,
		actions = r.actions or K.actions,
		vend = r.vend or K.vend,
	}
end

-- Quest scripting: open a satellite up (or change what it offers) and
-- close it again. Fields left out keep their current value.
function Sat.allow(universe, id, levers)
	local r = Sat.get(universe, id)
	if not r then return false end
	if levers.dock ~= nil then r.dock = levers.dock end
	if levers.actions ~= nil then r.actions = copy(levers.actions) end
	if levers.vend ~= nil then r.vend = copy(levers.vend) end
	return true
end

function Sat.revoke(universe, id)
	local r = Sat.get(universe, id)
	if not r then return false end
	r.dock, r.actions, r.vend = nil, nil, nil
	return true
end

-- Every satellite in a field, for quests to pick from.
function Sat.inField(universe, fieldId)
	local list = {}
	for _, r in pairs(store(universe)) do
		if r.field == fieldId and not r.lost then list[#list + 1] = r end
	end
	table.sort(list, function(a, b) return a.id < b.id end)
	return list
end

-- After a field is built and its saved objects restored: spawn every
-- satellite that isn't already there. A satellite already in the area's
-- save comes back through Game:restoreArea with its sat id; one that was
-- destroyed is marked lost and stays gone.
function Sat.populate(game)
	if game.preview or not game.universe or not game.field or game.field.transit then return end
	local present = {}
	for _, e in ipairs(game.entities) do
		if e.sat and not e.removed then present[e.sat] = e end
	end
	local saved = game.universe.areas and game.universe.areas[game.fieldId]
	local w = game.well
	local cx, cy = w and w.x or 0, w and w.y or 0
	for _, slot in ipairs(Sat.layout(game.fieldId, game.field)) do
		local r = Sat.record(game.universe, slot, game.fieldId)
		local e = present[slot.id]
		-- a satellite saved in this area but not restored was destroyed
		if not e and not r.lost and r.spawnedAt and saved and (saved.capturedAt or 0) >= r.spawnedAt then r.lost = true end
		if not e and not r.lost and data.wrecks[r.design] then
			local x, y = cx + math.cos(slot.angle) * slot.alt, cy + math.sin(slot.angle) * slot.alt
			local v = game.currentSpeed and game:currentSpeed(slot.alt) or 0
			e = game:spawnWreck(r.design, x, y, slot.angle + math.pi / 2,
				-math.sin(slot.angle) * v, math.cos(slot.angle) * v)
			if e then
				r.spawnedAt = game.universe.clock or 0
				game:stepOutOfStations(e)
			end
		end
		if e then Sat.adopt(e, r) end
	end
end

-- Tag a husk as this satellite.
function Sat.adopt(e, r)
	e.sat, e.name = r.id, r.name
	if e.body and not e.body:isDestroyed() then
		e.body:setAngularVelocity(0)
		e.body:setAngularDamping(2)
	end
end

-- Mark destroyed satellites: called when a husk with a sat id dies.
function Sat.lost(game, e)
	local r = e.sat and Sat.get(game.universe, e.sat)
	if r then r.lost = true end
end

-- Damage to a working satellite: off its own armor (the record's hp), the
-- whole thing at once. At zero it's knocked out: it goes dark and becomes an
-- ordinary wreck, which then breaks apart part by part when shot.
function Sat.damage(game, e, amount)
	local r = Sat.get(game.universe, e.sat)
	if not r then e.sat = nil; return end
	local def = data.wrecks[r.design]
	r.hp = (r.hp or (def and def.armor or 200)) - amount
	e.flash = 0.08
	if r.hp <= 0 then
		r.lost = true
		e.sat, e.name = nil, nil
		game:spark(e.body:getX(), e.body:getY(), 24, { 1, 0.7, 0.35 })
		game:explode(e.body:getX(), e.body:getY(), (e.radius or 100) * 0.3, 0, 0)
	end
end

-- Docking ------------------------------------------------------------------
--
-- A satellite docks like a small station: tap the tractor key on it in
-- range and, if its dock lever lets you in, the tractor beam (src/beam.lua)
-- pulls you to a berth beside the bus. Arrived, you're docked
-- (game.state = "docked") and the usual station screen opens with only the
-- tabs its services give. Launch leaves the berth. One ship at a time.

-- The satellite's services, as station service ids (Game.stationServices).
Sat.services = { vend = "market", repair = "repair" }

function Sat.permits(game, r, ship)
	local L = Sat.levers(r)
	local player = ship == game.player
	if L.dock == "anyone" then return true end
	if L.dock == "player" then return player end
	if L.dock == "rep" and player and r.owner then
		return (require("src.reputation").standing(game.universe, r.owner) or 0) >= (r.minRep or 10)
	end
	if L.dock == "owner" then return not player and ship.faction ~= nil and ship.faction == r.owner end
	return false
end

-- The station the docked screen sees: the satellite's own name, storage
-- key and services, with its body as the station's.
function Sat.station(game, e)
	local r = Sat.get(game.universe, e.sat)
	if not r then return nil end
	local L = Sat.levers(r)
	local services = {}
	for _, a in ipairs(L.actions or {}) do
		if Sat.services[a] then services[#services + 1] = Sat.services[a] end
	end
	e.satStation = e.satStation or {}
	local st = e.satStation
	st.sat, st.key, st.name, st.body, st.entity = r.id, "sat:" .. r.id, r.name, e.body, e
	st.marketId = "sat:" .. r.kind
	st.def = { services = services, marketId = st.marketId, repairRate = 2 }
	return st
end

-- Where the berth is, in the satellite's frame: off the side of the bus the
-- ship came from.
local function berthOffset(e, ship)
	local lx, ly = e.body:getLocalPoint(ship.body:getPosition())
	local side = ly < 0 and -1 or 1
	return 0, side * ((e.radius or 300) * 0.25 + (ship.halfLength or 40) + 40)
end

function Sat.request(game, e)
	local r = Sat.get(game.universe, e.sat)
	local p = game.player
	if not r or not p or p.dead or p.dockState then return false end
	if e.satHeld and e.satHeld ~= p and not e.satHeld.dead and e.satHeld.dockState then game:toast("BERTH OCCUPIED", 1.4); return false end
	if not Sat.permits(game, r, p) then game:toast("DOCKING REFUSED", 1.6); return false end
	local st = Sat.station(game, e)
	local bx, by = berthOffset(e, p)
	p.dockState = { station = st, phase = "tractor", t = 0, satBerth = { bx, by } }
	p.intent.firePrimary, p.intent.fireSecondary, p.intent.fireTertiary = false, false, false
	e.satHeld = p
	game:toast("TRACTOR LOCK", 1.4)
	return true
end

-- One step of a ship docking at or docked beside a satellite.
function Sat.updateDock(game, ship, dt)
	local ds = ship.dockState
	local st = ds.station
	local e = st.entity
	if not e or e.removed or e.dead or not e.sat or not e.body or e.body:isDestroyed() then
		ship.dockState = nil
		if ship == game.player and game.state == "docked" then game.state = "playing" end
		return
	end
	ds.t = ds.t + dt
	local b, sb = ship.body, e.body
	local wx, wy = sb:getWorldPoint(ds.satBerth[1], ds.satBerth[2])
	local fvx, fvy = sb:getLinearVelocityFromWorldPoint(wx, wy)
	if ds.phase == "tractor" then
		local x, y = b:getPosition()
		local dx, dy = wx - x, wy - y
		local d = math.sqrt(dx * dx + dy * dy)
		if d > (e.radius or 300) * 2.5 then
			ship.dockState, ship.dockCooldown, e.satHeld = nil, 3, nil
			game:toast("TRACTOR LOST", 1.4)
			return
		end
		local speed = math.min(260, math.max(40, d * 0.8))
		local near = 1 - math.min(1, d / ((e.radius or 300) * 2))
		require("src.beam").hold(game, ship, { t = ds.t, near = near, fvx = fvx, fvy = fvy,
			wx = dx / math.max(d, 1) * speed, wy = dy / math.max(d, 1) * speed,
			nose = sb:getAngle(), spin = sb:getAngularVelocity(), dt = dt })
		local vx, vy = b:getLinearVelocity()
		if d < 30 and (vx - fvx) ^ 2 + (vy - fvy) ^ 2 < 60 ^ 2 then
			ds.phase, ds.done, ds.t = "done", true, 0
			if ship == game.player then game.state = "docked" end
			require("src.events").emit("dock", ship, st)
		end
	else
		-- moored: ride along at the berth
		b:setPosition(wx, wy)
		b:setLinearVelocity(fvx, fvy)
		b:setAngularVelocity(sb:getAngularVelocity())
	end
end

-- Launch from a satellite berth: a gentle push away from the bus.
function Sat.undock(game, ship)
	local ds = ship.dockState
	local e = ds and ds.station.entity
	ship.dockState, ship.dockCooldown = nil, 2
	if e then
		e.satHeld = nil
		if e.body and not e.body:isDestroyed() then
			local x, y = ship.body:getPosition()
			local cx, cy = e.body:getPosition()
			local dx, dy = x - cx, y - cy
			local d = math.max(1, math.sqrt(dx * dx + dy * dy))
			local vx, vy = e.body:getLinearVelocityFromWorldPoint(x, y)
			ship.body:setLinearVelocity(vx + dx / d * 60, vy + dy / d * 60)
		end
	end
	require("src.events").emit("undock", ship, ds and ds.station)
end

return Sat
