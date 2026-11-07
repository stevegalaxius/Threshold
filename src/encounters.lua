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
local Fuel=require('src.reactor_fuel')
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
 return active(r) and (r.retreatUntil or 0)<=clock and r.ship.armor>maxArmor(r)*E.breakPoint(r)
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
function E.finish(u,a,b,clock,retreat,handoff,outcome)
 if not handoff and a and b then
  local reason=outcome or retreat and 'retreated' or (a.state=='dead' or b.state=='dead') and 'death' or 'disengaged'
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
-- The offline combat rule. One simplified model, meant as the target online
-- behaviour adheres to as well:
--  * a side's strength is sustained DPS x effective HP; agility is
--    acceleration (thrust / mass)
--  * pirates only attack when the odds favour them; faster prey may outrun
--    them before a shot is fired
--  * each round, hit chance depends on the shooter's agility against the
--    target's; lasers draw on power that recharges from the reactor
--  * a side breaks at its morale threshold: civilians surrender cargo,
--    pirates take it home, anyone else withdraws. Kills happen only when
--    a side is wrecked before it breaks.
local CIVILIAN={trader=true,courier=true,miner=true,salvager=true}
E.civilian=CIVILIAN
local function cargoOf(r)
 local hold=r.ship.hold and Hold.deserialize(r.ship.hold,function(id)return data.items[id]~=nil end)
 return hold,hold and Hold.totals(hold) or r.ship.cargo or {}
end
function E.profile(r)
 local hull=data.hulls[r.ship.hull]
 local st=Stats.compute(hull,r.ship.loadout)
 local _,cargo=cargoOf(r)
 local dps=0
 for _,id in pairs(r.ship.loadout) do
  local m=id and data.modules[id];local w=m and m.weapon
  if w and w.kind~='drone' then
   local rate=w.fireRate or 1;local hit=w.damage or 0
   if w.kind~='laser' then
    local ammo=data.ammoFor(m)
    if (cargo[ammo] or 0)>0 then hit=data.items[ammo].shot.damage else rate=0 end
   else
    local cost=w.powerPerShot or w.powerPerSecond or 0
    if cost>0 then rate=math.min(rate,math.max(0,st.powerNet or st.powerOut or 0)/cost) end
   end
   dps=dps+rate*hit
  end
 end
 if Fuel.condition(r)=='stranded' then dps=0 end
 local agility=(st.thrust or 0)/math.max(1,st.mass)
 return {dps=dps,hp=math.max(0,r.ship.armor),maxHp=math.max(1,st.armor),agility=agility,powerCap=st.powerCap,powerNet=st.powerNet or 0}
end
local function strength(p) return p.dps*p.hp end
-- Chance that a's side wins a straight fight against b's.
function E.odds(a,b,support)
 local pa,pb=E.profile(a),E.profile(b)
 local sa,sb=strength(pa),(pb.dps+(support or 0))*pb.hp
 if sa+sb<=0 then return .5 end
 return sa/(sa+sb)
end
function E.hitChance(attacker,target)
 local t=attacker.agility+target.agility
 return 0.3+0.5*(t>0 and attacker.agility/t or .5)
end
-- Morale: the armour fraction at which a side breaks off.
function E.breakPoint(r)
 return CIVILIAN[r.role] and T.offlineCivilianBreak or r.role=='pirate' and T.offlinePirateBreak or T.offlinePatrolBreak
end
-- Damage one side deals in a round. Spends real ammunition (carried back
-- into physical combat) and recharges laser power.
function E.damage(r,seconds,roll,target)
 if Fuel.condition(r)=='stranded' then return 0 end
 local me=E.profile(r)
 local hold,cargo=cargoOf(r)
 local st=Stats.compute(data.hulls[r.ship.hull],r.ship.loadout)
 r.power=math.min(st.powerCap,(r.power or st.powerCap)+math.max(0,st.powerNet or 0)*seconds)
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
   else
    local cost=w.powerPerShot or w.powerPerSecond or 0
    if cost>0 then shots=math.min(shots,math.floor(r.power/cost));r.power=r.power-shots*cost end
   end
   damage=damage+shots*hit
  end
 end
 if hold then Hold.sync(hold,cargo);r.ship.hold=Hold.serialize(hold) end
 r.ship.cargo=cargo
 local accuracy=target and E.hitChance(me,E.profile(target)) or .55
 return damage*accuracy*(.75+.5*roll)*T.offlineCombatHit*T.enemyDamage
end
-- A surrendering civilian hands its trade goods (not ammo or fuel) to the pirate.
local function surrender(game,pirate,victim)
 local vh,vc=cargoOf(victim);local ph,pc=cargoOf(pirate)
 local taken=0
 for id,n in pairs(vc) do
  local item=data.items[id]
  if n>0 and item and not item.shot and id~=Fuel.item() then
   local k=math.max(1,math.ceil(n*T.robberyShare))
   if ph then k=Hold.add(ph,id,n) else pc[id]=(pc[id] or 0)+n end
   if k>0 then
    if vh then Hold.take(vh,id,k) end
    vc[id]=n-k;if vc[id]<=0 then vc[id]=nil end
    pirate.stolenCargo=pirate.stolenCargo or {};pirate.stolenCargo[id]=(pirate.stolenCargo[id] or 0)+k
    taken=taken+k
   end
  end
 end
 if vh then victim.ship.hold=Hold.serialize(vh);vc=Hold.totals(vh) end
 victim.ship.cargo=vc
 if ph then pirate.ship.hold=Hold.serialize(ph);pc=Hold.totals(ph) end
 pirate.ship.cargo=pc
 return taken
end
E.surrender=surrender
-- Stations defend the space around them (as online, they only answer
-- aggression, so only fights already under way). Damage per second of a
-- station's turrets, endless ammo; 0 for none.
local stationDps={}
function E.stationDps(node)
 local id=node and L.canonical(node)
 if not id or not L.byId[id] or L.get(id).kind~='station' then return 0 end
 if stationDps[id] then return stationDps[id] end
 local ok,def=pcall(L.stationDefinition,id);local dps=0
 for _,t in ipairs(ok and def.turrets or {}) do
  local m=data.modules[t.module];local w=m and m.weapon
  if w and w.kind~='drone' then
   local hit=w.damage or 0
   if w.kind~='laser' then local ammo=data.ammoFor(m);hit=ammo and data.items[ammo] and data.items[ammo].shot.damage or hit end
   dps=dps+(w.fireRate or 1)*hit
  end
 end
 stationDps[id]=dps
 return dps
end
-- The guns covering a fight: the station at the node either side is near.
local function coveringStation(a,b,clock)
 local _,_,an=segment(a,clock);local _,_,bn=segment(b,clock)
 local node=E.stationDps(an)>0 and an or E.stationDps(bn)>0 and bn or nil
 return node,node and E.stationDps(node) or 0
end
E.coveringStation=coveringStation
local function wreck(u,r,clock)
 local fight=r.encounter
 u.alifeWrecks=u.alifeWrecks or {}
 u.alifeWrecks[r.id]={id=r.id,role=r.role,area=r.area,from=r.route[(r.index-2)%#r.route+1],to=r.route[r.index],
  progress=fight and fight.progress or fraction(r,clock),clock=clock,expires=clock+T.alifeWreckLifetime,
  ship=copy(r.ship),archetype=r.archetype}
 r.state='dead';r.ship.armor=0
 require('src.alife_trace').note(r,clock,'encounter','destroyed'..(fight and (' by '..fight.target) or ''))
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
   local da=E.damage(a,T.offlineCombatTick,random(fight),b)
   local db=E.damage(b,T.offlineCombatTick,random(fight),a)
   -- a covering station fires on the pirate side
   local _,guns=coveringStation(a,b,clock)
   if guns>0 then
    local roll=random(fight)
    local shot=guns*T.offlineCombatTick*T.offlineStationAccuracy*(.75+.5*roll)*T.offlineCombatHit
    if a.role=='pirate' and b.role~='pirate' then db=db+shot elseif b.role=='pirate' and a.role~='pirate' then da=da+shot end
   end
   a.ship.armor=math.max(0,a.ship.armor-db);b.ship.armor=math.max(0,b.ship.armor-da)
   fight.round=fight.round+1;fight.nextAt=clock+T.offlineCombatTick
   b.encounter.round=fight.round;b.encounter.nextAt=fight.nextAt
   if a.ship.armor<=0 then wreck(u,a,clock) end
   if b.ship.armor<=0 then wreck(u,b,clock) end
   if not active(a) or not active(b) then E.finish(u,a,b,clock)
   else
    local fa,fb=a.ship.armor/maxArmor(a),b.ship.armor/maxArmor(b)
    local brokeA,brokeB=fa<=E.breakPoint(a),fb<=E.breakPoint(b)
    if brokeA or brokeB or fight.round>=T.offlineCombatRounds then
     -- the side further past its breaking point gives way
     local loser=(fa-E.breakPoint(a))<(fb-E.breakPoint(b)) and a or b
     local winner=loser==a and b or a
     if CIVILIAN[loser.role] and winner.role=='pirate' then
      surrender(game,winner,loser)
      require('src.alife_trace').note(loser,clock,'encounter','broke, surrendered cargo to '..winner.id)
      require('src.alife_trace').note(winner,clock,'encounter','robbed '..loser.id..' -> heading home')
      E.finish(u,a,b,clock,nil,nil,'surrendered')
      loser.retreatUntil=clock+T.offlineRetreat;loser.taskStatus='robbed by pirates'
      require('src.piracy').returnRecord(game,winner)
     else
      E.finish(u,a,b,clock,loser)
      require('src.alife_trace').note(loser,clock,'encounter','broke off vs '..winner.id)
     end
    end
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
   if a.role=='pirate' and not a.encounter and not a.piracy and Fuel.condition(a)~='stranded'
    and (a.offlineEyed or {})[1]~=math.floor(clock/T.offlineEngageWindow) then
    -- pick the softest prey in reach; patrols only if nothing else
    local target,best
    for _,b in ipairs(group) do
     if (CIVILIAN[b.role] or b.role=='patrol') and not b.encounter and close(a,b,clock) then
      local odds=E.odds(a,b)-(b.role=='patrol' and 1 or 0)
      if not best or odds>best then target,best=b,odds end
     end
    end
    -- a station's guns count on the target's side
    local guns=0
    if target then guns=select(2,coveringStation(a,target,clock)) end
    local odds=target and E.odds(a,target,guns*T.offlineStationAccuracy)
    if target then require('src.alife_trace').note(a,clock,'encounter',('sized up %s: odds %.0f%%%s'):format(target.id,odds*100,guns>0 and ' (under station guns)' or '')) end
    if target and odds>=T.offlineEngageOdds then
     local pa,pb=E.profile(a),E.profile(target)
     local fight=a.id..target.id..math.floor(clock/T.offlineEngageWindow)
     local roll=random({seed=(#fight*7919+math.floor(clock))%2147483647})
     local escape=pb.agility>pa.agility and math.min(T.offlineEscapeMax,(pb.agility/math.max(1e-6,pa.agility)-1)*T.offlineEscapeGain) or 0
     History.begin(u,a.id,target.id,clock,a.area)
     if roll<escape then
      require('src.alife_trace').note(target,clock,'encounter','outran '..a.id)
      -- outran: no shots fired; the pirate won't try this pair again this window
      a.offlineEyed={math.floor(clock/T.offlineEngageWindow)}
      E.finish(u,a,target,clock,nil,nil,'evaded')
     else begin(a,target,clock)
      require('src.alife_trace').note(a,clock,'encounter','attacked '..target.id)
      require('src.alife_trace').note(target,clock,'encounter','attacked by '..a.id) end
    elseif target then a.offlineEyed={math.floor(clock/T.offlineEngageWindow)} end
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
   -- Each side marks the other as its aggressor: hostility checks always
   -- honour an aggressor, so the fight carries on onscreen instead of the
   -- next target scan quietly dropping it.
   local other=game.universe.npcs[r.encounter.target]
   e.aggressor=target;target.aggressor=e
   if r.role~='trader' then e.combatTarget=target;e.securityThink=game.time+T.securityThink end
   if other.role~='trader' then target.combatTarget=e;target.securityThink=game.time+T.securityThink end
   -- Once both bodies exist, ordinary AI owns the encounter completely.
   -- Do not leave frozen graph duties behind after a physical disengagement.
   History.begin(game.universe,r.id,other.id,game.universe.clock,r.area)
   E.finish(game.universe,r,other,game.universe.clock,nil,true)
  end
 end
end
function E.clearSpot(game,x,y,radius,seed)
 local a0=((tonumber(tostring(seed):match('%d+')) or 0)*2.3999632297)%(2*math.pi)
 for ring=0,6 do
  local d=ring*radius*1.5
  for k=0,ring==0 and 0 or 7 do
   local a=a0+k*math.pi/4
   local cx,cy=x+math.cos(a)*d,y+math.sin(a)*d
   local free=true
   for _,o in ipairs(game.entities) do
    if o.body and not o.removed and not o.dead and o.body.isDestroyed and not o.body:isDestroyed() then
     local ox,oy=o.body:getPosition();local r=(o.radius or o.halfLength or 50)+radius+40
     if (ox-cx)^2+(oy-cy)^2<r*r then free=false;break end
    end
   end
   if free then return cx,cy end
  end
 end
 return x,y
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
     fuelCharge=s.fuelCharge,fuelInitialized=true,
     color=copy(s.color),enemy=data.enemies[w.archetype]})
    -- Both sides of an offline fight wreck at the same point on the lane;
    -- spawned on top of each other (or of a rock), Box2D flings them apart.
    -- Step out to clear space first.
    x,y=E.clearSpot(game,x,y,ship.hull.radius or ship.halfLength or 60,id)
    local vx,vy=game:flowAt(x,y)
    if w.lootHold then ship.salvagedSlots=copy(w.salvagedSlots or {}) end
    local husk=game:spawnHusk(ship,x,y,math.atan2(vy,vx),vx,vy,0,w.lootHold and Hold.deserialize(w.lootHold))
    ship.body:destroy();husk.alifeWreckId=id;husk.historyWreckId=w.historyWreckId
    husk.origin=husk.origin or {};husk.origin.npc=w.npcId or id;husk.origin.role=w.role or husk.origin.role
    u.alifeWrecks[id]=nil
   end
  end
 end
end
return E
