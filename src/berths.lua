--[[
	Berths: clamps on the outside of a hull that carry whole ships, like an
	auto-transport trailer. A hull lists them in hull.berths:

	  berths = { { x, y, heading = deg, length = px, width = px }, ... }

	x, y and heading are in the carrier's own frame (+x the nose). A ship
	fits a berth when its hull is no longer and no wider than the berth,
	and it can't carry berths of its own (no nesting).

	A carried ship is a plain ship record (Ship.record) in e.carried[i],
	the same thing a station hangar keeps, so it keeps its fit, hold and
	damage. Loading and unloading happen docked, from the hangar screen:
	a parked ship of yours goes onto a free berth, and a carried one goes
	back into the station's parking. Carried ships add their mass and are
	drawn on the hull.
]]
local data = require("src.data")
local stats = require("src.stats")
local Hold = require("src.inventory.hold")

local B = {}

local function extents(hull)
	local x1, y1, x2, y2 = 0, 0, 0, 0
	for i = 1, #hull.shape, 2 do
		x1, y1 = math.min(x1, hull.shape[i]), math.min(y1, hull.shape[i + 1])
		x2, y2 = math.max(x2, hull.shape[i]), math.max(y2, hull.shape[i + 1])
	end
	return x2 - x1, y2 - y1
end

function B.list(hull) return hull and hull.berths or {} end
function B.count(hull) return #B.list(hull) end

-- Can a ship of hullId ride on berth i of carrier hull?
function B.fits(hull, i, hullId)
	local b = B.list(hull)[i]
	local h = data.hulls[hullId]
	if not b or not h or (h.berths and #h.berths > 0) then return false end
	local len, wid = extents(h)
	return len <= (b.length or 0) and wid <= (b.width or 0)
end

-- First free berth on carrier e that takes hullId, or nil.
function B.free(e, hullId)
	e.carried = e.carried or {}
	for i in ipairs(B.list(e.hull)) do
		if not e.carried[i] and B.fits(e.hull, i, hullId) then return i end
	end
end

-- How many ships e carries.
function B.aboard(e)
	local n = 0
	for _ in pairs(e.carried or {}) do n = n + 1 end
	return n
end

-- Mass of one ship record: dry mass plus its cargo.
function B.recordMass(rec)
	local hull = data.hulls[rec.hull]
	if not hull then return 0 end
	local m = stats.compute(hull, rec.loadout or hull.loadout).mass
	local counts = rec.hold and Hold.totals(rec.hold) or rec.cargo or {}
	local _, cm = stats.cargo(counts)
	return m + cm
end

-- Tonnes riding on e's berths.
function B.mass(e)
	local m = 0
	for _, rec in pairs(e.carried or {}) do m = m + B.recordMass(rec) end
	return m
end

-- Put parked ship i of this station's hangar onto a free berth of the
-- ship you're flying. Returns true, or false and why.
function B.load(game, st, i)
	local p = game.player
	local list = game:hangar(st)
	local rec = list[i]
	if not rec then return false, "NO SUCH SHIP" end
	if B.count(p.hull) == 0 then return false, "YOUR SHIP HAS NO BERTHS" end
	local slot = B.free(p, rec.hull)
	if not slot then return false, "NO BERTH FITS THAT SHIP" end
	table.remove(list, i)
	rec.bay, rec.mooring = nil, nil
	p.carried[slot] = rec
	require("src.ship").updateMass(p)
	return true
end

-- Put the ship on berth `slot` (the last one carried, if nil) back into
-- this station's parking.
function B.unload(game, st, slot)
	local p = game.player
	local carried = p.carried or {}
	if not slot then
		for i in pairs(carried) do slot = math.max(slot or 0, i) end
	end
	local rec = slot and carried[slot]
	if not rec then return false, "NOTHING ON YOUR BERTHS" end
	local parking = game:shipParkingFit(st, rec.hull, rec)
	if not parking then return false, "NO SUITABLE FREE PARKING" end
	carried[slot] = nil
	game:applyParking(rec, parking)
	table.insert(game:hangar(st), rec)
	require("src.ship").updateMass(p)
	return true
end

-- Draw what e carries, in e's own frame (called from Render's ship draw).
function B.draw(e, outline)
	if not e.carried or not next(e.carried) then return end
	local HullShape = require("src.hullshape")
	local weapons = require("src.weapon_visual")
	local lg = love.graphics
	for i, rec in pairs(e.carried) do
		local b = B.list(e.hull)[i]
		local hull = b and data.hulls[rec.hull]
		if hull then
			lg.push()
			lg.translate(b[1] or b.x or 0, b[2] or b.y or 0)
			lg.rotate(math.rad(b.heading or 0))
			local tint = rec.color or { 0.55, 0.8, 0.85 }
			local dark = { tint[1] * 0.22, tint[2] * 0.22, tint[3] * 0.22 }
			local loadout = rec.loadout or hull.loadout
			weapons.drawLoadout(hull, loadout, tint, dark, outline(1.5), false)
			HullShape.draw(hull, tint, function(c) return { c[1] * 0.22, c[2] * 0.22, c[3] * 0.22 } end,
				function(c) return c end, outline(1.5))
			weapons.drawLoadout(hull, loadout, tint, dark, outline(1.5), true)
			lg.pop()
		end
	end
end

-- Save and load: carried records go through the caller's ship saver.
function B.save(carried, saveShip)
	if not carried or not next(carried) then return nil end
	local out = {}
	for i, rec in pairs(carried) do out[tostring(i)] = saveShip(rec) end
	return out
end

function B.load_saved(t, loadShip)
	if not t then return nil end
	local out = {}
	for k, rec in pairs(t) do
		local r = loadShip(rec)
		if r then out[tonumber(k)] = r end
	end
	return out
end

return B
