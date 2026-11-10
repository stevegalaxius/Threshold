--[[
	Scavenging: the one loot loop for every NPC that picks things up.
	Pirates and salvagers share it, online and off (src/offline_loot.lua is
	the offline half). A role differs only by its profile:

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
 if r.role=='pirate' then return S.PROFILES.pirate end
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

local function claimed(thing, e, field, mine)
	local owner = thing[field]
	return owner and owner ~= e and not owner.dead and not owner.removed and owner[mine] == thing
end

-- Online: steer e at the nearest loot in reach. Returns true while busy.
function S.think(game, e, dt, AI, r, NPC)
	local p = S.profile(r)
	if not p then return false end
	Ship.ensureGridHold(e)
	local now = game.universe.clock
	local reach = S.range(p)
	local refresh = (e.scavengeThink or 0) <= game.time
	if refresh then
		e.scavengeThink = game.time + T.securityThink
		local x, y = e.body:getPosition()
		local best = reach ^ 2
		local previous = e.scavengePickup
		e.scavengePickup, e.scavengeContainer = nil, nil
		for _, pk in ipairs(game.pickups) do
			if not pk.inner and pk.count > 0 and not claimed(pk, e, 'collector', 'tractorTarget')
				and Ship.canFit(e, pk.item, 1) > 0 then
				local d = (pk.x - x) ^ 2 + (pk.y - y) ^ 2
				if d < best then best = d; e.scavengePickup = pk end
			end
		end
		if previous and previous ~= e.scavengePickup and previous.collector == e then previous.collector = nil end
		for _, box in ipairs(game.entities) do
			if box.kind == 'container' and box ~= game.looting and not box.dead and not box.removed
				and not claimed(box, e, 'lootCollector', 'scavengeContainer') and Loot.canTake(e, box) then
				local bx, by = box.body:getPosition()
				local d = (bx - x) ^ 2 + (by - y) ^ 2
				if d < best then best = d; e.scavengeContainer = box; e.scavengePickup = nil end
			end
		end
	end
	-- a whole container: pull it in
	local box = e.scavengeContainer
	if box and not box.dead and not box.removed and box ~= game.looting then
		local x, y = e.body:getPosition()
		local bx, by = box.body:getPosition()
		local vx, vy = box.body:getLinearVelocity()
		local dx, dy = bx - x, by - y
		local d = math.sqrt(dx * dx + dy * dy)
		AI.navigate(game, e, dx, dy, math.min(400, math.max(0, (d - 100) * .6)), vx, vy, d)
		e.intent.aimX, e.intent.aimY = bx, by; e.intent.tractor = true; e.tractorTarget = nil
		e.intent.firePrimary = false
		box.lootCollector = e; r.taskStatus = 'looting a cargo container'
		Loot.pull(game, e, box, dt)
		return true
	end
	-- loose cargo: tractor it
	local pk = e.scavengePickup
	local exists = false
	for _, q in ipairs(game.pickups) do if q == pk then exists = true break end end
	if pk and exists and pk.count > 0 and Ship.canFit(e, pk.item, 1) > 0 then
		local x, y = e.body:getPosition()
		local dx, dy = pk.x - x, pk.y - y
		local d = math.sqrt(dx * dx + dy * dy)
		local range = Ship.tractorRange(e)
		AI.navigate(game, e, dx, dy, NPC.approach(e, d, range * .5), pk.vx, pk.vy, d)
		e.intent.aimX, e.intent.aimY = pk.x, pk.y; e.intent.firePrimary = false
		local near = Ship.distanceTo(e, pk.x, pk.y) <= range
		e.intent.tractor = near; e.tractorTarget = near and pk or nil
		pk.collector = e
		r.taskStatus = 'collecting loose cargo'
		return true
	end
	e.intent.tractor = false; e.tractorTarget = nil
	if not p.wrecks then return false end
	-- a wreck: wrecks keep their cargo until broken open, so shoot it
	-- apart; what spills is collected above, and the hull is gone
	local wreck = e.scavengeWreck
	if wreck and (wreck.dead or wreck.removed or not wreck.body or wreck.body:isDestroyed()) then wreck = nil end
	local x, y = e.body:getPosition()
	if refresh then
		wreck = nil
		local best = reach ^ 2
		for _, o in ipairs(game.entities) do
			if o.kind == 'husk' and o ~= game.looting and (not p.clears or o.origin) and not o.dead and not o.removed and o.body and not o.body:isDestroyed() then
				local wx, wy = o.body:getPosition()
				local d = (wx - x) ^ 2 + (wy - y) ^ 2
				if d < best then wreck, best = o, d end
			end
		end
	end
	if not wreck then e.scavengeWreck = nil return false end
	local wx, wy = wreck.body:getPosition()
	local d2 = (wx - x) ^ 2 + (wy - y) ^ 2
	if d2 > reach ^ 2 then e.scavengeWreck = nil return false end
	-- pirates give a wreck a while; clean-up crews see it through
	if e.scavengeWreck ~= wreck then e.scavengeWreck = wreck; e.scavengeWreckUntil = now + (p.clears and math.huge or T.pirateLootTime) end
	if now > e.scavengeWreckUntil then return false end
	local d = math.sqrt(d2)
	local vx, vy = wreck.body:getLinearVelocity()
	if p.clears then
		-- clean-up crew: no guns needed. Alongside, it strips the hold a stack
		-- at a time, then cuts up the empty hull and hauls it off.
		local reachT = Ship.tractorRange(e)
		-- in close to drill, tractor range to strip
		local stand = e.scavengeDrilling == wreck and (wreck.radius or 0) + (e.halfLength or 60) or reachT * .5
		AI.navigate(game, e, wx - x, wy - y, NPC.approach(e, d, stand), vx, vy, d)
		e.intent.aimX, e.intent.aimY = wx, wy; e.intent.firePrimary = false; e.lock = nil
		local near = Ship.distanceTo(e, wx, wy) - (wreck.radius or 0) <= reachT
		e.intent.tractor = near; e.tractorTarget = nil
		r.taskStatus = 'stripping a wreck'
		if near and game.time >= (e.scavengeStripAt or 0) then
			e.scavengeStripAt = game.time + .5
			if wreck.hold and next(wreck.loot or {}) then
				local n, id, moved = Loot.takeStack(e.hold, wreck.hold)
				if n > 0 then
					e.cargo = Hold.totals(e.hold); Ship.updateMass(e)
					wreck.loot = Hold.totals(wreck.hold)
					require('src.events').emit('pickup', e, id, n, moved)
				else
					e.scavengeWreck = nil; return false        -- hold full
				end
			else
				-- stripped bare: drill the hull apart; its alloy spills as
				-- loose cargo and the loop above collects it
				e.scavengeDrilling = wreck
			end
		end
		if e.scavengeDrilling == wreck then
			e.intent.tractor = false
			e.intent.firePrimary = d < (wreck.radius or 0) + 260
			r.taskStatus = 'drilling a wreck apart'
		end
		return true
	end
	AI.navigate(game, e, wx - x, wy - y, math.max(0, math.min(400, (d - 400) * .6)), vx, vy, d)
	e.intent.aimX, e.intent.aimY = wx, wy; e.lock = nil
	e.intent.firePrimary = d < ((e.def and e.def.ai and e.def.ai.range) or 700)
	r.taskStatus = p.clears and 'cutting up a wreck' or 'breaking open a wreck'
	return true
end

-- Anything a scavenger picks up online counts as taken.
require('src.events').on('pickup', function(e, item, n, stack)
	local r = e.alifeRecord
	if not r or not S.profile(r) or r.piracy or r.salvageReturn then return end
	if r.role == 'pirate' and stack and (stack.inner or stack.wear ~= nil) then stack.stolen = true end
	S.took(r, item, n, e.alifeGame.universe.clock)
end)

return S
