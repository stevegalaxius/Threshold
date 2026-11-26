-- Faction and ownership rules shared by live combat and targeting displays.
local Access = require("src.npc_access")
local Rep = require("src.reputation")
local C = {}

function C.controller(e)
	return e and e.drone and e.owner or e
end

local function faction(e)
	if e.kind == "station" then return Rep.ofNode(e.locationId or e.key) end
	return Rep.crewFaction(e.alifeRecord)
end

local function friendlyFactions(u, af, bf)
	return af and bf and (af == bf or Rep.stance(af, bf, u) == "friendly")
end

local function alliedCrews(u, a, b)
	if not a or not b then return false end
	local aw, bw = a.wildcat, b.wildcat
	if aw and bw and aw.site and aw.site == bw.site then return true end
	return u and require("src.squads").allied(u, a, b) or false
end

function C.recordsAllied(u, a, b)
	return a and b and (a == b or friendlyFactions(u, Rep.crewFaction(a), Rep.crewFaction(b))
		or alliedCrews(u, a, b)) or false
end

function C.allied(u, a, b)
	a, b = C.controller(a), C.controller(b)
	if not a or not b then return false end
	if a == b or friendlyFactions(u, faction(a), faction(b)) then return true end
	if (a.siteEnemy and b.siteEnemy) or (a.siteHunter and b.siteHunter)
		or (a.scriptedEnemy and b.scriptedEnemy) then return true end
	return alliedCrews(u, a.alifeRecord, b.alifeRecord)
end

-- Used for scripted encounters and the debug enemy counter. Raiders are
-- defined by current behavior, while site defenders are authored as such.
function C.sceneEnemy(e)
	e = C.controller(e)
	return e and e.kind == "ship" and (e.scriptedEnemy or e.siteEnemy or Access.raiding(e.alifeRecord)) or false
end

local function attacks(game, actor, target)
	if actor.kind == "station" then return game:stationHostile(actor, target) end
	if actor.siteEnemy or actor.siteHunter or actor.scriptedEnemy then
		local other = C.controller(target)
		if actor.siteEnemy then return other.siteHunter or other.isPlayer end
		if actor.siteHunter then return other.siteEnemy end
		return other.isPlayer
	end
	return require("src.security").hostile(game, actor, target)
end

-- Automatic acquisition follows the attacker's rules. For the player,
-- highlight and lock ships that would attack them.
function C.hostile(game, source, target)
	if not source or not target or target.kind ~= "ship" or target.dead or target.removed
		or target.dockState or target.driverProtected or target.unpiloted or target.podHidden
		or C.allied(game.universe, source, target) then return false end
	local a, b = C.controller(source), C.controller(target)
	if source.aggressor == target or a.aggressor == target or a.aggressor == b then return true end
	if a.isPlayer then return b.aggressor == a or attacks(game, b, a) end
	return attacks(game, a, target)
end

return C
