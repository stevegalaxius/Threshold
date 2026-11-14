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

return Sat
