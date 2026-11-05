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
local events=require('src.events')
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

-- Is pirate still waiting on target's answer (so holds fire)?
function R.pending(pirate)
 local d=pirate.demand
 return d and not d.refused and d.target and not d.target.dead and not d.target.removed or false
end

-- The pirate has (re)chosen target; returns true if it should still shoot it.
function R.consider(game,pirate,target)
 if not target or target.dead then return true end
 local civilian=target.isPlayer or target.npcRole and require('src.security').prey(target)
 if not civilian then return true end
 pirate.spared=pirate.spared or setmetatable({},{__mode='k'})
 local d=pirate.demand
 if d and d.target==target then
  if d.refused then return true end
  local left=goods(target)
  if d.paid>=d.amount or left==0 then
   pirate.spared[target]=game.time+T.robberySpare
   pirate.demand=nil;target.robbedBy=nil
   pirate.combatTarget,pirate.lock=nil,nil
   announce(game,pirate,target,name(pirate)..': WISE CHOICE. MOVE ALONG.')
   return false
  end
  if game.time>=d.deadline then
   d.refused=true
   announce(game,pirate,target,name(pirate)..': YOU WERE WARNED.')
   return true
  end
  if target.isPlayer and game.time>=(d.nag or 0) then
   d.nag=game.time+3
   announce(game,pirate,target,('%s: JETTISON %d CARGO  %ds'):format(name(pirate),d.amount-d.paid,math.ceil(d.deadline-game.time)))
  end
  return false
 end
 local have=goods(target)
 if have==0 then pirate.spared[target]=game.time+T.robberySpare;return false end
 pirate.demand={target=target,amount=math.max(1,math.ceil(have*T.robberyShare)),paid=0,
  deadline=game.time+T.robberyWindow,started=game.time}
 target.robbedBy=pirate
 announce(game,pirate,target,('%s: JETTISON %d CARGO OR BE FIRED UPON'):format(name(pirate),pirate.demand.amount))
 return false
end

function R.isSpared(game,pirate,o)
 local t=pirate.spared and pirate.spared[o]
 return t and game.time<t or false
end

-- Count what a robbed ship throws out.
events.on('eject',function(e,id,count)
 local pirate=e.robbedBy
 local d=pirate and pirate.demand
 if not d or d.target~=e then return end
 local item=data.items[id]
 if item and not item.shot and id~=require('src.reactor_fuel').item() then d.paid=d.paid+count end
end)

-- An NPC victim's answer, decided once per demand by the offline rule's
-- odds (with any covering station's guns on its side).
function R.respond(game,e)
 local pirate=e.robbedBy
 local d=pirate and pirate.demand
 if not d or d.target~=e or d.answered or pirate.dead or pirate.removed then return end
 d.answered=true
 local E=require('src.encounters')
 local mine=game.universe.npcs[e.alifeId];local theirs=game.universe.npcs[pirate.alifeId]
 local odds=.5
 if mine and theirs then
  mine.ship.armor=e.armor;theirs.ship.armor=pirate.armor
  local _,guns=E.coveringStation(mine,theirs,game.universe.clock)
  odds=E.odds(mine,theirs,guns*T.offlineStationAccuracy)
 end
 if odds>=T.offlineEngageOdds then e.aggressor=pirate;return end
 -- comply: dump the demanded share, smallest stacks of goods first
 local need=d.amount
 local _,list=goods(e)
 for _,id in ipairs(list) do
  if need<=0 then break end
  local n=math.min(need,e.cargo[id] or 0)
  if n>0 then
   if e.hold then require('src.inventory.hold').take(e.hold,id,n);e.cargo=require('src.inventory.hold').totals(e.hold)
   else e.cargo[id]=e.cargo[id]-n;if e.cargo[id]<=0 then e.cargo[id]=nil end end
   require('src.ship').updateMass(e)
   game:eject(e,id,n)
   need=need-n
  end
 end
 if mine then mine.taskStatus='robbed by pirates' end
end

return R
