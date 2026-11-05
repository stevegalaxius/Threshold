-- Handover: one ship asks another to eject items, then watches for them.
-- The shared core of every "give me X" exchange between ships: robbery (a
-- pirate demands goods), distress (a stranded ship asks for fuel), and
-- whatever comes next. The items are always real: the giver ejects them
-- from its own hold with the ordinary eject, and the asker (or anyone)
-- picks them up. A future comms/messaging layer would carry these.
--
-- A request: { kind, asker, giver, amount, paid, deadline, accepts(id) }.
-- asker.request and giver.asked point at it (one of each per ship).
local data=require('src.data')
local events=require('src.events')
local H={}

function H.open(game,kind,asker,giver,amount,window,accepts)
 local req={kind=kind,asker=asker,giver=giver,amount=amount,paid=0,
  deadline=game.time+window,started=game.time,accepts=accepts}
 asker.request=req;giver.asked=req
 return req
end
function H.close(req)
 if not req then return end
 if req.asker.request==req then req.asker.request=nil end
 if req.giver.asked==req then req.giver.asked=nil end
 req.closed=true
end
function H.met(req) return req.paid>=req.amount end
function H.expired(game,req) return game.time>=req.deadline end
function H.gone(e) return not e or e.dead or e.removed end

-- Count what a giver ejects toward its open request.
events.on('eject',function(e,id,count)
 local req=e.asked
 if req and not req.closed and req.accepts(id) then req.paid=req.paid+count end
end)

-- Make giver eject up to n of the listed items (in order). Real items, out
-- of its real hold. Returns how many went out.
function H.give(game,giver,ids,n)
 local Hold=require('src.inventory.hold');local Ship=require('src.ship')
 local out=0
 for _,id in ipairs(ids) do
  if out>=n then break end
  local k=math.min(n-out,giver.cargo[id] or 0)
  if k>0 then
   if giver.hold then k=Hold.take(giver.hold,id,k);giver.cargo=Hold.totals(giver.hold)
   else giver.cargo[id]=giver.cargo[id]-k;if giver.cargo[id]<=0 then giver.cargo[id]=nil end end
   if k>0 then Ship.updateMass(giver);game:eject(giver,id,k);out=out+k end
  end
 end
 return out
end
return H
