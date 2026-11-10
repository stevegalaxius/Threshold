--[[
	Scavenging: the one loot loop for every NPC that picks things up.
	Pirates and salvagers share it, online and off (src/offline_loot.lua is
	the offline half). The active work selects its profile:

	  manifest   record field listing what it has taken (sold or fenced later)
	  deadline   record field: when it stops looking and heads to market
	  range      how far it looks
	  units      stop after this many units; nil = when the hold is full
	  time       seconds of looking after the first grab
	  wrecks     breaks open wrecks (shoots the husk until it spills)
	  clears     strips combat wrecks offline until gone (clean-up crews)

	Online, a scavenger works the nearest thing in reach: a cargo container
	(pulled in whole), loose cargo (tractored), then a wreck it breaks open
	so its cargo spills as loose cargo. Offline, offline_loot does the same
	against saved records.
]]
local T = require('src.tuning')
local Ship = require('src.ship')
local Loot = require('src.loot')
local Hold = require('src.inventory.hold')
local S = {}

S.PROFILES = {
	pirate = { manifest = 'stolenCargo', deadline = 'lootUntil', range = 'pirateLootRange',
		units = 'pirateLootUnits', time = 'pirateLootTime', wrecks = true },
	salvager = { manifest = 'salvageCargo', deadline = 'salvageUntil', range = 'salvagerRange',
		time = 'salvagerCollectTime', wrecks = true, clears = true },
}
function S.profile(r)
 if not r then return end
 if r.piracy or r.task and r.task.kind=='raid' then return S.PROFILES.pirate end
 if r.task and r.task.kind=='salvage' then return S.PROFILES.salvager end
end
-- how far it looks: clean-up crews work their whole area, pirates their patch
function S.range(p) return p.clears and math.huge or T[p.range] end
function S.time(p) return T[p.time] end

function S.taken(r, p)
	p = p or S.profile(r)
	local n = 0
	for _, c in pairs(p and r[p.manifest] or {}) do n = n + c end
	return n
end

-- Has it got all it came for? Roles with a unit cap stop there; the rest
-- stop when nothing more fits (the loop finds nothing it can take).
function S.full(r, p)
	p = p or S.profile(r)
	if not p then return true end
	return p.units ~= nil and S.taken(r, p) >= T[p.units]
end

-- Done looking: full, or out of time with something to show for it.
function S.done(r, clock)
	local p = S.profile(r)
	if not p then return true end
	return S.taken(r, p) > 0 and (S.full(r, p) or clock >= (r[p.deadline] or math.huge))
end

-- Note what was taken (online pickups and offline takes both land here).
function S.took(r, item, n, clock)
	local p = S.profile(r)
	if not p or n <= 0 then return end
	r[p.manifest] = r[p.manifest] or {}
	r[p.manifest][item] = (r[p.manifest][item] or 0) + n
	r[p.deadline] = r[p.deadline] or clock + S.time(p)
end

-- Selection returns a work request. No steering or scheduling belongs here.
function S.nextAction(ctx) return require('src.offline_loot').nextAction(ctx) end

-- A job hook, used for physical and abstract transfers alike.
function S.pickedUp(ctx,item,n,stack)
 local r=ctx.r
 if not S.profile(r) or r.piracy or r.salvageReturn then return end
 if S.profile(r)==S.PROFILES.pirate and stack and (stack.inner or stack.wear~=nil) then stack.stolen=true end
 S.took(r,item,n,ctx.clock)
end
return S
