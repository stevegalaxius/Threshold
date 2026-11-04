-- Offline encounters use graph segments and ship records, never remote bodies.
local Fields=require('src.fields')
local L=require('src.locations')
local G=require('src.travelgraph')
local data=require('src.data')
local Stats=require('src.stats')
local Hold=require('src.inventory.hold')
local Ship=require('src.ship')
local Tasks=require('src.tasks')
local copy=require('src.persistence').copy
local T=require('src.tuning')
local History=require('src.simulation_history')
local E={}
local function active(r)
 return r and (r.state=='travel' or r.state=='idle') and not r.driverState and r.area~=nil
end
local function fraction(r,clock)
 if r.encounter then return r.encounter.progress end
 return math.max(0,math.min(1,(clock-(r.depart or clock))/math.max(.01,(r.arrive or clock)-(r.depart or clock))))
end
local function segment(r,clock)
 local to=r.route[r.index]
 if r.state=='idle' then return 'node:'..to,0,to end
 local from=r.route[(r.index-2)%#r.route+1]
 local p=fraction(r,clock)
 local key=from<to and from..'>'..to or to..'>'..from
 return key,from<to and p or 1-p,p<T.offlineCombatSegment and from or p>1-T.offlineCombatSegment and to or nil
end
local function close(a,b,clock)
 if a.area~=b.area then return false end
 local ak,ap,an=segment(a,clock);local bk,bp,bn=segment(b,clock)
 return ak==bk and math.abs(ap-bp)<=T.offlineCombatSegment or an and an==bn
end
local function maxArmor(r) return Stats.compute(data.hulls[r.ship.hull],r.ship.loadout).armor end
local function fit(r,clock)
 return active(r) and (r.retreatUntil or 0)<=clock and r.ship.armor>maxArmor(r)*.2
end
local function resume(r,clock)
 local fight=r.encounter
 if not fight then return end
 if r.state=='travel' then
  local duration=math.max(.1,r.arrive-r.depart)
  r.depart=clock-fight.progress*duration;r.arrive=r.depart+duration
 elseif r.state=='idle' then r.untilTime=math.max(r.untilTime or clock,clock+1) end
 r.encounter=nil;r.targetId=nil
end
function E.finish(u,a,b,clock,retreat,handoff)
 if not handoff and a and b then
  local reason=retreat and 'retreated' or (a.state=='dead' or b.state=='dead') and 'death' or 'disengaged'
  History.finish(u,a.id,b.id,clock,reason,retreat and retreat.id)
 end
 resume(a,clock)
 if b then resume(b,clock) end
 if retreat then retreat.retreatUntil=clock+T.offlineRetreat;retreat.taskStatus='withdrawing after combat' end
end
local function begin(a,b,clock)
 local seed=((tonumber(a.id:match('%d+$')) or 1)*104729+(tonumber(b.id:match('%d+$')) or 2)*7919+math.floor(clock))%2147483647
 a.encounter={target=b.id,progress=fraction(a,clock),nextAt=clock+T.offlineCombatTick,round=0,seed=seed}
 b.encounter={target=a.id,progress=fraction(b,clock),nextAt=clock+T.offlineCombatTick,round=0,seed=seed}
 a.targetId,b.targetId=b.id,a.id
end
function E.begin(a,b,clock) begin(a,b,clock) end
local function random(fight)
 fight.seed=((fight.seed or 7193)*48271)%2147483647
 return fight.seed/2147483647
end
-- Spend real ammunition and carry that inventory back into physical combat.
function E.damage(r,seconds,roll)
 local hold=r.ship.hold and Hold.deserialize(r.ship.hold,function(id)return data.items[id]~=nil end)
 local cargo=hold and Hold.totals(hold) or r.ship.cargo or {}
 local damage=0
 for _,id in pairs(r.ship.loadout) do
  local m=id and data.modules[id];local w=m and m.weapon
  if w and w.kind~='drone' then
   local shots=math.max(1,math.floor((w.fireRate or 1)*seconds))
   local hit=w.damage or 0
   if w.kind~='laser' then
    local ammo=data.ammoFor(m)
    shots=math.min(shots,cargo[ammo] or 0)
    if shots>0 then cargo[ammo]=cargo[ammo]-shots;hit=data.items[ammo].shot.damage end
   elseif Stats.compute(data.hulls[r.ship.hull],r.ship.loadout).powerNet<=0 then shots=0 end
   damage=damage+shots*hit
  end
 end
 if hold then Hold.sync(hold,cargo);r.ship.hold=Hold.serialize(hold) end
 r.ship.cargo=cargo
 local health=math.max(.1,r.ship.armor/maxArmor(r))
 return damage*T.offlineCombatHit*(.5+roll)*math.sqrt(health)*T.enemyDamage
end
local function wreck(u,r,clock)
 local fight=r.encounter
 u.alifeWrecks=u.alifeWrecks or {}
 u.alifeWrecks[r.id]={id=r.id,area=r.area,from=r.route[(r.index-2)%#r.route+1],to=r.route[r.index],
  progress=fight and fight.progress or fraction(r,clock),clock=clock,expires=clock+T.alifeWreckLifetime,
  ship=copy(r.ship),archetype=r.archetype}
 r.state='dead';r.ship.armor=0
 History.death(u,r,clock,r.area,fight and fight.target)
 u.alifeWrecks[r.id].historyWreckId=History.wreck(u,r,clock,r.area)
 Tasks.release(u,r,'destroyed',clock)
end
function E.update(game,clock)
 local u=game.universe
 if clock<(u.encounterNext or 0) then return end
 u.encounterNext=clock+T.offlineCombatTick
 local records=u.npcs;local online=game.alifeOnline or {}
 local ids={};for id in pairs(records) do ids[#ids+1]=id end;table.sort(ids)
 -- End stale fights first. A live counterpart is excluded from dice damage.
 for _,id in ipairs(ids) do
  local a=records[id];local b=a.encounter and records[a.encounter.target]
  if a.encounter and b then History.begin(u,a.id,b.id,clock,a.area) end
  if a.encounter and (not active(a) or not active(b) or a.area~=b.area) then E.finish(u,a,b,clock) end
 end
 for _,id in ipairs(ids) do
  local a=records[id];local b=a.encounter and records[a.encounter.target]
  if b and a.id<b.id and not online[a.id] and not online[b.id] and clock>=a.encounter.nextAt then
   local fight=a.encounter
   -- Simultaneous exchange: neither side loses its shot to iteration order.
   local da=E.damage(a,T.offlineCombatTick,random(fight))
   local db=E.damage(b,T.offlineCombatTick,random(fight))
   a.ship.armor=math.max(0,a.ship.armor-db);b.ship.armor=math.max(0,b.ship.armor-da)
   fight.round=fight.round+1;fight.nextAt=clock+T.offlineCombatTick
   b.encounter.round=fight.round;b.encounter.nextAt=fight.nextAt
   if a.ship.armor<=0 then wreck(u,a,clock) end
   if b.ship.armor<=0 then wreck(u,b,clock) end
   if not active(a) or not active(b) then E.finish(u,a,b,clock)
   elseif not fit(a,clock) or not fit(b,clock) or fight.round>=T.offlineCombatRounds then
    E.finish(u,a,b,clock,a.ship.armor/maxArmor(a)<b.ship.armor/maxArmor(b) and a or b)
   end
  end
 end
 -- Group by area before considering same-edge encounters. No path poses,
 -- planets, stations or Box2D queries are needed for remote simulation.
 local areas={}
 for _,id in ipairs(ids) do
  local r=records[id]
  if fit(r,clock) and not r.encounter and not online[id] then
   local group=areas[r.area] or {};areas[r.area]=group;group[#group+1]=r
  end
 end
 for _,group in pairs(areas) do
  for _,a in ipairs(group) do
   if a.role=='pirate' and not a.encounter then
    local target
    for _,b in ipairs(group) do
     if (b.role=='trader' or b.role=='courier' or b.role=='miner' or b.role=='patrol') and not b.encounter and close(a,b,clock) then
      if not target or b.role=='patrol' and target.role~='patrol' then target=b end
     end
    end
    if target then begin(a,target,clock);History.begin(u,a.id,target.id,clock,a.area) end
   end
  end
 end
end
function E.syncOnline(game)
 local p=game.player
 for id,e in pairs(game.alifeOnline) do
  local r=game.universe.npcs[id]
  local other=r.encounter and game.universe.npcs[r.encounter.target]
  if p and not p.dead and active(other) and other.area==game.fieldId and not game.alifeOnline[other.id] then
   local A=require('src.alife')
   local x,y=A.point(other,game.universe.clock);local px,py=p.body:getPosition()
   if (x-px)^2+(y-py)^2<T.alifeFar^2 then A.wake(game,other) end
  end
 end
 for id,e in pairs(game.alifeOnline) do
  local r=game.universe.npcs[id]
  local target=r.encounter and game.alifeOnline[r.encounter.target]
  if target and not target.dead and not target.removed then
   if r.role=='trader' then e.aggressor=target else e.combatTarget=target;e.securityThink=game.time+T.securityThink end
   local other=game.universe.npcs[r.encounter.target]
   if other.role=='trader' then target.aggressor=e else target.combatTarget=e;target.securityThink=game.time+T.securityThink end
   -- Once both bodies exist, ordinary AI owns the encounter completely.
   -- Do not leave frozen graph duties behind after a physical disengagement.
   History.begin(game.universe,r.id,other.id,game.universe.clock,r.area)
   E.finish(game.universe,r,other,game.universe.clock,nil,true)
  end
 end
end
function E.materialize(game,px,py,clock)
 local u=game.universe
 for id,w in pairs(u.alifeWrecks or {}) do
  if clock>=w.expires then u.alifeWrecks[id]=nil
  elseif px and not game.lane and not game.flight and w.area==game.fieldId then
   local x,y=G.wreckPoint(w,clock)
   if (x-px)^2+(y-py)^2<T.alifeNear^2 then
    local s=w.ship
    local ship=Ship.new(game,{hull=s.hull,loadout=copy(s.loadout),cargo=copy(s.cargo),
     hold=s.hold and Hold.deserialize(s.hold,function(item)return data.items[item]~=nil end),
     color=copy(s.color),enemy=data.enemies[w.archetype]})
    local vx,vy=game:flowAt(x,y)
    if w.lootHold then ship.salvagedSlots=copy(w.salvagedSlots or {}) end
    local husk=game:spawnHusk(ship,x,y,math.atan2(vy,vx),vx,vy,0,w.lootHold and Hold.deserialize(w.lootHold))
    ship.body:destroy();husk.alifeWreckId=id;husk.historyWreckId=w.historyWreckId
    u.alifeWrecks[id]=nil
   end
  end
 end
end
return E
