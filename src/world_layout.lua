-- World authoring: stable station identities and navigation topology.
-- Station designs/services live in data/station_*.lua. Special construction stays
-- in its existing adapter; ordinary layout changes belong here.
local W={}
W.stations = {
	phobos = {
		{ id = "station:phobos_1", primary = true, name = "Phobos Strip Mine", adapter = "surface_mine", layout = "zhuhai_strip_mine" },
	},
	deimos = {
		{ id = "station:deimos_1", primary = true, name = "Deimos Strip Mine", adapter = "surface_mine", layout = "zhuhai_strip_mine" },
	},
	mercury = {
		{ id = "station:mercury_1", spin = 0.05, phase = -0.8, primary = true, name = "Terminator Station" },
		{ id = "station:mercury_2", spin = -0.05, phase = 2.3415926535897933, name = "Dawnline Station" },
	},
	venus = {
		{ id = "station:venus_1", spin = 0.05, phase = -0.8, primary = true, marketId = "market:venus_1", name = "Hub Station" },
		{ id = "station:venus_2", spin = -0.05, phase = 2.3415926535897933, name = "Cloudline Station" },
	},
	earth = {
		{ id = "station:earth_1", spin = 0.05, phase = -0.8, primary = true, marketId = "market:earth_1", name = "Orbital One" },
		{ id = "station:earth_2", marketId = "market:earth_2", spin = -0.05, phase = 2.3415926535897933, name = "Orbital Two" },
	},
	mars = {
		{ id = "station:mars_1", spin = 0.05, phase = -0.8, primary = true, layout = "shipyard_1", marketId = "market:mars_1", name = "Station Alpha" },
		{ id = "station:mars_2", marketId = "market:mars_2", spin = -0.05, phase = 2.3415926535897933, name = "Station Beta" },
	},
	belt = {
		{ id = "station:belt_1", spin = 0.05, phase = -0.8, primary = true, name = "Ceres Dock" },
		{ id = "station:belt_2", spin = -0.05, phase = 2.3415926535897933, name = "Piazzi Station" },
	},
	jupiter = {
		{ id = "station:jupiter_1", primary = true, name = "Olympus", adapter = "cloud" },
	},
	saturn = {
		{ id = "station:saturn_1", spin = 0.05, phase = -0.8, primary = true, name = "Cassini Gate" },
		{ id = "station:saturn_2", spin = -0.05, phase = 2.3415926535897933, name = "Enceladus Station" },
	},
	uranus = {
		{ id = "station:uranus_1", primary = true, name = "Herschel", adapter = "cloud" },
	},
	luna = {
		{ id = "station:luna_1", spin = 0.05, phase = -0.8, primary = true, marketId = "market:luna_1", name = "Tranquility Dock" },
		{ id = "station:luna_2", marketId = "market:luna_2", spin = -0.05, phase = 2.3415926535897933, name = "Shackleton Station" },
	},
	io = {
		{ id = "station:io_1", spin = 0.05, phase = -0.8, primary = true, marketId = "market:io_1", name = "Pele Works" },
		{ id = "station:io_2", marketId = "market:io_2", spin = -0.05, phase = 2.3415926535897933, name = "Loki Laboratory" },
	},
	europa = {
		{ id = "station:europa_1", spin = 0.05, phase = -0.8, primary = true, marketId = "market:europa_1", name = "Conamara Station" },
		{ id = "station:europa_2", marketId = "market:europa_2", spin = -0.05, phase = 2.3415926535897933, name = "Pwyll Station" },
	},
	ganymede = {
		{ id = "station:ganymede_1", spin = 0.05, phase = -0.8, primary = true, marketId = "market:ganymede_1", name = "Galileo Regio" },
		{ id = "station:ganymede_2", marketId = "market:ganymede_2", spin = -0.05, phase = 2.3415926535897933, name = "Uruk Station" },
	},
	callisto = {
		{ id = "station:callisto_1", spin = 0.05, phase = -0.8, primary = true, marketId = "market:callisto_1", name = "Valhalla Port" },
		{ id = "station:callisto_2", marketId = "market:callisto_2", spin = -0.05, phase = 2.3415926535897933, name = "Asgard Station" },
	},
	enceladus = {
		{ id = "station:enceladus_1", spin = 0.05, phase = -0.8, primary = true, marketId = "market:enceladus_1", name = "Tiger Stripe Laboratory" },
		{ id = "station:enceladus_2", marketId = "market:enceladus_2", spin = -0.05, phase = 2.3415926535897933, name = "South Pole Port" },
	},
	titan = {
		{ id = "station:titan_1", spin = 0.05, phase = -0.8, primary = true, marketId = "market:titan_1", name = "Kraken Station" },
		{ id = "station:titan_2", marketId = "market:titan_2", spin = -0.05, phase = 2.3415926535897933, name = "Huygens Station" },
	},
	titania = {
		{ id = "station:titania_1", spin = 0.05, phase = -0.8, primary = true, marketId = "market:titania_1", name = "Gertrude Port" },
		{ id = "station:titania_2", marketId = "market:titania_2", spin = -0.05, phase = 2.3415926535897933, name = "Messina Research Station" },
	},
	triton = {
		{ id = "station:triton_1", spin = 0.05, phase = -0.8, primary = true, marketId = "market:triton_1", name = "Cipango Station" },
		{ id = "station:triton_2", marketId = "market:triton_2", spin = -0.05, phase = 2.3415926535897933, name = "Voyager Station" },
	},
	pluto = {
		{ id = "station:pluto_1", spin = 0.05, phase = -0.8, primary = true, uses = { pirateBase = true }, layout = "jovian_kink", marketId = "market:pluto_1", name = "Milliways Freeport" },
		{ id = "station:pluto_2", marketId = "market:pluto_2", spin = -0.05, phase = 2.3415926535897933, name = "Sputnik Port" },
	},
	ring = {
		{ id = "station:ring_1", spin = 0.02, phase = -0.8, primary = true, name = "Ring Station", wheel = { 3000, 300 } },
	},
	station = {
		{ id = "station:station_1", spin = 0.04, phase = -0.8, primary = true, name = "Hub Station", marketId = "market:venus_1", wheel = { 1400, 160 } },
	},
}
-- IDs are "<home area>_<n>" slugs, assigned once. They never change when a
-- station is renamed, retuned or moved; markets reuse their station's slug.
W.defaults={marketId='market:venus_1'}
W.specials={heavenLadder={area='mars',id='station:mars_3',name='Heaven-Ladder',marketId='market:mars_3',
 access={'station:mars_3','access:mars_3_2','access:mars_3_3','access:mars_3_4'}}}
-- Read-only compatibility aliases for saves from before independent station IDs.
W.aliases={
 ["phobos/strip_mine"]="station:phobos_1",
 ["deimos/strip_mine"]="station:deimos_1",
 ["mercury/terminator_station"]="station:mercury_1",
 ["mercury/dawnline_station"]="station:mercury_2",
 ["venus/hub_station"]="station:venus_1",
 ["venus/cloudline_station"]="station:venus_2",
 ["earth/orbital_one"]="station:earth_1",
 ["earth/orbital_two"]="station:earth_2",
 ["mars/station_alpha"]="station:mars_1",
 ["mars/station_beta"]="station:mars_2",
 ["belt/ceres_dock"]="station:belt_1",
 ["belt/piazzi_station"]="station:belt_2",
 ["jupiter/olympus"]="station:jupiter_1",
 ["saturn/cassini_gate"]="station:saturn_1",
 ["saturn/enceladus_station"]="station:saturn_2",
 ["uranus/herschel"]="station:uranus_1",
 ["luna/tranquility_dock"]="station:luna_1",
 ["luna/shackleton_station"]="station:luna_2",
 ["io/pele_works"]="station:io_1",
 ["io/loki_laboratory"]="station:io_2",
 ["europa/conamara_station"]="station:europa_1",
 ["europa/pwyll_station"]="station:europa_2",
 ["ganymede/galileo_regio"]="station:ganymede_1",
 ["ganymede/uruk_station"]="station:ganymede_2",
 ["callisto/valhalla_port"]="station:callisto_1",
 ["callisto/asgard_station"]="station:callisto_2",
 ["enceladus/tiger_stripe_laboratory"]="station:enceladus_1",
 ["enceladus/south_pole_port"]="station:enceladus_2",
 ["titan/kraken_station"]="station:titan_1",
 ["titan/huygens_station"]="station:titan_2",
 ["titania/gertrude_port"]="station:titania_1",
 ["titania/messina_research_station"]="station:titania_2",
 ["triton/cipango_station"]="station:triton_1",
 ["triton/voyager_station"]="station:triton_2",
 ["pluto/tombaugh_station"]="station:pluto_1",
 ["pluto/sputnik_port"]="station:pluto_2",
 ["ring/ring_station"]="station:ring_1",
 ["station/hub_station"]="station:station_1",
 ["mars/heaven_ladder"]="station:mars_3",
 ["mars/heaven_ladder_2"]="access:mars_3_2",
 ["mars/heaven_ladder_3"]="access:mars_3_3",
 ["mars/heaven_ladder_4"]="access:mars_3_4",
 -- Numbered ids from before location-based slugs.
 ["access:001"]="access:mars_3_2",
 ["access:002"]="access:mars_3_3",
 ["access:003"]="access:mars_3_4",
 ["market:001"]="market:venus_1",
 ["market:002"]="market:mars_1",
 ["market:003"]="market:mars_3",
 ["market:004"]="market:mars_2",
 ["market:005"]="market:earth_1",
 ["market:006"]="market:earth_2",
 ["market:007"]="market:luna_1",
 ["market:008"]="market:luna_2",
 ["market:009"]="market:europa_1",
 ["market:010"]="market:europa_2",
 ["market:011"]="market:ganymede_1",
 ["market:012"]="market:ganymede_2",
 ["market:013"]="market:titan_1",
 ["market:014"]="market:titan_2",
 ["market:015"]="market:triton_1",
 ["market:016"]="market:triton_2",
 ["market:017"]="market:io_1",
 ["market:018"]="market:io_2",
 ["market:019"]="market:callisto_1",
 ["market:020"]="market:callisto_2",
 ["market:021"]="market:enceladus_1",
 ["market:022"]="market:enceladus_2",
 ["market:023"]="market:pluto_1",
 ["market:024"]="market:pluto_2",
 ["market:025"]="market:titania_1",
 ["market:026"]="market:titania_2",
 ["station:001"]="station:phobos_1",
 ["station:002"]="station:deimos_1",
 ["station:003"]="station:mercury_1",
 ["station:004"]="station:mercury_2",
 ["station:005"]="station:venus_1",
 ["station:006"]="station:venus_2",
 ["station:007"]="station:earth_1",
 ["station:008"]="station:earth_2",
 ["station:009"]="station:mars_1",
 ["station:010"]="station:mars_2",
 ["station:011"]="station:belt_1",
 ["station:012"]="station:belt_2",
 ["station:013"]="station:jupiter_1",
 ["station:014"]="station:saturn_1",
 ["station:015"]="station:saturn_2",
 ["station:016"]="station:uranus_1",
 ["station:017"]="station:luna_1",
 ["station:018"]="station:luna_2",
 ["station:019"]="station:io_1",
 ["station:020"]="station:io_2",
 ["station:021"]="station:europa_1",
 ["station:022"]="station:europa_2",
 ["station:023"]="station:ganymede_1",
 ["station:024"]="station:ganymede_2",
 ["station:025"]="station:callisto_1",
 ["station:026"]="station:callisto_2",
 ["station:027"]="station:enceladus_1",
 ["station:028"]="station:enceladus_2",
 ["station:029"]="station:titan_1",
 ["station:030"]="station:titan_2",
 ["station:031"]="station:titania_1",
 ["station:032"]="station:titania_2",
 ["station:033"]="station:triton_1",
 ["station:034"]="station:triton_2",
 ["station:035"]="station:pluto_1",
 ["station:036"]="station:pluto_2",
 ["station:037"]="station:ring_1",
 ["station:038"]="station:station_1",
 ["station:039"]="station:mars_3",
}

-- Every rotating region declares its actual buoy placements here. Optional
-- radius overrides the track; phase/heading/spin use radians. prop selects an
-- F2 prop ID; scale changes its visual size. A region-wide buoyProp or
-- defaults.buoyProp can supply the prop for entries without one.
-- A numeric buoys count is also accepted for evenly spaced generated rings.
W.navigation={
 mercury={buoys={
  {id='trade_buoy_a', phase=-.8+math.pi/2},
  {id='trade_buoy_b', phase=-.8+math.pi/2+math.pi},
 }},
 venus={buoys={
  {id='trade_buoy_a', phase=-.8+math.pi/2},
  {id='trade_buoy_b', phase=-.8+math.pi/2+math.pi},
 }},
 earth={buoys={
  {id='trade_buoy_a', phase=-.8+math.pi/2},
  {id='trade_buoy_b', phase=-.8+math.pi/2+math.pi},
 }},
 mars={buoys={
  {id='trade_buoy_a', phase=-.8+math.pi/2},
  {id='trade_buoy_b', phase=-.8+math.pi/2+math.pi},
 }},
 belt={buoys={
  {id='trade_buoy_a', phase=-.8+math.pi/2},
  {id='trade_buoy_b', phase=-.8+math.pi/2+math.pi},
 }},
 jupiter={buoys={
  {id='trade_buoy_a', phase=-.8+math.pi/2},
  {id='trade_buoy_b', phase=-.8+math.pi/2+math.pi},
 }, corridor='buoys', population={trader=0}},
 saturn={buoys={
  {id='trade_buoy_a', phase=-.8+math.pi/2},
  {id='trade_buoy_b', phase=-.8+math.pi/2+math.pi},
 }},
 uranus={buoys={
  {id='trade_buoy_a', phase=-.8+math.pi/2},
  {id='trade_buoy_b', phase=-.8+math.pi/2+math.pi},
 }, population={trader=0}},
 neptune={buoys={
  {id='trade_buoy_a', phase=-.8+math.pi/2},
  {id='trade_buoy_b', phase=-.8+math.pi/2+math.pi},
 }},
 luna={buoys={
  {id='trade_buoy_a', phase=-.8+math.pi/2},
  {id='trade_buoy_b', phase=-.8+math.pi/2+math.pi},
 }},
 phobos={buoys={
  {id='trade_buoy_a', phase=-.8+math.pi/2},
  {id='trade_buoy_b', phase=-.8+math.pi/2+1*math.pi*2/4},
  {id='trade_buoy_c', phase=-.8+math.pi/2+2*math.pi*2/4},
  {id='trade_buoy_d', phase=-.8+math.pi/2+3*math.pi*2/4},
 }, corridor='buoys'},
 deimos={buoys={
  {id='trade_buoy_a', phase=-.8+math.pi/2},
  {id='trade_buoy_b', phase=-.8+math.pi/2+1*math.pi*2/4},
  {id='trade_buoy_c', phase=-.8+math.pi/2+2*math.pi*2/4},
  {id='trade_buoy_d', phase=-.8+math.pi/2+3*math.pi*2/4},
 }, corridor='buoys'},
 io={buoys={
  {id='trade_buoy_a', phase=-.8+math.pi/2},
  {id='trade_buoy_b', phase=-.8+math.pi/2+math.pi},
 }},
 callisto={buoys={
  {id='trade_buoy_a', phase=-.8+math.pi/2},
  {id='trade_buoy_b', phase=-.8+math.pi/2+math.pi},
 }},
 enceladus={buoys={
  {id='trade_buoy_a', phase=-.8+math.pi/2},
  {id='trade_buoy_b', phase=-.8+math.pi/2+math.pi},
 }},
 pluto={buoys={
  {id='trade_buoy_a', phase=-.8+math.pi/2},
  {id='trade_buoy_b', phase=-.8+math.pi/2+math.pi},
 }},
 europa={buoys={
  {id='trade_buoy_a', phase=-.8+math.pi/2},
  {id='trade_buoy_b', phase=-.8+math.pi/2+math.pi},
 }},
 ganymede={buoys={
  {id='trade_buoy_a', phase=-.8+math.pi/2},
  {id='trade_buoy_b', phase=-.8+math.pi/2+math.pi},
 }},
 titan={buoys={
  {id='trade_buoy_a', phase=-.8+math.pi/2},
  {id='trade_buoy_b', phase=-.8+math.pi/2+math.pi},
 }},
 titania={buoys={
  {id='trade_buoy_a', phase=-.8+math.pi/2},
  {id='trade_buoy_b', phase=-.8+math.pi/2+math.pi},
 }},
 triton={buoys={
  {id='trade_buoy_a', phase=-.8+math.pi/2},
  {id='trade_buoy_b', phase=-.8+math.pi/2+math.pi},
 }},
}

-- Placement operations change this definition; WorldAuthoring applies/reloads it.
function W.find(id)
 for area,entries in pairs(W.stations) do
  for index,entry in ipairs(entries) do if entry.id==id then return entry,area,index end end
 end
 for _,entry in pairs(W.specials) do if entry.id==id then return entry,entry.area end end
end
function W.addStation(area,definition)
 assert(require('src.fields')[area],'unknown region '..tostring(area))
 local entry=require('src.persistence').copy(definition)
 if not entry.id then
  repeat entry.id=('station:%08x%08x'):format(love.math.random(0,2147483646),love.math.random(0,2147483646)) until not W.find(entry.id)
 end
 assert(not W.find(entry.id),'station id already exists: '..entry.id)
 assert(type(entry.name)=='string','station needs a name')
 if entry.spin==nil then entry.spin=area=='ring' and .02 or .04 end
 if not entry.position and not entry.motion and not entry.phase then
  local phases={}
  for _,existing in ipairs(W.stations[area] or {}) do
   phases[#phases+1]=(existing.phase or 0)%(math.pi*2)
  end
  table.sort(phases);local gap,phase=-1,0
  for i,value in ipairs(phases) do
   local nextValue=phases[i%#phases+1]+(i==#phases and math.pi*2 or 0)
   if nextValue-value>gap then gap,phase=nextValue-value,(nextValue+value)/2 end
  end
  entry.phase=phase
 end
 W.stations[area]=W.stations[area] or {}
 table.insert(W.stations[area],entry)
 return entry.id
end
function W.moveStation(id,area,position)
 local entry,oldArea,index=W.find(id);assert(entry,'unknown station '..tostring(id))
 assert(index,'special station placement belongs to its construction adapter')
 assert(require('src.fields')[area],'unknown region '..tostring(area))
 table.remove(W.stations[oldArea],index)
 W.stations[area]=W.stations[area] or {};table.insert(W.stations[area],entry)
 if position then entry.position=require('src.persistence').copy(position);entry.motion=nil;entry.phase=nil;entry.radius=nil end
 return id
end
function W.removeStation(id)
 local entry,area,index=W.find(id);assert(entry,'unknown station '..tostring(id))
 if index then table.remove(W.stations[area],index) else entry.enabled=false end
 return entry
end
function W.setStationEnabled(id,enabled)
 local entry=assert(W.find(id),'unknown station '..tostring(id));entry.enabled=not not enabled
end
function W.export()
 return 'return '..require('src.save').encode({stations=W.stations,navigation=W.navigation,specials=W.specials,defaults=W.defaults})
end
function W.signature()
 local h=0;local compiled={}
 local Fields=require('src.fields')
 for _,area in ipairs(Fields.list) do compiled[area]={locations=Fields[area].locations,links=Fields[area].travelLinks} end
 local text=W.export()..require('src.save').encode(compiled)
 for i=1,#text do h=(h*31+text:byte(i))%2147483647 end
 return h
end

-- Build corridor connections by bearing; surface/cloud destinations are spurs.
function W.connect(f)
 local byId={};for _,p in ipairs(f.locations) do byId[p.id]=p end
 local config=f.navigation or {}
 local corridor={}
 local orbiting=false
 for _,id in ipairs(f.stationIds) do if byId[id].motion.type=='orbit' then orbiting=true end end
 local buoyOnly=config.corridor=='buoys' or (not config.corridor and not orbiting)
 for _,id in ipairs(f.buoyIds) do corridor[#corridor+1]=id end
 if not buoyOnly then
  for _,id in ipairs(f.stationIds) do
   if byId[id].motion.type=='orbit' then corridor[#corridor+1]=id end
  end
 end
 table.sort(corridor,function(a,b)
  local aa,bb=byId[a].motion.phase or 0,byId[b].motion.phase or 0
  return aa==bb and a<b or aa<bb
 end)
 -- Start the local circuit at its explicitly designated primary port.
 local start=1
 for i,id in ipairs(corridor) do if byId[id].primary then start=i;break end end
 local ordered={};for i=1,#corridor do ordered[i]=corridor[(start+i-2)%#corridor+1] end
 corridor=ordered
 f.buoyCorridor=buoyOnly
 f.buoyCircuit={}
 for _,id in ipairs(corridor) do if byId[id].kind=='buoy' then f.buoyCircuit[#f.buoyCircuit+1]=id end end
 f.raidLinks={}
 for i,id in ipairs(f.buoyCircuit) do
  if #f.buoyCircuit>1 then f.raidLinks[#f.raidLinks+1]={id,f.buoyCircuit[i%#f.buoyCircuit+1]} end
 end
 f.travelLinks={};local seen={}
 local function link(a,b)
  if not a or not b or a==b then return end
  assert(byId[a] and byId[b],'unknown world connection '..tostring(a)..' -> '..tostring(b))
  local key=a<b and a..'|'..b or b..'|'..a
  if not seen[key] then seen[key]=true;f.travelLinks[#f.travelLinks+1]={a,b} end
 end
 for i,id in ipairs(corridor) do link(id,corridor[i%#corridor+1]) end
 local onCorridor={};for _,id in ipairs(corridor) do onCorridor[id]=true end
 local attachments=#corridor>0 and corridor or f.holdingId and {f.holdingId} or f.stationIds
 for _,id in ipairs(f.stationIds) do
  if not onCorridor[id] then
   for _,to in ipairs(#f.buoyIds>0 and f.buoyIds or attachments) do link(id,to) end
  end
 end
 for _,id in ipairs(f.drillIds) do link(byId[id].motion.home,id) end
 for _,id in ipairs(buoyOnly and #f.buoyIds>0 and f.buoyIds or {f.tradeHome or f.holdingId}) do link(f.driverId,id) end
 if f.ladderIds then
  for k,id in ipairs(f.ladderIds) do
   for _,to in ipairs(f.buoyIds) do link(id,to) end
   link(id,f.ladderIds[k%#f.ladderIds+1])
  end
 end
 for _,p in ipairs(f.locations) do
  if p.kind=='moon_gate' then for _,id in ipairs(attachments) do link(p.id,id) end end
 end
 for _,pair in ipairs(config.links or {}) do link(pair[1],pair[2]) end
 local circuit={}
 for _,id in ipairs(corridor) do circuit[#circuit+1]=id end
 for _,id in ipairs(f.stationIds) do
  if #corridor>0 and not onCorridor[id] and byId[id].uses.trade then
   -- The spur has links to the buoys; inserting it at a connected node keeps
   -- the local trader circuit valid without inventing navigation shortcuts.
   local function position(node)
    local m=byId[node].motion
    if m.type=='fixed' then return m.x,m.y end
    local a,r=m.type=='cloud' and m.a or m.phase,m.type=='cloud' and m.r or m.radius
    return (m.cx or 0)+math.cos(a)*r,(m.cy or 0)+math.sin(a)*r
   end
   local x,y=position(id);local attach,distance
   for _,candidate in ipairs(#f.buoyIds>0 and f.buoyIds or corridor) do
    local px,py=position(candidate);local d=(px-x)^2+(py-y)^2
    if not attach or d<distance or d==distance and candidate<attach then attach,distance=candidate,d end
   end
   for i,node in ipairs(circuit) do if node==attach then
    table.insert(circuit,i+1,id);table.insert(circuit,i+2,attach);break
   end end
  end
 end
 f.traderRoute=#circuit>0 and circuit or f.stationIds
 f.navigationVersion=(f.navigationVersion or 0)+1
end
return W
