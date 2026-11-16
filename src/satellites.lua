--[[
	Satellites: owned, persistent props in a planet's orbit (data/satellite_orbits.lua).

	Each is a satellite design from data/satellites/ spawned as a husk, so it flies,
	takes hits and is saved with its area like any placed wreck
	(src/persistence.lua). On top of that it carries:

	  e.sat = id    stable id, <field>_sat_<n>, for quests to name

	and the universe keeps one record per satellite (universe.satellites):

	  { id, field, kind, name, owner, dock, actions, vend, lost,
	    fuel, fuelAt, dryAt }

	The record is the truth for what the satellite is and what it allows; the
	husk is only where it is. Two levers, read through Sat.levers:

	  dock     who may lock on: "none" | "owner" | "rep" | "anyone" | "player"
	  actions  what you can do while locked: { "vend", "quest", ... }

	Kinds set the defaults; quests override them per satellite with
	Sat.allow / Sat.revoke, and the override is saved with the record.
]]

local data = require("src.data")

local Sat = {}
local berthOffsetFor

Sat.kinds = {
	passive = { design = "sat_passive", dock = "none", actions = {} },
	-- the trade-buoy hub: not in any orbit mix, one rides every trade buoy
	-- (Sat.hubs). A mini station for ships passing through.
	hub = { design = "trade_hub", dock = "anyone", actions = { "vend" },
		vend = { "deuterium_canister", "rounds_s", "rounds_m", "shell_s", "patch_kit" } },
}
-- Kinds that used to orbit on their own: their records become the slot's
-- new kind and the old husk is taken away (Sat.populate).
Sat.retired = { fuel = true, vendor = true }

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
	elseif Sat.retired[r.kind] and r.kind ~= slot.kind then
		r.kind, r.design, r.dock, r.actions, r.vend, r.retiredHusk = slot.kind, Sat.kinds[slot.kind].design, nil, nil, nil, true
	end
	return r
end

function Sat.get(universe, id) return universe and universe.satellites and universe.satellites[id] end

-- What it allows right now: the quest override if there is one, else its kind's.
-- Out of fuel it still docks, but its shelf is shut until it's refuelled.
function Sat.levers(r)
	local K = Sat.kinds[r.kind] or Sat.kinds.passive
	return {
		dock = r.dock or K.dock,
		actions = r.actions or K.actions,
		vend = Sat.dry(r) and {} or (r.vend or K.vend),
	}
end

-- Fuel ---------------------------------------------------------------------
--
-- Every satellite burns station-keeping fuel: r.fuel runs 1 -> 0 over
-- Sat.fuelLife game seconds. It's worked out from elapsed time when looked
-- at (Sat.fuel), so nothing steps per frame. Below Sat.refuelAt its system
-- posts a "satrefuel" job (src/sat_jobs.lua) that ordinary haulers take as
-- part of their usual work; the player can take the same job from the
-- station board. One open job per satellite, no other limit.
--
-- Running dry is soft: the satellite goes to low power (dim lights, shelf
-- shut, "Low power" on its tooltip) but is never lost, and r.dryAt says how
-- long it has been neglected for anything bigger (the director) to read.
-- Refuelling brings it straight back.
Sat.fuelLife, Sat.refuelAt, Sat.checkEvery = 2400, 1 / 3, 30

function Sat.fuel(universe, r)
	local clock = universe and universe.clock or 0
	if r.broken then r.broken, r.brokenAt, r.brokenBy, r.fuel = nil, nil, nil, 0 end -- old saves
	if r.fuel == nil or r.fuelAt == nil then r.fuel, r.fuelAt = r.fuel or 1, clock end
	local f = math.max(0, r.fuel - math.max(0, clock - r.fuelAt) / Sat.fuelLife)
	if f <= 0 and r.fuel > 0 then r.dryAt = r.fuelAt + r.fuel * Sat.fuelLife end
	r.fuel, r.fuelAt = f, clock
	if f <= 0 and not r.dryAt then r.dryAt = clock end
	return f
end

-- Out of fuel, as of the last look.
function Sat.dry(r) return r.fuel ~= nil and r.fuel <= 0 and not r.lost end

function Sat.refuel(universe, id, by)
	local r = Sat.get(universe, id)
	if not r or r.lost then return false end
	Sat.fuel(universe, r)
	r.fuel, r.fuelAt, r.dryAt = 1, universe.clock or 0, nil
	require("src.events").emit("sat_refuelled", id, by)
	require("src.sat_jobs").clear(universe, id, "satrefuel")
	return true
end

-- Called from the A-Life director: every Sat.checkEvery game seconds, bring
-- each satellite's fuel up to date and post refuel jobs for the low ones.
function Sat.tick(universe)
	local all, clock = universe and universe.satellites, universe and universe.clock
	if not all or not clock then return end
	if universe.satCheckAt and clock < universe.satCheckAt and universe.satCheckAt <= clock + Sat.checkEvery then return end
	universe.satCheckAt = clock + Sat.checkEvery
	if not universe.satFuelV then
		-- saves from before fuel: drop the retired repair work
		universe.satFuelV = 1
		local offers = require("src.tasks").state(universe).offers
		for oid, o in pairs(offers) do if o.kind == "satrepair" then offers[oid] = nil end end
		local qs = universe.quests
		if qs then
			for _, list in ipairs({ qs.offers or {}, qs.active or {} }) do
				for qid, q in pairs(list) do if q.kind == "sat_repair" then list[qid] = nil end end
			end
		end
	end
	Sat.ensureHubs(universe)
	local open = require("src.sat_jobs").open(universe, "satrefuel")
	for id, r in pairs(all) do
		-- low on its own fuel, or (a hub) its shelf nearly out of canisters
		local low = not r.lost and (Sat.fuel(universe, r) < Sat.refuelAt or r.hub
			and require("src.stockpile").available(universe, r.hub, require("src.reactor_fuel").item()) < Sat.hubLowStock)
		if low and not open[id] then
			require("src.sat_jobs").post(universe, r, "satrefuel")
		end
	end
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
		if e and r.retiredHusk then game:remove(e); e = nil end
		r.retiredHusk = nil
		-- a satellite saved in this area but not restored was destroyed
		if not e and not r.lost and r.spawnedAt and saved and (saved.capturedAt or 0) >= r.spawnedAt then Sat.markLost(game.universe, r) end
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
	Sat.hubs(game)
end

-- Trade-buoy hubs: every trade buoy on the map is a hub satellite. The buoy
-- entity itself is the satellite (it already rides the buoy's track and
-- draws its prop, data/wrecks/trade_hub.lua), so it just gets a record.
function Sat.hubId(locationId) return "hub:" .. locationId end
-- Records for every trade buoy in the system, loaded or not, so ships
-- passing an unvisited map's buoys are served too.
function Sat.ensureHubs(universe)
	local all, Fields, L = store(universe), require("src.fields"), require("src.locations")
	for _, area in ipairs(Fields.list) do
		for _, loc in ipairs(Fields[area].buoyIds or {}) do
			local id = Sat.hubId(loc)
			if not all[id] then
				local place = L.byId[loc]
				all[id] = { id = id, field = area, kind = "hub", design = "trade_hub", hub = loc,
					name = place and place.name and (Fields[area].name .. " " .. place.name:lower()) or "Trade hub" }
			end
		end
	end
end
function Sat.hubs(game)
	Sat.ensureHubs(game.universe)
	for _, e in ipairs(game.entities) do
		if e.kind == "buoy" and e.locationId and not e.removed then
			local r = Sat.get(game.universe, Sat.hubId(e.locationId))
			if r then e.sat, e.name = r.id, r.name end
		end
	end
end

-- The hub at a buoy node, working (fuelled) or not; nil if there's none yet.
function Sat.hubAt(universe, node)
	return node and Sat.get(universe, Sat.hubId(node))
end

-- NPCs and hubs ---------------------------------------------------------------
--
-- A working hub is a service stop for NPC upkeep (src/upkeep.lua), like a
-- small station: a ship short of fuel or ammunition can pick it, fly there,
-- lock on at one of its Sat.hubBerths berths and take what it needs off the
-- hub's shelf (src/supplies.lua; the buoy's own stockpile). A full hub is
-- skipped like a full station. Every ship served burns a little of the
-- hub's own fuel (Sat.hubServeCost), so busy hubs ask for refuels sooner;
-- the refuel hauler restocks the shelf too. No repairs at a hub.
Sat.hubBerths, Sat.hubServeCost, Sat.hubLowStock = 2, 0.02, 4

function Sat.hubWorking(universe, node)
	local r = universe and Sat.hubAt(universe, node)
	return r and not r.lost and Sat.fuel(universe, r) > 0 or false
end

-- Ships at (or locked on to) the hub now, other than `except`.
function Sat.hubOccupancy(universe, node, except)
	local n = 0
	for _, o in pairs(universe.npcs or {}) do
		if o ~= except and o.state == "docked" and o.node == node then n = n + 1 end
	end
	return n
end
function Sat.hubRoom(universe, node, except)
	return Sat.hubWorking(universe, node) and Sat.hubOccupancy(universe, node, except) < Sat.hubBerths
end

-- A ship was served: the hub's own fuel pays for it.
function Sat.hubServed(universe, node)
	local r = Sat.hubAt(universe, node)
	if not r then return end
	Sat.fuel(universe, r)
	r.fuel = math.max(0, r.fuel - Sat.hubServeCost)
	if r.fuel <= 0 and not r.dryAt then r.dryAt = universe.clock or 0 end
	r.served = (r.served or 0) + 1
end

-- The refuel hauler also restocks the shelf: each listed good back up to
-- at least half its listed amount.
function Sat.restockHub(universe, r)
	if not r.hub then return end
	local Stock, Shapes = require("src.stockpile"), require("src.inventory.shapes")
	for i, shop in ipairs(Stock.shops(r.hub)) do
		local stock = Stock.stock(universe, r.hub, i)
		for _, e in ipairs(shop.sells or {}) do
			local _, _, cap = Shapes.of(e[1])
			local want = math.floor(e[2] * cap / 2)
			if stock and (stock[e[1]] or 0) < want then stock[e[1]] = want end
		end
	end
end

-- Online: a live NPC on a service visit to this hub reaches the buoy. Lock
-- it on at a free berth; false if there's none (it flies on, and its
-- upkeep finds somewhere else).
function Sat.npcDock(game, e, stop)
	local u = game.universe
	local r = e.alifeId and u.npcs[e.alifeId]
	if not r or e.dockState or not stop.sat or not Sat.hubRoom(u, stop.locationId, r) then return false end
	local taken = {}
	for _, o in ipairs(game.entities) do
		local ds = o ~= e and not o.dead and not o.removed and o.dockState
		if ds and ds.station and ds.station.entity == stop and ds.satSide then taken[ds.satSide] = true end
	end
	local lx = stop.body:getLocalPoint(e.body:getPosition())
	local side = lx < 0 and -1 or 1
	if taken[side] then side = -side end
	if taken[side] then return false end
	local st = Sat.station(game, stop)
	local bx, by = berthOffsetFor(stop, e, side)
	e.dockState = { station = st, phase = "tractor", t = 0, satBerth = { bx, by }, satSide = side }
	e.intent.firePrimary, e.intent.fireSecondary, e.intent.fireTertiary = false, false, false
	return true
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
	if r then Sat.markLost(game.universe, r) end
end

-- Gone for good: its system posts a job to launch a replacement (free for
-- now). The replacement keeps the id, name and kind, so quests still find it.
function Sat.markLost(universe, r)
	if r.lost then return end
	r.lost = true
	require("src.sat_jobs").clear(universe, r.id, "satrefuel")
	require("src.sat_jobs").post(universe, r, "satlaunch")
end

-- The launch job is done: the slot is live again, and the next load of its
-- field spawns a fresh satellite at its home orbit.
function Sat.relaunch(universe, id, by)
	local r = Sat.get(universe, id)
	if not r or not r.lost then return false end
	r.lost, r.hp, r.spawnedAt = nil, nil, nil
	r.fuel, r.fuelAt, r.dryAt = 1, universe.clock or 0, nil
	require("src.events").emit("sat_launched", id, by)
	require("src.sat_jobs").clear(universe, id, "satlaunch")
	return true
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
		Sat.markLost(game.universe, r)
		e.sat, e.name = nil, nil
		game:spark(e.body:getX(), e.body:getY(), 24, { 1, 0.7, 0.35 })
		game:explode(e.body:getX(), e.body:getY(), (e.radius or 100) * 0.3, 0, 0)
	end
end

-- Where things are, for NPC work out at a satellite (src/sat_jobs.lua) ------

-- The live husk (or hub buoy) of a satellite on the loaded map.
function Sat.entity(game, id)
	for _, e in ipairs(game.entities or {}) do
		if e.sat == id and not e.removed and not e.dead and e.body and not e.body:isDestroyed() then return e end
	end
end

-- Its home position: a hub rides its buoy's track; an orbiting satellite
-- its seeded layout slot, about the planet (the map's origin).
function Sat.home(universe, r, game)
	local L = require("src.locations")
	if r.hub then return L.position(r.hub, universe.clock or 0) end
	if not r.alt then
		local Fields = require("src.fields")
		for _, slot in ipairs(Sat.layout(r.field, Fields[r.field])) do
			if slot.id == r.id then r.alt, r.angle = slot.alt, slot.angle end
		end
		if not r.alt then return end
	end
	local w = game and game.fieldId == r.field and game.well
	local cx, cy = w and w.x or 0, w and w.y or 0
	return cx + math.cos(r.angle) * r.alt, cy + math.sin(r.angle) * r.alt
end

-- The berth beside a satellite for `ship`, in world space, with the
-- berth's velocity (it turns and drifts with the satellite).
function Sat.berthPoint(e, ship)
	local bx, by = berthOffsetFor(e, ship)
	local x, y = e.body:getWorldPoint(bx, by)
	local vx, vy = e.body:getLinearVelocityFromWorldPoint(x, y)
	return x, y, vx, vy
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
	-- a hub's shelf is its buoy's stock, shared with ships served there
	st.sat, st.key, st.name, st.body, st.entity = r.id, r.hub or ("sat:" .. r.id), r.name, e.body, e
	st.locationId = r.hub
	st.marketId = "sat:" .. r.kind
	st.def = { services = services, marketId = st.marketId, repairRate = 2 }
	return st
end

-- Where the berth is, in the satellite's frame: off the side of the bus the
-- ship came from.
-- side: -1 or 1, which berth; nil picks the one nearer the ship. A hub
-- (on a trade buoy) has a berth pad off each docking arm; a satellite's
-- berths are either side of the bus.
local function berthOffset(e, ship, side)
	local lx, ly = e.body:getLocalPoint(ship.body:getPosition())
	if e.kind == "buoy" then
		side = side or (lx < 0 and -1 or 1)
		return side * (340 * (e.propScale or 1) + (ship.halfLength or 40) + 30), 0
	end
	side = side or (ly < 0 and -1 or 1)
	return 0, side * ((e.radius or 300) * 0.25 + (ship.halfLength or 40) + 40)
end
berthOffsetFor = berthOffset

function Sat.request(game, e)
	local r = Sat.get(game.universe, e.sat)
	local p = game.player
	if not r or not p or p.dead or p.dockState then return false end
	local held = e.satHeld
	local npcOn = held and held.alifeRecord and held.alifeRecord.action and held.alifeRecord.action.operation == "satservice"
	if e.kind ~= "buoy" and held and held ~= p and not held.dead and not held.removed and (held.dockState or npcOn) then game:toast("BERTH OCCUPIED", 1.4); return false end
	if not Sat.permits(game, r, p) then game:toast("DOCKING REFUSED", 1.6); return false end
	local st = Sat.station(game, e)
	local side
	if e.kind == "buoy" then
		local taken = {}
		for _, o in ipairs(game.entities) do
			local ds = o ~= p and not o.dead and not o.removed and o.dockState
			if ds and ds.station and ds.station.entity == e and ds.satSide then taken[ds.satSide] = true end
		end
		local lx = e.body:getLocalPoint(p.body:getPosition())
		side = lx < 0 and -1 or 1
		if taken[side] then side = -side end
		if taken[side] then game:toast("BERTHS OCCUPIED", 1.4); return false end
	end
	local bx, by = berthOffset(e, p, side)
	p.dockState = { station = st, phase = "tractor", t = 0, satBerth = { bx, by }, satSide = side }
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
			if ship.alifeId then Sat.npcDocked(game, ship, st) end
			require("src.events").emit("dock", ship, st)
		end
	else
		-- moored: ride along at the berth
		b:setPosition(wx, wy)
		b:setLinearVelocity(fvx, fvy)
		b:setAngularVelocity(sb:getAngularVelocity())
		if ship.alifeId and Sat.npcDeparts(game, ship, st) then return end
	end
end

-- Online NPC on the hub's berth: the same docked visit as a station's
-- (src/upkeep.lua), off the hub's shelf.
function Sat.npcDocked(game, e, st)
	local u = game.universe
	local r = u.npcs[e.alifeId]
	if not r then return end
	local node = st.locationId
	r.state, r.node, r.dockedAt, r.nextDecisionAt = "docked", node, u.clock, nil
	require("src.npc_repair").begin(r, node, u.clock, require("src.tuning").alifeStay, u)
	require("src.supplies").online(game, e)
end
function Sat.npcDeparts(game, e, st)
	local u = game.universe
	local r = u.npcs[e.alifeId]
	local Upkeep = require("src.upkeep")
	local short = r and r.service and Upkeep.isStation(r, st.locationId) and Upkeep.hubShort(r, u)
	if not short and r and r.service and Upkeep.isStation(r, st.locationId) and not Upkeep.canDepart(game, e, r) then return false end
	local A = require("src.alife")
	A.capture(game, e, false)
	Sat.undock(game, e)
	if short then
		Upkeep.abandonHub(r, u.clock, e)
		A.bindRoute(game, e, r)
	elseif r then
		if r.service then r.index = #r.route; Upkeep.passed(r, #r.route) end
		r.state, r.node, r.untilTime, r.nextDecisionAt = "idle", st.locationId, u.clock, nil
		A.bindRoute(game, e, r)
	end
	return true
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
