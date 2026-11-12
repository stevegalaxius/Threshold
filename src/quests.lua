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
	deliveries pay pro rata. Once accepted, a delivery holds until its
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
local function key(q) return q.giver..'|'..q.item end

-- Withdraw stale offers, fail overdue active deliveries, post new ones.
function Q.update(u,clock)
 local s=Q.state(u)
 if clock<(s.next or 0) then return end
 s.next=clock+T.questTick
 local E=require('src.economy')
 local taken,perStation={},{}
 for id,q in pairs(s.active) do
  if clock>q.deadline then s.active[id]=nil;q.state='failed';s.last={id=id,status='failed',clock=clock}
  else taken[key(q)]=true end
 end
 for id,q in pairs(s.offers) do
  local age=E.shortageAge(u,q.giver,q.item,clock)
  -- Short flickers in the shortage record don't withdraw it; a refilled shelf does.
  if clock>q.expires or Stock.count(u,q.giver,q.item)>=E.target(u,q.giver,q.item) then s.offers[id]=nil
  else
   taken[key(q)]=true;perStation[q.giver]=(perStation[q.giver] or 0)+1
   q.unit=Q.unitReward(u,q.giver,q.item,age)
  end
 end
 for _,st in ipairs(stations()) do
  local shortages=(Stock.record(u,st).shortages or {})
  local list={}
  for item,since in pairs(shortages) do
   local age=clock-since
   if age>=T.questShortageAge and data.items[item] and not taken[st..'|'..item] then list[#list+1]={item=item,age=age} end
  end
  table.sort(list,function(a,b) return a.age>b.age or a.age==b.age and a.item<b.item end)
  for _,c in ipairs(list) do
   if (perStation[st] or 0)>=T.questSlots then break end
   local want=E.target(u,st,c.item)
   local short=want-Stock.count(u,st,c.item)
   local cap=math.max(1,math.floor(T.questMaxVolume/math.max(.001,data.items[c.item].volume)))
   local amount=math.min(short,cap)
   if amount>=1 then
    s.nextId=s.nextId+1
    local id='quest/'..s.nextId
    s.offers[id]={id=id,kind='shortage_delivery',giver=st,item=c.item,amount=amount,
     unit=Q.unitReward(u,st,c.item,c.age),posted=clock,expires=clock+T.questOfferLife}
    perStation[st]=(perStation[st] or 0)+1
   end
  end
 end
end

-- What the contracts screen shows: offers at this station, best paying first.
function Q.offersAt(u,station)
 local out={}
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
 if n>=T.questMaxActive then return nil,('You can hold %d deliveries at once'):format(T.questMaxActive) end
 s.offers[id]=nil
 q.state='active';q.accepted=clock;q.deadline=clock+T.questDeadline;q.delivered=0
 s.active[id]=q
 return true,'Delivery accepted: bring '..q.amount..' '..(data.items[q.item].name or q.item)..' here'
end
function Q.abandon(u,id,clock)
 local s=Q.state(u);local q=s.active[id]
 if not q then return nil,'No such delivery' end
 s.active[id]=nil;s.last={id=id,status='abandoned',clock=clock}
 return true,'Delivery abandoned'
end
-- Hand over whatever part of the delivery the player carries, at the giver.
function Q.deliver(game,id,station)
 local u=game.universe;local s=Q.state(u);local q=s.active[id];local p=game.player
 if not q then return nil,'No such delivery' end
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
 if q.delivered>=q.amount then
  s.active[id]=nil;q.state='done';s.last={id=id,status='done',clock=u.clock}
  require('src.events').emit('quest_completed',q)
 end
 return true,('Delivered %d: paid %d CR'):format(n,pay)
end
return Q
