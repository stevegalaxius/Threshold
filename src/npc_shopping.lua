--[[
	An NPC's shopping visit at a station with player stalls (src/stalls.lua):
	one short list per docking, checked against the stall's prices and the
	house's, bought for real out of the NPC's own credits.

	  needs     what upkeep wants aboard (Supplies.targets: fuel, ammo,
	            flares) and is short of. The house shelf refills those for
	            nothing; a stall gets the sale when its tag is Cheap, or
	            when the house shelf has none left (then any tag: a ship
	            out of ammo pays Premium).
	  upgrades  modules: src/npc_refit.lua scores the stall's modules with
	            the house's and buys the one that suits its job best
	            (M.offers below; Premium needs a clearer improvement).
	  wants     one or two things it would like, from its job and
	            temperament: an aggressive pilot stocks extra ammunition
	            and patch kits, anyone damaged picks up patch kits, a
	            careful one carries spare flares; any of these only when
	            the price is right (a Cheap stall nearly always, Premium
	            rarely).

	Every purchase leaves Stall.reserve credits in the NPC's account.
	Cost: a few item lookups per docking, only at stations with a stall.
]]
local data = require("src.data")
local L = require("src.locations")
local Stall = require("src.stalls")
local M = {}
M.reserve = 300
-- how likely a want is bought, by the stall's tag
M.wantChance = { cheap = 0.85, fair = 0.5, premium = 0.15 }

local function cargoOf(r, e)
	local Hold = require("src.inventory.hold")
	if e then return e.hold, e.cargo or {} end
	local h = r.ship.hold and Hold.deserialize(r.ship.hold)
	return h, h and Hold.totals(h) or r.ship.cargo or {}
end

-- How many of id fit aboard.
local function room(r, e, h, cargo, id)
	local Hold = require("src.inventory.hold")
	if h then
		return Hold.room(h, id, 50, { pristine = true })
	end
	local stats = e and e.stats or require("src.stats").compute(data.hulls[r.ship.hull], r.ship.loadout)
	local used = 0
	for item, n in pairs(cargo) do used = used + (data.items[item] and data.items[item].volume or 0) * n end
	local v = data.items[id] and data.items[id].volume or 1
	return math.max(0, math.floor((stats.hold - used) / v + 1e-6))
end

local function aboard(r, e, h, cargo, id, n)
	local Hold = require("src.inventory.hold")
	if h then
		n = Hold.add(h, id, n, { pristine = true }) or 0
		if e then e.cargo = Hold.totals(h); e.massDirty = true else r.ship.hold = Hold.serialize(h); r.ship.cargo = Hold.totals(h) end
	else
		cargo[id] = (cargo[id] or 0) + n
		if e then e.cargo = cargo; e.massDirty = true else r.ship.cargo = cargo end
	end
	return n
end

-- Buy up to n of id off the stall: as many as fit, are stocked and it can
-- afford. Returns how many.
local function buy(u, k, s, r, e, h, cargo, id, n, clock)
	local price = Stall.price(s, id)
	local afford = math.floor(math.max(0, (r.credits or 0) - M.reserve) / price)
	n = math.min(n, s.stock[id] or 0, afford, room(r, e, h, cargo, id))
	if n <= 0 then return 0 end
	n = aboard(r, e, h, cargo, id, n)
	if n <= 0 then return 0 end
	r.credits = r.credits - Stall.sell(u, k, id, n, r, clock)
	return n
end

local function roll(r, clock, salt)
	local seed = 7
	local str = tostring(r.id) .. "|" .. tostring(math.floor(clock or 0)) .. "|" .. salt
	for i = 1, #str do seed = (seed * 31 + str:byte(i)) % 2147483647 end
	for _ = 1, 3 do seed = seed * 48271 % 2147483647 end
	return seed / 2147483647
end

-- The visit. node: the station it's docked at; e: its live ship, if online.
function M.visit(u, r, node, clock, e, once)
	if not (u and r and r.ship and node) then return end
	local k = L.canonical(node)
	local s = Stall.get(u, k)
	if not s or not next(s.stock) then return end
	-- once a docking (online, the caller marks the docking itself)
	if not once then
		local visit = k .. "@" .. tostring(r.dockedAt)
		if r.shopVisit == visit then return end
		r.shopVisit = visit
	end
	clock = clock or u.clock or 0
	require("src.personality").ensure(r)
	local h, cargo = cargoOf(r, e)
	local Stock = require("src.stockpile")
	local bought = 0
	-- needs
	local targets = require("src.supplies").targets(r, e)
	for id, target in pairs(targets) do
		local missing = target - (cargo[id] or 0)
		if missing > 0 and (s.stock[id] or 0) > 0 then
			local ok, houseHas = pcall(Stock.available, u, k, id)
			if s.tag == "cheap" or not ok or (houseHas or 0) <= 0 then
				bought = bought + buy(u, k, s, r, e, h, cargo, id, missing, clock)
			end
		end
	end
	-- wants
	local chance = M.wantChance[s.tag] or 0.5
	local wants = {}
	local maxArmor = require("src.npc_repair").maximum(r)
	local hurt = (e and e.armor or r.ship.armor or maxArmor) < maxArmor
	if hurt or r.aggression > 0.6 then wants[#wants + 1] = { "patch_kit", hurt and 2 or 1 } end
	if r.aggression > 0.6 then
		for id, target in pairs(targets) do
			if id ~= require("src.reactor_fuel").item() and id ~= "flare" then wants[#wants + 1] = { id, math.ceil(target * 0.5) } end
		end
	end
	if r.aggression < 0.35 and targets.flare then wants[#wants + 1] = { "flare", math.max(1, math.ceil(targets.flare * 0.5)) } end
	for i, w in ipairs(wants) do
		if (s.stock[w[1]] or 0) > 0 and roll(r, clock, w[1] .. i) < chance then
			bought = bought + buy(u, k, s, r, e, h, cargo, w[1], w[2], clock)
		end
	end
	return bought
end

-- For the refit check (src/npc_refit.lua): the stall's modules at this
-- station, { id = price }.
function M.offers(u, node)
	local s = Stall.get(u, node)
	if not s then return nil end
	local out
	for id, n in pairs(s.stock) do
		if n > 0 and data.modules[id] then out = out or {}; out[id] = Stall.price(s, id) end
	end
	return out, s
end

return M
