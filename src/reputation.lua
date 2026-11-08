--[[
	Factions and reputation, STALKER-style but without faction warfare.

	Three saved numbers, each -100..100, all drifting back to rest over the
	universe clock (so they work the same whether or not anyone is watching):

	  standing  per faction   u.reputation.standing[faction]
	  heat      per node      u.reputation.heat[nodeId]   (local, stays put)
	  goodwill  per NPC       record.goodwill

	What an NPC (or a station) thinks of the player is
	    goodwill + standing(its faction) - heat(its node)
	read through Rep.attitude, and turned into a tier by Rep.tier.

	There are no faction-vs-faction relations and no territory: who owns a
	node is fixed lore (Rep.FACTIONS / Rep.AREAS / Rep.NODES). Loners have no
	faction, so only their own goodwill and local heat count.
]]

local Rep = {}

Rep.FACTIONS = {
	estates   = { name = "The Estates",    major = true },
	zhuhai    = { name = "Zhuhai",         major = true },
	diwan     = { name = "The Diwan",      major = true },
	jove      = { name = "Jove",           major = true },
	ceres     = { name = "Ceres Concern" },
	milliways = { name = "Milliways" },
	bowman    = { name = "Bowman Atmospherics" },
}
Rep.ORDER = { "estates", "zhuhai", "diwan", "jove", "ceres", "milliways", "bowman" }

-- Who owns each area. Lore, not a world variable: nothing changes it.
Rep.AREAS = {
	mercury = "estates", venus = "estates", earth = "estates", luna = "estates", station = "estates",
	mars = "zhuhai", phobos = "zhuhai", deimos = "zhuhai",
	belt = "ceres", ceres_quarry = "ceres", quarry = "ceres",
	jupiter = "jove", io = "jove", europa = "jove", ganymede = "jove", callisto = "jove",
	saturn = "diwan", enceladus = "diwan", titan = "diwan",
	uranus = "bowman", titania = "bowman",
}
-- Single nodes that differ from their area (secondary factions' holdings).
Rep.NODES = {
	["station:pluto_1"] = "milliways",
}

-- Tiers, lowest first: the first whose max the value is under.
Rep.TIERS = {
	{ id = "hostile",  name = "Hostile",  max = -50 },
	{ id = "wary",     name = "Wary",     max = -15 },
	{ id = "neutral",  name = "Neutral",  max = 15 },
	{ id = "friendly", name = "Friendly", max = 50 },
	{ id = "trusted",  name = "Trusted",  max = math.huge },
}

-- Tuning (points, and points per hour of universe clock toward rest).
Rep.T = {
	standingDecay = 2,      -- a faction forgives slowly
	goodwillDecay = 10,     -- one ship forgets faster
	heatDecay = 600,        -- local heat cools in minutes
	heatPerHit = 15,        -- shooting a station: four hits and its guns answer
	heatMax = 100,
	standingPerHit = -1,    -- shooting a faction's station or patrol
	standingPerKill = -15,  -- killing one of its patrols
	standingPirateKill = 3, -- killing a pirate in its space
	goodwillPerHit = -20,   -- the ship you shot
}

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

local function store(u)
	u.reputation = u.reputation or { standing = {}, heat = {} }
	local s = u.reputation
	s.standing, s.heat = s.standing or {}, s.heat or {}
	return s
end

-- A decaying value { v = number, t = clock }: what it is now.
local function now(cell, rate, clock, rest)
	if not cell then return rest or 0 end
	rest = rest or 0
	local d = rate * math.max(0, clock - (cell.t or clock)) / 3600
	local v = cell.v
	if v > rest then v = math.max(rest, v - d) else v = math.min(rest, v + d) end
	return v
end
local function bump(cell, rate, clock, by, lo, hi)
	local v = clamp(now(cell, rate, clock) + by, lo, hi)
	return { v = v, t = clock }
end

---------------------------------------------------------------- ownership

function Rep.areaOf(nodeId)
	return type(nodeId) == "string" and nodeId:match("^%a+:(.-)_%d+$") or nil
end

-- The faction that owns a node (or nil for unowned / loner space).
function Rep.ofNode(nodeId)
	local n = Rep.NODES[nodeId]
	if n ~= nil then return n or nil end
	local a = Rep.areaOf(nodeId)
	return a and Rep.AREAS[a] or nil
end
function Rep.ofArea(area) return area and Rep.AREAS[area] or nil end

-- An NPC record's faction: patrols serve whoever owns their home; every
-- other role is a loner. A record may carry an explicit faction.
function Rep.ofRecord(r)
	if not r then return nil end
	if r.faction ~= nil then return r.faction or nil end
	if r.role ~= "patrol" then return nil end
	return Rep.ofNode(r.homeNode or r.homeStation) or Rep.ofArea(r.home or r.area)
end

---------------------------------------------------------------- reads

function Rep.standing(u, f)
	if not f then return 0 end
	return now(store(u).standing[f], Rep.T.standingDecay, u.clock or 0)
end
function Rep.heat(u, nodeId)
	if not nodeId then return 0 end
	return now(store(u).heat[nodeId], Rep.T.heatDecay, u.clock or 0)
end
function Rep.goodwill(u, r)
	return r and now(r.goodwill, Rep.T.goodwillDecay, u.clock or 0) or 0
end

function Rep.tier(v)
	for _, t in ipairs(Rep.TIERS) do if v < t.max then return t end end
	return Rep.TIERS[#Rep.TIERS]
end
function Rep.tierName(v) return Rep.tier(v).name end
-- What a station node thinks of the player.
function Rep.stationAttitude(u, nodeId)
	return clamp(Rep.standing(u, Rep.ofNode(nodeId)) - Rep.heat(u, nodeId), -100, 100)
end
-- What an NPC record thinks of the player (nodeId: where it is, for heat).
function Rep.attitude(u, r, nodeId)
	return clamp(Rep.goodwill(u, r) + Rep.standing(u, Rep.ofRecord(r)) - Rep.heat(u, nodeId), -100, 100)
end
function Rep.hostile(v) return Rep.tier(v).id == "hostile" end

-- Market price factor at a node: friends get discounts, the wary pay more.
local PRICE = { hostile = 1.25, wary = 1.1, neutral = 1, friendly = 0.95, trusted = 0.9 }
function Rep.priceFactor(u, nodeId)
	if not nodeId then return 1 end
	return PRICE[Rep.tier(Rep.stationAttitude(u, nodeId)).id]
end

---------------------------------------------------------------- writes

function Rep.addStanding(u, f, by)
	if not f or by == 0 then return end
	local s = store(u)
	s.standing[f] = bump(s.standing[f], Rep.T.standingDecay, u.clock or 0, by, -100, 100)
end
function Rep.addHeat(u, nodeId, by)
	if not nodeId or by == 0 then return end
	local s = store(u)
	s.heat[nodeId] = bump(s.heat[nodeId], Rep.T.heatDecay, u.clock or 0, by, 0, Rep.T.heatMax)
end
function Rep.addGoodwill(u, r, by)
	if not r or by == 0 then return end
	r.goodwill = bump(r.goodwill, Rep.T.goodwillDecay, u.clock or 0, by, -100, 100)
end

-- The player shot a station.
function Rep.stationHit(u, nodeId)
	Rep.addHeat(u, nodeId, Rep.T.heatPerHit)
	Rep.addStanding(u, Rep.ofNode(nodeId), Rep.T.standingPerHit)
end
-- The player shot an NPC (record r, at node or area).
function Rep.shipHit(u, r)
	Rep.addGoodwill(u, r, Rep.T.goodwillPerHit)
	Rep.addStanding(u, Rep.ofRecord(r), Rep.T.standingPerHit)
end
-- The player killed an NPC; area is where it happened.
function Rep.shipKilled(u, r, area)
	local f = Rep.ofRecord(r)
	if f then Rep.addStanding(u, f, Rep.T.standingPerKill)
	elseif r and r.role == "pirate" then Rep.addStanding(u, Rep.ofArea(area), Rep.T.standingPirateKill) end
end

-- Helping, heard from the world's event log (src/simulation_history.lua):
-- the ship you saved remembers it, and whoever owns the node where it
-- happened saw it (a faction watches its own space).
Rep.T.goodwillRescue = 35
Rep.T.standingRescue = 3
function Rep.onOutcome(u, e)
	if e.kind == "rescued" and e.result and e.result.rescuer == "player" then
		local victim = u.npcs and u.npcs[e.participants[1]]
		Rep.addGoodwill(u, victim, Rep.T.goodwillRescue)
		Rep.addStanding(u, e.node and Rep.ofNode(e.node) or Rep.ofArea(e.area), Rep.T.standingRescue)
	end
end
-- Hook the listener once per game (the universe can be swapped on load).
function Rep.listen(game)
	Rep.game = game
	if Rep.listening then return end
	Rep.listening = require("src.events").on("simulation_outcome", function(e)
		local g = Rep.game
		if g and g.universe then Rep.onOutcome(g.universe, e) end
	end)
end

-- Drop heat that has cooled all the way (keeps saves small).
function Rep.prune(u)
	local s = store(u)
	for id in pairs(s.heat) do if Rep.heat(u, id) <= 0 then s.heat[id] = nil end end
end

-- One line per faction, for UI.
function Rep.summary(u)
	local out = {}
	for _, f in ipairs(Rep.ORDER) do
		local v = Rep.standing(u, f)
		out[#out + 1] = { id = f, name = Rep.FACTIONS[f].name, major = Rep.FACTIONS[f].major, value = v, tier = Rep.tierName(v) }
	end
	return out
end

return Rep
