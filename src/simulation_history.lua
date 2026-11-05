-- Saved observations, not an event-sourced world. Gameplay remains authoritative.
local copy=require('src.persistence').copy
local T=require('src.tuning')
local events=require('src.events')
local H={}
function H.state(u)
 u.simulationHistory=u.simulationHistory or {entries={},fights={},nextId=0,nextFightId=0}
 return u.simulationHistory
end
local function append(u,kind,clock,area,participants,result,fightId)
 local s=H.state(u);s.nextId=s.nextId+1
 local entry={id='outcome/'..s.nextId,kind=kind,clock=clock,area=area,
  participants=copy(participants),result=copy(result or {}),fightId=fightId}
 s.entries[#s.entries+1]=entry
 while #s.entries>T.historyLimit do table.remove(s.entries,1) end
 for _,id in ipairs(participants) do
  local r=u.npcs and u.npcs[id]
  if r then r.lastOutcomeId=entry.id end
 end
 -- Listeners receive a copy so they cannot mutate the saved observation.
 events.emit('simulation_outcome',copy(entry))
 return entry
end
local function key(a,b) if a>b then a,b=b,a end return a..'|'..b,a,b end
function H.fuelCondition(u,r,clock,previous,status,fuel,power)
 return append(u,'fuel_condition_changed',clock,r.area,{r.id},
  {from=previous,to=status,fuelEnergy=fuel,power=power})
end
function H.begin(u,a,b,clock,area)
 if not a or not b or a==b then return end
 local k,x,y=key(a,b);local s=H.state(u)
 local fight=s.fights[k]
 if not fight then
  s.nextFightId=s.nextFightId+1
  fight={id='fight/'..s.nextFightId,participants={x,y},clock=clock,area=area,lastActive=clock}
  s.fights[k]=fight
  append(u,'combat_started',clock,area,fight.participants,{},fight.id)
 end
 fight.lastActive=clock
 return fight
end
function H.finish(u,a,b,clock,reason,fled)
 if not a or not b then return end
 local k=key(a,b);local s=H.state(u);local fight=s.fights[k]
 if not fight then return end
 local result={reason=reason or 'disengaged',dead={},fled={},wrecks={}}
 for _,id in ipairs(fight.participants) do
  local r=u.npcs and u.npcs[id]
  if r and (r.state=='dead' or r.deathOutcomeId) or fight.dead and fight.dead[id] then
   result.dead[#result.dead+1]=id
   if r and r.historyWreckId then result.wrecks[#result.wrecks+1]=r.historyWreckId end
  end
  if id==fled then result.fled[#result.fled+1]=id end
 end
 s.fights[k]=nil
 local entry=append(u,'combat_ended',clock,fight.area,fight.participants,result,fight.id)
 for _,id in ipairs(fight.participants) do
  local r=u.npcs and u.npcs[id]
  if r then r.fight_log=copy(entry) end
 end
 return entry
end
function H.death(u,r,clock,area,killer)
 if r.deathOutcomeId then return end
 local entry=append(u,'npc_died',clock,area,{r.id},{killer=killer})
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
  H.begin(game.universe,a,b,game.universe.clock,game.fieldId)
 end
end
-- Observe physical AI without steering it. A quiet interval ends an engagement;
-- removing a body for distance or saving is not itself an outcome.
function H.update(game)
 local u=game.universe;local clock=u.clock;local online=game.alifeOnline or {}
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
  if e.fightId then Slab.Text('  '..e.fightId..' '..(e.result.reason or '')) end
  if e.result.wreckId then Slab.Text('  '..e.result.wreckId) end
  if e.kind=='fuel_condition_changed' then Slab.Text('  '..e.result.from..' -> '..e.result.to) end
  if #((e.result or {}).dead or {})>0 then Slab.Text('  Dead: '..table.concat(e.result.dead,', ')) end
  if #((e.result or {}).fled or {})>0 then Slab.Text('  Fled: '..table.concat(e.result.fled,', ')) end
 end
end
return H
