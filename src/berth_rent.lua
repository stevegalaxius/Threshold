--[[
	Berth rent: every ship you leave parked at a station pays for the space
	it takes, by the hour, on the universe clock (the same way market stalls
	bill, src/stalls.lua). The ship you're flying pays nothing.

	A parked ship record carries its tenancy in rec.lease:

	  landlord  station key the rent is owed to
	  rate      credits an hour, fixed when the lease starts (or moves)
	  inside    true for an interior hangar bay, false for an outside mooring
	  paidTo    universe clock the rent is paid up to
	  owed      unpaid rent; a ship in arrears can't leave until it's paid
	  paid      lifetime rent paid

	Rent is per hangar cell the hull takes (Game.hangarFootprint), dearer
	inside than out. When you can't pay, the bill runs up. Once it reaches
	Rent.graceHours of rent, the station impounds the ship and puts it on
	its dealer lot; whatever the sale clears beyond the debt is paid to you.

	The landlord is a field, not an assumption: a player-owned station
	(not built yet) will be a landlord too, and Rent.payee is where its
	takings will go.
]]
local data = require("src.data")
local L = require("src.locations")

local Rent = {}
Rent.perCellInside, Rent.perCellOutside, Rent.minimum = 4, 2, 10
Rent.graceHours = 48
local HOUR = 3600

local function footprint(hullId)
	local hull = data.hulls[hullId]
	if not hull or not hull.shape then return 1 end
	local Game = require("src.game")
	local w, h = Game.hangarFootprint(hullId, false)
	return math.max(1, w * h)
end

-- Credits an hour for a ship of hullId, inside a bay or out on a mooring.
function Rent.rate(hullId, inside)
	local per = inside and Rent.perCellInside or Rent.perCellOutside
	return math.max(Rent.minimum, math.floor(footprint(hullId) * per + 0.5))
end

-- Who collects: nil for a station that isn't anyone's (the money just
-- leaves the game). A future player station returns its owner here.
function Rent.payee(u, landlord) return nil end

-- Start (or re-rate) the lease on a parked record at station key.
function Rent.lease(u, key, rec)
	local inside = rec.bay ~= nil
	local l = rec.lease
	if l and l.landlord == key and l.inside == inside then return l end
	l = l or { owed = 0, paid = 0 }
	l.landlord, l.inside, l.rate = key, inside, Rent.rate(rec.hull, inside)
	l.paidTo = math.max(l.paidTo or 0, u.clock or 0)
	rec.lease = l
	return l
end

function Rent.owed(rec) return rec and rec.lease and rec.lease.owed or 0 end

-- Pay what a ship owes, if you can. Returns true when it's clear.
function Rent.settle(u, rec)
	local owed = Rent.owed(rec)
	if owed <= 0 then return true end
	local pay = math.min(owed, math.max(0, u.credits or 0))
	u.credits = u.credits - pay
	rec.lease.owed, rec.lease.paid = owed - pay, (rec.lease.paid or 0) + pay
	return rec.lease.owed <= 0
end

-- Every hangar list in the universe with the station key it belongs to.
local function hangars(u)
	local out = {}
	for key, r in pairs(u.stations or {}) do
		if r.hangar then out[#out + 1] = { key = key, list = r.hangar } end
		for _, a in pairs(r.accessHangars or {}) do
			if a.hangar then out[#out + 1] = { key = key, list = a.hangar } end
		end
	end
	table.sort(out, function(a, b) return a.key < b.key end)
	return out
end

-- The station takes a ship for unpaid rent and puts it up for sale.
local function impound(u, key, list, i, game)
	local rec = table.remove(list, i)
	local Game = require("src.game")
	local value = Game.shipSellPrice(rec)
	local back = math.max(0, value - Rent.owed(rec))
	u.credits = (u.credits or 0) + back
	rec.lease = nil
	require("src.dealers").resell(u, key, rec)
	if game and game.toast then
		local hull = data.hulls[rec.hull]
		game:toast(("%s IMPOUNDED AT %s FOR UNPAID BERTH RENT"):format(
			(hull and hull.name or rec.hull):upper(), (L.byId[key] and L.byId[key].name or key):upper()), 3)
	end
end

-- Hourly billing, from the universe update.
function Rent.tick(u, game)
	local clock = u.clock
	if not clock then return end
	for _, h in ipairs(hangars(u)) do
		for i = #h.list, 1, -1 do
			local rec = h.list[i]
			local l = Rent.lease(u, h.key, rec)
			while l.paidTo <= clock do
				l.paidTo = l.paidTo + HOUR
				if (u.credits or 0) >= l.rate + (l.owed or 0) then
					Rent.settle(u, rec)
					u.credits = u.credits - l.rate
					require("src.accounts").receive(u, h.key, l.rate, "sold", "rent")
					l.paid = (l.paid or 0) + l.rate
				elseif (l.owed or 0) < l.rate * Rent.graceHours then
					-- (a long clock jump stops at the impound line, not past it)
					l.owed = (l.owed or 0) + l.rate
				end
			end
			if (l.owed or 0) > 0 then Rent.settle(u, rec) end
			if (l.owed or 0) >= l.rate * Rent.graceHours and require("src.dealers").def(h.key) then
				impound(u, h.key, h.list, i, game)
			end
		end
	end
end

-- Total an hour for everything you keep parked (for the HUD / Manage tab).
function Rent.total(u)
	local n, owed = 0, 0
	for _, h in ipairs(hangars(u)) do
		for _, rec in ipairs(h.list) do
			if rec.lease then n = n + rec.lease.rate; owed = owed + (rec.lease.owed or 0) end
		end
	end
	return n, owed
end

return Rent
