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
	-- a hub: a larger satellite with a shop, a mini station for ships
	-- passing through (placed per planet: data/satellite_orbits.lua, hubs)
	hub = { design = "sat_hub", dock = "anyone", actions = { "vend" },
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
	-- hubs: their own slots (ids <field>_hub_<n>), after the mix,
	-- so adding hubs never reshuffles a field's other satellites
	for n = 1, def.hubs or 0 do
		local f = 0.3 + rng:random() * 0.3
		-- each hub keeps station by one of the field's trade buoys, where the
		-- routes already pass (Sat.hubPoint); none left: a plain slot
		local buoys = require("src.fields")[fieldId] and require("src.fields")[fieldId].buoyIds or {}
		out[#out + 1] = { id = ("%s_hub_%d"):format(fieldId, n), n = n, kind = "hub", buoy = buoys[n],
			alt = R + (edge - R) * f, angle = rng:random() * math.pi * 2, owner = def.owner,
			name = ("%s trade hub%s"):format(def.names or field.name or fieldId, (def.hubs or 0) > 1 and (" " .. n) or "") }
	end
	return out
end

-- The record for a satellite, made from its layout slot the first time.
function Sat.record(universe, slot, fieldId)
	local all = store(universe)
	local r = all[slot.id]
	if not r then
		local K = Sat.kinds[slot.kind]
		r = { id = slot.id, field = fieldId, kind = slot.kind, name = slot.name, owner = slot.owner, buoy = slot.buoy }
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
	local open = require("src.sat_jobs").open(universe, "satrefuel")
	for id, r in pairs(all) do
		-- low on its own fuel, or (a hub) its shelf nearly out of canisters
		local low = not r.lost and (Sat.fuel(universe, r) < Sat.refuelAt or Sat.hubLow(universe, r))
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
		r.buoy = r.buoy or slot.buoy
		r.alt = r.alt or slot.alt
		if not r.rate and not r.buoy and game.currentSpeed then
			-- first visit: learn the current's turn rate at its altitude, and
			-- phase the slot so it's where it is now (an old save's satellite
			-- where it was left, a new one at its seeded angle)
			r.rate = game:currentSpeed(r.alt) / math.max(1, r.alt)
			local a = r.angle or slot.angle
			if e and e.body and not e.body:isDestroyed() then
				local ex, ey = e.body:getPosition()
				a = math.atan2(ey - cy, ex - cx)
			end
			r.angle = a - r.rate * (game.universe.clock or 0)
		end
		if not e and not r.lost and data.wrecks[r.design] then
			local x, y = Sat.restPoint(game.universe, r)
			local nx, ny = Sat.slotPoint(game.universe, r, (game.universe.clock or 0) + 1)
			local sx, sy = Sat.slotPoint(game.universe, r, game.universe.clock or 0)
			if x then
				local vx, vy = nx - sx, ny - sy
				e = game:spawnWreck(r.design, cx + x, cy + y, math.atan2(y, x) + math.pi / 2, vx, vy)
			end
			if e then
				r.spawnedAt = game.universe.clock or 0
				game:stepOutOfStations(e)
			end
		end
		if e then Sat.adopt(e, r) end
	end
end

-- NPCs and hubs ---------------------------------------------------------------
--
-- A working hub (kind "hub") sells fuel and supplies off its own shelf to the
-- player and NPCs alike. An NPC short of fuel or ammunition (src/upkeep.lua's
-- needs) with a working hub nearby flies out to it with the same work action
-- the refuel haulers use (src/sat_jobs.lua, operation "hubservice"), holds on
-- its berth, buys what it needs and carries on. One ship at a time, like any
-- satellite berth. Each ship served burns a little of the hub's own fuel
-- (Sat.hubServeCost), so busy hubs ask for refuels sooner, and a hub low on
-- canisters gets a refuel job too; that hauler restocks the shelf. No repairs.
Sat.hubServeCost, Sat.hubLowStock = 0.02, 4

-- Its shelf, as the stockpile sees it (the same key the docked screen uses).
function Sat.shelf(r) return { key = "sat:" .. r.id, marketId = "sat:" .. r.kind } end

function Sat.hubWorking(universe, r)
	return r and r.kind == "hub" and not r.lost and Sat.fuel(universe, r) > 0 or false
end

-- A ship was served: the hub's own fuel pays for it.
function Sat.hubServed(universe, r)
	Sat.fuel(universe, r)
	r.fuel = math.max(0, r.fuel - Sat.hubServeCost)
	if r.fuel <= 0 and not r.dryAt then r.dryAt = universe.clock or 0 end
	r.served = (r.served or 0) + 1
end

-- Low on canisters to sell.
function Sat.hubLow(universe, r)
	return r.kind == "hub" and require("src.stockpile").available(universe, Sat.shelf(r),
		require("src.reactor_fuel").item()) < Sat.hubLowStock
end

-- What a hub's shelf is short of: each listed good up to half its listed
-- amount. The refuel hauler brings it from its trade station's stock
-- (src/sat_jobs.lua) and Sat.stockHub puts it on the shelf.
function Sat.hubShortfall(universe, r)
	local out = {}
	if r.kind ~= "hub" then return out end
	local Stock, Shapes = require("src.stockpile"), require("src.inventory.shapes")
	local shelf = Sat.shelf(r)
	for i, shop in ipairs(Stock.shops(shelf)) do
		local stock = Stock.stock(universe, shelf, i)
		for _, e in ipairs(shop.sells or {}) do
			local _, _, cap = Shapes.of(e[1])
			local want = math.floor(e[2] * cap / 2) - (stock and stock[e[1]] or 0)
			if want > 0 then out[e[1]] = want end
		end
	end
	return out
end
function Sat.stockHub(universe, r, item, n)
	if r.kind ~= "hub" or n <= 0 then return end
	require("src.stockpile").add(universe, Sat.shelf(r), item, n)
end

-- The nearest working hub on a map to (x, y). Hubs are only placed where
-- markets are sparse, so any hub on the same map is worth the trip.
function Sat.nearestHub(universe, area, x, y)
	local best, bestD
	for _, r in pairs(store(universe)) do
		if r.field == area and Sat.hubWorking(universe, r) then
			local hx, hy = Sat.home(universe, r)
			if hx then
				local d = (hx - x) ^ 2 + (hy - y) ^ 2
				if not bestD or d < bestD then best, bestD = r, d end
			end
		end
	end
	return best
end

-- Tag a husk as this satellite.
function Sat.adopt(e, r)
	e.sat, e.name = r.id, r.name
	if e.body and not e.body:isDestroyed() then
		e.body:setAngularVelocity(0)
		e.body:setAngularDamping(2)
	end
end

-- Station-keeping -------------------------------------------------------------
--
-- What the fuel is for. A fuelled satellite holds its slot: its own
-- altitude, and its place along the orbit (the slot's angle, turning at the
-- current's rate there, r.rate, learnt the first time the field is
-- visited), so a bump only pushes it away for a while. A hub's slot is
-- Sat.hubOffset outward from its trade buoy, so it travels with the buoy.
-- Dry, it stops correcting: it rides the current wherever it was knocked
-- and sinks Sat.decay px/s, never below Sat.floor of the planet's radius,
-- until a refuel brings it climbing back.
Sat.hubOffset, Sat.decay, Sat.floor = 1100, 1, 1.15
Sat.keepGain, Sat.keepMax, Sat.keepBlend = 0.4, 80, 2

-- Where the slot is at `clock`, about the planet (the map's origin).
function Sat.slotPoint(universe, r, clock)
	if r.buoy then
		local x, y = require("src.locations").position(r.buoy, clock)
		local d = math.max(1, math.sqrt(x * x + y * y))
		return x + x / d * Sat.hubOffset, y + y / d * Sat.hubOffset
	end
	if not r.alt then
		local Fields = require("src.fields")
		for _, slot in ipairs(Sat.layout(r.field, Fields[r.field])) do
			if slot.id == r.id then r.alt, r.angle = slot.alt, slot.angle end
		end
		if not r.alt then return end
	end
	local a = r.angle + (r.rate or 0) * clock
	return math.cos(a) * r.alt, math.sin(a) * r.alt
end
function Sat.hubPoint(universe, r) return Sat.slotPoint(universe, r, universe.clock or 0) end

-- Where it is offline: on its slot, or (dry) sunk below it by now.
function Sat.restPoint(universe, r)
	local x, y = Sat.slotPoint(universe, r, universe.clock or 0)
	if not x then return end
	if Sat.dry(r) and r.dryAt then
		local d = math.max(1, math.sqrt(x * x + y * y))
		local F = require("src.fields")[r.field]
		local low = F and F.planetR and F.planetR * Sat.floor or 0
		local to = math.max(low, d - Sat.decay * math.max(0, (universe.clock or 0) - r.dryAt))
		x, y = x / d * to, y / d * to
	end
	return x, y
end

-- Every step, for each satellite on the map (Game:update, after the current).
function Sat.keep(game, dt)
	local u, w = game.universe, game.well
	if not u or not w or dt <= 0 then return end
	local clock = u.clock or 0
	for _, e in ipairs(game.entities) do
		local r = e.sat and not e.removed and not e.dead and Sat.get(u, e.sat)
		local b = r and e.body
		if b and not b:isDestroyed() and b:getType() == "dynamic" then
			local x, y = b:getPosition()
			local vx, vy = b:getLinearVelocity()
			local wx, wy, k = vx, vy, math.min(1, dt * Sat.keepBlend)
			if Sat.fuel(u, r) > 0 then
				local tx, ty = Sat.slotPoint(u, r, clock)
				local nx, ny = Sat.slotPoint(u, r, clock + 1)
				if tx then
					tx, ty, nx, ny = tx + w.x, ty + w.y, nx + w.x, ny + w.y
					local ex, ey = (tx - x) * Sat.keepGain, (ty - y) * Sat.keepGain
					local m = math.sqrt(ex * ex + ey * ey)
					if m > Sat.keepMax then ex, ey = ex / m * Sat.keepMax, ey / m * Sat.keepMax end
					wx, wy = nx - tx + ex, ny - ty + ey
				end
			else
				-- dry: let its radial motion settle into a slow sink
				local dx, dy = x - w.x, y - w.y
				local d = math.max(1, math.sqrt(dx * dx + dy * dy))
				local ux, uy = dx / d, dy / d
				local vr = vx * ux + vy * uy
				local want = d > (game.field.planetR or 0) * Sat.floor and -Sat.decay or 0
				wx, wy = vx + (want - vr) * ux, vy + (want - vr) * uy
			end
			b:setLinearVelocity(vx + (wx - vx) * k, vy + (wy - vy) * k)
		end
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

-- The live husk of a satellite on the loaded map.
function Sat.entity(game, id)
	for _, e in ipairs(game.entities or {}) do
		if e.sat == id and not e.removed and not e.dead and e.body and not e.body:isDestroyed() then return e end
	end
end

-- Its home position: its seeded layout slot, about the planet (the map's
-- origin). Online, Sat.entity gives where it has actually drifted to.
function Sat.home(universe, r, game)
	local x, y = Sat.restPoint(universe, r)
	if not x then return end
	local w = game and game.fieldId == r.field and game.well
	return (w and w.x or 0) + x, (w and w.y or 0) + y
end

-- The berth beside a satellite for `ship`, in world space, with the
-- berth's velocity (it turns and drifts with the satellite).
function Sat.berthPoint(e, ship, i)
	local bx, by = berthOffsetFor(e, ship, i)
	local x, y = e.body:getWorldPoint(bx, by)
	local vx, vy = e.body:getLinearVelocityFromWorldPoint(x, y)
	return x, y, vx, vy
end

-- Berths -------------------------------------------------------------------
--
-- A satellite's berths come from its design: every part ticked "Docking
-- module" in the editor has one berth, just off that part's outer side
-- (away from the satellite's centre). No runway, no tractor zone: a ship
-- locks on and is pulled to the berth. A design without one can't be
-- docked at. Each berth is claimed on its own: an NPC through its work
-- action's claim on the berth record (r.berths[i], saved with the
-- satellite), the player through the live husk's e.berthHeld[i] while
-- locked on. Neither takes a berth the other holds.
local dockCache = setmetatable({}, { __mode = "k" })
-- The design's docking parts: { cx, cy (part centre), ux, uy (outward),
-- reach (how far the part extends that way from its centre) }.
function Sat.docks(def)
	if not def then return {} end
	if dockCache[def] then return dockCache[def] end
	local out = {}
	for _, part in ipairs(def.parts or {}) do
		if part.dock and part.shape then
			local sh, cx, cy, n = part.shape, 0, 0, #part.shape / 2
			for k = 1, #sh, 2 do cx, cy = cx + sh[k], cy + sh[k + 1] end
			cx, cy = cx / n, cy / n
			local d = math.sqrt(cx * cx + cy * cy)
			local ux, uy = d > 1 and cx / d or 0, d > 1 and cy / d or 1
			local reach = 0
			for k = 1, #sh, 2 do reach = math.max(reach, (sh[k] - cx) * ux + (sh[k + 1] - cy) * uy) end
			out[#out + 1] = { cx = cx, cy = cy, ux = ux, uy = uy, reach = reach }
		end
	end
	dockCache[def] = out
	return out
end
function Sat.berthCount(r) return #Sat.docks(data.wrecks[r.design]) end
function Sat.berth(r, i)
	r.berths = r.berths or {}
	r.berths[i] = r.berths[i] or {}
	return r.berths[i]
end
-- The live player on berth i, if any.
function Sat.playerOn(e, i)
	local p = e and e.berthHeld and e.berthHeld[i]
	if p and not p.dead and not p.removed and p.dockState and p.dockState.station and p.dockState.station.entity == e then return p end
	if e and e.berthHeld then e.berthHeld[i] = nil end
end
-- An NPC's live claim on berth i.
function Sat.npcOn(universe, r, i)
	local b = r.berths and r.berths[i]
	local owner = b and b.actionOwner and universe.npcs and universe.npcs[b.actionOwner]
	local a = owner and owner.action
	return owner and owner.state ~= "dead" and a and not a.pausedAt and a.key == b.actionKey or false
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
-- side: -1 or 1, which berth; nil picks the one nearer the ship. A hub has
-- a berth pad off each docking arm; other satellites, either side of the bus.
-- Berth i, in the satellite's frame: off the outer side of its docking
-- part, far enough out for this ship's hull.
local function berthOffset(e, ship, i)
	local d = Sat.docks(e.hull)[i or 1]
	-- (no docking module: a service ship holds just off the bus)
	if not d then return 0, (e.radius or 300) * 0.25 + (ship.halfLength or 40) + 40 end
	local out = d.reach + (ship.halfLength or 40) + 30
	return d.cx + d.ux * out, d.cy + d.uy * out
end
berthOffsetFor = berthOffset

function Sat.request(game, e)
	local r = Sat.get(game.universe, e.sat)
	local p = game.player
	if not r or not p or p.dead or p.dockState then return false end
	-- the nearest free berth: neither an NPC's nor already the player's
	local count = Sat.berthCount(r)
	if count == 0 then game:toast("NO BERTH", 1.4); return false end
	local free, best
	for i = 1, count do
		if not Sat.playerOn(e, i) and not Sat.npcOn(game.universe, r, i) then
			local bx, by = e.body:getWorldPoint(berthOffset(e, p, i))
			local px, py = p.body:getPosition()
			local d = (bx - px) ^ 2 + (by - py) ^ 2
			if not best or d < best then free, best = i, d end
		end
	end
	if not free then game:toast("BERTH OCCUPIED", 1.4); return false end
	if not Sat.permits(game, r, p) then game:toast("DOCKING REFUSED", 1.6); return false end
	local st = Sat.station(game, e)
	local bx, by = berthOffset(e, p, free)
	p.dockState = { station = st, phase = "tractor", t = 0, satBerth = { bx, by }, satBerthIndex = free }
	p.intent.firePrimary, p.intent.fireSecondary, p.intent.fireTertiary = false, false, false
	e.berthHeld = e.berthHeld or {}
	e.berthHeld[free] = p
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
			if e.berthHeld and ds.satBerthIndex then e.berthHeld[ds.satBerthIndex] = nil end
			ship.dockState, ship.dockCooldown = nil, 3
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
		if e.berthHeld and ds.satBerthIndex then e.berthHeld[ds.satBerthIndex] = nil end
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
