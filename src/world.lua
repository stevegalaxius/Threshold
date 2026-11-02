--[[
	The universe: everything that lasts while levels come and go, and the
	game's way between them.

	  universe  game.universe = { stations = { [key] = { storage, hangar,
	            market } }, home = { field, key }, credits, clock } (markets
	            and credits: src/market.lua). Authored station keys are stable location IDs
	            (src/locations.lua), independent of display name and spawn order. home is where you last docked.
	  levels    each named field keeps selected world objects in universe.areas
	            (src/persistence.lua). Wrecks, containers and loose cargo follow
	            the orbital current while unloaded. Scenery and unmanaged NPCs regenerate on visits;
	            Station traders persist as A-Life records (src/alife.lua);
	            transit lanes remain temporary.
	  travel    mass drivers and the transit lane between planets: see
	            src/transit.lua.
	  hangar    every station has a hangar bay: a grid (T.hangarW x
	            T.hangarH cells) where each ship takes a footprint the size
	            of its hull. The ship you're docked in has a spot too
	            (player.bay). Fly any parked ship out, and the one you came
	            in stays parked where it was. Each record keeps its spot in
	            rec.bay = { x, y, rot }.
	  respawn   lose your ship and you get a starter ship docked at home
	            (any level), or at the start if you've never docked.
	  saving    Game:saveState() is one plain table of all of the above plus
	            your ship and where it is; Game:loadState() puts it back.
	            src/save.lua writes and reads it. F5 saves, F9 loads, and
	            docking autosaves.

	Added to Game by src/game.lua: require("src.world")(Game).
]]

local data = require("src.data")
local T = require("src.tuning")
local Ship = require("src.ship")
local Fields = require("src.fields")
local Hold = require("src.inventory.hold")
local Save = require("src.save")
local Grid = require("src.inventory.grid")
local Persistence = require("src.persistence")
local events = require("src.events")

local sqrt, cos, sin, pi, max = math.sqrt, math.cos, math.sin, math.pi, math.max

return function(Game)

function Game:newUniverse()
	self.alifeOnline = {}
	self.alifeActiveArea = nil
	self.universe = { stations = {}, areas = {}, nextObjectId = 0, npcs = {}, npcAreas = {}, nextNpcId = 0, home = nil, credits = T.startCredits, clock = 0 }
end

-- The lasting record for a station: its storage and its hangar.
function Game:stationRecord(st)
	local u = self.universe.stations
	local r = u[st.key]
	if not r then
		r = {
			storage = Hold.new({ { key = "storage", name = "Station storage", w = T.storageW, h = T.storageH } }),
			hangar = {},
		}
		u[st.key] = r
	end
	return r
end

function Game:findStation(key)
	for _, e in ipairs(self.entities) do
		if e.kind == "station" and e.key == key then return e end
	end
end

-- Where you'd respawn: { field, key, name }, or nil.
function Game:homeStation()
	return self.universe.home
end

-- Called when the player finishes docking: this is home now, and the game
-- autosaves.
function Game:playerDocked(st)
	self:givePlayerBay(st)
	self.universe.home = { field = self.fieldId, key = st.key, name = st.name }
	self:autosave()
end

-- Put a ship straight into a station's dock, already inside.
function Game:dockInstantly(e, st)
	local d = st.dock
	e.dockState = { station = st, phase = "done", done = true, t = 0 }
	e.body:setActive(false)
	e.body:setPosition(self.dockWorld(st, 1, (d.x1 + d.x2) / 2, 0))
	e.body:setAngle(self.dockAngle(st, 1) + pi)
	e.body:setLinearVelocity(0, 0)
	e.body:setAngularVelocity(0)
	if e == self.player then
		self.state = "docked"
		self.camera.x, self.camera.y = e.body:getPosition()
		self:givePlayerBay(st)
	end
end

-- Spawn the player in a level that's already built (see Game:loadField
-- for rec and at).
function Game:placePlayer(rec, at)
	local p = self:spawnPlayer(rec)
	at = at or {}
	if at.station then
		local st = self:findStation(at.station)
		if st and st.dock then self:dockInstantly(p, st) return p end
	end
	if at.driver and self:placeAtDriver(p, at.exit) then return p end
	if at.catch and self:placeForCatch(p) then return p end
	if at.x then
		p.body:setPosition(at.x, at.y)
		p.body:setAngle(at.angle or 0)
		p.body:setLinearVelocity(at.vx or 0, at.vy or 0)
		self.camera.x, self.camera.y = at.x, at.y
	end
	return p
end

-- Levels ----------------------------------------------------------------------

-- The level's enemies, scattered away from where the player arrives.
function Game:spawnFieldEnemies()
	local sx, sy = self.field.spawn[1], self.field.spawn[2]
	for _, group in ipairs(self.field.enemies or {}) do
		for _ = 1, group[2] do
			for _ = 1, 20 do
				local a = love.math.random() * pi * 2
				local d = 1500 + love.math.random() * (self.arenaRadius - 2500)
				local x, y = cos(a) * d, sin(a) * d
				if (x - sx) ^ 2 + (y - sy) ^ 2 > (T.aggroRange + 800) ^ 2 and self:isClear(x, y, 150) then
					self:spawnEnemy(group[1], x, y, { idle = true })
					break
				end
			end
		end
	end
end

-- Hangar ----------------------------------------------------------------------

function Game:hangar(st)
	local list = self:stationRecord(st).hangar
	-- ships parked before bays had spots (older saves) get one now
	for _, rec in ipairs(list) do
		if not rec.bay then rec.bay = self:hangarFit(st, rec.hull, rec) or { x = 0, y = 0, rot = false } end
	end
	return list
end

-- A hull's footprint in a hangar bay, in cells: its length and width over
-- T.hangarCell pixels (hull.hangar = { w, h } overrides). Rotated, it's
-- the other way round.
function Game.hangarFootprint(hullId, rot)
	local hull = data.hulls[hullId]
	local w, h
	if hull.hangar then
		w, h = hull.hangar[1], hull.hangar[2]
	else
		local nx, tx, wy = 0, 0, 0
		for i = 1, #hull.shape, 2 do
			nx, tx = max(nx, hull.shape[i]), math.min(tx, hull.shape[i])
			wy = max(wy, math.abs(hull.shape[i + 1]))
		end
		w, h = math.ceil((nx - tx) / T.hangarCell), math.ceil(wy * 2 / T.hangarCell)
	end
	if rot then w, h = h, w end
	return w, h
end

-- The station's bay as a grid of everything parked in it (and the ship
-- you're docked in), leaving out `ignore` (a record, or the player).
function Game:hangarGrid(st, ignore)
	local g = Grid.new(T.hangarW, T.hangarH, "Hangar bay")
	local function put(owner, hullId, bay)
		if owner == ignore or not bay then return end
		local w, h = Game.hangarFootprint(hullId, bay.rot)
		if Grid.isFree(g, bay.x, bay.y, w, h) then Grid.place(g, { x = bay.x, y = bay.y, w = w, h = h, owner = owner }) end
	end
	for _, rec in ipairs(self:stationRecord(st).hangar) do put(rec, rec.hull, rec.bay) end
	local p = self.player
	if p and not p.dead and p.dockState and p.dockState.station == st then put(p, p.hull.id, p.bay) end
	return g
end

-- The first free spot for a hull (unrotated first), or nil if it's full.
function Game:hangarFit(st, hullId, ignore)
	local g = self:hangarGrid(st, ignore)
	for _, rot in ipairs({ false, true }) do
		local w, h = Game.hangarFootprint(hullId, rot)
		local x, y = Grid.firstFit(g, w, h)
		if x then return { x = x, y = y, rot = rot } end
	end
end

-- Can this ship (a record, or the player) sit at bay?
function Game:hangarFree(st, owner, hullId, bay)
	local w, h = Game.hangarFootprint(hullId, bay.rot)
	return Grid.isFree(self:hangarGrid(st, owner), bay.x, bay.y, w, h)
end

-- The ship you're docked in takes a spot in the bay (if it hasn't one
-- here already). A full bay leaves it on the landing pad: docked, but
-- not on the grid.
function Game:givePlayerBay(st)
	local p = self.player
	if p.bayStation == st.key and p.bay and self:hangarFree(st, p, p.hull.id, p.bay) then return end
	p.bayStation = st.key
	p.bay = self:hangarFit(st, p.hull.id, p)
end

-- A brand-new ship of a hull, parked in this station's hangar (the debug
-- panel's way of getting ships until there's a market). nil if the bay
-- has no room for it.
function Game:addToHangar(st, hullId)
	local bay = self:hangarFit(st, hullId)
	if not bay then self:toast("NO ROOM IN THE HANGAR", 1.4) return nil end
	local e = Ship.new(self, { hull = hullId, team = 1, grid = true, color = self.playerColor })
	local rec = Ship.record(e)
	e.body:destroy()
	rec.bay = bay
	table.insert(self:hangar(st), rec)
	return rec
end

-- Fly parked ship i out of this station. The one you're in stays parked
-- where it was (or, if it was on the landing pad, goes to the first spot
-- the departing ship leaves room for).
function Game:flyFromHangar(i)
	local p = self.player
	local st = p and p.dockState and p.dockState.done and p.dockState.station
	if not st then return false end
	local list = self:hangar(st)
	local rec = list[i]
	if not rec then return false end
	local old = Ship.record(p)
	old.bay = p.bay
	if not old.bay then
		old.bay = self:hangarFit(st, old.hull, rec)
		if not old.bay then self:toast("NO ROOM TO PARK YOUR SHIP", 1.4) return false end
	end
	list[i] = old
	local ship = self:spawnPlayer(rec)
	ship.bay, ship.bayStation = rec.bay, st.key
	self:dockInstantly(ship, st)
	events.emit("swapship", ship, st)
	return true
end

-- Respawn ---------------------------------------------------------------------

-- After losing your ship: a starter ship, docked at the station you last
-- docked at (travelling there if it's in another level), or at the
-- level's start if you never docked anywhere.
function Game:respawn()
	if self.state ~= "dead" then return end
	local rec = { hull = T.starterHull }
	local home = self.universe.home
	if home and home.field ~= self.fieldId then
		self:loadField(home.field, { player = rec, at = { station = home.key } })
	else
		self:placePlayer(rec, home and { station = home.key })
	end
	if home then self:toast(("NEW SHIP AT %s"):format(home.name:upper()), 2) end
end

-- Saving ----------------------------------------------------------------------

local function saveShip(rec)
	return {
		hull = rec.hull, loadout = rec.loadout, armor = rec.armor, color = rec.color, bay = rec.bay,
		hold = rec.hold and Hold.serialize(rec.hold) or nil, cargo = rec.cargo,
	}
end

local function known(id) return data.items[id] ~= nil end

local function loadShip(t)
	if not t or not data.hulls[t.hull] then return { hull = T.starterHull } end
	return {
		hull = t.hull, loadout = t.loadout, armor = t.armor, color = t.color, bay = t.bay,
		hold = t.hold and Hold.deserialize(t.hold, known) or nil, cargo = t.cargo,
	}
end

-- The whole game as one plain table (see src/save.lua).
function Game:saveState()
	self:captureALife(false)
	self:captureArea()
	if self.trip and self.trip.originScene then
		self.trip.originScene:syncAreaMotion()
		self.trip.originScene:captureArea()
	end
	local stations = {}
	for key, r in pairs(self.universe.stations) do
		local hangar = {}
		for _, rec in ipairs(r.hangar) do table.insert(hangar, saveShip(rec)) end
		local market = r.market and { hold = Hold.serialize(r.market.hold), next = r.market.next }
		stations[key] = { storage = Hold.serialize(r.storage), hangar = hangar, market = market }
	end
	local u = self.universe
	-- saved mid-transit: you'll be at the far end's driver when you load
	local field = self.flight and self.flight.to or self.trip and self.trip.to or self.fieldId
	local state = { field = field, kills = self.kills, home = u.home, stations = stations,
		credits = u.credits, clock = u.clock, areas = Persistence.copy(u.areas), nextObjectId = u.nextObjectId,
		npcs = Persistence.copy(u.npcs), npcAreas = Persistence.copy(u.npcAreas), nextNpcId = u.nextNpcId }
	local p = self.player
	if p and not p.dead then
		local where
		if p.dockState and p.dockState.station then
			where = { station = p.dockState.station.key, bay = p.bay }
		else
			local x, y = p.body:getPosition()
			local vx, vy = p.body:getLinearVelocity()
			where = { x = x, y = y, angle = p.body:getAngle(), vx = vx, vy = vy }
			if self.trip then where = { driver = self.trip.from, exit = self:laneExit() } end
			if self.flight or p.catching then where = { catch = true } end
		end
		state.player = { ship = saveShip(Ship.record(p)), at = where }
	end
	return state
end

function Game:loadState(state)
	self:newUniverse()
	self.universe.areas = Persistence.copy(state.areas or {})
	self.universe.nextObjectId = state.nextObjectId or 0
	self.universe.npcs = Persistence.copy(state.npcs or {})
	self.universe.npcAreas = Persistence.copy(state.npcAreas or {})
	self.universe.nextNpcId = state.nextNpcId or 0
	for key, r in pairs(state.stations or {}) do
		local hangar = {}
		for _, t in ipairs(r.hangar or {}) do table.insert(hangar, loadShip(t)) end
		self.universe.stations[key] = {
			storage = r.storage and Hold.deserialize(r.storage, known)
				or Hold.new({ { key = "storage", name = "Station storage", w = T.storageW, h = T.storageH } }),
			hangar = hangar,
			market = r.market and { hold = Hold.deserialize(r.market.hold, known), next = r.market.next or {} },
		}
	end
	self.universe.home = state.home
	self.universe.credits = state.credits or T.startCredits
	self.universe.clock = state.clock or 0
	self.kills = state.kills or 0
	local field = Fields[state.field] and state.field or Fields.start
	local pl = state.player
	self:loadField(field, { player = pl and loadShip(pl.ship), at = pl and pl.at, skipCapture = true })
	local p = self.player
	local st = p and p.dockState and p.dockState.station
	if st and pl.at.bay and self:hangarFree(st, p, p.hull.id, pl.at.bay) then p.bay = pl.at.bay end
	if not pl then self.state = "dead" end
end

function Game:saveTo(slot)
	local ok, err = Save.write(slot, self:saveState())
	if ok then self:toast(slot == "auto" and "AUTOSAVED" or "GAME SAVED", 1.2, "pickup")
	else self:toast("SAVE FAILED: " .. tostring(err), 2) end
	return ok
end

-- slot nil: whichever save is newest (F5's or the autosave).
function Game:loadFrom(slot)
	slot = slot or Save.newest()
	if not slot then self:toast("NO SAVE YET", 1.4) return false end
	local state, err = Save.read(slot)
	if not state then self:toast(("CAN'T LOAD: %s"):format(tostring(err):upper()), 2) return false end
	self:loadState(state)
	self:toast("GAME LOADED", 1.2, "pickup")
	return true
end

-- Start over: no saves, an empty universe, the first level.
function Game:newGame()
	Save.delete("quick")
	Save.delete("auto")
	self:newUniverse()
	self.kills = 0
	self:loadField(Fields.start, { skipCapture = true })
end

function Game:autosave()
	if self.autosaveOff then return end
	self:saveTo("auto")
end

end
