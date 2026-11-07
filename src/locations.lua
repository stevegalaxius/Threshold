-- Authored places exist independently of loaded physics bodies. These IDs
-- identify places, not their display names or their order in a spawn loop.
local Fields = require("src.fields")
local T = require("src.tuning")
local L = { byId = {}, byArea = {} }
local pi, cos, sin = math.pi, math.cos, math.sin

local function register(area)
 L.byArea[area]={}
 for _,location in ipairs(Fields[area].locations) do
  assert(not L.byId[location.id],'duplicate location '..location.id)
  L.byId[location.id]=location;L.byArea[area][#L.byArea[area]+1]=location
 end
end
-- Rebuild catalogue/topology together after changing authoring definitions.
function L.rebuild(area)
 for id,place in pairs(L.byId) do if place.area==area then L.byId[id]=nil end end
 Fields.configureLocations(area)
 register(area)
end
for _,area in ipairs(Fields.list) do register(area) end
function L.rebuildAll()
 L.byId,L.byArea={},{}
 for _,area in ipairs(Fields.list) do Fields.configureLocations(area);register(area) end
end
function L.nearest(area,x,y,clock)
 local best,distance
 for _,place in ipairs(L.list(area)) do
  if place.kind=='buoy' or place.kind=='station' or place.id==Fields[area].holdingId then
   local px,py=L.position(place.id,clock or 0);local d=(px-x)^2+(py-y)^2
   if not best or d<distance or d==distance and place.id<best then best,distance=place.id,d end
  end
 end
 return best or Fields[area].driverId
end


-- The station a location belongs to: itself, or the station it's an
-- access point of (the Heaven-Ladder's anchors).
function L.canonical(id)
	local place = id and L.byId[id]
	return place and place.accessOf or id
end

function L.get(id) return assert(L.byId[id], "unknown location " .. tostring(id)) end
function L.list(area) return L.byArea[area] or {} end

function L.rate(m)
	if m.period then return pi * 2 / (T.yearLength * m.period) end
	if m.surface then
		local at = m.flowRadius or m.radius
		return 290 * math.min(1, m.surface / 6000) * math.sqrt(m.surface / math.max(at, m.surface)) * T.currentScale * (m.speedScale or 1) / m.radius
	end
	return m.rate or 0
end

-- The optional third result is the radial bearing. Cloud-city orientation
-- and an idle driver's barrel use it; station spin is independent of orbit.
function L.motionPosition(m, clock)
	if m.type == "fixed" then return m.x, m.y, 0 end
 if m.type=='mining' then
  local angle=-pi/2
  if m.home then local hx,hy=L.position(m.home,0);angle=math.atan2(hy-m.y,hx-m.x) end
  if m.planet then angle=angle+pi end
  -- off to one side of the drill's spoil field, never in its line of fire
  local distance=m.radius+T.mineWorkAltitude
  local side=T.mineWorkSide or 0
  return m.x+cos(angle)*distance-sin(angle)*side,m.y+sin(angle)*distance+cos(angle)*side,angle
 end
	if m.type == "cloud" then
		local r = m.r + m.up * sin(clock / m.upPeriod * pi * 2 + m.phase)
		local a = m.a + m.across * sin(clock / m.acrossPeriod * pi * 2 + m.phase * 0.7) / m.r
		return cos(a) * r, sin(a) * r, a
	end
	local a = m.phase + clock * L.rate(m)
	return (m.cx or 0) + cos(a) * m.radius, (m.cy or 0) + sin(a) * m.radius, a
end

function L.position(id,clock) return L.motionPosition(L.get(id).motion,clock) end

-- Non-docking visits to cloud cities stay above the gravity band. Follow the
-- city's bearing rather than its runway, which is intentionally below it.
function L.inspectionPosition(id,clock)
 local place=L.get(id)
 local x,y=L.position(id,clock)
 if place.motion.type=='cloud' then
  local radius=math.sqrt(x*x+y*y)
  local safe=Fields[place.area].planetR+T.surfacePullRange+1000
  return x/radius*safe,y/radius*safe
 end
 return x,y
end
function L.inspectionVelocity(id,clock)
 local x1,y1=L.inspectionPosition(id,clock-.01)
 local x2,y2=L.inspectionPosition(id,clock+.01)
 return (x2-x1)/.02,(y2-y1)/.02
end

function L.heading(id, clock)
	local location = L.get(id)
	if location.motion.type == "cloud" then
		local _, _, a = L.position(id, clock)
		return a + pi / 2
	end
	return (location.heading or 0) + (location.spin or 0) * clock
end

-- A station with rotors keeps its core (docks, berths) still and lets the
-- rotors take the location's spin instead.
function L.coreHeading(e, id, clock)
	local location = L.get(id)
	if e.rotors and location.motion.type ~= "cloud" then return location.heading or 0 end
	return L.heading(id, clock)
end

function L.velocity(id, clock)
	local x1, y1 = L.position(id, clock - 0.01)
	local x2, y2 = L.position(id, clock + 0.01)
	return (x2 - x1) / 0.02, (y2 - y1) / 0.02
end

-- Station selection uses purpose tags, never construction order.
function L.station(area,purpose)
 local best
 for _,place in pairs(L.byId) do
  if place.kind=='station' and not place.accessOf and (not area or place.area==area)
   and place.uses and place.uses[purpose] then
   if not best or (place.primary and not best.primary)
    or (not not place.primary==not not best.primary and place.id<best.id) then best=place end
  end
 end
 return best and best.id
end
function L.stations(area,purpose)
 local ids={}
 for _,place in ipairs(L.list(area)) do
  if place.kind=='station' and not place.accessOf and (not purpose or place.uses and place.uses[purpose]) then ids[#ids+1]=place.id end
 end
 table.sort(ids)
 return ids
end
function L.rally(area,from,clock)
 local field=Fields[area];local x,y=0,0
 if from then x,y=L.position(from,clock or 0) end
 local best,distance
 for _,id in ipairs(field.buoyIds) do
  local px,py=L.position(id,clock or 0);local d=(px-x)^2+(py-y)^2
  if not best or d<distance or d==distance and id<best then best,distance=id,d end
 end
 return best or field.driverId
end
-- Resolve/generate the definition without building a physics scene. The live
-- builder uses this exact definition too, including generated wheels/cities.
function L.stationDefinition(id)
 local place=L.get(id)
 assert(place.kind=='station','not a station: '..id)
 local data=require('src.data');local def=data.stations[place.layout]
 if not def then
  local Stations=require('src.stations');local generated
  if place.adapter=='cloud' and place.layout==Stations.cityId(Fields[place.area].cityScale or 1) then
   generated=Stations.city(Fields[place.area].cityScale or 1)
  elseif place.wheel and place.layout==Stations.ringId(unpack(place.wheel)) then generated=Stations.ring(unpack(place.wheel)) end
  assert(generated,'unknown station layout '..tostring(place.layout)..' at '..id)
  local err;def,err=data.defineStation(generated);assert(def,err)
 end
 return def
end
function L.stationServices(id)
 return require('src.station_services').get(L.stationDefinition(id))
end
function L.buoyDefinition(id)
 local place=L.get(id)
 assert(place.kind=='buoy','not a navigation buoy: '..id)
 if not place.prop then return end
 local def=require('src.data').wrecks[place.prop]
 assert(def and def.kind=='prop','buoy '..id..' needs an F2 prop: '..tostring(place.prop))
 local scale=place.scale or 1
 assert(type(scale)=='number' and scale>0 and scale<math.huge,'buoy scale must be positive and finite: '..id)
 return def,scale
end

function L.spawnStation(game,id)
 local place=L.get(id);local def=L.stationDefinition(id);local station
 if place.adapter=='cloud' then station=game:spawnCloudCity(place.motion.a,Fields[place.area].cityScale,id,def.id)
 else
  station=game:spawnStation(def.id,0,0,place.spin or 0,false,id)
  station.surfaceMine=place.adapter=='surface_mine' or nil
  if place.motion.type=='orbit' then game:setOrbit(station,place.motion.cx or 0,place.motion.cy or 0,L.rate(place.motion)*place.motion.radius) end
 end
 return station
end

function L.install(Game)
	function Game:bindLocation(e, id)
		local location = L.get(id)
		assert(location.area == self.fieldId, "binding a location from another area")
		e.locationId = id
		if e.kind == "station" then e.key, e.name = id, location.name end
		local clock = self.universe.clock
		e.body:setPosition(L.position(id, clock))
		e.body:setAngle(L.coreHeading(e, id, clock))
		e.body:setLinearVelocity(L.velocity(id, clock))
		e.body:setAngularVelocity(e.rotors and 0 or location.spin or 0)
		for _, r in ipairs(e.rotors or {}) do
			if not r.fixed then r.spin = location.spin or 0 end
		end
		return e
	end

	function Game:syncLocations()
		for _, e in ipairs(self.entities) do
			if e.locationId and not e.removed then
				e.body:setPosition(L.position(e.locationId, self.universe.clock))
				e.body:setAngle(L.coreHeading(e, e.locationId, self.universe.clock))
				e.body:setLinearVelocity(L.velocity(e.locationId, self.universe.clock))
			end
		end
	end

	-- The entity for a location. A station with several access points
	-- (the Heaven-Ladder's anchors) has one entity each; given x, y, the
	-- nearest is returned, otherwise the first.
	function Game:locationEntity(id, x, y)
		local best, bestD
		for _, e in ipairs(self.entities) do
			if e.locationId == id and not e.removed then
				if not x then return e end
				local ex, ey = e.body:getPosition()
				local d = (ex - x) ^ 2 + (ey - y) ^ 2
				if not best or d < bestD then best, bestD = e, d end
			end
		end
		return best
	end
end

return L
