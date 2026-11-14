--[[
	Prospecting: NPCs going after rare ore they come across.

	Online, any NPC with a working gun or drill, room in its hold and nothing
	pressing (no fight, no service run, not docked) that passes within
	T.prospectRange of rare ore detours for it: a rock with its gold core or
	ice with its crystal (src/rock_chips.lua) it cuts into, rare chips it
	shoots open, loose rare ore it tractors in. Then it carries on with its
	job. How keen it is depends on what it is: miners and pirates always,
	traders now and then, patrols never (T.prospectEager); each ship decides
	once per rock.

	Offline there are no wild rocks to see, so it's a roll instead: an NPC
	arriving somewhere after a leg through a belt sometimes brings in a unit
	of that belt's rare ore, at the same keenness.

	Whatever rare ore it carries it sells wherever it next docks, onto the
	station's shelf, for its own credits. It never feeds an industry chain.
]]
local T = require('src.tuning')
local Ore = require('src.ore')
local data = require('src.data')
local Hold = require('src.inventory.hold')
local Actions = require('src.npc_actions')
local P = {}

function P.eagerness(r)
	if r.piracy or r.task and r.task.kind == 'raid' then return T.prospectEager.pirate end
	return T.prospectEager[r.populationGroup or ''] or T.prospectEager.other
end

local function busy(ctx)
	local r, e = ctx.r, ctx.e
	if r.state == 'docked' or r.service or r.worldRecovery or r.salvageReturn or r.encounter then return true end
	if e.combatTarget or e.aggressor or e.asked or e.drone or e.alifeEgress or e.launch or e.dockState or e.driverTractor then return true end
	return false
end

-- Is this live thing worth prospecting (and how to work it)?
local function rareRock(o)
	return o.kind == 'asteroid' and not o.dead and not o.removed and not o.miningId
		and (o.core and o.rare or o.chip and o.rare) and o.body and not o.body:isDestroyed()
end

-- Has this ship already decided about this target? Decide once, by keenness.
local function wants(ctx, key)
	local e = ctx.e
	e.prospectRolls = e.prospectRolls or {}
	local v = e.prospectRolls[key]
	if v == nil then v = love.math.random() < P.eagerness(ctx.r); e.prospectRolls[key] = v end
	return v
end

function P.nextAction(ctx)
	local e, game = ctx.e, ctx.game
	if not e or not game or busy(ctx) then return end
	if P.eagerness(ctx.r) <= 0 then return end
	if ctx.clock < (e.prospectAt or 0) then return end
	e.prospectAt = ctx.clock + T.prospectThink
	local x, y = e.body:getPosition()
	local best, bestD, spec = nil, T.prospectRange ^ 2, nil
	-- loose rare ore first: it's free
	for _, p in ipairs(game.pickups or {}) do
		if p.looseId and p.count > 0 and Ore.isRare(p.item) and not p.collector then
			local d = (p.x - x) ^ 2 + (p.y - y) ^ 2
			if d < bestD and require('src.ship').canFit(e, p.item, 1) > 0 and wants(ctx, p.looseId) then
				local s = { kind = 'work', operation = 'collect', target = { provider = 'resource', id = p.looseId, expected = 'loot' } }
				local target = Actions.resolve(ctx, s)
				if target and not target.done and Actions.available(ctx, target) then best, bestD, spec = p, d, s end
			end
		end
	end
	if spec then return spec end
	if not require('src.wreck_salvage').weapon(e) then return end
	for _, o in ipairs(game.entities) do
		if rareRock(o) then
			local ox, oy = o.body:getPosition()
			local d = (ox - x) ^ 2 + (oy - y) ^ 2
			if d < bestD and require('src.ship').canFit(e, o.rare, 1) > 0 and wants(ctx, 'rock/' .. o.id) then
				best, bestD = o, d
			end
		end
	end
	if best then return { kind = 'work', operation = 'prospect', target = { provider = 'rock', id = best.id } } end
end

-- A live rock, by entity id (online only: wild rock has no record).
Actions.registerTarget('rock', { resolve = function(ctx, t)
	local game = ctx.game
	if not ctx.e or not game then return end
	for _, o in ipairs(game.entities) do
		if o.id == t.id then
			if not rareRock(o) then return { done = true, x = 0, y = 0 } end
			local x, y = o.body:getPosition()
			local vx, vy = o.body:getLinearVelocity()
			return { entity = o, x = x, y = y, vx = vx, vy = vy, radius = o.radius }
		end
	end
end })

local function hasDrill(e)
	for _, slot in ipairs(e.weapons or {}) do if slot.w and slot.w.kind == 'drill' then return true end end
	return false
end

-- Cut into it: close in with a drill, stand off with a gun, and fire
-- only with a clear line to the rock.
Actions.registerOperation('prospect', {
	keepDistance = true,
	distance = function(ctx, target)
		local e = ctx.e
		if e and hasDrill(e) then return (target.radius or 0) + (e.noseX or 60) + 25 end
		return (target.radius or 0) + T.prospectStandoff
	end,
	-- close enough to cut: a drill needs to touch, a gun just a clear shot
	inRange = function(ctx, target)
		local e = ctx.e
		local x, y = e.body:getPosition()
		local d = math.sqrt((target.x - x) ^ 2 + (target.y - y) ^ 2)
		local reach = hasDrill(e) and (e.halfLength or 60) * 1.6 or T.prospectStandoff + 200
		return d <= (target.radius or 0) + reach
	end,
	online = function(ctx, target)
		local e, rock = ctx.e, target.entity
		if not rock or not rareRock(rock) then return 'done' end
		local x, y = e.body:getPosition()
		local angle = e.body:getAngle()
		local diff = (math.atan2(target.y - y, target.x - x) - angle + math.pi) % (2 * math.pi) - math.pi
		local hit = ctx.game:raycast(x + math.cos(angle) * e.halfLength, y + math.sin(angle) * e.halfLength, target.x, target.y, e.team)
		e.intent.aimX, e.intent.aimY = target.x, target.y
		e.intent.firePrimary = math.abs(diff) < 0.18 and (not hit or hit.entity == rock or rareRock(hit.entity))
		e.intent.targetDist = nil
		ctx.r.taskStatus = 'prospecting'
		return 'running'
	end,
	offline = function() return 'done' end,          -- the rock was left behind
	missing = function() return 'done' end,
})

-- Sell any rare ore aboard onto this station's shelf, for the NPC's own money.
function P.sell(u, r, node)
	local cargo = r.ship and r.ship.cargo
	if not cargo then return 0 end
	local total, sold = 0, {}
	for _, item in pairs(Ore.rare) do
		local n = cargo[item] or 0
		if n > 0 then
			require('src.jobs').deliver(u, node, item, n); cargo[item] = nil; sold[item] = n
			total = total + n * (data.items[item].price or 0)
		end
	end
	if total <= 0 then return 0 end
	if r.ship.hold then
		local h = Hold.deserialize(r.ship.hold, function(id) return data.items[id] ~= nil end)
		Hold.sync(h, cargo); r.ship.hold = Hold.serialize(h)
	end
	r.credits = (r.credits or 0) + total; r.rareEarnings = (r.rareEarnings or 0) + total
	require('src.events').emit('rare_sale', r.id, node, sold, total)
	return total
end

-- Offline: did it pick up some rare ore on the leg into this area?
function P.offlineFind(u, r, area, roll)
	roll = roll or love.math.random
	local f = require('src.fields')[area]
	local mix = f and f.mix
	if not mix then return end
	local rock, ice, all = mix.rock or 0, mix.ice or 0, 0
	for _, w in pairs(mix) do all = all + w end
	if rock + ice <= 0 then return end
	-- the more of the field is rock and ice (not junk), the better the odds
	if roll() >= T.prospectOffline * P.eagerness(r) * (rock + ice) / all then return end
	local item = Ore.rare[roll() * (rock + ice) < ice and 'ice' or 'rock']
	if require('src.npc_operations').room(r, item) <= 0 then return end
	r.ship.cargo = r.ship.cargo or {}
	if r.ship.hold then
		local h = Hold.deserialize(r.ship.hold, function(id) return data.items[id] ~= nil end)
		if Hold.add(h, item, 1) <= 0 then return end
		r.ship.hold = Hold.serialize(h); r.ship.cargo = Hold.totals(h)
	else
		r.ship.cargo[item] = (r.ship.cargo[item] or 0) + 1
	end
	return item
end

return P
