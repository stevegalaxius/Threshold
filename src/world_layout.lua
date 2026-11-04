-- World authoring: stable station identities and navigation topology.
-- Station designs/services live in data/station_*.lua. Special construction stays
-- in its existing adapter; ordinary layout changes belong here.
local W={}
W.stations = {
	phobos = {
		{ id = "station:001", primary = true, name = "Phobos Strip Mine", adapter = "surface_mine", layout = "zhuhai_strip_mine" },
	},
	deimos = {
		{ id = "station:002", primary = true, name = "Deimos Strip Mine", adapter = "surface_mine", layout = "zhuhai_strip_mine" },
	},
	mercury = {
		{ id = "station:003", spin = 0.05, phase = -0.8, primary = true, name = "Terminator Station" },
		{ id = "station:004", spin = -0.05, phase = 2.3415926535897933, name = "Dawnline Station" },
	},
	venus = {
		{ id = "station:005", spin = 0.05, phase = -0.8, primary = true, marketId = "market:001", name = "Hub Station" },
		{ id = "station:006", spin = -0.05, phase = 2.3415926535897933, name = "Cloudline Station" },
	},
	earth = {
		{ id = "station:007", spin = 0.05, phase = -0.8, primary = true, marketId = "market:005", name = "Orbital One" },
		{ id = "station:008", marketId = "market:006", spin = -0.05, phase = 2.3415926535897933, name = "Orbital Two" },
	},
	mars = {
		{ id = "station:009", spin = 0.05, phase = -0.8, primary = true, layout = "shipyard_1", marketId = "market:002", name = "Station Alpha" },
		{ id = "station:010", marketId = "market:004", spin = -0.05, phase = 2.3415926535897933, name = "Station Beta" },
	},
	belt = {
		{ id = "station:011", spin = 0.05, phase = -0.8, primary = true, name = "Ceres Dock" },
		{ id = "station:012", spin = -0.05, phase = 2.3415926535897933, name = "Piazzi Station" },
	},
	jupiter = {
		{ id = "station:013", primary = true, name = "Olympus", adapter = "cloud" },
	},
	saturn = {
		{ id = "station:014", spin = 0.05, phase = -0.8, primary = true, name = "Cassini Gate" },
		{ id = "station:015", spin = -0.05, phase = 2.3415926535897933, name = "Enceladus Station" },
	},
	uranus = {
		{ id = "station:016", primary = true, name = "Herschel", adapter = "cloud" },
	},
	luna = {
		{ id = "station:017", spin = 0.05, phase = -0.8, primary = true, marketId = "market:007", name = "Tranquility Dock" },
		{ id = "station:018", marketId = "market:008", spin = -0.05, phase = 2.3415926535897933, name = "Shackleton Station" },
	},
	io = {
		{ id = "station:019", spin = 0.05, phase = -0.8, primary = true, marketId = "market:017", name = "Pele Works" },
		{ id = "station:020", marketId = "market:018", spin = -0.05, phase = 2.3415926535897933, name = "Loki Laboratory" },
	},
	europa = {
		{ id = "station:021", spin = 0.05, phase = -0.8, primary = true, marketId = "market:009", name = "Conamara Station" },
		{ id = "station:022", marketId = "market:010", spin = -0.05, phase = 2.3415926535897933, name = "Pwyll Station" },
	},
	ganymede = {
		{ id = "station:023", spin = 0.05, phase = -0.8, primary = true, marketId = "market:011", name = "Galileo Regio" },
		{ id = "station:024", marketId = "market:012", spin = -0.05, phase = 2.3415926535897933, name = "Uruk Station" },
	},
	callisto = {
		{ id = "station:025", spin = 0.05, phase = -0.8, primary = true, marketId = "market:019", name = "Valhalla Port" },
		{ id = "station:026", marketId = "market:020", spin = -0.05, phase = 2.3415926535897933, name = "Asgard Station" },
	},
	enceladus = {
		{ id = "station:027", spin = 0.05, phase = -0.8, primary = true, marketId = "market:021", name = "Tiger Stripe Laboratory" },
		{ id = "station:028", marketId = "market:022", spin = -0.05, phase = 2.3415926535897933, name = "South Pole Port" },
	},
	titan = {
		{ id = "station:029", spin = 0.05, phase = -0.8, primary = true, marketId = "market:013", name = "Kraken Station" },
		{ id = "station:030", marketId = "market:014", spin = -0.05, phase = 2.3415926535897933, name = "Huygens Station" },
	},
	titania = {
		{ id = "station:031", spin = 0.05, phase = -0.8, primary = true, marketId = "market:025", name = "Gertrude Port" },
		{ id = "station:032", marketId = "market:026", spin = -0.05, phase = 2.3415926535897933, name = "Messina Research Station" },
	},
	triton = {
		{ id = "station:033", spin = 0.05, phase = -0.8, primary = true, marketId = "market:015", name = "Cipango Station" },
		{ id = "station:034", marketId = "market:016", spin = -0.05, phase = 2.3415926535897933, name = "Voyager Station" },
	},
	pluto = {
		{ id = "station:035", spin = 0.05, phase = -0.8, primary = true, uses = { pirateBase = true }, layout = "jovian_kink", marketId = "market:023", name = "Milliways Freeport" },
		{ id = "station:036", marketId = "market:024", spin = -0.05, phase = 2.3415926535897933, name = "Sputnik Port" },
	},
	ring = {
		{ id = "station:037", spin = 0.02, phase = -0.8, primary = true, name = "Ring Station", wheel = { 3000, 300 } },
	},
	station = {
		{ id = "station:038", spin = 0.04, phase = -0.8, primary = true, name = "Hub Station", marketId = "market:001", wheel = { 1400, 160 } },
	},
}
-- IDs are assigned once and remain unchanged when stations move or get renamed.
W.defaults={marketId='market:001'}
W.specials={heavenLadder={area='mars',id='station:039',name='Heaven-Ladder',marketId='market:003',
 access={'station:039','access:001','access:002','access:003'}}}
-- Read-only compatibility aliases for saves from before independent station IDs.
W.aliases={
 ["phobos/strip_mine"]="station:001",
 ["deimos/strip_mine"]="station:002",
 ["mercury/terminator_station"]="station:003",
 ["mercury/dawnline_station"]="station:004",
 ["venus/hub_station"]="station:005",
 ["venus/cloudline_station"]="station:006",
 ["earth/orbital_one"]="station:007",
 ["earth/orbital_two"]="station:008",
 ["mars/station_alpha"]="station:009",
 ["mars/station_beta"]="station:010",
 ["belt/ceres_dock"]="station:011",
 ["belt/piazzi_station"]="station:012",
 ["jupiter/olympus"]="station:013",
 ["saturn/cassini_gate"]="station:014",
 ["saturn/enceladus_station"]="station:015",
 ["uranus/herschel"]="station:016",
 ["luna/tranquility_dock"]="station:017",
 ["luna/shackleton_station"]="station:018",
 ["io/pele_works"]="station:019",
 ["io/loki_laboratory"]="station:020",
 ["europa/conamara_station"]="station:021",
 ["europa/pwyll_station"]="station:022",
 ["ganymede/galileo_regio"]="station:023",
 ["ganymede/uruk_station"]="station:024",
 ["callisto/valhalla_port"]="station:025",
 ["callisto/asgard_station"]="station:026",
 ["enceladus/tiger_stripe_laboratory"]="station:027",
 ["enceladus/south_pole_port"]="station:028",
 ["titan/kraken_station"]="station:029",
 ["titan/huygens_station"]="station:030",
 ["titania/gertrude_port"]="station:031",
 ["titania/messina_research_station"]="station:032",
 ["triton/cipango_station"]="station:033",
 ["triton/voyager_station"]="station:034",
 ["pluto/tombaugh_station"]="station:035",
 ["pluto/sputnik_port"]="station:036",
 ["ring/ring_station"]="station:037",
 ["station/hub_station"]="station:038",
 ["mars/heaven_ladder"]="station:039",
 ["mars/heaven_ladder_2"]="access:001",
 ["mars/heaven_ladder_3"]="access:002",
 ["mars/heaven_ladder_4"]="access:003",
}

-- Every rotating region declares its actual buoy placements here. Optional
-- radius overrides the region track; phase is the starting angle in radians.
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
 return 'return '..require('src.save').encode({stations=W.stations,navigation=W.navigation,specials=W.specials})
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
