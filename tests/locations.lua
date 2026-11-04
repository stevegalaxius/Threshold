-- Stable authored IDs and shared live/offline motion: love . --locationtest
return function(game)
	local L = require("src.locations")
	local Fields = require("src.fields")
	local Hold = require("src.inventory.hold")
	local Save = require("src.save")
	local checks = 0
	local function check(ok, message) assert(ok, message); checks = checks + 1 end
	local function near(a, b) return math.abs(a - b) < 0.03 end
	game.autosaveOff = true
	local ids = {}
	for _, area in ipairs(Fields.list) do
		for _, place in ipairs(L.list(area)) do
			check(not ids[place.id] and place.area == area, "duplicate or misplaced location")
			ids[place.id] = true
			local x, y = L.position(place.id, 500)
			check(x == x and y == y, "non-finite location position")
		end
	end
	-- All authored stations are bound, including fixed hubs and cloud cities;
	-- querying a remote position never needs to instantiate its region.
	for _, area in ipairs(Fields.list) do
		game.universe.clock = 500
		game:loadField(area)
		for _, e in ipairs(game.entities) do
			if e.kind == "station" or e.kind == "driver" or e.kind == "buoy" then
				check(e.locationId ~= nil, area .. ": unbound authored object")
				local x, y = L.position(e.locationId, game.universe.clock)
				local bx, by = e.body:getPosition()
				check(near(x, bx) and near(y, by), "loaded object differs from catalogue")
				if e.kind == "station" then
     check(e.key == L.canonical(e.locationId), "station save key is not stable: "..e.locationId)
     check(e.def==L.stationDefinition(e.locationId),'live/offline station layouts disagree: '..e.locationId)
     for _,service in ipairs(game.SERVICES) do
      check(game.stationServices(e)[service]==L.stationServices(e.locationId)[service],'live/offline service mismatch: '..e.locationId..' / '..service)
     end
    end
			end
		end
  if area=='pluto' then
   local base=game:locationEntity(L.station(nil,'pirateBase'))
   check(base and base.name=='Milliways Freeport','pirate base rename not reflected in live station')
   check(base.def.id=='jovian_kink','pirate base did not use the Jovian Kink layout')
   check(game.marketDefinition(base).station=='Milliways Freeport','pirate base market lost its identity')
  end
		for _ = 1, 3 do game:step(1 / 120) end
		for _, e in ipairs(game.entities) do
			if e.locationId then
				local x, y = L.position(e.locationId, game.universe.clock)
				local bx, by = e.body:getPosition()
				check(near(x, bx) and near(y, by), "live motion differs from offline position")
			end
		end
		for _, gate in ipairs(game.moonGates or {}) do
			local x, y = L.position(gate.locationId, game.universe.clock)
			check(near(x, gate.x) and near(y, gate.y), "moon gate differs from catalogue")
		end
	end
	game:loadField("earth")
	local st = game:locationEntity("station:007")
	local key = st.key
	Hold.add(game:stationRecord(st).storage, "scrap", 2)
	game:dockInstantly(game.player, st)
 local Homes=require('src.npc_home');local resident
 for _,r in pairs(game.universe.npcs) do if r.role=='patrol' and r.home=='earth' then resident=r;break end end
 assert(resident);Homes.assign(resident,'station:008');local residentId=resident.id
	local saved = assert(Save.decode(Save.encode(game:saveState())))
	check(saved.player.at.station == key and saved.stations[key] ~= nil, "save does not use location IDs")
 check(saved.npcs[residentId].homeStation=='station:008','game snapshot lost NPC home')
 Homes.assign(resident,'station:007')
	-- Rename it and insert an unrelated station ahead of normal construction.
	local place = L.get(key)
	local oldName = place.name
	place.name = "Renamed Orbital One"
	local original = game.spawnWheelStation
	local inserted = false
	game.spawnWheelStation = function(self, ...)
		if not inserted then inserted = true; original(self, 1000, 20000, 300, 60, 0) end
		return original(self, ...)
	end
	game:loadState(saved)
	game.spawnWheelStation = nil
 check(Homes.get(game.universe.npcs[residentId])=='station:008','loading did not restore assigned NPC home')
	st = game:locationEntity(key)
	check(st.name == place.name and st.key == key, "rename or spawn order changed identity")
	check(game.player.dockState.station == st, "saved station reference broke after reordering")
	check(Hold.totals(game:stationRecord(st).storage).scrap == 2, "station inventory followed spawn order")
	check(game.marketDefinition(st) ~= nil, "display rename lost market definition")
	place.name = oldName
	-- Rebuilding at the same clock is reproducible; advancing it changes pose.
	local clock = game.universe.clock
	local x, y = L.position(key, clock)
	game:loadField("mars")
	game:loadField("earth")
	st = game:locationEntity(key)
	check(near(st.body:getX(), x) and near(st.body:getY(), y), "reload restarted station orbit")
	game.universe.clock = clock + 100
	game:loadField("earth")
	st = game:locationEntity(key)
	local nx, ny = L.position(key, game.universe.clock)
	check(near(st.body:getX(), nx) and near(st.body:getY(), ny) and not near(nx, x), "advanced clock did not move station")
	-- Retained highway scenes use the same rules as remote lookups.
	game:launchTrip("luna", { bearing = 0, length = Fields.moons.luna.gap })
	game.universe.clock = game.universe.clock + 100
	game:arrive(true)
	st = game:locationEntity(key)
	nx, ny = L.position(key, game.universe.clock)
	check(near(st.body:getX(), nx) and near(st.body:getY(), ny), "turnaround restored stale station position")
	print(("stable locations: %d checks passed"):format(checks))
end
