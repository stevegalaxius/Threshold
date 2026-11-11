-- One dealer allocation policy for remote and loaded stations. Reuse the
-- normal spatial grid, doorway, berth size and hull-clearance checks.
local P={scenes=setmetatable({},{__mode='k'}),stations={}}
function P.bind(u,game,station)
 P.scenes[u]=P.scenes[u] or {};P.scenes[u][station.key]=setmetatable({game=game,station=station},{__mode='v'})
end
function P.reserve(st)
 local T=require('src.tuning');local h=st.def.hangar or {}
 local policy=require('data.industry').dealerParking
 local rows=math.max(1,math.ceil((h.h or T.hangarH)*policy.guestHangarFraction))
 local berths={};for i,b in ipairs(st.def.berths or {}) do berths[#berths+1]={id=i,size=(b.maxLength or b.size*2)*(b.maxWidth or b.size*1.1)} end
 table.sort(berths,function(a,b)return a.size>b.size or a.size==b.size and a.id<b.id end)
 local reserved={};for i=1,math.min(policy.guestBerths,#berths) do reserved[berths[i].id]=true end
 return rows,reserved
end
function P.mask(st,grid)
 local rows=P.reserve(st);local Grid=require('src.inventory.grid')
 for y=math.max(0,grid.h-rows),grid.h-1 do for x=0,grid.w-1 do
  if Grid.isFree(grid,x,y,1,1) then Grid.place(grid,{x=x,y=y,w=1,h=1,guestReserve=true}) end
 end end
end
function P.bayAllowed(st,bay,w,h)
 local rows=P.reserve(st);local height=(st.def.hangar or {}).h or require('src.tuning').hangarH
 return bay.y+h<=height-rows
end
local function context(u,key)
 local Game,L=require('src.game'),require('src.locations')
 local def=L.stationDefinition(key)
 local binding=P.scenes[u] and P.scenes[u][key]
 local live=binding and binding.game and binding.station and binding.game.universe==u and binding.station.body and not binding.station.body:isDestroyed() and binding.game.fieldId==L.get(key).area
 local station=live and binding.station or P.stations[key]
 if not station or station.def~=def then station={key=key,def=def,docks=def.docks,dock=def.docks[1]};P.stations[key]=station end
 local roster={};local record=require('src.stockpile').record(u,key)
 for _,rec in ipairs(record.hangar or {}) do roster[#roster+1]=rec end
 for _,lot in ipairs(u.dealers and u.dealers[key] and u.dealers[key].lots or {}) do roster[#roster+1]=lot end
 local entities={};local online=live and binding.game.alifeOnline or {}
 if live then for _,e in ipairs(binding.game.entities) do
  if e.kind=='ship' and not e.dead and not e.removed and e.dockState and e.dockState.station.key==key then entities[#entities+1]=e end
 end end
 local proxy=setmetatable({universe=u,entities=entities,stationRoster=function()return roster end,stationRecord=function()return record end},{__index=Game})
 -- Remote docked NPCs do not have precise bay coordinates. Place them in a
 -- deterministic temporary occupancy map; never reserve their space for sale.
 local visitors={}
 for id,r in pairs(u.npcs or {}) do
  local node=r.node or r.route and r.route[r.index]
  if r.state=='docked' and node and L.canonical(node)==key and not online[id] then visitors[#visitors+1]=r end
 end
 table.sort(visitors,function(a,b)return a.id<b.id end)
 for _,r in ipairs(visitors) do
  local owner={hull=r.ship.hull}
  local parking=proxy:shipParkingFit(station,owner.hull,owner)
  if not parking then return nil end -- Existing visitors already exceed physical capacity.
  proxy:applyParking(owner,parking);roster[#roster+1]=owner
 end
 return proxy,station,roster
end
function P.plan(u,key,hull,count)
 local proxy,station,roster=context(u,key);if not proxy then return {} end
 local placements={}
 -- Refuse to hide unallocated existing inventory behind more production.
 for _,owner in ipairs(roster) do
  if not proxy:shipParkingValid(station,owner,owner.hull) then return placements end
 end
 for _=1,count do
  local owner={hull=hull,dealerStock=true}
  local parking=proxy:shipParkingFit(station,hull,owner)
  if not parking then break end
  proxy:applyParking(owner,parking);roster[#roster+1]=owner;placements[#placements+1]=parking
 end
 return placements
end
return P
