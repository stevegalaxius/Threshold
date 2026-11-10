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

local function announce(game,pirate,target,text)
 if target.isPlayer then game:toast(text,2.5,nil,true) end
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
   announce(game,pirate,target,name(pirate)..': WISE CHOICE. MOVE ALONG.')
   return false
  end
  if Handover.expired(game,d) then
   d.refused=true
   require('src.alife_trace').entity(game,pirate,'robbery',tostring(target.alifeId or 'player')..' did not pay -> attack')
   announce(game,pirate,target,name(pirate)..': YOU WERE WARNED.')
   return true
  end
  if target.isPlayer and game.time>=(d.nag or 0) then
   d.nag=game.time+3
   announce(game,pirate,target,('%s: JETTISON %d CARGO  %ds'):format(name(pirate),d.amount-d.paid,math.ceil(d.deadline-game.time)))
  end
  return false
 end
 if d then Handover.close(d) end
 local have=goods(target)
 if have==0 then pirate.spared[target]=game.time+T.robberySpare;return false end
 if target.asked then return true end   -- already handing something over to someone
 d=Handover.open(game,'robbery',pirate,target,math.max(1,math.ceil(have*T.robberyShare)),T.robberyWindow,isGood)
 announce(game,pirate,target,('%s: JETTISON %d CARGO OR BE FIRED UPON'):format(name(pirate),d.amount))
 require('src.alife_trace').entity(game,pirate,'robbery',('demanded %d from %s'):format(d.amount,tostring(target.alifeId or 'player')))
 require('src.alife_trace').entity(game,target,'robbery',('%s demanded %d cargo'):format(tostring(pirate.alifeId),d.amount))
 return false
end

function R.isSpared(game,pirate,o)
 local t=pirate.spared and pirate.spared[o]
 return t and game.time<t or false
end

-- An NPC victim's answer, decided once per demand by the offline rule's
-- odds (with any covering station's guns on its side).
function R.respond(game,e)
 local d=e.asked
 if not d or d.kind~='robbery' or d.closed or d.answered or Handover.gone(d.asker) then return end
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
 if odds>=require('src.personality').engageOdds(mine) then e.aggressor=pirate
  require('src.alife_trace').entity(game,e,'robbery',('odds %.0f%% -> refuse and fight'):format(odds*100));return end
 require('src.alife_trace').entity(game,e,'robbery',('odds %.0f%% -> comply'):format(odds*100))
 -- comply: dump the demanded share of goods
 local _,list=goods(e)
 Handover.give(game,e,list,d.amount)
 if mine then mine.taskStatus='robbed by pirates' end
end

return R
