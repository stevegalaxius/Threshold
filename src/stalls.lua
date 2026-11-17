--[[
	Market stalls: a space the player rents in a station's market, stocks
	with anything, and prices with one tag. NPCs shop there on their visits
	(src/npc_shopping.lua) alongside the house shelves, and each sale pays
	the player.

	State: u.stalls[station key] = {
	  tag       "cheap" | "fair" | "premium" (Stall.TAGS)
	  stock     { item id = n }
	  paidTo    universe clock the rent is paid up to (billed hourly)
	  ledger    the last Stall.LEDGER sales, newest first:
	            { at, item, n, price, buyer (ship name) }
	  earned    lifetime takings; rentPaid lifetime rent
	}

	Renting needs Friendly standing with the station (Stall.minRep, its
	attitude to the player: src/reputation.lua) and a station with a market.
	Rent is Stall.rent credits an hour, billed in Stall.tick (every game
	hour, from the A-Life update). If the player can't pay, the stall
	closes: its stock goes to the player's storage at that station, and
	nothing is lost.
]]
local data = require("src.data")
local L = require("src.locations")
local Stall = {}

Stall.rent, Stall.minRep, Stall.LEDGER = 150, 15, 30
-- A tag sets every item's price from its list price, and how keen
-- NPCs are on it (src/npc_shopping.lua compares it with the house).
Stall.TAGS = {
	{ id = "cheap", name = "Cheap", factor = 0.9, note = "10% under list: sells fast" },
	{ id = "fair", name = "Fair", factor = 1.0, note = "list price" },
	{ id = "premium", name = "Premium", factor = 1.25, note = "25% over list: sells slowly" },
}
local byTag = {}
for _, t in ipairs(Stall.TAGS) do byTag[t.id] = t end
Stall.byTag = byTag

local function key(st) return L.canonical(type(st) == "table" and (st.key or st.locationId) or st) end
local function store(u) u.stalls = u.stalls or {}; return u.stalls end

function Stall.get(u, st) return u and u.stalls and u.stalls[key(st)] end

-- An item's list price (what the house charges, before reputation).
function Stall.list(id)
	local item = data.items[id]
	return item and item.price or 0
end
function Stall.price(s, id)
	return math.max(1, math.floor(Stall.list(id) * (byTag[s.tag] or byTag.fair).factor + 0.5))
end

-- Whether the player may rent here; false and why if not.
function Stall.canRent(u, st)
	local k = key(st)
	local place = L.byId[k]
	if not place or place.kind ~= "station" then return false, "Stalls are only in station markets" end
	if not L.stationServices(k).market then return false, "This station has no market" end
	if Stall.get(u, k) then return false, "You already rent a stall here" end
	local Rep = require("src.reputation")
	if Rep.stationAttitude(u, k) < Stall.minRep then return false, "The market won't rent to you (need Friendly standing)" end
	if (u.credits or 0) < Stall.rent then return false, "Not enough credits for the first hour's rent" end
	return true
end

function Stall.open(u, st)
	local ok, why = Stall.canRent(u, st)
	if not ok then return nil, why end
	local clock = u.clock or 0
	u.credits = u.credits - Stall.rent
	local s = { tag = "fair", stock = {}, paidTo = clock + 3600, ledger = {}, earned = 0, rentPaid = Stall.rent, openedAt = clock }
	store(u)[key(st)] = s
	return s
end

-- Close it: the stock goes to the player's storage at the station.
function Stall.close(u, st, game)
	local k = key(st)
	local s = Stall.get(u, k)
	if not s then return end
	local storage = Stall.storage(u, k, game)
	local Hold = require("src.inventory.hold")
	for id, n in pairs(s.stock) do
		if n > 0 and storage then Hold.add(storage, id, n) end
	end
	store(u)[k] = nil
	return true
end

-- The player's storage at a station (a Hold), live or saved.
function Stall.storage(u, k, game)
	-- (the same record Game:stationRecord keeps, made here if it's new)
	u.stations = u.stations or {}
	local rec = u.stations[k]
	if not rec then
		rec = { storage = require("src.stockpile").newStorage(k), hangar = {} }
		u.stations[k] = rec
	end
	return rec.storage
end

function Stall.setTag(s, tag) if byTag[tag] then s.tag = tag end end

-- Move goods between the player's ship hold (a Hold) and the stall.
function Stall.stock(s, hold, id, n)
	local Hold = require("src.inventory.hold")
	n = math.min(n, Hold.count(hold, id))
	if n <= 0 then return 0 end
	Hold.take(hold, id, n)
	s.stock[id] = (s.stock[id] or 0) + n
	return n
end
function Stall.unstock(s, hold, id, n)
	local Hold = require("src.inventory.hold")
	n = math.min(n, s.stock[id] or 0)
	if n <= 0 then return 0 end
	n = Hold.add(hold, id, n) or 0
	if n > 0 then
		s.stock[id] = s.stock[id] - n
		if s.stock[id] <= 0 then s.stock[id] = nil end
	end
	return n
end

-- A sale: n of id to `buyer` (an NPC record). Takes the stock, pays the
-- player, and notes it in the ledger. Returns the total paid.
function Stall.sell(u, k, id, n, buyer, clock)
	local s = Stall.get(u, k)
	if not s or (s.stock[id] or 0) < n or n <= 0 then return 0 end
	local total = Stall.price(s, id) * n
	s.stock[id] = s.stock[id] - n
	if s.stock[id] <= 0 then s.stock[id] = nil end
	u.credits = (u.credits or 0) + total
	s.earned = (s.earned or 0) + total
	table.insert(s.ledger, 1, { at = clock or u.clock or 0, item = id, n = n, price = total,
		buyer = Stall.buyerName(buyer) })
	while #s.ledger > Stall.LEDGER do table.remove(s.ledger) end
	return total
end

-- Who bought: its name, else its ship and where it's from.
function Stall.buyerName(r)
	if not r then return "?" end
	if r.name then return r.name end
	local hull = r.ship and data.hulls[r.ship.hull]
	local home = r.homeStation and L.byId[r.homeStation]
	return (hull and hull.name or "A ship") .. (home and (" from " .. home.name) or "")
end

-- Sales in the last `seconds` (default a game day): count and takings.
function Stall.recent(u, s, seconds)
	local since = (u.clock or 0) - (seconds or 86400)
	local n, cr = 0, 0
	for _, e in ipairs(s.ledger) do
		if e.at >= since then n = n + 1; cr = cr + e.price end
	end
	return n, cr
end

-- Hourly rent. A stall the player can't pay for closes.
function Stall.tick(u, game)
	local all, clock = u.stalls, u.clock
	if not all or not clock then return end
	local closing = {}
	for k, s in pairs(all) do
		while (s.paidTo or clock) <= clock do
			if (u.credits or 0) < Stall.rent then closing[#closing + 1] = k; break end
			u.credits = u.credits - Stall.rent
			s.rentPaid = (s.rentPaid or 0) + Stall.rent
			s.paidTo = (s.paidTo or clock) + 3600
		end
	end
	for _, k in ipairs(closing) do
		Stall.close(u, k, game)
		if game and game.toast then game:toast("STALL CLOSED: RENT UNPAID AT " .. (L.byId[k] and L.byId[k].name or k):upper(), 3) end
	end
end

return Stall
