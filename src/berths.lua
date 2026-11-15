--[[
	Berths: clamps on the outside of a hull that carry whole ships, like an
	auto-transport trailer. A hull lists them in hull.berths:

	  berths = { { x, y, heading = deg, maxLength = px, maxWidth = px }, ... }

	The Shipyard edits them with the Ship berths tool.

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

-- A berth's length and width in px: maxLength / maxWidth, or from its
-- size the way the Shipyard draws a new pad (2 x size by 1.1 x size).
function B.size(b)
	local s = b.size or 40
	return b.maxLength or b.length or s * 2, b.maxWidth or b.width or s * 1.1
end

-- Does a ship of hullId fit berth b (a table)?
function B.fitsSize(b, hullId)
	local h = data.hulls[hullId]
	if not b or not h or not h.shape or (h.berths and #h.berths > 0) then return false end
	local len, wid = extents(h)
	local bl, bw = B.size(b)
	return len <= bl and wid <= bw
end

-- Can a ship of hullId ride on berth i of carrier hull?
function B.fits(hull, i, hullId)
	return B.fitsSize(B.list(hull)[i], hullId)
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

-- Physics: each carried ship collides as part of its carrier. Its hull's
-- triangles go on the carrier's body at the berth's pose, tagged with the
-- berth (fixture user data is still the carrier, so every weapon and ram
-- finds it). Rebuilt only when what's aboard changes, and never while
-- the world is mid-step.
local function pose(b)
	local a = math.rad(b.heading or 0)
	return b[1] or b.x or 0, b[2] or b.y or 0, math.cos(a), math.sin(a)
end

function B.syncFixtures(e)
	local body = e.body
	if not body or body:isDestroyed() then return end
	local sig = {}
	for i, rec in pairs(e.carried or {}) do sig[#sig + 1] = i .. "=" .. tostring(rec) end
	table.sort(sig)
	sig = table.concat(sig, ",")
	if body:getWorld():isLocked() then
		if sig ~= (e.berthSig or "") or e.berthLost then e.massDirty = true end
		return
	end
	-- ships torn off their berths: each leaves a husk where it rode
	for _, lost in ipairs(e.berthLost or {}) do B.spawnHusk(lost.game, e, lost.rec, lost.berth, lost) end
	e.berthLost = nil
	if sig == (e.berthSig or "") then return end
	for _, f in ipairs(e.berthFixtures or {}) do if not f:isDestroyed() then f:destroy() end end
	e.berthFixtures, e.berthSig = {}, sig
	local T = require("src.tuning")
	for i, rec in pairs(e.carried or {}) do
		local b, hull = B.list(e.hull)[i], data.hulls[rec.hull]
		if b and hull then
			local bx, by, c, s = pose(b)
			for _, part in ipairs(hull.parts or {}) do
				if part.collide ~= false then
					for _, t in ipairs(part.tris or {}) do
						local p = {}
						for k = 1, 6, 2 do
							p[k], p[k + 1] = bx + t[k] * c - t[k + 1] * s, by + t[k] * s + t[k + 1] * c
						end
						local a2 = math.abs((p[3] - p[1]) * (p[6] - p[2]) - (p[5] - p[1]) * (p[4] - p[2]))
						if a2 > 4 then
							local f = love.physics.newFixture(body, love.physics.newPolygonShape(p), 0)
							f:setRestitution(0.35); f:setFriction(0.3)
							f:setUserData(e); f:setCategory(T.collideShip)
							e.berthFixtures[#e.berthFixtures + 1] = f
						end
					end
				end
			end
		end
	end
end

-- The husk of carried ship rec, torn off berth b of carrier e: a dead
-- ship of that hull and fit where it rode, drifting with the carrier,
-- with its hold to loot.
function B.spawnHusk(game, e, rec, b, lost)
	if not (game and game.spawnHusk and data.hulls[rec.hull]) then return end
	local bx, by = pose(b)
	local x, y = e.body:getWorldPoint(bx, by)
	local vx, vy = e.body:getLinearVelocityFromWorldPoint(x, y)
	local a = e.body:getAngle() + math.rad(b.heading or 0)
	-- a real ship, dead on arrival: it dies the way any ship does (the
	-- explosion, then a husk with its whole hold and surviving modules)
	local Ship = require("src.ship")
	local ship = Ship.new(game, { hull = rec.hull, loadout = rec.loadout, triggers = rec.triggers, loads = rec.loads,
		cargo = rec.cargo, hold = rec.hold, armor = 0, color = rec.color, fuelCharge = rec.fuelCharge,
		fuelInitialized = rec.fuelInitialized, power = rec.power, team = 0, x = x, y = y, angle = a })
	-- thrown clear of the carrier: out from its centre through the berth
	-- (sideways for a berth on the spine), so the husk doesn't sit in the
	-- cradle or get run down. The death path keeps 60% of a dead ship's
	-- velocity, so this is scaled up to leave the husk at the carrier's
	-- speed plus the push.
	local cx, cy = e.body:getPosition()
	local ox, oy = x - cx, y - cy
	local d = math.sqrt(ox * ox + oy * oy)
	if d < 1 then ox, oy, d = math.cos(a + math.pi / 2), math.sin(a + math.pi / 2), 1 end
	local push = 90
	ship.body:setLinearVelocity((vx + ox / d * push) / 0.6, (vy + oy / d * push) / 0.6)
	ship.body:setAngularVelocity(e.body:getAngularVelocity())
	ship.armor, ship.dead, ship.lastHitBy = 0, true, lost and lost.source
	table.insert(game.entities, ship)
end

-- A hit on carrier e at world point hx, hy: if it lands on a carried
-- ship, that ship takes it (its own armor) and the carrier doesn't.
-- A carried ship whose armor runs out is torn off its berth and lost.
-- Returns true when a carried ship took the hit.
function B.hit(game, e, amount, hx, hy, source)
	if not (e.carried and next(e.carried) and hx and e.body) then return false end
	local lx, ly = e.body:getLocalPoint(hx, hy)
	for i, rec in pairs(e.carried) do
		local b, hull = B.list(e.hull)[i], data.hulls[rec.hull]
		if b and hull and hull.shape then
			local bx, by, c, s = pose(b)
			local dx, dy = lx - bx, ly - by
			local u, v = dx * c + dy * s, -dx * s + dy * c   -- into the carried ship's frame
			local x1, y1, x2, y2 = 0, 0, 0, 0
			for k = 1, #hull.shape, 2 do
				x1, y1 = math.min(x1, hull.shape[k]), math.min(y1, hull.shape[k + 1])
				x2, y2 = math.max(x2, hull.shape[k]), math.max(y2, hull.shape[k + 1])
			end
			if u >= x1 - 3 and u <= x2 + 3 and v >= y1 - 3 and v <= y2 + 3 then
				local full = stats.compute(hull, rec.loadout or hull.loadout).armor
				rec.armor = (rec.armor or full) - amount
				if rec.armor <= 0 then
					e.carried[i] = nil
					-- its husk is spawned next step, outside the physics step
					e.berthLost = e.berthLost or {}
					table.insert(e.berthLost, { game = game, rec = rec, berth = b, source = source })
					e.massDirty = true   -- next step drops its mass and fixtures
					if game.spark then game:spark(hx, hy, 24) end
					if e.isPlayer and game.toast then game:toast(("%s ON BERTH %d DESTROYED"):format(hull.name:upper(), i), 1.6) end
				elseif game.spark then game:spark(hx, hy, 4) end
				return true
			end
		end
	end
	return false
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
