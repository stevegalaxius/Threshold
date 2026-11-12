-- Player freight uses the shared offers, cargo reservations and settlement.
-- Only the task/owner record is saved here; the real player ship owns cargo.
local Tasks,Transport=require('src.tasks'),require('src.transport')
local Hold,Ship=require('src.inventory.hold'),require('src.ship')
local Stock,L=require('src.stockpile'),require('src.locations')
local copy=require('src.persistence').copy
local C={}
local function owner(u)
 local state=Tasks.state(u)
 state.player=state.player or {id='player',player=true}
 return state.player
end
function C.active(game) return owner(game.universe).task end
function C.station(game)
 local p=game.player;local ds=p and not p.dead and p.dockState
 return game.state=='docked' and ds and ds.done and Stock.key(ds.station) or nil
end
local function attach(game)
 local r=owner(game.universe);local p=game.player
 r.ship={hull=p.hull.id,loadout=p.loadout,cargo=copy(p.cargo),hold=p.hold and Hold.serialize(p.hold)}
 r.credits=0
 return r
end
local function detach(game,r,changed)
 if changed then
  local p=game.player
  p.cargo=r.ship.cargo
  if r.ship.hold then p.hold=Hold.deserialize(r.ship.hold) end
  Ship.updateMass(p)
  game.universe.credits=game.universe.credits+(r.credits or 0)
 end
 r.ship=nil;r.credits=nil
end
local function supported(o)
 -- Standing mining/salvage/police duties do not yet define player rewards.
 return o.kind=='transport' and o.order and (o.stocked or o.mine) and L.byId[o.source] and L.byId[o.target]
end
local function access(game,o)
 local A=require('src.npc_access');local p=game.player
 local r={ship={hull=p.hull.id,loadout=p.loadout}}
 local caps=A.capabilities(r)
 return A.eligible(r,o,caps) and A.eligible(r,Tasks.definitions[o.kind],caps)
end
function C.quote(game,o)
 local u=game.universe
 if not o or not supported(o) then return nil,'Not a player contract' end
 if o.state~='available' or (o.readyAt or 0)>u.clock then return nil,'Job no longer available' end
 if not access(game,o) then return nil,'Requirements not met' end
 local amount=math.min(o.amount,Ship.canFit(game.player,o.item,o.amount),Transport.available(u,o.source,o.item,o.id))
 amount=math.floor(amount)
 if amount<1 then return nil,'No cargo space or available stock' end
 Transport.quote(o,u.clock,u)
 local t=copy(o);t.amount=amount
 local bill=Transport.invoice(t)
 return {amount=amount,payment=bill.total,routeAU=t.routeAU,volume=bill.volume,handling=bill.handling}
end
function C.list(game)
 local out={}
 for _,o in pairs(Tasks.state(game.universe).offers) do
  if supported(o) and o.state=='available' and (o.readyAt or 0)<=game.universe.clock then out[#out+1]=o end
 end
 local here=C.station(game)
 table.sort(out,function(a,b)
  if (a.source==here)~=(b.source==here) then return a.source==here end
  local an,bn=L.byId[a.source].name or a.source,L.byId[b.source].name or b.source
  return an<bn or an==bn and a.id<b.id
 end)
 return out
end
function C.accept(game,id)
 local here=C.station(game)
 if not here then return nil,'Dock at a station to accept work' end
 if C.active(game) then return nil,'Finish or cancel your current contract first' end
 local u=game.universe;local o=Tasks.state(u).offers[id]
 local q,why=C.quote(game,o);if not q then return nil,why end
 local t=copy(o);t.amount=q.amount;t.phase='prepare';t.assigned=u.clock;t.state=nil
 local r=attach(game);local def=Tasks.definitions[t.kind]
 if not def.eligible(u,r,t,here,u.clock) then detach(game,r);return nil,'This freight order is no longer eligible' end
 if not def.feasible(u,r,t,here,u.clock) then detach(game,r);return nil,'No route to pickup or delivery' end
 -- Explicitly accept the displayed amount; do not bundle other offers.
 local amount=o.amount;o.amount=t.amount
 local ok=def.prepare(u,r,t,here,u.clock)
 if not ok then o.amount=amount;detach(game,r);return nil,'Cargo is unavailable or does not fit' end
 o.owner=r.id;o.state='reserved';r.task=t
 if amount>t.amount then
  local remainder=copy(o);remainder.amount=amount-t.amount;remainder.owner=nil;remainder.manifestRoot=nil;remainder.loaded=nil
  Tasks.post(u,remainder)
 end
 detach(game,r,true)
 return true,t.phase=='delivery' and 'Contract accepted: cargo loaded' or 'Contract accepted: collect cargo at the source'
end
function C.advance(game)
 local here=C.station(game);local t=C.active(game)
 if not here or not t then return nil,'No active contract at this station' end
 local destination=t.phase=='pickup' and t.source or t.target
 if here~=destination then return nil,t.phase=='pickup' and 'Dock at the pickup station' or 'Dock at the delivery station' end
 if t.phase=='delivery' and (game.player.cargo[t.item] or 0)<t.amount then return nil,'Cargo missing: replace it before delivery' end
 if t.phase=='pickup' and Ship.canFit(game.player,t.item,t.amount)<t.amount then return nil,'Make room for the contracted cargo first' end
 local r=attach(game);local clock=game.universe.clock
 if t.phase=='pickup' then
  local ok=Transport.load(game.universe,r,t);detach(game,r,ok)
  return ok,ok and 'Contract cargo loaded' or 'Pickup stock is unavailable'
 end
 local payment=Transport.payment(t)
 local done=Tasks.arrive(game.universe,r,here,clock,game)
 detach(game,r,done)
 return done,done and ('Delivered: paid '..payment..' CR') or 'Delivery could not be completed'
end
function C.cancel(game)
 local here=C.station(game);local t=C.active(game)
 if not here or not t then return nil,'Dock at a station to cancel your contract' end
 if t.phase=='delivery' then
  if here~=t.source then return nil,'Return the cargo to its source to cancel' end
  if (game.player.cargo[t.item] or 0)<t.amount then return nil,'Replace missing cargo before returning it' end
  local p=game.player
  if p.hold then assert(Hold.take(p.hold,t.item,t.amount)==t.amount);p.cargo=Hold.totals(p.hold)
  else p.cargo[t.item]=p.cargo[t.item]-t.amount end
  Stock.add(game.universe,t.source,t.item,t.amount);Ship.updateMass(p)
 end
 Tasks.release(game.universe,owner(game.universe),'cancelled',game.universe.clock)
 return true,'Contract cancelled'
end
return C
