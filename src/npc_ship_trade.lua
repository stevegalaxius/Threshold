--[[
	NPCs trade ships at the station lots, the same lots the player uses.
	Checked once per game day per NPC, while it sits docked (offline) at a
	station with a dealer (src/dealers.lua):

	  upgrade  an NPC with money to spare trades its ship in for a better
	           one on this lot: dearer hull, at least as much hold, every
	           capability its job needs. Its old ship goes on the lot
	           (Dealers.resell), credited at the player's trade-in rate.
	           Only with an empty hold, so no cargo is lost in the swap.
	  retire   an NPC from a replenished population group sometimes leaves
	           the system for good: it sells its ship here and is gone.
	           Population arrivals (src/population.lua) refill the gap.

	Both are written to the simulation history.
]]
local data = require("src.data")
local M = {}
M.checkHours = 24
M.retireChance = 0.04      -- per daily check
M.upgradeReserve = 1500    -- credits kept back after an upgrade
M.upgradeGain = 1.25       -- the new hull must list this much dearer

local function rand() return love and love.math and love.math.random() or math.random() end

local function cargoEmpty(r)
	local s = r.ship
	if s.hold then
		local Hold = require("src.inventory.hold")
		local h = Hold.deserialize(s.hold)
		for _, n in pairs(Hold.totals(h)) do if n > 0 then return false end end
		return true
	end
	for _, n in pairs(s.cargo or {}) do if n > 0 then return false end end
	return true
end

local function tradeIn(r)
	local Game = require("src.game")
	return Game.shipSellPrice(r.ship)
end

local function note(u, kind, r, node, result)
	require("src.simulation_history").note(u, kind, u.clock, r.area, { r.id }, result, node)
end

-- Sell this NPC's ship to the lot at node (if the station takes it).
local function sellShip(u, r, node)
	return require("src.dealers").resell(u, node, r.ship)
end

function M.upgrade(u, r, node)
	if not cargoEmpty(r) then return false end
	local D = require("src.dealers")
	local cur = data.hulls[r.ship.hull]
	if not cur then return false end
	local stats = require("src.stats")
	local curStats = stats.compute(cur, r.ship.loadout or cur.loadout)
	local need = require("src.npc_access").capabilities(r)
	local credit = tradeIn(r)
	local budget = (r.credits or 0) + credit - M.upgradeReserve
	local best
	for _, lot in ipairs(D.lots(u, node)) do
		local hull = data.hulls[lot.hull]
		if hull and lot.price <= budget and (hull.price or 0) >= (cur.price or 0) * M.upgradeGain then
			local st = stats.compute(hull, lot.loadout)
			local ok = st.thrust > 0 and st.powerOut > 0 and (st.hold or 0) >= (curStats.hold or 0)
			local caps = require("src.npc_access").capabilities({ ship = { hull = lot.hull, loadout = lot.loadout } })
			for name, want in pairs(need) do if want and not caps[name] then ok = false end end
			if ok and (not best or (hull.price or 0) > (data.hulls[best.hull].price or 0)) then best = lot end
		end
	end
	if not best then return false end
	local old = r.ship
	sellShip(u, r, node)
	D.take(u, node, best.id)
	r.ship = D.ship(best)
	r.ship.armor = best.armor
	r.credits = (r.credits or 0) + credit - best.price
	note(u, "npc_ship_upgraded", r, node, { station = node, from = old.hull, to = best.hull, price = best.price, credit = credit })
	return true
end

function M.retire(u, r, node)
	if not r.populationGroup or r.task or r.encounter then return false end
	if rand() >= M.retireChance then return false end
	local lot = sellShip(u, r, node)
	r.credits = (r.credits or 0) + (lot and tradeIn(r) or 0)
	r.state = "escaped"
	r.retiredAt = u.clock
	note(u, "npc_retired", r, node, { station = node, hull = r.ship.hull, sold = lot ~= nil })
	return true
end

-- From the docked NPC's offline step (src/npc_repair.lua).
function M.dock(u, r, node, clock)
	if not r.ship or not node or r.state ~= "docked" then return end
	if clock < (r.shipTradeAt or 0) then return end
	r.shipTradeAt = clock + M.checkHours * 3600
	local def = require("src.dealers").def(node)
	if not def or def.service then return end
	if M.retire(u, r, node) then return end
	M.upgrade(u, r, node)
end

return M
