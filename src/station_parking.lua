-- One station roster, with spatial interior bays and finite exterior positions.
local data,T=require('src.data'),require('src.tuning')
local Sweep=require('src.collision_prediction')
local P={}
function P.dimensions(hullId)
 local hull=data.hulls[hullId];local x1,y1,x2,y2=0,0,0,0
 for i=1,#hull.shape,2 do
  x1,y1=math.min(x1,hull.shape[i]),math.min(y1,hull.shape[i+1])
  x2,y2=math.max(x2,hull.shape[i]),math.max(y2,hull.shape[i+1])
 end
 return x2-x1,y2-y1
end
return function(Game)
 Game.shipDimensions=P.dimensions
 function Game.hangarSize(st)
  local h=st.def and st.def.hangar or {}
  return h.w or T.hangarW,h.h or T.hangarH
 end
 function Game:stationMoorings(st)
  local r=self:stationRecord(st)
  r.moorings=r.moorings or {}
  for i,b in ipairs(st.def.berths or {}) do
   local slot=r.moorings[i] or {};r.moorings[i]=slot
   slot.x,slot.y,slot.heading,slot.berth=b.x,b.y,b.heading or 0,i
   slot.length=b.maxLength or b.size*T.berthShipScale*2
   slot.width=b.maxWidth or b.size*T.berthShipScale*1.1
  end
  -- Only editor-authored berths are parking locations. Drop old overflow slots.
  for i=#r.moorings,#(st.def.berths or {})+1,-1 do r.moorings[i]=nil end
  return r.moorings
 end
 function Game:mooringTaken(st,index,ignore)
  for _,rec in ipairs(self:stationRecord(st).hangar) do
   if rec~=ignore and rec.mooring==index then return true end
  end
  for _,e in ipairs(self.entities) do
   if e~=ignore and not e.dead and not e.removed then
    local ds=e.dockState
    if ds and ds.station==st then
     local slot=self:stationMoorings(st)[index]
     if e.parkingMooring==index or ds.mooring and ds.mooring.slot==index
      or slot.berth and ds.berth==slot.berth then return true end
    end
   end
  end
  return false
 end
 -- Check once per hull and station-local pose. A nominally large berth
 -- is unusable if the parked hull would overlap the station itself.
 -- Where a hull actually sits on berth `index`: the authored berth point,
 -- or slid along the berth's heading (outward first) until the hull is clear
 -- of the station. A berth's point is sized for small hulls; a freighter
 -- centred on it pokes into the station, and every berth read as blocked.
 -- nil when the berth has no clear spot for this hull within its length.
 function Game:berthPose(st,index,hullId)
  local slot=self:stationMoorings(st)[index];local hull=data.hulls[hullId]
  if not slot or not hull then return nil end
  st.parkingClearance=st.parkingClearance or {}
  local cache=st.parkingClearance[hullId] or {};st.parkingClearance[hullId]=cache
  local old=cache[index]
  if old and old.x==slot.x and old.y==slot.y and old.heading==slot.heading and old.hull==hull then return old.pose end
  local x1,y1,x2,y2=0,0,0,0
  for i=1,#hull.shape,2 do
   x1,y1=math.min(x1,hull.shape[i]),math.min(y1,hull.shape[i+1])
   x2,y2=math.max(x2,hull.shape[i]),math.max(y2,hull.shape[i+1])
  end
  local angle=math.rad(slot.heading or 0);local c,s=math.cos(angle),math.sin(angle)
  local function clearAt(cx,cy)
   local rect={}
   for _,p in ipairs({{x1-2,y1-2},{x2+2,y1-2},{x2+2,y2+2},{x1-2,y2+2}}) do
    rect[#rect+1]=cx+p[1]*c-p[2]*s;rect[#rect+1]=cy+p[1]*s+p[2]*c
   end
   for _,fixture in ipairs(st.body:getFixtures()) do
    local shape=fixture:getShape()
    if not fixture:isSensor() and shape:getType()=='polygon'
     and Sweep.sweepPolygon(rect,{shape:getPoints()},0,0,0) then return false end
   end
   return true
  end
  local pose
  local reach=math.max(0,(slot.length or 0)/2-(x2-x1)/2)
  for slide=0,reach,20 do
   for _,dir in ipairs(slide==0 and {1} or {1,-1}) do
    local cx,cy=slot.x+c*slide*dir,slot.y+s*slide*dir
    if clearAt(cx,cy) then pose={x=cx,y=cy,heading=slot.heading,slot=index};break end
   end
   if pose then break end
  end
  cache[index]={x=slot.x,y=slot.y,heading=slot.heading,hull=hull,pose=pose}
  return pose
 end
 function Game:mooringClear(st,index,hullId)
  return self:berthPose(st,index,hullId)~=nil
 end
 function Game:mooringFits(st,index,hullId,ignore)
  local slot=self:stationMoorings(st)[index]
  if not slot or self:mooringTaken(st,index,ignore) then return false end
  local length,width=P.dimensions(hullId)
  return length<=slot.length and width<=slot.width and self:mooringClear(st,index,hullId)
 end
 function Game:mooringFit(st,hullId,ignore)
  for i in ipairs(self:stationMoorings(st)) do if self:mooringFits(st,i,hullId,ignore) then return i end end
 end
 function Game:shipParkingFit(st,hullId,ignore)
  local bay=self:hangarFit(st,hullId,ignore)
  if bay then return {bay=bay} end
  local mooring=self:mooringFit(st,hullId,ignore)
  if mooring then return {mooring=mooring} end
 end
 function Game:shipParkingValid(st,owner,hullId)
  local bay=owner.bay
  local mooring=owner==self.player and owner.parkingMooring or owner.mooring
  return bay and self:hangarFree(st,owner,hullId,bay) or mooring and self:mooringFits(st,mooring,hullId,owner)
 end
 function Game:applyParking(owner,parking)
  owner.bay=parking and parking.bay or nil
  if owner==self.player then owner.parkingMooring=parking and parking.mooring or nil
  else owner.mooring=parking and parking.mooring or nil end
 end
 function Game:parkingPlacement(st,parking,dock)
  if parking and parking.mooring then
   local slot=self:stationMoorings(st)[parking.mooring]
   return {dock=dock or st.dock,berth=slot and slot.berth,parking=parking}
  end
  return {dock=dock or st.dock,parking=parking,interior=true}
 end
 function Game:moveStationShip(st,owner,outside)
  local hullId=owner==self.player and owner.hull.id or owner.hull
  local parking
  if outside then
   local i=self:mooringFit(st,hullId,owner);if i then parking={mooring=i} end
  else
   local bay=self:hangarFit(st,hullId,owner);if bay then parking={bay=bay} end
  end
  if not parking then return false,'NO SUITABLE FREE PARKING' end
  self:applyParking(owner,parking)
  if owner==self.player then self:dockInstantly(owner,st,self:parkingPlacement(st,parking)) end
  return true
 end
 function Game:shipParkingLabel(st,owner)
  local i=owner==self.player and owner.parkingMooring or owner.mooring
  if i then return 'Berth '..i end
  return owner.bay and 'Interior hangar' or 'Awaiting allocation'
 end
end
