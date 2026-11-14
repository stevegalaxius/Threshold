-- Dark grids: unlisted places reached like moons. Each loads with its
-- stations, NPCs can route to it, and the player's way out to it from the
-- parent planet's map only opens once it's charted.
return function(game)
 local Fields,Dark,L,G=require('src.fields'),require('src.dark'),require('src.locations'),require('src.travelgraph')
 local checks=0
 local function check(ok,msg)assert(ok,msg);checks=checks+1 end
 local u=game.universe
 local grids={milliways={'pluto',1},shoals={'belt',3},cordelia={'uranus',1}}
 local saved=Dark.DEBUG_CHARTED;Dark.DEBUG_CHARTED={}
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
  local p=L.get(id);check((p.spin or 0)~=0,id..' does not turn')
  local x,y=L.position(id,u.clock);spots[#spots+1]={x,y,id}
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
