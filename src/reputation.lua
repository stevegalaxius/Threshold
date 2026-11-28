--[[
	Factions and reputation, STALKER-style but without faction warfare.

	Three saved numbers, each -100..100, all drifting back to rest over the
	universe clock (so they work the same whether or not anyone is watching):

	  standing  per faction   u.reputation.standing[faction]
	  heat      per node      u.reputation.heat[nodeId]   (local, stays put)
	  goodwill  per NPC       record.goodwill

	Standing has two parts. What a faction saw for itself (in its own
	space) is counted straight away. What it only read about comes in
	through the news (src/news.lua) as reported standing: a separate,
	faster-fading number, rate-capped per hour, that can never push a
	faction past Wary on its own. Rep.standing is the sum.

	What an NPC (or a station) thinks of the player is
	    goodwill + standing(its faction) - heat(its node)
	read through Rep.attitude, and turned into a tier by Rep.tier.

	Rep.STANCE supplies starting relationships between factions. A universe
	can override a pair through Rep.setStance. Territory and station ownership
	are authored in Rep.AREAS and Rep.NODES.
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
	-- Providence (the belt hub across the Sun from Ceres): a neutral
	-- exchange open to every house and owned by all of them jointly.
	providence = { name = "Providence" },
}
Rep.ORDER = { "estates", "zhuhai", "diwan", "jove", "ceres", "milliways", "bowman", "providence" }

-- The cartel and how each major power treats it. A hostile power embargoes
-- it (Rep.embargoed: no trade with cartel stations, no contraband in its
-- markets except through a fence) and its patrols shoot cartel crews on
-- sight in its own space (src/security.lua). Ambivalent powers trade with
-- the cartel like anyone else and leave its crews alone unless they start
-- something.
--   Estates: the labs run on medicine bought out from under the Garden.
--   Diwan:   a devout House, and the cartel's brine and chemistry are
--            smuggled out of its own moons.
--   Jove:    a customer is a customer; Kyrakos looks the other way.
--   Zhuhai:  the Mandate can't agree on a crackdown, and the spokes run on stims.
-- Other code reads this through Rep.stance, so notables and news can use it.
Rep.CARTEL = "milliways"
Rep.STANCE = {
	milliways = { estates = "hostile", diwan = "hostile", jove = "ambivalent", zhuhai = "ambivalent" },
}
-- Relationships are mutual. A universe can override the authored starting
-- stance without affecting other saves, or clear an override with nil.
local function pair(a,b)
	if b<a then return b..':'..a end
	return a..':'..b
end

function Rep.stance(a,b,u)
	if not a or not b or a==b then return nil end
	local relations=u and u.reputation and u.reputation.factions
	return (relations and relations[pair(a,b)])
		or (Rep.STANCE[a] and Rep.STANCE[a][b]) or (Rep.STANCE[b] and Rep.STANCE[b][a]) or nil
end

function Rep.setStance(u,a,b,stance)
	assert(a and b and a~=b and Rep.FACTIONS[a] and Rep.FACTIONS[b],'invalid faction pair')
	assert(stance==nil or stance=='neutral' or stance=='ambivalent' or stance=='hostile' or stance=='friendly','invalid faction stance')
	u.reputation=u.reputation or {}
	local rep=u.reputation
	rep.factions=rep.factions or {}
	rep.factions[pair(a,b)]=stance
end

-- Older cartel records identify their allegiance through their base or runner
-- role. Piracy alone is also used for independent crews such as wildcats.
function Rep.crewFaction(r)
	if not r then return end
	if r.affiliation then return r.affiliation end
	if r.wildcat then return end
	local home=r.homeStation
	if r.darkRunner or home and Rep.ofNode(require('src.locations').canonical(home))==Rep.CARTEL then
		return Rep.CARTEL
	end
end

function Rep.cartelCrew(r) return Rep.crewFaction(r)==Rep.CARTEL end

function Rep.hostileToCrew(u,owner,r)
	return Rep.stance(owner,Rep.crewFaction(r),u)=='hostile'
end

-- The cartel's product: what a hostile power's market refuses outside a fence.
Rep.CONTRABAND = { amphetamines = true, fentanyl = true, cannabinoid_moss = true }
-- Is trade from station s to station c blocked? A power hostile to the
-- cartel neither buys from nor sells to cartel stations, and buys no
-- contraband from anyone. Its fences (uses.fence) are the way in.
function Rep.embargoed(s, c, item)
	local L = require("src.locations")
	local Dark = require("src.dark")
	if Dark.isFence(c) or Dark.isFence(s) then return false end
	-- the drugs trade everywhere: illegal, but the stations buy them anyway;
	-- the risk is the police on the way in (src/contraband.lua)
	if item and Rep.CONTRABAND[item] then return false end
	local fs, fc = Rep.ofNode(L.canonical(s)), Rep.ofNode(L.canonical(c))
	local function hostile(f) return Rep.stance(f, Rep.CARTEL) == "hostile" end
	if fs == Rep.CARTEL and hostile(fc) then return true end
	if fc == Rep.CARTEL and hostile(fs) then return true end

	return false
end

-- Who owns each area. Lore, not a world variable: nothing changes it.
Rep.AREAS = {
	mercury = "estates", venus = "estates", earth = "estates", luna = "estates", station = "estates",
	mars = "zhuhai", phobos = "zhuhai", deimos = "zhuhai",
	belt = "ceres", ceres_quarry = "ceres", quarry = "ceres", ring = "ceres",
	jupiter = "jove", io = "jove", europa = "jove", ganymede = "jove", callisto = "jove",
	saturn = "diwan", enceladus = "diwan", titan = "diwan",
	uranus = "bowman", titania = "bowman",
	milliways = "milliways", shoals = "milliways", cordelia = "milliways", antichthon = "milliways",
}
-- Single nodes that differ from their area (secondary factions' holdings).
Rep.NODES = {
	["station:pluto_1"] = "milliways",
	["station:ring_1"] = "providence",
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
	reportedDecay = 1.5,    -- what you read of someone fades a little slower than what you saw
	reportedFloor = -49,    -- reports alone stop short of Hostile
	reportedCap = 10,       -- most reported standing can move per hour, per faction
}

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

local function store(u)
	u.reputation = u.reputation or { standing = {}, heat = {} }
	local s = u.reputation
	s.standing, s.heat = s.standing or {}, s.heat or {}
	s.reported, s.drift = s.reported or {}, s.drift or {}
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

-- Affiliation is authored independently of occupation or active work.
function Rep.ofRecord(r) return r and r.affiliation or nil end

---------------------------------------------------------------- reads

-- What the faction saw itself.
function Rep.witnessed(u, f)
	if not f then return 0 end
	return now(store(u).standing[f], Rep.T.standingDecay, u.clock or 0)
end
-- What it read in the news.
function Rep.reported(u, f)
	if not f then return 0 end
	return now(store(u).reported[f], Rep.T.reportedDecay, u.clock or 0)
end
function Rep.standing(u, f)
	if not f then return 0 end
	return clamp(Rep.witnessed(u, f) + Rep.reported(u, f), -100, 100)
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
-- A story reached faction f (src/news.lua). Capped per hour, and never
-- pushes the total under reportedFloor by itself. Returns what landed.
function Rep.addReported(u, f, by, storyId)
	if not f or not Rep.FACTIONS[f] or by == 0 then return 0 end
	local s, clock = store(u), u.clock or 0
	local hour = math.floor(clock / 3600)
	local d = s.drift[f]
	if not d or d.hour ~= hour then d = { hour = hour, n = 0 }; s.drift[f] = d end
	local room = Rep.T.reportedCap - d.n
	if room <= 0 then return 0 end
	by = clamp(by, -room, room)
	local w, r = Rep.witnessed(u, f), Rep.reported(u, f)
	if by < 0 then
		local lowest = math.min(r, Rep.T.reportedFloor - w)  -- never deeper than it already is
		by = math.max(by, lowest - r)
		if by >= 0 then return 0 end
	end
	d.n = d.n + math.abs(by)
	s.reported[f] = { v = clamp(r + by, -100, 100), t = clock, story = storyId }
	return by
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
-- A faction watches its own space: what happens there it sees. Anywhere
-- else it only hears about it if the news prints it (src/news.lua).
local function seen(f, area) return area ~= nil and Rep.ofArea(area) == f end
-- The player shot an NPC (record r) in area.
function Rep.shipHit(u, r, area)
	Rep.addGoodwill(u, r, Rep.T.goodwillPerHit)
	local f = Rep.ofRecord(r)
	if not f then return end
	if area == nil or seen(f, area) then Rep.addStanding(u, f, Rep.T.standingPerHit)
	elseif r and not r.newsHit then
		-- out of its sight: a deed the papers may pick up, once per ship
		r.newsHit = true
		local News = require("src.news")
		News.deed(u, { faction = f, delta = News.T.hitDelta, area = area, kind = "hit", witnessed = false })
	end
end
-- The player killed an NPC; area is where it happened.
function Rep.shipKilled(u, r, area)
	local f = Rep.ofRecord(r)
	if f then
		local witnessed = seen(f, area)
		if witnessed then Rep.addStanding(u, f, Rep.T.standingPerKill) end
		if area then require("src.news").deed(u, { faction = f, delta = Rep.T.standingPerKill, area = area, witnessed = witnessed }) end
	elseif r and r.wildcat then Rep.addStanding(u, Rep.ofArea(r.home), Rep.T.standingPirateKill)
	elseif r and (r.deathOutlaw or require("src.npc_access").raiding(r)) then Rep.addStanding(u, Rep.ofArea(area), Rep.T.standingPirateKill) end
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
		local f = e.node and Rep.ofNode(e.node) or Rep.ofArea(e.area)
		Rep.addStanding(u, f, Rep.T.standingRescue)
		require("src.news").addStanding(u, require("src.news").ofFaction(f), 3)
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
		out[#out + 1] = { id = f, name = Rep.FACTIONS[f].name, major = Rep.FACTIONS[f].major, value = v, tier = Rep.tierName(v), reported = Rep.reported(u, f) }
	end
	return out
end

return Rep
