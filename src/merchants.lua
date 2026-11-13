--[[
	Merchant houses: speculators living on top of the goods economy.

	Haulers stay couriers. A house never flies anything: it holds credits
	and goods in warehouses, reads station prices, and acts through the
	same stock and freight board everyone else uses.

	  buy       at its hub warehouse, any of its own faction's stations, and
	            the Ring Station exchange (open to every house) a good priced under its buyBelow is bought out
	            of the station's spare stock at the market price +spread,
	            into the house's warehouse. That pulls the shelf down and the
	            price back up.
	  sell      anywhere a good is priced over its sellAbove, the house
	            sells from warehouse stock: on the spot if it holds stock
	            right there, else by posting an ordinary freight job from
	            its warehouse, paying the courier, and booking the sale at
	            the price it sees now (a forward sale: the risk is its own).
	  flavour   each house belongs to a faction and trades like it: its
	            thresholds, lot size, reach and appetite differ, and it
	            prefers to sell into its own faction's stations.
	  money     every house has credits. A house that goes broke on bad
	            bets turns insolvent: it stops buying and fire-sells its
	            stock until it recovers, or someone bails it out
	            (M.bailout). Its flows are booked on the economy ledger
	            under its id.

	Runs on the universe table alone (offline too), from Economy.update.
]]
local L=require('src.locations')
local Fields=require('src.fields')
local T=require('src.tuning')
local M={}

-- The Ring Station: the belt's open exchange. Every house may buy there
-- and keep stock there; it is nobody's house.
M.exchange='station:ring_1'

-- One house per faction. buyBelow/sellAbove are price multipliers (x list);
-- lot: units per deal; hold: the most of one good it will keep in one
-- warehouse; reach: 'own' sells only into its faction's stations, 'any'
-- sells anywhere (own faction first).
M.houses={
 {id='house:triton',faction='neptune',name='Black Hexagon Group',
  -- Neptune's corporation: the outer system's money. No territory to protect, so
  -- they go anywhere, buy deep and sell only into real pain.
  warehouses={'station:triton_3'},buyBelow=.7,sellAbove=1.8,lot=120,hold=600,reach='any',capital=400000},
 {id='house:estates',faction='estates',name='Venusian Trust',
  -- old money: patient hoarders, big positions, sell late and only at home
  warehouses={'station:venus_1'},buyBelow=.8,sellAbove=1.6,lot=200,hold=1200,reach='own',capital=900000},
 {id='house:zhuhai',faction='zhuhai',name='Zhuhai Mandate Trading',
  -- Mars's state traders: thin margins, fast turnover, buy raw goods cheap
  -- and sell into shortages anywhere
  warehouses={'station:mars_4'},buyBelow=.85,sellAbove=1.2,lot=150,hold=500,reach='any',capital=500000},
 {id='house:diwan',faction='diwan',name='Hyrum & Cohen',
  -- the Diwan's merchant bankers: small, frequent, careful arbitrage
  warehouses={'station:saturn_3'},buyBelow=.75,sellAbove=1.3,lot=60,hold=300,reach='any',capital=300000},
}
M.peak={}
M.byId={};for _,h in ipairs(M.houses) do M.byId[h.id]=h end

local function factionOf(id)
 local Rep=require('src.reputation')
 local place=L.byId[id];if not place then return end
 return Rep.ofNode(id) or (place.area=='triton' or place.area=='neptune') and 'neptune' or nil
end
local function exists(id) return L.byId[id]~=nil end

function M.state(u)
 local s=u.merchants
 if not s then s={houses={},next=0};u.merchants=s end
 for _,h in ipairs(M.houses) do
  if not s.houses[h.id] then s.houses[h.id]={credits=h.capital,stock={},deals=0,lastSale=u.clock} end
 end
 return s
end

-- Warehouses a house may use: its own plus the exchange.
local function sites(h)
 local list,seen={},{}
 local function add(id) if exists(id) and not seen[id] then seen[id]=true;list[#list+1]=id end end
 for _,id in ipairs(h.warehouses) do add(id) end
 add(M.exchange)
 -- an invisible hand: it can act through any of its own faction's stations
 for _,area in ipairs(Fields.list) do for _,id in ipairs(L.stations(area,'trade')) do
  if factionOf(id)==h.faction then add(id) end
 end end
 return list
end
local function held(rec,site,item) return (rec.stock[site] or {})[item] or 0 end
local function hold(rec,site,item,n)
 local w=rec.stock[site] or {};rec.stock[site]=w
 w[item]=(w[item] or 0)+n;if w[item]<=0 then w[item]=nil end
end

local function buy(u,h,rec,site,item,clock)
 local Markets,S,E=require('src.markets'),require('src.stockpile'),require('src.economy')
 local price=Markets.price(u,site,item)
 local d=require('src.data').items[item]
 if price>=(d.price or 0)*h.buyBelow then return end
 -- only with somewhere to sell it: a glut everywhere (ammo nobody fires)
 -- is dead money, not a bargain
 if (M.peak[item] or 0)<price*(1+T.merchantMargin)*(1+T.marketSpread)/(1-T.marketSpread) then return end
 -- only what the station holds over its own target: a house buys up a
 -- glut, it doesn't strip a shelf bare
 local spare=S.available(u,site,item)-E.target(u,site,item)
 local n=math.min(h.lot,spare,h.hold-held(rec,site,item))
 local unit=price*(1+T.marketSpread)
 n=math.min(n,math.floor(rec.credits/math.max(.01,unit)))
 if n<1 or not S.take(u,site,item,n) then return end
 local cost=math.floor(n*unit+.5)
 -- average cost of what it holds of this good, to know a profit when it sees one
 rec.cost=rec.cost or {}
 local before=0;for _,w in pairs(rec.stock) do before=before+(w[item] or 0) end
 rec.cost[item]=((rec.cost[item] or 0)*before+unit*n)/(before+n)
 rec.credits=rec.credits-cost;hold(rec,site,item,n);rec.deals=rec.deals+1
 E.ledger(u,site,'sold',cost,item);E.ledger(u,h.id,'spent',cost,item)
 require('src.simulation_history').note(u,'merchant_bought',clock,L.byId[site].area,{},{house=h.id,item=item,amount=n,price=unit},site)
 return true
end

-- Sell into a station whose price is over the house's line, from the
-- nearest warehouse holding the good.
local function sell(u,h,rec,target,item,clock)
 local Markets,S,E=require('src.markets'),require('src.stockpile'),require('src.economy')
 local Transport,Tasks=require('src.transport'),require('src.tasks')
 local price=Markets.price(u,target,item)
 local d=require('src.data').items[item]
 local unit=price*(1-T.marketSpread)
 -- its own line, or any clear profit on what it paid (or, insolvent, any
 -- price over list: cash now)
 local line=(d.price or 0)*(rec.insolvent and T.merchantFireSale or h.sellAbove)
 local paid=rec.cost and rec.cost[item]
 if paid and not rec.insolvent then line=math.min(line,paid*(1+T.merchantMargin)) end
 if price<=line then return end
 -- a station takes what it would reorder anyway (up to twice its target)
 local want=E.target(u,target,item)
 local short=math.max(0,want*2-S.count(u,target,item))
 if short<1 then return end
 for _,site in ipairs(sites(h)) do
  local n=math.min(held(rec,site,item),h.lot,short)
  if n>=1 then
   local income=math.floor(n*unit+.5)
   if site==target then
    hold(rec,site,item,-n);S.add(u,site,item,n)
   else
    if not Transport.route(site,target,clock) then n=0
    else
     -- the goods go back on the warehouse station's shelf, reserved by an
     -- ordinary freight job to the buyer; the house pays the courier
     local offer=Transport.quote({kind='transport',source=site,target=target,item=item,amount=n,stocked=true,
      layoutScope='merchant',house=h.id,order=true,priority=0,urgency=1,cooldown=30,placed=clock,
      npcClaimAt=clock+T.freightListingSeconds},clock,u)
     local fee=Transport.payment(offer)
     if fee>=income then n=0
     else
      hold(rec,site,item,-n);S.add(u,site,item,n);Tasks.post(u,offer)
      income=income-fee;E.ledger(u,h.id,'freight',fee,item)
     end
    end
   end
   if n>=1 then
    rec.credits=rec.credits+income;rec.deals=rec.deals+1;rec.lastSale=clock
    E.ledger(u,target,'bought',income,item);E.ledger(u,h.id,'earned',income,item)
    require('src.simulation_history').note(u,'merchant_sold',clock,L.byId[target].area,{},{house=h.id,item=item,amount=n,price=unit,from=site},target)
    return true
   end
  end
 end
end

-- The buffer: a factory's surplus doesn't sit on its own shelf. A house
-- buys what one of its own faction's stations holds over twice its target
-- and has it hauled to the house's hub warehouse (warehouses[1]), where it
-- waits as house stock until some station is short (sell). Up to
-- T.merchantBuffer of each good, counting what is already on the way.
local function intake(u,h,rec,site,item,clock)
 local hub=h.warehouses[1]
 if site==hub or site==M.exchange or not exists(hub) then return end
 local Markets,S,E=require('src.markets'),require('src.stockpile'),require('src.economy')
 local Transport,Tasks=require('src.transport'),require('src.tasks')
 rec.inbound=rec.inbound or {}
 local spare=S.available(u,site,item)-math.max(E.target(u,site,item)*2,E.lot or 120)
 local room=T.merchantBuffer-held(rec,hub,item)-(rec.inbound[item] or 0)
 local n=math.floor(math.min(h.lot*2,spare,room))
 if n<h.lot*.25 or not Transport.route(site,hub,clock) then return end
 local unit=Markets.price(u,site,item)*(1+T.marketSpread)
 local offer=Transport.quote({kind='transport',source=site,target=hub,item=item,amount=n,stocked=true,
  layoutScope='merchant',house=h.id,intake=h.id,order=true,priority=0,urgency=1,cooldown=30,placed=clock,
  npcClaimAt=clock+T.freightListingSeconds},clock,u)
 local fee=Transport.payment(offer)
 local cost=math.floor(n*unit+.5)
 if cost+fee>rec.credits then return end
 -- the goods stay on the factory shelf, reserved by the freight job; the
 -- house owns them from now on and books them in when they land
 rec.credits=rec.credits-cost-fee;rec.deals=rec.deals+1
 rec.inbound[item]=(rec.inbound[item] or 0)+n
 rec.cost=rec.cost or {}
 local before=0;for _,w in pairs(rec.stock) do before=before+(w[item] or 0) end
 rec.cost[item]=((rec.cost[item] or 0)*before+unit*n)/(before+n)
 Tasks.post(u,offer)
 E.ledger(u,site,'sold',cost,item);E.ledger(u,h.id,'spent',cost,item);E.ledger(u,h.id,'freight',fee,item)
 require('src.simulation_history').note(u,'merchant_intake',clock,L.byId[site].area,{},{house=h.id,item=item,amount=n,price=unit,to=hub},site)
 return true
end
-- A house's intake freight has landed at its hub: off the shelf, into stock.
function M.received(u,id,station,item,n)
 local h=M.byId[id];local rec=M.state(u).houses[id];if not h or not rec then return end
 local S=require('src.stockpile')
 rec.inbound=rec.inbound or {}
 rec.inbound[item]=math.max(0,(rec.inbound[item] or 0)-n)
 if S.take(u,station,item,n) then hold(rec,station,item,n) end
end

function M.update(u,clock)
 local s=M.state(u)
 if clock<(s.next or 0) then return end
 s.next=clock+T.merchantTick
 local Markets=require('src.markets')
 local items={};for item in pairs(Markets.items) do items[#items+1]=item end
 table.sort(items)
 local stations={}
 for _,area in ipairs(Fields.list) do for _,id in ipairs(L.stations(area,'trade')) do stations[#stations+1]=id end end
 -- the best price each good fetches anywhere right now
 M.peak={}
 for _,item in ipairs(items) do
  local best=0
  for _,id in ipairs(stations) do best=math.max(best,Markets.price(u,id,item)) end
  M.peak[item]=best
 end
 for _,h in ipairs(M.houses) do
  local rec=s.houses[h.id]
  for _,item in ipairs(items) do
   if not rec.insolvent then for _,site in ipairs(sites(h)) do
    if not buy(u,h,rec,site,item,clock) then intake(u,h,rec,site,item,clock) end
   end end
   -- own faction first, then (if it reaches) everyone else
   local own,other={}, {}
   for _,id in ipairs(stations) do
    if factionOf(id)==h.faction then own[#own+1]=id elseif h.reach=='any' then other[#other+1]=id end
   end
   for _,list in ipairs({own,other}) do for _,id in ipairs(list) do sell(u,h,rec,id,item,clock) end end
  end
  -- Insolvent: nearly out of cash and nothing sold for a long while (its
  -- stock bought too dear to move). It stays in business, which is the
  -- point: it stops buying and dumps stock at any price over list to
  -- raise cash, and the quest layer can pick that up (a fire sale to
  -- profit from, creditors to settle, a rescue: M.bailout). It recovers
  -- once its cash is back over merchantRecover of its capital.
  if not rec.insolvent and rec.credits<h.capital*T.merchantBankrupt and clock-(rec.lastSale or clock)>T.merchantStale then
   rec.insolvent=clock;rec.failures=(rec.failures or 0)+1
   require('src.simulation_history').note(u,'merchant_insolvent',clock,nil,{},{house=h.id,credits=rec.credits})
   require('src.events').emit('merchant_insolvent',h.id,rec)
  elseif rec.insolvent and rec.credits>=h.capital*T.merchantRecover then
   rec.insolvent=nil
   require('src.simulation_history').note(u,'merchant_recovered',clock,nil,{},{house=h.id,credits=rec.credits})
   require('src.events').emit('merchant_recovered',h.id,rec)
  end
 end
end
-- Someone (the player, a faction, a quest) puts credits into a house.
function M.bailout(u,id,credits)
 local rec=M.state(u).houses[id];if not rec or credits<=0 then return false end
 rec.credits=rec.credits+credits;rec.lastSale=u.clock
 require('src.economy').ledger(u,id,'bailout',credits)
 return true
end
-- Houses currently insolvent: { {house=def, record=rec}, ... }
function M.insolvent(u)
 local out={}
 for _,h in ipairs(M.houses) do local rec=M.state(u).houses[h.id];if rec.insolvent then out[#out+1]={house=h,record=rec} end end
 return out
end
return M
