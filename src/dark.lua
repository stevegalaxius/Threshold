--[[
	Dark locations: grids that exist in the world but not on the public
	charts. A dark grid (dark = true on its Fields.orbits entry or its
	field) is simulated like any other area: its stations trade, NPCs fly
	there (pirates know the way), it has a mass driver. What it lacks is a
	listing: the player's driver window and lane view leave it out until
	the player discovers it.

	Discovery is saved per universe in universe.discovered[area] = clock.
	Dark.discover(u, area) is the one way in (a tip-off, a scan, a quest
	reward, following a pirate home); Dark.forget undoes it for debugging.

	Dark.DEBUG_CHARTED lists grids treated as known in every game for now,
	so they can be tested from the driver without playing to them. Remove
	an entry to make that grid start hidden.

	Fences (uses.fence on a white station) are the door from the dark
	network into the white one: see Dark.isFence.

	Hooks for a dark economy: Dark.isDarkArea / isDarkNode
	tell public systems (freight board, contracts, price listings) to keep
	a grid's stations off public listings, and Dark.listeners lets other
	systems react when the player finds one.
]]

local Dark = {}

-- Grids shown as found while they're being built and tested.
Dark.DEBUG_CHARTED = { milliways = true, shoals = true, cordelia = true, antichthon = true }

-- function(u, area) called after a grid is discovered.
Dark.listeners = {}

local function fields() return require("src.fields") end

-- Is this area a dark grid?
function Dark.isDarkArea(area)
	local F = fields()
	local o, f = F.orbits[area], F[area]
	return (o and o.dark) or (type(f) == "table" and f.dark) or false
end

-- Is this location (station, driver, buoy) on a dark grid?
function Dark.isDarkNode(id)
	local place = require("src.locations").byId[id]
	return place ~= nil and Dark.isDarkArea(place.area)
end

-- Every dark grid, in list order.
function Dark.areas()
	local out = {}
	for _, area in ipairs(fields().list) do if Dark.isDarkArea(area) then out[#out + 1] = area end end
	return out
end

-- Is this a fence: a white station (uses.fence) whose back room buys
-- stolen goods? The only white stations dark stock is sold into
-- (src/economy.lua), and the only white markets that take stolen
-- stacks from the player (src/market.lua tradeProblem).
function Dark.isFence(id)
	local place = require("src.locations").byId[id]
	return place ~= nil and place.uses ~= nil and place.uses.fence == true and not Dark.isDarkArea(place.area)
end

function Dark.fences()
	local out = {}
	for _, area in ipairs(fields().list) do
		for _, id in ipairs(require("src.locations").stations(area, "fence")) do
			if Dark.isFence(id) then out[#out + 1] = id end
		end
	end
	return out
end

function Dark.isDiscovered(u, area)
	return (u and u.discovered and u.discovered[area]) ~= nil
end

-- Does the player have this area on their charts? Every public area does.
function Dark.charted(u, area)
	if not Dark.isDarkArea(area) then return true end
	return Dark.DEBUG_CHARTED[area] == true or Dark.isDiscovered(u, area)
end

-- Mark a dark grid found. Returns true if it was new.
function Dark.discover(u, area)
	if not Dark.isDarkArea(area) or Dark.isDiscovered(u, area) then return false end
	u.discovered = u.discovered or {}
	u.discovered[area] = u.clock or 0
	for _, fn in ipairs(Dark.listeners) do fn(u, area) end
	return true
end

function Dark.forget(u, area)
	if u.discovered then u.discovered[area] = nil end
end

return Dark
