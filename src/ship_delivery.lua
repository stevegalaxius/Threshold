--[[
	Ship deliveries: new ships moving from a shipyard's lot to a dealer
	that sells them but doesn't build them, carried on a ship hauler's
	berths (src/berths.lua).

	Everything here reads the data, so new hull designs need no edits:
	  * a hauler is any NPC whose hull has berths (capability "berths");
	    a hauler bought for delivery (workProfile ship_hauler) buys whichever
	    such hull it can afford
	  * a delivery fits a hauler when some free berth of its hull takes the
	    ship's hull (Berths.fits: length and width)
	  * a dealer wants a delivery for each hull on its list it has no lot
	    of, sourced from any shipyard with that hull on its lot

	Deliveries are the only way a dealer that doesn't build ships restocks
	(past its opening stock): nothing is conjured if no hauler comes.
]]
local Tasks = require("src.tasks")
local L = require("src.locations")
local G = require("src.travelgraph")
local T = require("src.tuning")
local data = require("src.data")
local Berths = require("src.berths")
local copy = require("src.persistence").copy

local SD = {}
local HOUR = 3600
T.shipDeliveryPatience = T.shipDeliveryPatience or 6     -- game hours before a dealer restocks anyway
T.shipDeliveryRate = T.shipDeliveryRate or 0.03          -- share of the ship's price paid per delivery
T.shipDeliveryPerAU = T.shipDeliveryPerAU or 1500        -- plus credits per AU of route

local function Transport() return require("src.transport") end
local function Dealers() return require("src.dealers") end

-- A stand-in carrier for berth checks on an NPC record.
local function carrierOf(r)
	return { hull = data.hulls[r.ship.hull], carried = r.ship.carried or {} }
end

local function offers(u, fn)
	for _, o in pairs(Tasks.state(u).offers) do if o.kind == "ship_delivery" then fn(o) end end
end

-- The dealer stations that build ships, and the ones that only sell.
local function stations()
	local D, factories, shops = Dealers(), {}, {}
	for key, place in pairs(L.byId) do
		if place.kind == "station" and not place.accessOf then
			local def = D.def(key)
			if def and not def.usedOnly then
				if D.buildsShips(key) then factories[#factories + 1] = key else shops[#shops + 1] = key end
			end
		end
	end
	table.sort(factories); table.sort(shops)
	return factories, shops
end
SD.stations = stations

-- Is a delivery for this target and hull already on the board?
function SD.pending(u, target, hull)
	local found
	offers(u, function(o) if o.target == target and (not hull or o.hull == hull) then found = o end end)
	return found
end

-- Should dealer `key` still wait for a hauler rather than restock hull?
function SD.waiting(u, key, hull, clock)
	local o = SD.pending(u, key, hull)
	return o and (o.state == "reserved" or clock < (o.placed or clock) + T.shipDeliveryPatience * HOUR) or false
end

-- Post a delivery for every hull a shop lacks that a shipyard has on its lot.
function SD.refresh(u, clock)
	local D = Dealers()
	local factories, shops = stations()
	-- lots already promised to a delivery
	local promised = {}
	offers(u, function(o) promised[o.source .. "/" .. tostring(o.lot)] = true end)
	for _, target in ipairs(shops) do
		local s, def = D.state(u, target)
		if s and #s.lots < (def.lots or 6) then
			local have = {}
			for _, lot in ipairs(s.lots) do have[lot.hull] = true end
			for _, hull in ipairs(def.hulls or {}) do
				if not have[hull] and not SD.pending(u, target, hull) and data.hulls[hull] then
					for _, source in ipairs(factories) do
						local lot
						for _, l in ipairs(D.lots(u, source)) do
							if l.hull == hull and not l.used and not promised[source .. "/" .. tostring(l.id)] then lot = l break end
						end
						if lot and Transport().route(source, target, clock) then
							promised[source .. "/" .. tostring(lot.id)] = true
							Tasks.post(u, { kind = "ship_delivery", source = source, target = target, hull = hull, lot = lot.id,
								price = lot.price, placed = clock, cooldown = 120, requires = { capabilities = { "berths" } } })
							break
						end
					end
				end
			end
		end
	end
	-- drop offers whose ship has gone (sold off the lot) before pickup
	local state = Tasks.state(u)
	for id, o in pairs(state.offers) do
		if o.kind == "ship_delivery" and o.state == "available" and not D.find(u, o.source, o.lot) then state.offers[id] = nil end
	end
end

local function payment(o, clock)
	Transport().quote(o, clock)
	return math.floor((o.price or 50000) * T.shipDeliveryRate + (o.routeAU or 0) * T.shipDeliveryPerAU)
end

-- Keep a hauler that's flying in the scene in step with its record: its
-- entity draws and collides with what's on its berths.
local function mirror(game, r)
	if not (game and game.entities) then return end
	for _, e in ipairs(game.entities) do
		if e.alifeId == r.id and not e.removed then
			e.carried = r.ship.carried and copy(r.ship.carried) or nil
			require("src.ship").updateMass(e)
		end
	end
end

-- Load the promised ship onto a free berth. False if it's gone or won't fit.
local function load(u, r, t)
	local D = Dealers()
	local lot = D.find(u, t.source, t.lot)
	if not lot then return false end
	local slot = Berths.free(carrierOf(r), lot.hull)
	if not slot then return false end
	D.take(u, t.source, t.lot)
	local rec = D.ship(lot)
	rec.delivery, rec.lot = t.id, copy(lot)
	r.ship.carried = r.ship.carried or {}
	r.ship.carried[slot] = rec
	t.berth, t.phase = slot, "delivery"
	return true
end

Tasks.register("ship_delivery", {
	requires = { capabilities = { "berths" } },
	plan = function(t, station, clock)
		if t.phase == "pickup" then return G.itinerary(station, t.source, clock) end
		return Transport().route(station, t.target, clock)
	end,
	eligible = function(u, r, o, station, clock)
		if station ~= o.source and (r.task or not L.byId[station]) then return false end
		if not (L.byId[o.source] and L.byId[o.target]) then return false end
		if not Dealers().find(u, o.source, o.lot) then return false end
		return Berths.free(carrierOf(r), o.hull) ~= nil
	end,
	feasible = function(u, r, o, station, clock)
		return (station == o.source or G.itinerary(station, o.source, clock) ~= nil) and Transport().route(o.source, o.target, clock) ~= nil
	end,
	score = function(u, r, o, station, clock)
		local pay = payment(o, clock)
		return pay / math.max(60, Transport().duration(o, station, clock)) * 100 - (station ~= o.source and 50 or 0)
	end,
	prepare = function(u, r, t, station, clock)
		t.route = Transport().route(t.source, t.target, clock)
		if not t.route then return false end
		t.phase = "pickup"
		if station ~= t.source then return true end
		return load(u, r, t)
	end,
	complete = function(u, r, t, station, clock, game)
		if t.settled then return true end
		if t.phase == "pickup" then
			if station ~= t.source then return false end
			if not load(u, r, t) then Tasks.release(u, r, "ship gone", clock) else mirror(game, r) end
			return false
		end
		if station ~= t.target then return false end
		local carried = r.ship.carried or {}
		local rec = t.berth and carried[t.berth]
		if not (rec and rec.delivery == t.id) then Tasks.release(u, r, "ship lost", clock) return false end
		-- onto the dealer's lot, parked outside while there's room
		local D = Dealers()
		local s = D.state(u, station)
		local lot = rec.lot or { hull = rec.hull, loadout = rec.loadout, price = t.price }
		lot.armor = rec.armor or lot.armor
		local parking = require("src.dealer_parking").plan(u, station, lot.hull, 1, "outside")[1]
		if not parking then return false end   -- no room yet: wait docked
		lot.bay, lot.mooring, lot.dealerStock, lot.deliveredAt = parking.bay, parking.mooring, true, clock
		s.lots[#s.lots + 1] = lot
		carried[t.berth] = nil
		if not next(carried) then r.ship.carried = nil end
		mirror(game, r)
		local pay = require("src.accounts").pay(u, station, payment(t, clock), "freight")
		r.credits = (r.credits or 0) + pay
		r.freightEarnings = (r.freightEarnings or 0) + pay
		t.settled = true
		return true
	end,
})

-- Ship-delivery berths an area wants among its haulers: one where a
-- shipyard builds ships for sale, while any shop sells what they build.
-- (The hauler population in src/alife.lua adds these to its target and
-- buys a berth hull for the next arrival while they're missing.)
function SD.berthsWanted(area)
	if not L.station(area, "trade") then return 0 end
	local factories, shops = stations()
	if #shops == 0 then return 0 end
	for _, key in ipairs(factories) do
		if L.byId[key] and L.byId[key].area == area then return 1 end
	end
	return 0
end
-- Haulers homed here working ship delivery.
function SD.berthHaulers(u, area)
	local n = 0
	for _, r in pairs(u.npcs or {}) do
		if r.populationGroup == "hauler" and r.workProfile == "ship_hauler" and r.home == area
			and r.state ~= "dead" and r.state ~= "escaped" then n = n + 1 end
	end
	return n
end

return SD
