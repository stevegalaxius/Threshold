-- World authoring: stable station identities and navigation topology.
-- Station designs/services live in data/station_*.lua. Special construction stays
-- in its existing adapter; ordinary layout changes belong here.
local W={}
W.stations = {
	phobos = {
		{ id = "strip_mine", primary = true, name = "Phobos Strip Mine", adapter = "surface_mine", layout = "zhuhai_strip_mine" },
	},
	deimos = {
		{ id = "strip_mine", primary = true, name = "Deimos Strip Mine", adapter = "surface_mine", layout = "zhuhai_strip_mine" },
	},
	mercury = {
		{ id = "terminator_station", primary = true, name = "Terminator Station" },
		{ id = "dawnline_station", name = "Dawnline Station" },
	},
	venus = {
		{ id = "hub_station", primary = true, name = "Hub Station" },
		{ id = "cloudline_station", name = "Cloudline Station" },
	},
	earth = {
		{ id = "orbital_one", primary = true, name = "Orbital One" },
		{ id = "orbital_two", name = "Orbital Two" },
	},
	mars = {
		{ id = "station_alpha", primary = true, layout = "shipyard_1", name = "Station Alpha" },
		{ id = "station_beta", name = "Station Beta" },
	},
	belt = {
		{ id = "ceres_dock", primary = true, name = "Ceres Dock" },
		{ id = "piazzi_station", name = "Piazzi Station" },
	},
	jupiter = {
		{ id = "olympus", primary = true, name = "Olympus", adapter = "cloud" },
	},
	saturn = {
		{ id = "cassini_gate", primary = true, name = "Cassini Gate" },
		{ id = "enceladus_station", name = "Enceladus Station" },
	},
	uranus = {
		{ id = "herschel", primary = true, name = "Herschel", adapter = "cloud" },
	},
	luna = {
		{ id = "tranquility_dock", primary = true, name = "Tranquility Dock" },
		{ id = "shackleton_station", name = "Shackleton Station" },
	},
	io = {
		{ id = "pele_works", primary = true, name = "Pele Works" },
		{ id = "loki_laboratory", name = "Loki Laboratory" },
	},
	europa = {
		{ id = "conamara_station", primary = true, name = "Conamara Station" },
		{ id = "pwyll_station", name = "Pwyll Station" },
	},
	ganymede = {
		{ id = "galileo_regio", primary = true, name = "Galileo Regio" },
		{ id = "uruk_station", name = "Uruk Station" },
	},
	callisto = {
		{ id = "valhalla_port", primary = true, name = "Valhalla Port" },
		{ id = "asgard_station", name = "Asgard Station" },
	},
	enceladus = {
		{ id = "tiger_stripe_laboratory", primary = true, name = "Tiger Stripe Laboratory" },
		{ id = "south_pole_port", name = "South Pole Port" },
	},
	titan = {
		{ id = "kraken_station", primary = true, name = "Kraken Station" },
		{ id = "huygens_station", name = "Huygens Station" },
	},
	titania = {
		{ id = "gertrude_port", primary = true, name = "Gertrude Port" },
		{ id = "messina_research_station", name = "Messina Research Station" },
	},
	triton = {
		{ id = "cipango_station", primary = true, name = "Cipango Station" },
		{ id = "voyager_station", name = "Voyager Station" },
	},
	pluto = {
		{ id = "tombaugh_station", primary = true, uses = { pirateBase = true }, layout = "jovian_kink", name = "Milliways Freeport" },
		{ id = "sputnik_port", name = "Sputnik Port" },
	},
	ring = {
		{ id = "ring_station", primary = true, name = "Ring Station", wheel = { 3000, 300 } },
	},
	station = {
		{ id = "hub_station", primary = true, name = "Hub Station", marketId = "venus/hub_station", wheel = { 1400, 160 } },
	},
}
-- Omit an override to retain the region's default corridor. Buoys can also be
-- a list of {id, phase, radius}; phases are radians, radii are world units.
W.navigation={
 jupiter={corridor='buoys'},
 phobos={buoys=4,corridor='buoys'},
 deimos={buoys=4,corridor='buoys'},
}

function W.home(purpose,area)
 local best
 for region,stations in pairs(W.stations) do
  if not area or region==area then
   for _,entry in ipairs(stations) do
    if type(entry)=='table' and entry.uses and entry.uses[purpose] then
     local id=region..'/'..(entry.id or entry[1])
     if not best or id<best then best=id end
    end
   end
  end
 end
 return best
end

-- Build corridor connections from the authored nodes. Stations in the corridor
-- are ordered by bearing; surface/cloud destinations are spurs off the buoys.
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
 local attachments=#corridor>0 and corridor or f.stationIds
 for _,id in ipairs(f.stationIds) do
  if not onCorridor[id] then
   for _,to in ipairs(#f.buoyIds>0 and f.buoyIds or attachments) do link(id,to) end
  end
 end
 for _,id in ipairs(f.drillIds) do link(byId[id].motion.home,id) end
 for _,id in ipairs(buoyOnly and f.buoyIds or {f.tradeHome}) do link(f.driverId,id) end
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
