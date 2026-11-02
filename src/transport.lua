-- Authored dispatch work, independent of market prices and NPC credits.
local Tasks=require('src.tasks')
local Fields=require('src.fields')
local L=require('src.locations')
local G=require('src.travelgraph')
local Hold=require('src.inventory.hold')
local data=require('src.data')
local Transport={}
local function hold(r)
 return r.ship.hold and Hold.deserialize(r.ship.hold,function(id)return data.items[id]~=nil end)
end
local function room(r,item,amount)
 local h=hold(r)
 if h then return Hold.room(h,item,amount) end
 local used=0
 for id,n in pairs(r.ship.cargo or {}) do used=used+data.items[id].volume*n end
 return math.max(0,math.floor(((data.hulls[r.ship.hull].hold or 0)-used)/data.items[item].volume))
end
local function cargo(r,item,amount)
 local h=hold(r)
 if h then
  local totals=Hold.totals(h);totals[item]=(totals[item] or 0)+amount
  Hold.sync(h,totals);r.ship.hold=Hold.serialize(h);r.ship.cargo=Hold.totals(h)
 else
  r.ship.cargo=r.ship.cargo or {}
  r.ship.cargo[item]=(r.ship.cargo[item] or 0)+amount
 end
end
function Transport.route(source,target,clock)
 local a,b=L.get(source),L.get(target)
 local from,to=Fields[a.area].driverId,Fields[b.area].driverId
 if not from or not to or a.area==b.area then return end
 local out=G.route(G.build(a.area),source,from,clock)
 local inbound=G.route(G.build(b.area),to,target,clock)
 if not out or not inbound then return end
 local route={source}
 for _,leg in ipairs(out.legs) do route[#route+1]=leg.edge.to end
 route[#route+1]=to
 for _,leg in ipairs(inbound.legs) do route[#route+1]=leg.edge.to end
 return route
end
Tasks.register('transport',{
 roles={trader=true,courier=true},
 plan=function(t,station,clock) return Transport.route(station,t.target,clock) end,
 eligible=function(u,r,o,station,clock)
  return station==o.source and room(r,o.item,o.amount)>=o.amount and Transport.route(o.source,o.target,clock)~=nil
 end,
 score=function(u,r,o,station,clock)
  -- Oldest dispatch first, with immediate return trips deprioritized.
  return clock-(o.readyAt or 0)-(r.lastOrigin==o.target and 100000 or 0)
 end,
 prepare=function(u,r,t,station,clock)
  t.route=Transport.route(t.source,t.target,clock)
  if not t.route or room(r,t.item,t.amount)<t.amount then return false end
  cargo(r,t.item,t.amount);t.phase='delivery'
  return true
 end,
 complete=function(u,r,t,station,clock)
  if station~=t.target then return false end
  local h=hold(r)
  local amount=h and Hold.count(h,t.item) or (r.ship.cargo or {})[t.item] or 0
  if amount<t.amount then
   Tasks.release(u,r,'cargo lost',clock);return false
  end
  cargo(r,t.item,-t.amount)
  local state=Tasks.state(u);state.delivered=state.delivered or {}
  state.delivered[station]=(state.delivered[station] or 0)+t.amount
  r.lastDestination=station;r.lastOrigin=t.source
  return true
 end
})
function Transport.seed(u)
 local state=Tasks.state(u)
 if state.transportSeeded then return end
 state.transportSeeded=true
 -- Recurring dispatches from each port to the other planets. These are test manifests,
 -- not market stock; the economy can post real work through Tasks.post later.
 for _,from in ipairs(Fields.list) do
  if Fields[from].driverId and Fields[from].stationIds[1] then
   for _,to in ipairs(Fields.list) do
    if from~=to and Fields[to].driverId and Fields[to].stationIds[1] then
     for _,source in ipairs(Fields[from].stationIds) do
      Tasks.post(u,{kind='transport',source=source,
       target=Fields[to].stationIds[1],item='scrap',amount=5})
     end
    end
   end
  end
 end
end
return Transport
