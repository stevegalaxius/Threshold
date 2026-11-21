--[[
	Soak event log: SOAK_LOG=file love . --soak writes one JSON object a line
	(JSON Lines), so one soak can answer later questions without another run.
	tools/soaklog/report.py reads it.

	Every line has t (game seconds since the soak began) and ev:

	  order       a board offer posted: id, kind, and for freight src, dst,
	              item, n, m3, scope, trunk, urgency, house
	  take        an NPC took a job: npc, role, kind, id, at; for freight
	              src, dst, lines, stops, m3 and the ship's hold
	  gone        an order left the board without being taken (expired or
	              withdrawn): id, item, n, age
	  hist        a world event from src/simulation_history.lua (deliveries
	              with pay, ship purchases, merchant deals, fights, sites):
	              kind, area, node, who, result
	  death       a ship lost: npc, role, hull, task, cargo m3 and goods,
	              area, killer and the killer's role
	  npc         every LOG_EVERY seconds, each NPC: role, hull, hold,
	              credits, earnings and spending counters, task, state, area
	  stock       every LOG_EVERY seconds, each station: per good stock,
	              target and price (goods with either)
	  plant       every LOG_EVERY seconds, each factory installation:
	              policy, recipe mix and status
	  counts      every LOG_EVERY seconds: docked/undocked and other
	              high-volume history kinds, only counted
]]
local L={}
local data=require('src.data')
local json=require('src.economy_model').json
local LOG_EVERY=600

local file,u,t0,lastSnap
local live={}      -- open orders we saw posted: id -> {t,item,n}
local counted={}   -- high-volume history kinds, counted not logged
local QUIET={docked=true,undocked=true,arrived=true,left_area=true,fuel_condition_changed=true}

local function now() return (u.clock or 0)-t0 end
local function emit(ev,rec)
 rec.ev=ev;rec.t=math.floor(now()*10+.5)/10
 file:write(json(rec),'\n')
end
local function hold(r)
 local hull=r.ship and data.hulls[r.ship.hull]
 return hull and hull.hold or 0
end
local function cargoOf(r)
 local m3,goods=0,{}
 for item,n in pairs(r.ship and r.ship.cargo or {}) do
  if n>0 then m3=m3+n*((data.items[item] or {}).volume or 1);goods[item]=n end
 end
 return m3,goods
end
local function vol(item,n) return (n or 0)*((data.items[item] or {}).volume or 1) end

function L.start(game,path)
 u=game.universe;t0=u.clock or 0;lastSnap=-math.huge
 file=assert(io.open(path,'w'),'SOAK_LOG: cannot write '..path)
 emit('start',{clock=t0,field=game.fieldId,npcs=(function() local n=0 for _ in pairs(u.npcs or {}) do n=n+1 end return n end)()})
 local Tasks=require('src.tasks')
 -- orders
 local post=Tasks.post
 Tasks.post=function(u_,offer,...)
  local o=post(u_,offer,...)
  if u_==u and o then
   local rec={id=o.id,kind=o.kind}
   if o.kind=='transport' then
    rec.src=o.source;rec.dst=o.target;rec.item=o.item;rec.n=o.amount;rec.m3=o.item and vol(o.item,o.amount) or nil
    rec.scope=o.layoutScope;rec.trunk=o.trunk or nil;rec.urgency=o.urgency;rec.house=o.house
    live[o.id]={t=now(),item=o.item,n=o.amount}
   end
   emit('order',rec)
  end
  return o
 end
 -- jobs taken
 local choose=Tasks.choose
 local seen=setmetatable({},{__mode='k'})
 Tasks.choose=function(u_,r,station,...)
  local t=choose(u_,r,station,...)
  if u_==u and t and seen[r]~=t then
   seen[r]=t
   local rec={npc=r.id,role=r.populationGroup,kind=t.kind,id=t.id,at=station}
   if t.kind=='transport' then
    local m3,stops,lines=0,{},0
    for _,l in ipairs(t.manifest or {t}) do
     lines=lines+1;m3=m3+vol(l.item,l.amount);stops[l.target or t.target]=true
     if l.id then live[l.id]=nil end
    end
    local n=0 for _ in pairs(stops) do n=n+1 end
    rec.src=t.source;rec.dst=t.target;rec.lines=lines;rec.stops=n;rec.m3=m3;rec.hold=hold(r)
    rec.wait=t.placed and (u.clock-t.placed) or nil
   end
   live[t.id]=nil
   emit('take',rec)
  end
  return t
 end
 -- deaths, with what the ship was doing and carrying
 local H=require('src.simulation_history')
 local death=H.death
 H.death=function(u_,r,clock,area,killer,...)
  if u_==u and r and not r.deathOutcomeId then
   local work=r.task or r.lastTask
   local k=killer and killer~='player' and u.npcs and u.npcs[killer]
   local m3,goods=cargoOf(r)
   emit('death',{npc=r.id,role=r.populationGroup,hull=r.ship and r.ship.hull,task=work and work.kind or 'idle',
    cargo=m3,goods=goods,area=area,node=r.node,killer=killer,killerRole=killer=='player' and 'player' or k and k.populationGroup or nil,
    credits=r.credits})
  end
  return death(u_,r,clock,area,killer,...)
 end
 -- every other world event
 require('src.events').on('simulation_outcome',function(e)
  if QUIET[e.kind] then counted[e.kind]=(counted[e.kind] or 0)+1;return end
  if e.kind=='npc_died' then return end -- (logged above, with more detail)
  emit('hist',{kind=e.kind,area=e.area,node=e.node,who=e.participants,result=e.result})
 end)
end

local COUNTERS={'freightEarnings','salvageEarnings','miningEarnings','rareEarnings','wageEarnings','bountyEarnings',
 'fuelSpent','suppliesSpent','dockFees','jobsStarted'}
local function snapshot()
 local E=require('src.economy');local Stock=require('src.stockpile');local Markets=require('src.markets')
 local Loc=require('src.locations');local Fields=require('src.fields');local I=require('src.industry')
 local C=require('src.commodities')
 for id,r in pairs(u.npcs or {}) do
  local rec={npc=id,role=r.populationGroup,hull=r.ship and r.ship.hull,hold=hold(r),credits=math.floor(r.credits or 0),
   task=r.task and r.task.kind or nil,status=r.taskStatus,state=r.state,area=r.area,node=r.node}
  for _,k in ipairs(COUNTERS) do if r[k] then rec[k]=math.floor(r[k]) end end
  rec.cargo=(cargoOf(r))
  emit('npc',rec)
 end
 local goods=E.goods()
 for _,area in ipairs(Fields.list) do for _,st in ipairs(Loc.stations(area,'trade')) do
  local rows={}
  for _,item in ipairs(goods) do
   local n=Stock.count(u,st,item);local tg=E.target(u,st,item) or 0
   if n>0 or tg>0 then rows[item]={n,tg,math.floor(Markets.price(u,st,item)+.5)} end
  end
  emit('stock',{station=st,area=area,goods=rows})
  for id,inst in pairs(I.installations(st)) do
   local def=I.definition(id,inst)
   local state=I.state(u,st,id);local status={}
   for _,recipe in ipairs(def.recipes or {}) do
    local c=C.byId[recipe]
    if c then local ok,s=pcall(I.status,u,st,id,c);status[recipe]=ok and s or nil end
   end
   emit('plant',{station=st,facility=id,policy=def.policy,capacity=inst.capacity,mix=state and state.mix,status=status})
  end
 end end
 emit('counts',{history=counted})
 counted={}
end

-- Each game minute: orders that left the board untaken, and snapshots.
function L.minute()
 if not file then return end
 local offers=require('src.tasks').state(u).offers
 for id,o in pairs(live) do
  if not offers[id] then emit('gone',{id=id,item=o.item,n=o.n,age=math.floor(now()-o.t)});live[id]=nil end
 end
 if now()-lastSnap>=LOG_EVERY then lastSnap=now();snapshot() end
 file:flush()
end
function L.finish()
 if not file then return end
 snapshot();emit('end',{clock=u.clock})
 file:close();file=nil
end
return L
