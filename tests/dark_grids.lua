-- Dark grids: unlisted places reached like moons. Each loads with its
-- stations, NPCs can route to it, and the player's way out to it from the
-- parent planet's map only opens once it's charted.
return function(game)
 local Fields,Dark,L,G=require('src.fields'),require('src.dark'),require('src.locations'),require('src.travelgraph')
 local checks=0
 local function check(ok,msg)assert(ok,msg);checks=checks+1 end
 local u=game.universe
 local grids={milliways={'pluto',1},cordelia={'uranus',1}}
 local saved=Dark.DEBUG_CHARTED;Dark.DEBUG_CHARTED={}
 -- the Shoals: its own place on the belt's orbit, between Ceres and Ring
 -- Station, reached by mass driver once found
 do
  local o,b,ring=Fields.orbits.shoals,Fields.orbits.belt,Fields.orbits.ring
  check(o and o.dark and not Fields.moons.shoals and o.au==b.au,'the Shoals are not on the belt orbit')
  local function gap(a,c) return math.abs((a-c+math.pi)%(2*math.pi)-math.pi) end
  check(math.abs(gap(o.phase,b.phase)-gap(o.phase,ring.phase))<1e-6,'the Shoals are not halfway between Ceres and Ring Station')
  check(#Fields.shoals.stationIds==3 and Fields.shoals.driverId,'the Shoals lack stations or a mass driver')
  u.discovered={}
  check(not Dark.charted(u,'shoals'),'the Shoals start charted')
  game:loadField('belt')
  game.driverMenu={driver={}}
  check(not game:fireDriver('shoals'),'the driver fired at uncharted Shoals')
  game.driverMenu=nil
  check(G.itinerary(Fields.belt.driverId,Fields.shoals.stationIds[1],u.clock),'no NPC route from Ceres to the Shoals')
  Dark.discover(u,'shoals')
  check(Dark.charted(u,'shoals'),'the Shoals did not chart once found')
 end
 -- Antichthon: Earth's orbit opposite Earth, a driver stop with a farm
 do
  local o,e=Fields.orbits.antichthon,Fields.orbits.earth
  check(o and o.dark and o.au==e.au and math.abs((o.phase-e.phase)%(2*math.pi)-math.pi)<1e-6,'Antichthon is not opposite Earth')
  check(Fields.antichthon.driverId and #Fields.antichthon.stationIds==1,'Antichthon lacks its driver or farm')
  check(L.get(Fields.antichthon.stationIds[1]).facilities.farm,'Antichthon Gardens grows nothing')
  check(require('src.reputation').AREAS.antichthon=='milliways','Antichthon is not pirate-held')
 end
 -- the dark chain's factories
 local function has(id,f) return (L.get(id).facilities or {})[f]~=nil end
 check(has('station:shoals_1','roll_steel') and has('station:shoals_1','press_canisters') and has('station:shoals_1','water_melter'),'Slag Harbor is missing steel, canisters or water')
 check(has('station:shoals_2','ammunition') and has('station:shoals_2','chemicals') and has('station:shoals_2','process_nitrates'),'Cinder Works cannot make its own explosives')
 check(has('station:cordelia_1','crack_ice') and has('station:cordelia_1','ice_wells'),'Cordelia makes no deuterium')
 for area,spec in pairs(grids) do
  local parent,n=spec[1],spec[2]
  check(Dark.isDarkArea(area) and Fields.moons[area] and Fields.moons[area].parent==parent,area..' is not a dark moon of '..parent)
  check(not Fields.orbits[area],area..' still has its own orbit')
  check(#Fields[area].stationIds==n,area..' has '..#Fields[area].stationIds..' stations')
  -- hidden: no way out from the parent
  u.discovered={}
  game:loadField(parent)
  local open=false
  for _,g in ipairs(game.moonGates or {}) do if g.to==area then open=true end end
  check(not open,area..' transit showed before it was found')
  -- NPCs still know the way
  local from=L.station(parent,'trade') or Fields[parent].stationIds[1] or Fields[parent].buoyIds[1]
  check(G.itinerary(from,Fields[area].stationIds[1],u.clock),'no NPC route from '..parent..' to '..area)
  -- found: the transit opens
  Dark.discover(u,area);game:loadField(parent)
  open=false
  for _,g in ipairs(game.moonGates or {}) do if g.to==area then open=true end end
  check(open,area..' transit did not open once found')
  game:loadField(area)
  local back=false
  for _,g in ipairs(game.moonGates or {}) do if g.to==parent then back=true end end
  check(back,area..' has no way back to '..parent)
  check(require('src.reputation').AREAS[area]=='milliways',area..' is not pirate-held')
 end
 Dark.DEBUG_CHARTED=saved
 -- the Shoals' stations stand apart and slowly turn (no planet to hold them)
 local spots={}
 for _,id in ipairs(Fields.shoals.stationIds) do
  local p=L.get(id);check((p.drift or 0)~=0 and L.coreHeading({rotors={}},id,100)~=L.coreHeading({rotors={}},id,0),id..' does not turn')
  local x,y=L.position(id,u.clock);spots[#spots+1]={x,y,id}
  local x2,y2=L.position(id,u.clock+600);check(math.abs(x2-x)+math.abs(y2-y)>500,id..' does not circle the centre')
 end
 for i=1,#spots do for j=i+1,#spots do
  local d=math.sqrt((spots[i][1]-spots[j][1])^2+(spots[i][2]-spots[j][2])^2)
  check(d>4500,spots[i][3]..' and '..spots[j][3]..' overlap ('..math.floor(d)..' px)')
 end end
 -- station drones are never a station's targets, even after a stray hit
 game:loadField('milliways')
 local st;for _,e in ipairs(game.entities) do if e.kind=='station' then st=e end end
 local drone={kind='ship',team=0,drone=true,owner=st,body=st.body}
 game:damage(st,5,drone,'shot')
 check(not (st.grudge and st.grudge[drone]),'a station holds a grudge against its own drone')
 check(not game:stationHostile(st,drone),'a station targets its own drone')
 print(('DARK GRIDS TEST PASSED (%d checks)'):format(checks))
end
