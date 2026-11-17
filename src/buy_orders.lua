--[[
	Buy orders: the player asks for goods delivered to a station, into their
	storage there or onto their stall (src/stalls.lua). The order goes on
	the freight board as an ordinary stocked transport job
	(src/transport.lua) from whichever station has the goods to spare, so
	NPC haulers take it with the rest of their work and settle it the
	usual way; only the delivery lands in the player's storage or stall
	instead of the station's shelves.

	The player pays up front, per unit: the goods at list price plus the
	hauler's freight quote (escrow). A delivery uses that up; cancelling an
	order nobody has loaded yet refunds the rest. A hauler that can carry
	only part of it delivers that part, and the rest goes back on the
	board.

	State: u.buyOrders = { list = { order, ... }, next = n }
	  order = { id, item, amount, delivered, target, deliver ("storage" |
	            "stall"), source, unit (credits per unit held), taskId,
	            placed, done }
]]
local data = require("src.data")
local L = require("src.locations")
local Tasks = require("src.tasks")
local B = {}
B.max = 8           -- open orders at once
B.scope = "player_buy"

local function state(u)
	u.buyOrders = u.buyOrders or { list = {}, next = 0 }
	return u.buyOrders
end
function B.list(u) return state(u).list end
function B.open(u)
	local out = {}
	for _, o in ipairs(state(u).list) do if not o.done then out[#out + 1] = o end end
	return out
end

local function allStations()
	local out = {}
	for _, area in ipairs(require("src.fields").list) do
		for _, id in ipairs(L.stations(area)) do out[#out + 1] = id end
	end
	return out
end

-- Where n of item could come from for delivery to target: the station with
-- the most to spare, nearest first (same system, then fewest AU).
function B.source(u, item, n, target, clock)
	local Transport = require("src.transport")
	local here = L.byId[target] and L.byId[target].area
	local best, bestKey
	for _, id in ipairs(allStations()) do
		if id ~= target then
			local ok, have = pcall(Transport.available, u, id, item)
			have = ok and have or 0
			if have > 0 then
				local route = Transport.route(id, target, clock)
				if route then
					local enough = have >= n and 0 or 1
					local away = L.byId[id].area == here and 0 or 1
					local key = enough * 1e6 + away * 1e5 + #route * 100 - math.min(99, have)
					if not bestKey or key < bestKey then best, bestKey = { id = id, have = have }, key end
				end
			end
		end
	end
	return best
end

-- What's on offer for an order to target: { item, have, source } for every
-- good some station has to spare, by name.
function B.catalogue(u, target, clock)
	local Transport = require("src.transport")
	local seen = {}
	for _, id in ipairs(allStations()) do
		if id ~= target then
			local ok, shops = pcall(require("src.stockpile").shops, id)
			for _, shop in ipairs(ok and shops or {}) do
				for _, e in ipairs(shop.sells or {}) do
					local item = e[1]
					if data.items[item] and not seen[item] then
						local okA, have = pcall(Transport.available, u, id, item)
						if okA and have and have > 0 then seen[item] = true end
					end
				end
			end
		end
	end
	local out = {}
	for item in pairs(seen) do out[#out + 1] = item end
	table.sort(out, function(a, b) return data.items[a].name < data.items[b].name end)
	return out
end

local function offer(u, o, n, source, clock)
	local Transport = require("src.transport")
	return Tasks.post(u, Transport.quote({ kind = "transport", source = source, target = o.target, item = o.item, amount = n,
		stocked = true, order = true, layoutScope = B.scope, priority = 1, urgency = 1, cooldown = 30, placed = clock,
		npcClaimAt = clock, playerOrder = o.id }, clock, u))
end

-- The price of n of item to target from source, per unit: list price plus
-- the freight quote. Returns unit, goods, freight (totals for n).
function B.quote(u, item, n, source, target, clock)
	local Transport = require("src.transport")
	local t = Transport.quote({ kind = "transport", source = source, target = target, item = item, amount = n, placed = clock }, clock, u)
	local freight = Transport.payment(t)
	local goods = (data.items[item].price or 0) * n
	return math.ceil((goods + freight) / n), goods, freight
end

-- Place an order. Returns the order, or nil and why.
function B.place(u, item, n, target, deliver, clock)
	clock = clock or u.clock or 0
	if #B.open(u) >= B.max then return nil, ("You have %d orders open already"):format(B.max) end
	if not data.items[item] or n <= 0 then return nil, "Nothing to order" end
	if deliver == "stall" and not require("src.stalls").get(u, target) then return nil, "You have no stall here" end
	local src = B.source(u, item, n, target, clock)
	if not src then return nil, "No station has any to spare" end
	n = math.min(n, src.have)
	local unit = B.quote(u, item, n, src.id, target, clock)
	if (u.credits or 0) < unit * n then return nil, "Not enough credits" end
	local s = state(u)
	s.next = s.next + 1
	local o = { id = "buy/" .. s.next, item = item, amount = n, delivered = 0, target = target, deliver = deliver or "storage",
		source = src.id, unit = unit, placed = clock }
	u.credits = u.credits - unit * n
	local t = offer(u, o, n, src.id, clock)
	o.taskId = t.id
	table.insert(s.list, 1, o)
	while #s.list > 20 do table.remove(s.list) end
	return o
end

function B.get(u, id)
	for _, o in ipairs(state(u).list) do if o.id == id then return o end end
end

-- Where it is: "open" (on the board), "hauling" (a hauler has it),
-- "delivered", "cancelled".
function B.status(u, o)
	if o.done then return o.done end
	local t = o.taskId and Tasks.state(u).offers[o.taskId]
	if t and t.owner then return "hauling" end
	return "open"
end

-- Cancel: only while nobody has taken it. Refunds what's left.
function B.cancel(u, o)
	if o.done then return false end
	local offers = Tasks.state(u).offers
	local t = o.taskId and offers[o.taskId]
	if t and t.owner then return false, "A hauler is already carrying it" end
	if t then offers[o.taskId] = nil end
	local left = o.amount - o.delivered
	u.credits = (u.credits or 0) + left * o.unit
	o.done = "cancelled"
	return true
end

-- A hauler delivered n of it (src/transport.lua's settlement). Into the
-- player's storage or stall at the station; the rest goes back on the
-- board if it carried only part.
function B.delivered(u, id, station, item, n, clock)
	local o = B.get(u, id)
	local key = L.canonical(station)
	if o and o.deliver == "stall" and require("src.stalls").get(u, key) then
		local s = require("src.stalls").get(u, key)
		s.stock[item] = (s.stock[item] or 0) + n
	else
		local storage = require("src.stalls").storage(u, key)
		local put = require("src.inventory.hold").add(storage, item, n) or 0
		-- storage full: what didn't fit is sold back at the station, and the
		-- player gets what they paid for it
		if put < n and o then
			u.credits = (u.credits or 0) + (n - put) * o.unit
			o.overflow = (o.overflow or 0) + (n - put)
			require("src.stockpile").add(u, key, item, n - put)
		end
	end
	if not o then return end
	o.delivered = o.delivered + n
	if o.delivered >= o.amount then
		o.done = "delivered"
	else
		local t = offer(u, o, o.amount - o.delivered, o.source, clock or u.clock or 0)
		o.taskId = t.id
	end
end

return B
