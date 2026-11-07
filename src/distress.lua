-- Distress: a stranded ship asks nearby ships for reactor fuel, and gets
-- it only as real items. Built on handover.lua (the same core as robbery).
--
-- Online: the stranded ship keeps its tractor on and pulls in any fuel
-- pickup in reach (anyone's: the player can just eject some nearby). It
-- also calls the nearest non-pirate NPC with fuel to spare, which flies
-- over and ejects some from its own hold next to it.
-- Offline: the stranded record claims loose fuel records near it, and a
-- record in the same region with fuel to spare hands some over after the
-- time it would take to fly there: the units move from one hold to the other.
local T=require('src.tuning')
local data=require('src.data')
local Fuel=require('src.reactor_fuel')
local Supplies=require('src.supplies')
local Handover=require('src.handover')
local Tractor=require('src.tractor')
local Hold=require('src.inventory.hold')
local D={}
local function isFuel(id) return id==Fuel.item() end
-- Would h answer r's call? For now anyone with fuel to spare helps anyone;
-- factions will narrow this later.
local function helps(h,r) return h.role~=nil end
-- Units a ship would like to receive / can give away.
local function want(r) return math.max(1,math.ceil((Supplies.targets(r)[Fuel.item()] or 1)*T.distressShare)) end
local function spare(r,cargo)
 local keep=math.ceil((Supplies.targets(r)[Fuel.item()] or 0)*T.npcFuelLow)+1
 return math.max(0,(cargo[Fuel.item()] or 0)-keep)
end
D.want,D.spare=want,spare

-- ---------------------------------------------------------------- online
-- Each frame for a stranded online NPC (its AI is otherwise idle).
function D.stranded(game,e,r,dt)
 -- pull in fuel already floating nearby
 local x,y=e.body:getPosition();local reach=require('src.ship').tractorRange(e)
 local best,bd
 for _,k in ipairs(game.pickups) do
  if isFuel(k.item) and k.count>0 and (not k.collector or k.collector==e) then
   local d=(k.x-x)^2+(k.y-y)^2
   if d<(reach*3)^2 and (not bd or d<bd) then best,bd=k,d end
  end
 end
 if best then best.collector=e;e.tractorTarget=best;e.intent.tractor=true;Tractor.pull(game,e,best,dt) end
 -- and call for help
 local req=e.request
 if req and req.kind=='distress' then
  if req.closed or Handover.gone(req.giver) or Handover.expired(game,req) then Handover.close(req);e.nextDistressAt=game.time+T.distressRetry;r.taskStatus='stranded: calling for fuel' end
  return
 end
 if game.time<(e.nextDistressAt or 0) then return end
 e.nextDistressAt=game.time+T.distressRetry
 local helper,hd
 for _,o in pairs(game.alifeOnline or {}) do
  local h=game.universe.npcs[o.alifeId]
  if o~=e and not o.dead and not o.removed and not o.dockState and not o.asked and h and helps(h,r)
   and h.fuelStatus~='stranded' and spare(h,o.cargo)>=T.distressMinSpare then
   local ox,oy=o.body:getPosition();local d=(ox-x)^2+(oy-y)^2
   if d<T.distressRange^2 and (not hd or d<hd) then helper,hd=o,d end
  end
 end
 if helper then
  local h=game.universe.npcs[helper.alifeId]
  Handover.open(game,'distress',e,helper,math.min(want(r),spare(h,helper.cargo)),T.distressWindow,isFuel)
  require('src.alife_trace').note(r,game.universe.clock,'distress','called '..h.id..' for fuel (online)')
  require('src.alife_trace').note(h,game.universe.clock,'distress','answering '..r.id..': fuel run')
  r.taskStatus='stranded: '..(helper.def and helper.def.name or 'a ship')..' is bringing fuel'
 else r.taskStatus='stranded: calling for fuel' end
end

-- Each frame for an online helper on a fuel run. Returns true if it owns
-- the ship's intent this frame.
function D.helper(game,e,dt,AI)
 local req=e.asked
 if not req or req.kind~='distress' then return false end
 local asker=req.asker
 if req.closed or Handover.gone(asker) or asker.fuelStatus~='stranded' and req.paid>0 or Handover.expired(game,req) then
  Handover.close(req);return false
 end
 local x,y=e.body:getPosition();local ax,ay=asker.body:getPosition()
 local vx,vy=asker.body:getLinearVelocity()
 local dx,dy=ax-x,ay-y;local d=math.sqrt(dx*dx+dy*dy)
 local close=require('src.ship').tractorRange(asker)*.8+asker.halfLength+e.halfLength
 AI.navigate(game,e,dx,dy,math.min(require('src.npc').liveCruise(e),math.max(0,(d-close*.6)*.6)),vx,vy,d)
 e.intent.aimX,e.intent.aimY=ax,ay
 e.intent.firePrimary,e.intent.fireSecondary,e.intent.fireTertiary=false,false,false
 local r=game.universe.npcs[e.alifeId]
 if r then r.taskStatus='bringing fuel to a stranded ship' end
 if d<close and not req.given then
  req.given=true
  local n=Handover.give(game,e,{Fuel.item()},req.amount-req.paid)
  if r then require('src.alife_trace').note(r,game.universe.clock,'distress',('ejected %d fuel for %s'):format(n,tostring(asker.alifeId))) end
  Handover.close(req)
 end
 return true
end

-- --------------------------------------------------------------- offline
local function withHold(r,fn) return Fuel.withRecord(r,function(e) return fn(e) end) end
local function add(e,n)
 if e.hold then n=Hold.add(e.hold,Fuel.item(),n);e.cargo=Hold.totals(e.hold)
 else e.cargo[Fuel.item()]=(e.cargo[Fuel.item()] or 0)+n end
 return n
end
local function take(e,n)
 if e.hold then n=Hold.take(e.hold,Fuel.item(),n);e.cargo=Hold.totals(e.hold)
 else n=math.min(n,e.cargo[Fuel.item()] or 0);e.cargo[Fuel.item()]=(e.cargo[Fuel.item()] or 0)-n end
 return n
end
-- For a stranded offline record. Returns true if it got fuel.
function D.advance(game,r,clock)
 if r.fuelStatus~='stranded' or not r.area or not game then r.distress=nil;return false end
 local u=game.universe
 local A=require('src.alife');local x,y=A.point(r,clock)
 -- loose fuel floating near it
 if x then
  local Loose=require('src.loose')
  for _,l in ipairs(Loose.offline(game,r.area,clock)) do
   if isFuel(l.record.item) and (l.x-x)^2+(l.y-y)^2<(T.tractorBase*3)^2 then
    local got=withHold(r,function(e) return add(e,l.record.count) end)
    if got>0 then
     l.record.count=l.record.count-got
     if l.record.count<=0 then Loose.remove(u,l.record.id) end
     Fuel.observe(u,r,clock);r.taskStatus='recovered floating fuel'
     require('src.alife_trace').note(r,clock,'distress',('claimed %d floating fuel'):format(got))
     return true
    end
   end
  end
 end
 -- a fuel run by another record in the same region
 local run=r.distress
 if run then
  local h=u.npcs[run.helper]
  if not h or h.state=='dead' or h.area~=r.area or h.encounter or game.alifeOnline and game.alifeOnline[h.id] then
   require('src.alife_trace').note(r,clock,'distress','fuel run by '..run.helper..' fell through');r.distress=nil;r.taskStatus='stranded: calling for fuel';return false end
  if clock<run.at then return false end
  r.distress=nil
  local n=withHold(h,function(e) return take(e,math.min(run.amount,spare(h,e.cargo))) end)
  if n<=0 then require('src.alife_trace').note(r,clock,'distress',run.helper..' had no fuel left to spare');r.taskStatus='stranded: calling for fuel';return false end
  local got=withHold(r,function(e) return add(e,n) end)
  if got<n then withHold(h,function(e) add(e,n-got) end) end
  Fuel.observe(u,r,clock);Fuel.observe(u,h,clock)
  r.taskStatus='refuelled by a passing ship'
  require('src.alife_trace').note(r,clock,'distress',('got %d fuel from %s'):format(got,h.id))
  require('src.alife_trace').note(h,clock,'distress',('gave %d fuel to %s'):format(got,r.id))
  return got>0
 end
 if clock<(r.nextDistressAt or 0) then return false end
 r.nextDistressAt=clock+T.distressRetry
 local best,bd
 for id,h in pairs(u.npcs) do
  if h~=r and h.area==r.area and helps(h,r) and (h.state=='travel' or h.state=='idle' or h.state=='docked')
   and h.fuelStatus~='stranded' and not h.encounter and not (game.alifeOnline and game.alifeOnline[id]) then
   local cargo=h.ship.hold and Hold.totals(Hold.deserialize(h.ship.hold)) or h.ship.cargo or {}
   -- a real margin, so it still has it to give when it gets there
   if spare(h,cargo)>=T.distressMinSpare then
    local hx,hy=A.point(h,clock);local d=hx and x and (hx-x)^2+(hy-y)^2 or math.huge
    if not bd or d<bd then best,bd=h,d end
   end
  end
 end
 if best then
  local speed=best.speed or 300
  r.distress={helper=best.id,amount=want(r),at=clock+math.sqrt(bd==math.huge and T.distressRange^2 or bd)/speed*2+T.alifeStay}
  r.taskStatus='stranded: '..best.id..' bringing fuel'
  require('src.alife_trace').note(r,clock,'distress','called '..best.id..' for fuel')
 else r.taskStatus='stranded: calling for fuel';require('src.alife_trace').note(r,clock,'distress','called for fuel: nobody in '..r.area..' can spare any') end
 return false
end
return D
