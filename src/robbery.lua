-- Robbery: one mechanic for NPC and player victims alike.
-- A pirate that picks a civilian (or the player) as its target first
-- broadcasts a demand and holds fire. It then watches what the target
-- jettisons (the ordinary eject, for the player and NPCs both). Enough
-- cargo out before the deadline and the pirate spares the target and
-- collects it; otherwise it opens fire. A ship with no trade goods isn't
-- worth robbing and is left alone. Offline, encounters.lua resolves the
-- same outcome as an instant handover.
local T=require('src.tuning')
local data=require('src.data')
local Handover=require('src.handover')
local R={}
local function Comms() return require('src.comms') end

-- Trade goods: everything but ammunition and reactor fuel.
local function goods(e)
 local fuel=require('src.reactor_fuel').item()
 local n,list=0,{}
 for id,count in pairs(e.cargo or {}) do
  local item=data.items[id]
  if count>0 and item and not item.shot and id~=fuel then n=n+count;list[#list+1]=id end
 end
 table.sort(list)
 return n,list
end
R.goods=goods

local function name(e) return (e.def and e.def.name or 'PIRATE'):upper() end

-- To the player: a notification (src/notify.lua), one per demand, that
-- updates in place as the countdown runs and the outcome comes in.
local function announce(game,pirate,target,text,title)
 if not target.isPlayer then return end
 local who=pirate.def and pirate.def.name or 'Pirate'
 require('src.notify').post(game.universe,{kind='robbery',title=title or (who..' demand'),text=text,
  key='robbery:'..tostring(pirate.alifeId or pirate)})
end

local function isGood(id)
 local item=data.items[id]
 return item and not item.shot and id~=require('src.reactor_fuel').item() or false
end
local function demandOf(pirate)
 local d=pirate.request
 return d and d.kind=='robbery' and not d.closed and d or nil
end
-- Is pirate still waiting on target's answer (so holds fire)?
function R.pending(pirate)
 local d=demandOf(pirate)
 return d and not d.refused and not Handover.gone(d.giver) or false
end

-- The pirate has (re)chosen target; returns true if it should still shoot it.
function R.consider(game,pirate,target)
 if not target or target.dead then return true end
 local civilian=target.isPlayer or require('src.security').prey(target)
 if not civilian then return true end
 pirate.spared=pirate.spared or setmetatable({},{__mode='k'})
 local d=demandOf(pirate)
 if d and d.giver==target then
  if d.refused then return true end
  if Handover.met(d) or goods(target)==0 then
   pirate.spared[target]=game.time+T.robberySpare
   Handover.close(d)
   require('src.alife_trace').entity(game,pirate,'robbery',('paid %d by %s -> spared'):format(d.paid,tostring(target.alifeId or 'player')))
   pirate.combatTarget,pirate.lock=nil,nil
   announce(game,pirate,target,'"Wise choice. Move along."','Robbed: '..d.paid..' cargo taken')
   Comms().go(d.channel,'paid')
   local wc=pirate.alifeId and game.universe.npcs[pirate.alifeId]
   if wc and wc.wildcat then require('src.wildcats').harm(game.universe,wc) end
   return false
  end
  if Handover.expired(game,d) then
   d.refused=true
   require('src.alife_trace').entity(game,pirate,'robbery',tostring(target.alifeId or 'player')..' did not pay -> attack')
   announce(game,pirate,target,'"You were warned." They\'re opening fire.','Robbery refused')
   if d.channel and d.channel.node~='refused' then Comms().go(d.channel,'refused') end
   return true
  end
  return false
 end
 if d then Comms().close(d.channel,'retargeted');Handover.close(d) end
 local have=goods(target)
 if have==0 then pirate.spared[target]=game.time+T.robberySpare;return false end
 if target.asked then return true end   -- already handing something over to someone
 d=Handover.open(game,'robbery',pirate,target,math.max(1,math.ceil(have*T.robberyShare)),T.robberyWindow,isGood)
 d.channel=Comms().open(game,'robbery',pirate,target,{request=d,amount=d.amount})
 require('src.alife_trace').entity(game,pirate,'robbery',('demanded %d from %s'):format(d.amount,tostring(target.alifeId or 'player')))
 require('src.alife_trace').entity(game,target,'robbery',('%s demanded %d cargo'):format(tostring(pirate.alifeId),d.amount))
 return false
end

function R.isSpared(game,pirate,o)
 local t=pirate.spared and pirate.spared[o]
 return t and game.time<t or false
end

-- The player (or an NPC) hands over what's still owed.
function R.pay(game,giver,d)
 local _,list=goods(giver)
 return Handover.give(game,giver,list,math.max(0,d.amount-d.paid))
end
-- Haggling: a chance to cut the demand; failing halves the time left.
function R.haggle(game,d)
 if math.random()<T.robberyHaggle then
  d.amount=math.max(d.paid+1,math.ceil(d.amount*T.robberyHaggleCut))
  return true
 end
 d.deadline=game.time+(d.deadline-game.time)*.5
 return false
end

-- An NPC victim's answer, decided once per demand by the offline rule's
-- odds (with any covering station's guns on its side). Returns the robbery
-- script's option: 1 jettison, or the last (refuse).
function R.npcAnswer(game,e,d)
 if not d or d.closed or d.answered or Handover.gone(d.asker) then return end
 local pirate=d.asker
 d.answered=true
 local E=require('src.encounters')
 local mine=game.universe.npcs[e.alifeId];local theirs=game.universe.npcs[pirate.alifeId]
 local odds=.5
 if mine and theirs then
  mine.ship.armor=e.armor;theirs.ship.armor=pirate.armor
  local _,guns=E.coveringStation(mine,theirs,game.universe.clock)
  odds=E.odds(mine,theirs,guns*T.offlineStationAccuracy)
 end
 if odds>=require('src.personality').engageOdds(mine) then
  require('src.alife_trace').entity(game,e,'robbery',('odds %.0f%% -> refuse and fight'):format(odds*100))
  return #require('src.comms').options(d.channel)
 end
 require('src.alife_trace').entity(game,e,'robbery',('odds %.0f%% -> comply'):format(odds*100))
 if mine then mine.taskStatus='robbed by pirates' end
 return 1
end
-- Kept for the AI's call (src/ai.lua): the comms channel answers for NPCs
-- now; a demand without one (shouldn't happen) still gets the old answer.
function R.respond(game,e)
 local d=e.asked
 if not d or d.kind~='robbery' or d.closed or d.answered or d.channel then return end
 local pick=R.npcAnswer(game,e,d)
 if pick==1 then R.pay(game,e,d) elseif pick then e.aggressor=d.asker end
end

return R
