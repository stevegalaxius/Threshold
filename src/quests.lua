--[[
	Quests: player work generated from the simulation, kept in its own saved
	records (u.quests). A quest reads world state and acts on it only through
	the levers the simulation already uses (station stock, credits); it never
	reserves or owns a Tasks board offer, so the freight board's churn can't
	make it disappear.

	First generator, shortage deliveries: a trade station that has been short
	of a good for T.questShortageAge (economy.lua records when each shortage
	began) posts a delivery for up to T.questMaxVolume of it, paying
	T.questPremium of its price plus up to T.questAgeBonus more as the
	shortage ages. Delivered goods go into station stock, so the economy's
	own order trim cancels matching freight on its next tick. Partial
	deliveries pay pro rata. A shortage is only posted while some other
	station holds spare stock of the good, so it can always be sourced.
	Once accepted, a delivery holds until its
	deadline even if the shortage clears.

	Later generators (rescue, bounty, wreck recovery, escort) post the same
	record shape: kind, giver, item/amount or subject, reward, expiry.
]]
local L=require('src.locations')
local Fields=require('src.fields')
local Stock=require('src.stockpile')
local T=require('src.tuning')
local data=require('src.data')
local Q={}

function Q.state(u)
 u.quests=u.quests or {nextId=0,offers={},active={},next=0}
 return u.quests
end
local function stations()
 local list={}
 for _,area in ipairs(Fields.list) do for _,id in ipairs(L.stations(area,'trade')) do list[#list+1]=id end end
 return list
end
local function price(u,key,item) return require('src.markets').price(u,key,item) end
function Q.unitReward(u,key,item,age)
 local bonus=T.questAgeBonus*math.min(1,math.max(0,age-T.questShortageAge)/3600)
 return math.max(1,math.floor(price(u,key,item)*(T.questPremium+bonus)+.5))
end
-- Somewhere else must hold more than it needs, or the player could never
-- fill the delivery (the economy records goods nobody makes as shortages too).
local function sourced(u,E,list,st,item,n)
 for _,s in ipairs(list) do
  if s~=st and Stock.count(u,s,item)-E.target(u,s,item)>=n then return true end
 end
 return false
end
local function shortageKey(q) return q.giver..'|'..q.item end

-- Generators ---------------------------------------------------------------
-- Each one proposes candidate quests for a station; the arbiter below picks
-- which get posted. keep(u,q,clock) says whether an unaccepted offer still
-- stands; resolve(game,q,clock) settles an active one ('done'/'failed'/nil).
Q.generators={}
Q.order={'shortage_delivery','rescue'}

Q.generators.shortage_delivery={
 label='Delivery',
 keep=function(u,q,clock)
  local E=require('src.economy')
  -- Short flickers in the shortage record don't withdraw it; a refilled shelf does.
  if Stock.count(u,q.giver,q.item)>=E.target(u,q.giver,q.item) then return false end
  q.unit=Q.unitReward(u,q.giver,q.item,E.shortageAge(u,q.giver,q.item,clock))
  return true
 end,
 propose=function(u,st,clock,ctx)
  local E=require('src.economy');local out={}
  for item,since in pairs(Stock.record(u,st).shortages or {}) do
   local age=clock-since
   if age>=T.questShortageAge and data.items[item] and not ctx.taken[st..'|'..item] then
    local short=E.target(u,st,item)-Stock.count(u,st,item)
    local cap=math.max(1,math.floor(T.questMaxVolume/math.max(.001,data.items[item].volume)))
    local amount=math.min(short,cap)
    if amount>=1 and sourced(u,E,ctx.stations,st,item,math.min(amount,T.orderMinLoad)) then
     out[#out+1]={kind='shortage_delivery',giver=st,item=item,amount=amount,unit=Q.unitReward(u,st,item,age),age=age}
    end
   end
  end
  table.sort(out,function(a,b) return a.age>b.age or a.age==b.age and a.item<b.item end)
  return out
 end,
}

-- Rescue: a real stranded record. The station nearest it posts the job;
-- it pays when the ship is no longer stranded while you are beside it, and
-- fails if someone else refuels it first, or it dies.
local function rescueGiver(r,clock)
 local A=require('src.alife');local x,y=A.point(r,clock)
 local best,bd
 for _,id in ipairs(L.stations(r.area,'trade')) do
  local px,py=L.position(id,clock);local d=x and (px-x)^2+(py-y)^2 or 0
  if not bd or d<bd then best,bd=id,d end
 end
 return best
end
Q.generators.rescue={
 label='Rescue',
 keep=function(u,q,clock)
  local r=(u.npcs or {})[q.subject]
  return r and r.state~='dead' and r.state~='escaped' and r.fuelStatus=='stranded'
 end,
 propose=function(u,st,clock,ctx)
  local list=ctx.stranded[st]
  if not list then return {} end
  local out={}
  local Fuel,D=require('src.reactor_fuel'),require('src.distress')
  for _,r in ipairs(list) do
   if not ctx.taken['rescue|'..r.id] and clock-(r.strandedSince or clock)>=T.rescueMinAge then
    local amount=D.want(r)
    local reward=math.floor(T.rescueBase+amount*price(u,st,Fuel.item())*T.rescueFuelMultiple)
    out[#out+1]={kind='rescue',giver=st,subject=r.id,area=r.area,item=Fuel.item(),amount=amount,
     unit=math.ceil(reward/amount),name=(data.hulls[r.ship and r.ship.hull] or {}).name}
   end
  end
  table.sort(out,function(a,b) return a.subject<b.subject end)
  return out
 end,
 watch=function(game,q,clock)
  local e=game.alifeOnline and game.alifeOnline[q.subject];local p=game.player
  if e and p and not p.dead and e.body and not e.body:isDestroyed() then
   local x,y=e.body:getPosition();local px,py=p.body:getPosition()
   if (x-px)^2+(y-py)^2<T.rescueRange^2 then q.near=clock end
  end
 end,
 resolve=function(game,q,clock)
  local r=(game.universe.npcs or {})[q.subject]
  if not r or r.state=='dead' or r.state=='escaped' then return 'failed','The stranded ship was lost' end
  if r.fuelStatus~='stranded' then
   if q.near and clock-q.near<=T.rescueCredit then return 'done','Rescue complete' end
   return 'failed','Someone else reached the stranded ship first'
  end
 end,
}

-- Rewards and reputation ------------------------------------------------------
local function rep() return require('src.reputation') end
function Q.attitude(u,station) return rep().stationAttitude(u,station) end
-- Hostile stations offer you nothing; the rest do.
function Q.willOffer(u,station) return not rep().hostile(Q.attitude(u,station)) end
local function settle(u,q,status,clock,game)
 local s=Q.state(u);s.active[q.id]=nil;q.state=status;s.last={id=q.id,status=status,clock=clock}
 local faction=rep().ofNode(q.giver)
 if status=='done' then
  if q.kind=='rescue' then
   local pay=q.unit*q.amount;u.credits=u.credits+pay;q.paid=pay
   rep().addGoodwill(u,(u.npcs or {})[q.subject],rep().T.goodwillRescue)
  end
  rep().addStanding(u,faction,T.questStanding)
  require('src.events').emit('quest_completed',q)
 else
  rep().addStanding(u,faction,-T.questFailStanding)
  require('src.events').emit('quest_failed',q)
 end
 if game and game.toast and q.kind=='rescue' then
  game:toast(status=='done' and ('Rescue complete: paid %d CR'):format(q.paid or 0) or 'Rescue failed',3)
 end
end

-- Arbiter -----------------------------------------------------------------------
-- Per station: up to T.questSlots open offers, at most T.questKindMax of one
-- kind, each kind waits its cooldown after posting there, and the kind
-- posted last at a station goes after the others when it's free to choose.
-- Weights (T.questWeights, or a location's questWeights) order the rest.
local function weight(st,kind)
 local place=L.byId[st]
 return (place and place.questWeights and place.questWeights[kind]) or T.questWeights[kind] or 1
end
local function arbitrate(u,st,clock,ctx,s)
 local cool=s.cooldown[st] or {};s.cooldown[st]=cool
 local open,count=ctx.perStation[st] or 0,ctx.perKind[st] or {}
 while open<T.questSlots do
  local kinds={}
  for _,kind in ipairs(Q.order) do
   if (count[kind] or 0)<T.questKindMax and clock>=(cool[kind] or 0) then kinds[#kinds+1]=kind end
  end
  table.sort(kinds,function(a,b)
   local la,lb=a==s.lastKind[st],b==s.lastKind[st]
   if la~=lb then return lb end
   local wa,wb=weight(st,a),weight(st,b)
   if wa~=wb then return wa>wb end
   return a<b
  end)
  local posted=false
  for _,kind in ipairs(kinds) do
   local c=Q.generators[kind].propose(u,st,clock,ctx)[1]
   if c then
    s.nextId=s.nextId+1
    local id='quest/'..s.nextId
    c.id=id;c.age=nil;c.posted=clock;c.expires=clock+T.questOfferLife
    s.offers[id]=c
    ctx.taken[c.kind=='rescue' and 'rescue|'..c.subject or shortageKey(c)]=true
    open=open+1;count[kind]=(count[kind] or 0)+1
    cool[kind]=clock+(T.questCooldown[kind] or 0);s.lastKind[st]=kind
    posted=true;break
   end
  end
  if not posted then break end
 end
end

-- Settle active quests, withdraw stale offers, then let the arbiter post.
function Q.update(u,clock,game)
 local s=Q.state(u);s.cooldown=s.cooldown or {};s.lastKind=s.lastKind or {}
 if clock<(s.next or 0) then return end
 s.next=clock+T.questTick
 local ctx={taken={},perStation={},perKind={},stations=stations(),stranded={}}
 for id,q in pairs(s.active) do
  local g=Q.generators[q.kind]
  local status=g and g.resolve and game and g.resolve(game,q,clock)
  if status then settle(u,q,status,clock,game)
  elseif clock>q.deadline then settle(u,q,'failed',clock,game)
  else ctx.taken[q.kind=='rescue' and 'rescue|'..q.subject or shortageKey(q)]=true end
 end
 for id,q in pairs(s.offers) do
  local g=Q.generators[q.kind]
  if clock>q.expires or not g or not g.keep(u,q,clock) then s.offers[id]=nil
  else
   ctx.taken[q.kind=='rescue' and 'rescue|'..q.subject or shortageKey(q)]=true
   ctx.perStation[q.giver]=(ctx.perStation[q.giver] or 0)+1
   local k=ctx.perKind[q.giver] or {};ctx.perKind[q.giver]=k;k[q.kind]=(k[q.kind] or 0)+1
  end
 end
 for id,r in pairs(u.npcs or {}) do
  if r.fuelStatus=='stranded' and r.area and r.state~='dead' and r.state~='escaped' then
   r.strandedSince=r.strandedSince or clock
   local st=rescueGiver(r,clock)
   if st then ctx.stranded[st]=ctx.stranded[st] or {};table.insert(ctx.stranded[st],r) end
  else r.strandedSince=nil end
 end
 for _,st in ipairs(ctx.stations) do arbitrate(u,st,clock,ctx,s) end
end
-- Every simulation tick: things that need a closer eye than once a minute.
function Q.watch(game,clock)
 for _,q in pairs(Q.state(game.universe).active) do
  local g=Q.generators[q.kind]
  if g and g.watch then g.watch(game,q,clock) end
 end
end

-- What the contracts screen shows: offers at this station, best paying first.
function Q.offersAt(u,station)
 local out={}
 if not Q.willOffer(u,station) then return out end
 for _,q in pairs(Q.state(u).offers) do if q.giver==station then out[#out+1]=q end end
 table.sort(out,function(a,b) return a.unit*a.amount>b.unit*b.amount or a.unit*a.amount==b.unit*b.amount and a.id<b.id end)
 return out
end
function Q.active(u)
 local out={}
 for _,q in pairs(Q.state(u).active) do out[#out+1]=q end
 table.sort(out,function(a,b) return a.deadline<b.deadline or a.deadline==b.deadline and a.id<b.id end)
 return out
end
function Q.accept(u,id,clock)
 local s=Q.state(u);local q=s.offers[id]
 if not q then return nil,'Delivery no longer offered' end
 local n=0;for _ in pairs(s.active) do n=n+1 end
 if n>=T.questMaxActive then return nil,('You can hold %d jobs at once'):format(T.questMaxActive) end
 if not Q.willOffer(u,q.giver) then return nil,'This station will not work with you' end
 s.offers[id]=nil
 q.state='active';q.accepted=clock;q.deadline=clock+(q.kind=='rescue' and T.rescueDeadline or T.questDeadline);q.delivered=0
 s.active[id]=q
 if q.kind=='rescue' then return true,'Rescue accepted: bring fuel to the stranded '..(q.name or 'ship')..' in '..q.area end
 return true,'Delivery accepted: bring '..q.amount..' '..(data.items[q.item].name or q.item)..' here'
end
function Q.abandon(u,id,clock)
 local s=Q.state(u);local q=s.active[id]
 if not q then return nil,'No such delivery' end
 s.active[id]=nil;s.last={id=id,status='abandoned',clock=clock}
 rep().addStanding(u,rep().ofNode(q.giver),-T.questFailStanding)
 return true,'Job abandoned'
end
-- Hand over whatever part of the delivery the player carries, at the giver.
function Q.deliver(game,id,station)
 local u=game.universe;local s=Q.state(u);local q=s.active[id];local p=game.player
 if not q then return nil,'No such delivery' end
 if q.kind~='shortage_delivery' then return nil,'Not a delivery' end
 if station~=q.giver then return nil,'Dock at '..((L.byId[q.giver] or {}).name or q.giver)..' to deliver' end
 local have=p.cargo[q.item] or 0
 local n=math.min(have,q.amount-q.delivered)
 if n<1 then return nil,'No '..(data.items[q.item].name or q.item)..' aboard' end
 local Hold,Ship=require('src.inventory.hold'),require('src.ship')
 if p.hold then
  local got=Hold.take(p.hold,q.item,n);n=got or n;p.cargo=Hold.totals(p.hold)
 else p.cargo[q.item]=have-n;if p.cargo[q.item]<=0 then p.cargo[q.item]=nil end end
 Ship.updateMass(p)
 Stock.add(u,q.giver,q.item,n)
 local pay=n*q.unit
 u.credits=u.credits+pay;q.delivered=q.delivered+n;q.paid=(q.paid or 0)+pay
 if q.delivered>=q.amount then settle(u,q,'done',u.clock,game) end
 return true,('Delivered %d: paid %d CR'):format(n,pay)
end
return Q
