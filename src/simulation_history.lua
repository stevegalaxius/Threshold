-- Saved observations, not an event-sourced world. Gameplay remains authoritative.
local copy=require('src.persistence').copy
local T=require('src.tuning')
local events=require('src.events')
local H={}
function H.state(u)
 u.simulationHistory=u.simulationHistory or {entries={},fights={},nextId=0,nextFightId=0}
 return u.simulationHistory
end
-- Short logs kept beside the global one: the last few things each record
-- did (r.log) and the last few things that happened at each node, for
-- quests and random events to query (H.recent).
local RECORD_LOG,NODE_LOG=5,20
local function push(list,item,limit)
 list[#list+1]=item
 while #list>limit do table.remove(list,1) end
end
local function append(u,kind,clock,area,participants,result,fightId,node)
 local s=H.state(u);s.nextId=s.nextId+1
 local entry={id='outcome/'..s.nextId,kind=kind,clock=clock,area=area,node=node,
  participants=copy(participants),result=copy(result or {}),fightId=fightId}
 s.entries[#s.entries+1]=entry
 while #s.entries>T.historyLimit do table.remove(s.entries,1) end
 local brief={id=entry.id,kind=kind,clock=clock,area=area,node=node}
 for _,id in ipairs(participants) do
  local r=u.npcs and u.npcs[id]
  if r then r.lastOutcomeId=entry.id;r.log=r.log or {};push(r.log,brief,RECORD_LOG) end
 end
 if node then
  s.nodes=s.nodes or {};s.nodes[node]=s.nodes[node] or {}
  push(s.nodes[node],entry,NODE_LOG)
 end
 -- Listeners receive a copy so they cannot mutate the saved observation.
 events.emit('simulation_outcome',copy(entry))
 return entry
end
-- Record anything that happened in the world (for quests, random events
-- and reputation). kind is a short verb; participants are record ids or
-- 'player'; node is where, when known.
function H.note(u,kind,clock,area,participants,result,node)
 return append(u,kind,clock,area,participants,result,nil,node)
end
-- Recent entries matching a filter: { kind=, node=, area=, participant=,
-- since= (clock) }, newest first, at most limit (default 20).
function H.recent(u,filter,limit)
 filter=filter or {};limit=limit or 20
 local s=H.state(u);local out={}
 local list=filter.node and (s.nodes and s.nodes[filter.node] or {}) or s.entries
 for i=#list,1,-1 do
  local e=list[i]
  if filter.since and e.clock<filter.since then break end
  local ok=(not filter.kind or e.kind==filter.kind) and (not filter.area or e.area==filter.area)
  if ok and filter.participant then
   ok=false;for _,id in ipairs(e.participants) do if id==filter.participant then ok=true end end
  end
  if ok then out[#out+1]=copy(e);if #out>=limit then break end end
 end
 return out
end
local function key(a,b) if a>b then a,b=b,a end return a..'|'..b,a,b end
function H.fuelCondition(u,r,clock,previous,status,fuel,power)
 return append(u,'fuel_condition_changed',clock,r.area,{r.id},
  {from=previous,to=status,fuelEnergy=fuel,power=power})
end
local function nodeOf(u,a,b)
 local r=u.npcs and (u.npcs[a] or u.npcs[b])
 return r and r.node
end
-- a: whoever was hit (or is fighting), b: whoever started it, when known
function H.begin(u,a,b,clock,area,aggressor)
 if not a or not b or a==b then return end
 local k,x,y=key(a,b);local s=H.state(u)
 local fight=s.fights[k]
 if not fight then
  s.nextFightId=s.nextFightId+1
  fight={id='fight/'..s.nextFightId,participants={x,y},clock=clock,area=area,lastActive=clock,
   aggressor=aggressor,node=nodeOf(u,a,b)}
  s.fights[k]=fight
  append(u,'combat_started',clock,area,fight.participants,{aggressor=aggressor},fight.id,fight.node)
 end
 fight.lastActive=clock
 return fight
end
function H.finish(u,a,b,clock,reason,fled)
 if not a or not b then return end
 local k=key(a,b);local s=H.state(u);local fight=s.fights[k]
 if not fight then return end
 local result={reason=reason or 'disengaged',dead={},fled={},wrecks={},aggressor=fight.aggressor}
 for _,id in ipairs(fight.participants) do
  local r=u.npcs and u.npcs[id]
  if r and (r.state=='dead' or r.deathOutcomeId) or fight.dead and fight.dead[id] then
   result.dead[#result.dead+1]=id
   if r and r.historyWreckId then result.wrecks[#result.wrecks+1]=r.historyWreckId end
  end
  if id==fled then result.fled[#result.fled+1]=id end
 end
 s.fights[k]=nil
 local entry=append(u,'combat_ended',clock,fight.area,fight.participants,result,fight.id,fight.node)
 -- a pirate killed while it had someone else in its sights: they were rescued
 for _,dead in ipairs(result.dead) do
  local r=u.npcs and u.npcs[dead]
  if r and r.role=='pirate' then
   local killer=r.deathKiller
   for k2,other in pairs(s.fights) do
    local victim=other.participants[1]==dead and other.participants[2] or other.participants[2]==dead and other.participants[1]
    if victim and victim~=killer then
     append(u,'rescued',clock,fight.area,{victim,killer or dead},{pirate=dead,rescuer=killer},nil,fight.node)
    end
   end
  end
 end
 for _,id in ipairs(fight.participants) do
  local r=u.npcs and u.npcs[id]
  if r then r.fight_log=copy(entry) end
 end
 return entry
end
function H.death(u,r,clock,area,killer)
 if r.deathOutcomeId then return end
 r.deathKiller=killer
 local entry=append(u,'npc_died',clock,area,{r.id},{killer=killer},nil,r.node)
 r.deathOutcomeId=entry.id
 return entry
end
function H.wreck(u,r,clock,area)
 if r.historyWreckId then return r.historyWreckId end
 -- A record has one life. The same reference follows its abstract and real wreck.
 r.historyWreckId='wreck/'..r.id
 append(u,'wreck_created',clock,area,{r.id},{wreckId=r.historyWreckId})
 return r.historyWreckId
end
function H.entityId(e) return e and (e.alifeId or e.isPlayer and 'player') end
function H.hit(game,victim,source)
 local a,b=H.entityId(victim),H.entityId(source)
 if a and b and (a~='player' or b~='player') then
  H.begin(game.universe,a,b,game.universe.clock,game.fieldId,b)
 end
end

-- Comings and goings, seen from the records themselves so online and
-- offline ships report the same way: whatever set r.state, the change is
-- noticed here (about twice a second) and written down once.
local OBSERVE=0.5
function H.observe(u,clock)
 local s=H.state(u)
 if s.observedAt and clock-s.observedAt<OBSERVE and clock>=s.observedAt then return end
 s.observedAt=clock
 for id,r in pairs(u.npcs or {}) do
  local seen=r.seen
  local now={state=r.state,area=r.area,node=r.node}
  if seen and r.state~='dead' and r.state~='escaped' then
   if seen.state=='docked' and r.state~='docked' then
    append(u,'undocked',clock,seen.area,{id},{role=r.role},nil,seen.node)
   elseif seen.state~='docked' and r.state=='docked' then
    append(u,'docked',clock,r.area,{id},{role=r.role},nil,r.node)
   end
   if seen.area and not r.area then
    append(u,'left_area',clock,seen.area,{id},{role=r.role},nil,seen.node)
   elseif r.area and seen.area~=r.area then
    append(u,'arrived',clock,r.area,{id},{role=r.role,from=seen.area},nil,r.node)
   end
  end
  r.seen=now
 end
end
-- Observe physical AI without steering it. A quiet interval ends an engagement;
-- removing a body for distance or saving is not itself an outcome.
function H.update(game)
 local u=game.universe;local clock=u.clock;local online=game.alifeOnline or {}
 H.observe(u,clock)
 for id,e in pairs(online) do
  if not e.dead and not e.removed then
   local target=e.combatTarget or e.aggressor
   local other=H.entityId(target)
   if other and not target.dead and not target.removed and not target.fleeing and not e.fleeing then
    H.begin(u,id,other,clock,game.fieldId)
   end
  end
 end
 local keys={};for k in pairs(H.state(u).fights) do keys[#keys+1]=k end;table.sort(keys)
 for _,k in ipairs(keys) do
  local f=H.state(u).fights[k];local a,b=unpack(f.participants)
  local reason,pendingDeath,abstract
  for _,id in ipairs(f.participants) do
   local r=u.npcs and u.npcs[id];local e=id=='player' and game.player or online[id]
   -- Reaping records death and salvage before the fight summary is closed.
   if r and r.deathOutcomeId then reason='death'
   elseif r and r.state=='dead' then pendingDeath=true end
   if id=='player' and e and e.dead then
    reason='death';f.dead=f.dead or {};f.dead[id]=true
   end
   if e and e.fleeing then f.fled=id end
   if r and r.encounter then abstract=true end
  end
  if reason and not pendingDeath then H.finish(u,a,b,clock,reason,f.fled)
  elseif not pendingDeath and not abstract and clock-f.lastActive>=T.historyQuietTime then
   H.finish(u,a,b,clock,f.fled and 'retreated' or 'disengaged',f.fled)
  end
 end
end
function H.panel(game,Slab)
 local s=H.state(game.universe)
 Slab.Text(('Recent outcomes: %d / %d'):format(#s.entries,T.historyLimit))
 for i=#s.entries,math.max(1,#s.entries-39),-1 do
  local e=s.entries[i]
  Slab.Text(('%s  %.1fs  %s'):format(e.id,e.clock,e.kind))
  Slab.Text(('  %s / %s'):format(e.area or 'transit',table.concat(e.participants,', ')))
  if e.node then Slab.Text('  at '..e.node) end
  if e.fightId then Slab.Text('  '..e.fightId..' '..(e.result.reason or '')..(e.result.aggressor and (' started by '..e.result.aggressor) or '')) end
  if e.kind=='rescued' then Slab.Text('  from '..tostring(e.result.pirate)..' by '..tostring(e.result.rescuer)) end
  if e.result.wreckId then Slab.Text('  '..e.result.wreckId) end
  if e.kind=='fuel_condition_changed' then Slab.Text('  '..e.result.from..' -> '..e.result.to) end
  if #((e.result or {}).dead or {})>0 then Slab.Text('  Dead: '..table.concat(e.result.dead,', ')) end
  if #((e.result or {}).fled or {})>0 then Slab.Text('  Fled: '..table.concat(e.result.fled,', ')) end
 end
end
return H
