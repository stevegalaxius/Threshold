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
local Paint = require("src.paint")
local Fields = require("src.fields")
local Locations=require("src.locations")
local Hold = require("src.inventory.hold")
local Save = require("src.save")
local Grid = require("src.inventory.grid")
local Persistence = require("src.persistence")
local events = require("src.events")

local sqrt, cos, sin, pi, max = math.sqrt, math.cos, math.sin, math.pi, math.max

return function(Game)

function Game:editWorldLayout(edit) return require("src.world_authoring").apply(self,edit) end

function Game:newUniverse()
	if self.universe then require("src.mining").unload(self) end
	self.miningNext = nil
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

-- access: which access point of a station that has several (the
-- Heaven-Ladder's anchors); left out, the first found.
function Game:findStation(key, access)
	local first
	for _, e in ipairs(self.entities) do
		if e.kind == "station" and e.key == key then
			if not access or e.accessIndex == access then return e end
			first = first or e
		end
	end
	return first
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

-- Restore a completed dock, including its exterior berth when supplied.
function Game:dockInstantly(e, st, placement)
	placement = placement or {}
	local d = placement.dock or (st.docks or {})[placement.dockIndex] or st.dock
	local side = placement.side or 1
 local parking=placement.parking
 if not parking and placement.bay then parking={bay=placement.bay} end
 if not parking and placement.parkingMooring then parking={mooring=placement.parkingMooring} end
 local wantsBerth=parking and parking.mooring or placement.berth or placement.mooring
 if not wantsBerth then
  local fit=self:hangarFit(st,e.hull.id,e)
  if fit then
   local preferred=parking and parking.bay
   parking={bay=preferred and self:hangarFree(st,e,e.hull.id,preferred) and preferred or fit}
  else parking=nil;wantsBerth=true end
 end
 local berth
 local previous=st.def.berths and st.def.berths[placement.berth]
 if parking and parking.mooring then
  local slot=self:stationMoorings(st)[parking.mooring]
  if slot then previous=st.def.berths[slot.berth] end
 end
 if previous then e.body:setPosition(st.body:getWorldPoint(previous.x,previous.y)) end
 if wantsBerth then
  berth=self:freeBerth(st,e)
  if not berth then
   -- Old overflow assignments are not valid parking. Leave the ship at
   -- the station entrance, under player control, rather than restoring them.
   local x,y=self.dockWorld(st,side,d.x2+e.halfLength+60,0,d)
   e.body:setPosition(x,y);e.body:setActive(true)
   e.body:setLinearVelocity(st.body:getLinearVelocityFromWorldPoint(x,y))
   e.dockState=nil;e.bay,e.mooring,e.parkingMooring,e.bayStation=nil,nil,nil,nil
   if e==self.player then
    self:applyParking(e,nil);self.state='playing'
    self.camera.x,self.camera.y=x,y
    self:toast('NO SUITABLE FREE BERTH',2)
   end
   return false
  end
  parking={mooring=berth}
 end
 if parking and parking.bay and not self:fitsDock(e,d) then
  for _,candidate in ipairs(st.docks or {st.dock}) do if self:fitsDock(e,candidate) then d=candidate;break end end
 end
 self:applyParking(e,parking);e.bayStation=st.key
	e.dockState = { station = st, phase = "done", done = true, t = 0, dock = d, side = side, berth = berth }
 for i,candidate in ipairs(st.docks or {st.dock}) do if candidate==d then e.dockState.dockIndex=i end end
	e.body:setActive(false)
	if berth then
		local b = st.def.berths[berth]
		e.body:setPosition(st.body:getWorldPoint(b.x, b.y))
		e.body:setAngle(st.body:getAngle() + math.rad(b.heading))
	else
		e.body:setPosition(self.dockWorld(st, side, (d.x1 + d.x2) / 2, 0, d))
		e.body:setAngle(self.dockAngle(st, side, d) + pi)
	end
	e.body:setLinearVelocity(0, 0)
	e.body:setAngularVelocity(0)
	if e == self.player then
		self.state = "docked"
		self.camera.x, self.camera.y = e.body:getPosition()
		if parking then self:applyParking(e,parking);e.bayStation=st.key else self:givePlayerBay(st) end
	end
 return true
end

-- Spawn the player in a level that's already built (see Game:loadField
-- for rec and at).
function Game:placePlayer(rec, at)
	local p = self:spawnPlayer(rec)
	at = at or {}
	if at.station then
		local st = self:findStation(at.station, at.access)
		if st and st.dock then self:dockInstantly(p, st, at) return p end
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
	if not self.field.instance then return end
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
 local list=self:stationRecord(st).hangar
 for _,rec in ipairs(list) do
  if rec.bay and not self:hangarFree(st,rec,rec.hull,rec.bay) then rec.bay=nil end
  if rec.mooring and not self:mooringFits(st,rec.mooring,rec.hull,rec) then rec.mooring=nil end
  if not rec.bay and not rec.mooring then self:applyParking(rec,self:shipParkingFit(st,rec.hull,rec)) end
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

-- One occupied grid for stored ships and docked player/NPC ships, including
-- ships currently being pulled inside. Leave out `ignore` when checking itself.
function Game:hangarGrid(st, ignore)
	local w,h=Game.hangarSize(st)
	local g = Grid.new(w,h,"Interior hangar")
	local function put(owner, hullId, bay)
		if owner == ignore or not bay then return end
		-- A ship on an exterior berth takes no interior cells, even if an
		-- old bay assignment is still attached to it.
		if owner.mooring or owner.parkingMooring or owner.dockState and owner.dockState.berth then return end
		local w, h = Game.hangarFootprint(hullId, bay.rot)
		if Grid.isFree(g, bay.x, bay.y, w, h) then Grid.place(g, { x = bay.x, y = bay.y, w = w, h = h, owner = owner }) end
	end
	for _, rec in ipairs(self:stationRecord(st).hangar) do put(rec, rec.hull, rec.bay) end
	for _,e in ipairs(self.entities) do
		if e.kind=='ship' and not e.dead and not e.removed and e.dockState and e.dockState.station.key==st.key then
			put(e,e.hull.id,e.bay)
		end
	end
	return g
end

-- The first free spot for a hull (unrotated first), or nil if it's full.
function Game:hangarFit(st, hullId, ignore)
 local hull=data.hulls[hullId];local width=0
 for i=2,#hull.shape,2 do width=max(width,math.abs(hull.shape[i])) end
 local access=false
 for _,dock in ipairs(st.docks or {st.dock}) do if width+10<=dock.hw then access=true;break end end
 if not access then return nil end
	local g = self:hangarGrid(st, ignore)
	for _, rot in ipairs({ false, true }) do
		local w, h = Game.hangarFootprint(hullId, rot)
		local x, y = Grid.firstFit(g, w, h)
		if x then return { x = x, y = y, rot = rot } end
	end
end

-- Can this ship (a record, the player, or an NPC) sit at bay?
function Game:hangarFree(st, owner, hullId, bay)
	local w, h = Game.hangarFootprint(hullId, bay.rot)
	return Grid.isFree(self:hangarGrid(st, owner), bay.x, bay.y, w, h)
end

-- The ship you're docked in takes a spot in the bay (if it hasn't one
-- here already). A full bay leaves it on the landing pad: docked, but
-- not on the grid.
function Game:givePlayerBay(st)
 local p=self.player
 if p.bayStation==st.key and self:shipParkingValid(st,p,p.hull.id) then return end
 p.bayStation=st.key
 local ds=p.dockState
 local selected
 if ds and ds.berth then
  for i,slot in ipairs(self:stationMoorings(st)) do
   if slot.berth==ds.berth and self:mooringFits(st,i,p.hull.id,p) then selected={mooring=i};break end
  end
 elseif ds and ds.mooring and ds.mooring.slot then selected={mooring=ds.mooring.slot} end
 self:applyParking(p,selected or self:shipParkingFit(st,p.hull.id,p))
end

-- A brand-new ship of a hull, parked in this station's hangar (the debug
-- panel's way of getting ships until there's a market). nil if the bay
-- has no room for it.
function Game:addToHangar(st, hullId, paintName)
	local parking=self:shipParkingFit(st,hullId)
	if not parking then self:toast("NO SUITABLE FREE PARKING",1.4) return nil end
	local e = Ship.new(self, { hull = hullId, team = 1, grid = true, color = paintName and Paint.preset(paintName) or nil })
	local rec = Ship.record(e)
	e.body:destroy()
	self:applyParking(rec,parking)
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
 local old=Ship.record(p)
 local oldParking={bay=p.bay,mooring=p.parkingMooring}
 if not oldParking.bay and not oldParking.mooring then
  oldParking=self:shipParkingFit(st,p.hull.id,p)
  if not oldParking then self:toast('NO ROOM TO PARK YOUR SHIP',1.4);return false end
 end
 local newParking={bay=rec.bay,mooring=rec.mooring}
 if not newParking.bay and not newParking.mooring then
  newParking=self:shipParkingFit(st,rec.hull,rec)
  if not newParking then self:toast('NO SUITABLE FREE PARKING',1.4);return false end
 end
 self:applyParking(old,oldParking)
 list[i]=old
 local ship=self:spawnPlayer(rec)
 self:applyParking(ship,newParking);ship.bayStation=st.key
 self:dockInstantly(ship,st,self:parkingPlacement(st,newParking))
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
		hull = rec.hull, loadout = rec.loadout, triggers = rec.triggers, loads = rec.loads, armor = rec.armor, color = rec.color, bay = rec.bay, mooring=rec.mooring,
		fuelCharge=rec.fuelCharge, fuelInitialized=rec.fuelInitialized, power=rec.power,
		hold = rec.hold and Hold.serialize(rec.hold) or nil, cargo = rec.cargo,
	}
end

local function known(id) return data.items[id] ~= nil end

-- NPC records keep their ship as plain ids. Renamed hulls and modules take
-- their new ids, modules follow a hull whose slots moved, and an engine or
-- reactor slot an older build emptied takes the archetype's part again, so
-- the ship isn't left drifting with fuel it can't burn.
local function repairNpcShip(r)
	local s = r and r.ship
	if not s then return end
	if data.renamedHulls[s.hull] then s.hull = data.renamedHulls[s.hull] end
	local hull = data.hulls[s.hull]
	if not hull then return end
	for i, id in pairs(s.loadout or {}) do
		if data.renamedModules[id] then s.loadout[i] = data.renamedModules[id] end
	end
	s.loadout = data.fitLoadout(hull, s.loadout)
	local preset = data.enemies[r.archetype]
	local want = preset and data.fitLoadout(hull, preset.loadout or hull.loadout) or {}
	for i, slot in ipairs(hull.slots) do
		if not s.loadout[i] and (slot.family == "engine" or slot.family == "reactor") and want[i] then
			s.loadout[i] = want[i]
		end
	end
end

local function loadShip(t)
	if t and data.renamedHulls[t.hull] then t.hull = data.renamedHulls[t.hull] end
	if not t or not data.hulls[t.hull] then return { hull = T.starterHull } end
	-- the Cargo Pod XL is gone: a save that fitted one gets a Cargo Pod
	for i, id in pairs(t.loadout or {}) do if id == "hold_pod_m" then t.loadout[i] = "hold_pod_s" end end
	-- renamed weapons (and torpedo tubes, now missile racks) take their new ids
	for i, id in pairs(t.loadout or {}) do
		if data.renamedModules[id] then t.loadout[i] = data.renamedModules[id] end
	end
	return {
		hull = t.hull, loadout = t.loadout, triggers = t.triggers, loads = t.loads, armor = t.armor, color = t.color, bay = t.bay, mooring=t.mooring,
		fuelCharge=t.fuelCharge, fuelInitialized=t.fuelInitialized, power=t.power,
		hold = t.hold and Hold.deserialize(t.hold, known) or nil, cargo = t.cargo,
	}
end

-- The whole game as one plain table (see src/save.lua).
function Game:saveState()
	require("src.mining").captureResources(self)
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
		local shops = {}
		for i, m in pairs(r.shops or {}) do shops[i] = { hold = m.hold and Hold.serialize(m.hold), next = m.next, stock = Persistence.copy(m.stock) } end
		stations[key] = { storage = Hold.serialize(r.storage), hangar = hangar, shops = shops, shop = r.shop, moorings=Persistence.copy(r.moorings) }
	end
	local u = self.universe
	-- saved mid-transit: you'll be at the far end's driver when you load
	local field = self.flight and self.flight.to or self.trip and self.trip.to or self.fieldId
	local state = { field = field, kills = self.kills, home = u.home, stations = stations,
		credits = u.credits, clock = u.clock, areas = Persistence.copy(u.areas), nextObjectId = u.nextObjectId,
		simulationHistory = Persistence.copy(u.simulationHistory), salvage=Persistence.copy(u.salvage),
		piracy = Persistence.copy(u.piracy), reputation = (require('src.reputation').prune(u) or Persistence.copy(u.reputation)), alifeWrecks = Persistence.copy(u.alifeWrecks), encounterNext = u.encounterNext,
		worldLayoutSignature=u.worldLayoutSignature,worldLocations=Persistence.copy(u.worldLocations),
        populationSpawns = Persistence.copy(u.populationSpawns), mining = Persistence.copy(u.mining),
		tasks = Persistence.copy(u.tasks), jobs = Persistence.copy(u.jobs), npcs = Persistence.copy(u.npcs), npcAreas = Persistence.copy(u.npcAreas), nextNpcId = u.nextNpcId }
	local p = self.player
	if p and not p.dead then
		local where
		if p.dockState and p.dockState.station then
			local ds = p.dockState
			local dockIndex
			for i, d in ipairs(ds.station.docks or {}) do if d == ds.dock then dockIndex = i; break end end
			where = { station = ds.station.key, access = ds.station.accessIndex, bay = p.bay, parkingMooring=p.parkingMooring, berth = ds.berth, mooring = Persistence.copy(ds.mooring), side = ds.side, dockIndex = dockIndex }
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
 state=require("src.world_migration").ids(state)
 -- Detach the outgoing scene while it still owns its universe. Capturing old
 -- bodies after installing the snapshot can overwrite incoming NPC/resource data.
 require('src.mining').unload(self)
 self:captureALife(true)
	self:newUniverse()
	self.universe.areas = Persistence.copy(state.areas or {})
	self.universe.nextObjectId = state.nextObjectId or 0
	self.universe.piracy = Persistence.copy(state.piracy)
	self.universe.reputation = Persistence.copy(state.reputation)
	self.universe.alifeWrecks = Persistence.copy(state.alifeWrecks)
	self.universe.encounterNext = state.encounterNext
	self.universe.simulationHistory = Persistence.copy(state.simulationHistory)
 self.universe.salvage=Persistence.copy(state.salvage)
	self.universe.pirateSpawns = Persistence.copy(state.pirateSpawns)
	self.universe.populationSpawns = Persistence.copy(state.populationSpawns)
	self.universe.worldLayoutSignature=state.worldLayoutSignature
 self.universe.worldLocations=Persistence.copy(state.worldLocations or state.worldStations)
	self.universe.mining = Persistence.copy(state.mining)
	self.universe.jobs = Persistence.copy(state.jobs)
	self.universe.tasks = Persistence.copy(state.tasks)
	self.universe.npcs = Persistence.copy(state.npcs or {})
	self.universe.npcAreas = Persistence.copy(state.npcAreas or {})
	for _, r in pairs(self.universe.npcs) do repairNpcShip(r) end
	self.universe.nextNpcId = state.nextNpcId or 0
	for key, r in pairs(state.stations or {}) do
		local hangar = {}
		for _, t in ipairs(r.hangar or {}) do table.insert(hangar, loadShip(t)) end
		self.universe.stations[key] = {
			storage = r.storage and Hold.deserialize(r.storage, known)
				or Hold.new({ { key = "storage", name = "Station storage", w = T.storageW, h = T.storageH } }),
			hangar = hangar, moorings=Persistence.copy(r.moorings),
			shop = r.shop,
		}
		-- shops; a save from before shops had one market, which is shop 1
		local shops = {}
		for i, m in pairs(r.shops or (r.market and { r.market }) or {}) do
			shops[tonumber(i)] = { hold = m.hold and Hold.deserialize(m.hold, known), next = m.next or {}, stock = Persistence.copy(m.stock) }
		end
		self.universe.stations[key].shops = shops
	end
	self.universe.home = state.home
	self.universe.credits = state.credits or T.startCredits
	self.universe.clock = state.clock or 0
	self.kills = state.kills or 0
	local field = Fields[state.field] and state.field or Fields.start
	local pl = state.player
 if pl and pl.at and pl.at.station then
  local place=Locations.byId[pl.at.station]
  if place then field=place.area
  else
   local replacement=Locations.station(field,'trade')
   pl.at=replacement and {station=replacement} or {x=Fields[field].spawn[1],y=Fields[field].spawn[2]}
  end
 end
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
