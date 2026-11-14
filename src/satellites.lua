--[[
	Satellites: owned, persistent props in a planet's orbit (data/satellites.lua).

	Each is a prop design from data/wrecks/ spawned as a husk, so it flies,
	takes hits and is saved with its area like any placed wreck
	(src/persistence.lua). On top of that it carries:

	  e.sat = id    stable id, <field>_sat_<n>, for quests to name

	and the universe keeps one record per satellite (universe.satellites):

	  { id, field, kind, name, owner, dock, actions, vend, lost }

	The record is the truth for what the satellite is and what it allows; the
	husk is only where it is. Two levers, read through Sat.levers:

	  dock     who may lock on: "none" | "owner" | "rep" | "anyone" | "player"
	  actions  what you can do while locked: { "vend", "quest", ... }

	Kinds set the defaults; quests override them per satellite with
	Sat.allow / Sat.revoke, and the override is saved with the record.
]]

local data = require("src.data")

local Sat = {}

Sat.kinds = {
	passive = { design = "sat_passive", dock = "none", actions = {} },
	fuel = { design = "sat_fuel_buoy", dock = "anyone", actions = { "vend" }, vend = { "deuterium_canister" } },
	vendor = { design = "sat_vendor", dock = "anyone", actions = { "vend" },
		vend = { "rounds_s", "rounds_m", "shell_s", "patch_kit", "deuterium_canister" } },
}

local function copy(t)
	if type(t) ~= "table" then return t end
	local o = {}
	for k, v in pairs(t) do o[k] = copy(v) end
	return o
end

local function store(universe)
	universe.satellites = universe.satellites or {}
	return universe.satellites
end

-- A rolled, seeded list of { id, kind, alt, angle } for a field: the same
-- every time, so a field always has the same satellites.
function Sat.layout(fieldId, field)
	local def = data.satellites[fieldId]
	if not def or not field or not field.planetR then return {} end
	local seed = 0
	for i = 1, #fieldId do seed = seed * 31 + fieldId:byte(i) end
	local rng = love.math.newRandomGenerator(seed % 2147483647 + 1)
	local count = def.count or 12
	if type(count) == "table" then count = rng:random(count[1], count[2]) end
	local kinds, total = {}, 0
	for k, w in pairs(def.mix or { passive = 1 }) do
		if Sat.kinds[k] then kinds[#kinds + 1] = { k, w }; total = total + w end
	end
	table.sort(kinds, function(a, b) return a[1] < b[1] end)
	local band = def.band or { 0.08, 0.85 }
	local R, edge = field.planetR, field.radius or field.planetR * 3
	local out = {}
	for n = 1, count do
		local r, kind = rng:random() * total, kinds[1] and kinds[1][1] or "passive"
		for _, kw in ipairs(kinds) do
			if r < kw[2] then kind = kw[1]; break end
			r = r - kw[2]
		end
		local f = band[1] + rng:random() * (band[2] - band[1])
		out[n] = { id = ("%s_sat_%02d"):format(fieldId, n), n = n, kind = kind,
			alt = R + (edge - R) * f, angle = rng:random() * math.pi * 2, owner = def.owner,
			name = ("%s sat %02d"):format(def.names or field.name or fieldId, n) }
	end
	return out
end

-- The record for a satellite, made from its layout slot the first time.
function Sat.record(universe, slot, fieldId)
	local all = store(universe)
	local r = all[slot.id]
	if not r then
		local K = Sat.kinds[slot.kind]
		r = { id = slot.id, field = fieldId, kind = slot.kind, name = slot.name, owner = slot.owner }
		all[slot.id] = r
		r.design = K.design
	end
	return r
end

function Sat.get(universe, id) return universe and universe.satellites and universe.satellites[id] end

-- What it allows right now: the quest override if there is one, else its kind's.
function Sat.levers(r)
	local K = Sat.kinds[r.kind] or Sat.kinds.passive
	return {
		dock = r.dock or K.dock,
		actions = r.actions or K.actions,
		vend = r.vend or K.vend,
	}
end

-- Quest scripting: open a satellite up (or change what it offers) and
-- close it again. Fields left out keep their current value.
function Sat.allow(universe, id, levers)
	local r = Sat.get(universe, id)
	if not r then return false end
	if levers.dock ~= nil then r.dock = levers.dock end
	if levers.actions ~= nil then r.actions = copy(levers.actions) end
	if levers.vend ~= nil then r.vend = copy(levers.vend) end
	return true
end

function Sat.revoke(universe, id)
	local r = Sat.get(universe, id)
	if not r then return false end
	r.dock, r.actions, r.vend = nil, nil, nil
	return true
end

-- Every satellite in a field, for quests to pick from.
function Sat.inField(universe, fieldId)
	local list = {}
	for _, r in pairs(store(universe)) do
		if r.field == fieldId and not r.lost then list[#list + 1] = r end
	end
	table.sort(list, function(a, b) return a.id < b.id end)
	return list
end

-- After a field is built and its saved objects restored: spawn every
-- satellite that isn't already there. A satellite already in the area's
-- save comes back through Game:restoreArea with its sat id; one that was
-- destroyed is marked lost and stays gone.
function Sat.populate(game)
	if game.preview or not game.universe or not game.field or game.field.transit then return end
	local present = {}
	for _, e in ipairs(game.entities) do
		if e.sat and not e.removed then present[e.sat] = e end
	end
	local saved = game.universe.areas and game.universe.areas[game.fieldId]
	local w = game.well
	local cx, cy = w and w.x or 0, w and w.y or 0
	for _, slot in ipairs(Sat.layout(game.fieldId, game.field)) do
		local r = Sat.record(game.universe, slot, game.fieldId)
		local e = present[slot.id]
		-- a satellite saved in this area but not restored was destroyed
		if not e and not r.lost and r.spawnedAt and saved and (saved.capturedAt or 0) >= r.spawnedAt then r.lost = true end
		if not e and not r.lost and data.wrecks[r.design] then
			local x, y = cx + math.cos(slot.angle) * slot.alt, cy + math.sin(slot.angle) * slot.alt
			local v = game.currentSpeed and game:currentSpeed(slot.alt) or 0
			e = game:spawnWreck(r.design, x, y, slot.angle + math.pi / 2,
				-math.sin(slot.angle) * v, math.cos(slot.angle) * v)
			if e then
				r.spawnedAt = game.universe.clock or 0
				game:stepOutOfStations(e)
			end
		end
		if e then Sat.adopt(e, r) end
	end
end

-- Tag a husk as this satellite.
function Sat.adopt(e, r)
	e.sat, e.name = r.id, r.name
	if e.body and not e.body:isDestroyed() then
		e.body:setAngularVelocity(0)
		e.body:setAngularDamping(2)
	end
end

-- Mark destroyed satellites: called when a husk with a sat id dies.
function Sat.lost(game, e)
	local r = e.sat and Sat.get(game.universe, e.sat)
	if r then r.lost = true end
end

-- Docking ------------------------------------------------------------------
--
-- Tap the tractor key with the cursor on a satellite in tractor range to
-- ask for a lock. If its dock lever lets you in, it holds your ship in place
-- beside it (game.satLock) and shows its menu; tap again, or press E, to
-- leave. One ship at a time.

Sat.markup = 1.25        -- vending price over an item's base price
Sat.hooks = {}           -- [satellite id] = function(game, record) -> text?

-- Quest scripting: what happens when the player picks "quest" on this
-- satellite. The function may return a line to show. Set nil to clear.
function Sat.onQuest(id, fn) Sat.hooks[id] = fn end

function Sat.permits(game, r, ship)
	local L = Sat.levers(r)
	local player = ship == game.player
	if L.dock == "anyone" then return true end
	if L.dock == "player" then return player end
	if L.dock == "rep" and player and r.owner then
		local Rep = require("src.reputation")
		return (Rep.standing(game.universe, r.owner) or 0) >= (r.minRep or 10)
	end
	if L.dock == "owner" then return not player and ship.faction ~= nil and ship.faction == r.owner end
	return false
end

function Sat.request(game, e)
	local r = Sat.get(game.universe, e.sat)
	local p = game.player
	if not r or not p or p.dead then return false end
	if game.satLock then Sat.release(game); return false end
	if e.satHeld and e.satHeld ~= p then game:toast(r.name:upper() .. ": BUSY", 1.4); return false end
	if not Sat.permits(game, r, p) then game:toast(r.name:upper() .. ": DOCKING REFUSED", 1.6); return false end
	local lx, ly = e.body:getLocalPoint(p.body:getPosition())
	local d = math.sqrt(lx * lx + ly * ly)
	local want = (e.radius or 100) * 0.35 + (p.halfLength or 30) + 30
	if d < 1 then lx, ly, d = 0, 1, 1 end
	lx, ly = lx / d * want, ly / d * want
	game.satLock = { e = e, r = r, lx = lx, ly = ly, pick = 1, note = nil }
	e.satHeld = p
	game:toast(r.name:upper() .. ": LOCKED ON", 1.2)
	return true
end

function Sat.release(game)
	local lock = game.satLock
	if not lock then return end
	if lock.e then lock.e.satHeld = nil end
	game.satLock = nil
end

-- Each step: hold the ship beside the satellite (and drop the lock if
-- either is gone).
function Sat.update(game, dt)
	local lock = game.satLock
	if not lock then return end
	local e, p = lock.e, game.player
	if not p or p.dead or p.removed or e.removed or e.dead or not e.body or e.body:isDestroyed() then Sat.release(game); return end
	local wx, wy = e.body:getWorldPoint(lock.lx, lock.ly)
	local px, py = p.body:getPosition()
	local k = math.min(1, dt * 6)
	p.body:setPosition(px + (wx - px) * k, py + (wy - py) * k)
	p.body:setLinearVelocity(e.body:getLinearVelocityFromWorldPoint(wx, wy))
end

-- The menu's rows: { label, kind, item? }.
function Sat.menu(game)
	local lock = game.satLock
	if not lock then return {} end
	local L, rows = Sat.levers(lock.r), {}
	for _, a in ipairs(L.actions or {}) do
		if a == "vend" then
			for _, id in ipairs(L.vend or {}) do
				local it = data.items[id]
				if it then rows[#rows + 1] = { label = it.name, kind = "vend", item = id, price = math.floor((it.price or 0) * Sat.markup + 0.5) } end
			end
		elseif a == "quest" then
			rows[#rows + 1] = { label = "Uplink", kind = "quest" }
		end
	end
	rows[#rows + 1] = { label = "Release lock", kind = "leave" }
	return rows
end

function Sat.choose(game, row)
	local lock = game.satLock
	if not lock or not row then return end
	if row.kind == "leave" then Sat.release(game); return end
	if row.kind == "vend" then
		local Ship = require("src.ship")
		local u = game.universe
		if (u.credits or 0) < row.price then lock.note = "Not enough credits"; return end
		if Ship.canFit(game.player, row.item, 1) < 1 then lock.note = "No room in the hold"; return end
		Ship.addCargo(game.player, row.item, 1)
		u.credits = u.credits - row.price
		lock.note = ("Bought %s for %d cr"):format(row.label, row.price)
	elseif row.kind == "quest" then
		local hook = Sat.hooks[lock.r.id]
		local text = hook and hook(game, lock.r)
		require("src.events").emit("satellite_uplink", lock.r, game)
		lock.note = text or "No traffic on this channel"
	end
end

function Sat.keypressed(game, key)
	local lock = game.satLock
	if not lock then return false end
	local rows = Sat.menu(game)
	if key == "e" or key == "escape" then Sat.release(game); return true end
	if key == "up" or key == "w" then lock.pick = (lock.pick - 2) % #rows + 1; return true end
	if key == "down" or key == "s" then lock.pick = lock.pick % #rows + 1; return true end
	if key == "return" or key == "kpenter" or key == "space" then Sat.choose(game, rows[lock.pick]); return true end
	local n = tonumber(key)
	if n and rows[n] then lock.pick = n; Sat.choose(game, rows[n]); return true end
	return false
end

function Sat.draw(game)
	local lock = game.satLock
	if not lock then return end
	local lg = love.graphics
	local rows = Sat.menu(game)
	local font = lg.getFont()
	local lh = font:getHeight() + 6
	local w, h = 320, 52 + #rows * lh + (lock.note and lh or 0)
	local x, y = lg.getWidth() - w - 24, lg.getHeight() / 2 - h / 2
	lg.setColor(0.04, 0.05, 0.08, 0.9)
	lg.rectangle("fill", x, y, w, h, 4)
	lg.setColor(0.45, 0.55, 0.75)
	lg.rectangle("line", x, y, w, h, 4)
	lg.setColor(0.9, 0.92, 0.96)
	lg.print(lock.r.name, x + 12, y + 10)
	lg.setColor(0.55, 0.6, 0.7)
	lg.printf(("%d cr"):format(game.universe.credits or 0), x, y + 10, w - 12, "right")
	for i, row in ipairs(rows) do
		local ry = y + 40 + (i - 1) * lh
		if i == lock.pick then lg.setColor(0.2, 0.3, 0.5, 0.6); lg.rectangle("fill", x + 6, ry - 2, w - 12, lh) end
		lg.setColor(0.85, 0.88, 0.94)
		lg.print(("%d  %s"):format(i, row.label), x + 12, ry)
		if row.price then lg.printf(row.price .. " cr", x, ry, w - 12, "right") end
	end
	if lock.note then
		lg.setColor(1, 0.8, 0.45)
		lg.print(lock.note, x + 12, y + 40 + #rows * lh + 4)
	end
end

return Sat
