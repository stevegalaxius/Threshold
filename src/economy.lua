--[[
	The goods economy: stations order what they run short of, and haulers
	fill the orders from whoever has it. Nothing here is a hand-set route or
	a fixed amount; it settles from what stations actually use.

	  usage     every station keeps a decaying per-hour rate of what it uses
	            up (E.consume): fuel sold at Supplies, a commodity's use, a
	            recipe's inputs. Hauling stock out is not use.
	  target    how much a station wants on hand: E.hours of its usage, or
	            of what its recipes would use running flat out (so a
	            starved maker keeps ordering instead of forgetting it ever
	            needed anything), and never below E.floor for the good.
	  orders    every E.tick seconds, for every good and every trade
	            station alike: a station that makes the good keeps
	            E.reserveHours of its use and offers the rest; any other
	            station below its target buys back up to twice it, and offers
	            whatever it holds over twice it. Buyers are served neediest
	            first, each from the nearest station with enough spare, in
	            orders of up to E.lot. Unclaimed orders expire after E.expire
	            and are placed again, so they follow wherever the stock is.
	  stats     E.stat counts what was made, used and hauled of each good,
	            for the economy test's hourly table.

	Works on the universe table alone, so it runs the same offline.
]]
local L=require('src.locations')
local Fields=require('src.fields')
local Tasks=require('src.tasks')
local Transport=require('src.transport')
local Stock=require('src.stockpile')
local C=require('src.commodities')
local Food=require('src.food')
local T=require('src.tuning')
local E={scaleMin=.25,scaleMax=4,scaleStep=.05,tick=60,lot=120,hours=2,halfLife=4*3600,expire=1200,reserveHours=1,scope='economy'}
-- Every trade station keeps at least this much of these on hand.
E.floor={deuterium_canister=40}

-- Usage ----------------------------------------------------------------

local function record(u,key)
 local r=Stock.record(u,key);r.usage=r.usage or {};return r.usage
end
-- Running totals of what was made, used and hauled, by good.
function E.stat(u,kind,item,n)
 if not n or n<=0 then return end
 u.economyStats=u.economyStats or {}
 local t=u.economyStats[kind] or {};u.economyStats[kind]=t
 t[item]=(t[item] or 0)+n
end
function E.consume(u,key,item,n)
 if n<=0 or not u.clock then return end
 E.stat(u,'used',item,n)
 local m=record(u,key);local e=m[item] or {rate=0,at=u.clock}
 local dt=math.max(0,u.clock-e.at)
 -- an exponentially weighted rate, in units an hour
 local k=math.exp(-dt/E.halfLife)
 e.rate=e.rate*k;e.at=u.clock
 e.rate=e.rate+n*3600/E.halfLife
 m[item]=e
end
function E.rate(u,key,item)
 local e=record(u,key)[item];if not e then return 0 end
 return e.rate*math.exp(-math.max(0,u.clock-e.at)/E.halfLife)
end

-- Who uses and who supplies what -----------------------------------------

local function tradeStations(area) return L.stations(area,'trade') end
local function supportsSupplies(id) return require('src.supplies').supports(id) end
-- How hard a station runs each recipe, against its authored rate: it
-- speeds up while buyers of what it makes go short and it ships all it
-- makes, and slows down while its own stock sits unwanted (E.adjust).
function E.scale(u,key,c)
 if c.factory then return require('src.chemical_economy').scale(u,key,c.item) end
 local t=u.industry and u.industry[key];return t and t[c.id] or 1
end
local function fed(u,key,c)
 for _,input in ipairs(C.inputs(c)) do
  if Stock.count(u,key,input.item)<(c.make[key] or 0)*input.n*.25 then return false end
 end
 return true
end
local function adjust(u,unmet)
 u.industry=u.industry or {}
 for _,c in ipairs(C.list) do
  if not c.factory then
  for key in pairs(c.make) do
   local t=u.industry[key] or {};u.industry[key]=t
   local v=t[c.id] or 1
   local have=Stock.count(u,key,c.item)
   -- stock piling up here always slows it, whatever anyone else is short of
   if have>=E.lot*2 then v=v*(1-E.scaleStep)
   -- speed up only with inputs on hand: a starved maker asking for more
   -- capacity would just raise its own input orders, round and round
   elseif (unmet[c.item] or 0)>0 and have<E.lot and fed(u,key,c) then v=v*(1+E.scaleStep) end
   t[c.id]=math.max(E.scaleMin,math.min(E.scaleMax,v))
  end
  end
 end
end
-- What a station's recipes would use an hour, running flat out.
local function capacityUse(u,key,item)
 local place=L.byId[key];if not place then return 0 end
 local n=item==Food.item and Food.rates(key) or 0
 if item==Food.fertilizer then n=n+Food.fertilizerUse(key) end
 for _,c in ipairs(C.list) do
  n=n+(c.use[key] or 0)*(c.item==item and 1 or 0)
  for _,input in ipairs(C.inputs(c)) do
   if input.item==item then n=n+(c.make[key] or 0)*E.scale(u,key,c)*input.n end
  end
 end
 return n
end
-- A supplier keeps only E.reserveHours of its own use back: what it makes
-- is for shipping, and hoarding hours of local sales starves everyone else.
local function makes(key,item)
 local place=L.byId[key];if not place then return false end
 if item==Food.item then local _,make=Food.rates(key);return make>0 end
 for _,c in ipairs(C.list) do if c.item==item and (c.make[key] or 0)>0 then return true end end
 return false
end
function E.target(u,key,item,supplier)
 local want=math.max(E.rate(u,key,item),capacityUse(u,key,item))*(supplier and E.reserveHours or E.hours)
 local floor=E.floor[item]
 if floor and supportsSupplies(key) then want=math.max(want,floor) end
 local P=require('src.repair_materials')
 if item==P.item and P.supports(key) then want=math.max(want,P.floor) end
 want=math.max(want,require('src.ammunition').reserve(key,item))
 local place=L.byId[key]
 if place then want=math.max(want,place.chemicalReserves and place.chemicalReserves[item] or 0) end
 if item=='nitrates' then want=math.max(want,(place and place.chemicalCapacity or 0)*E.hours) end
 return math.ceil(want)
end
-- The goods that move: every commodity, its inputs, what the drills dig,
-- and reactor fuel. Every trade station can hold, sell and buy any of them;
-- nobody is listed by hand as a supplier or a user.
local function goods()
 local set,list={},{}
 local function add(item) if item and not set[item] then set[item]=true;list[#list+1]=item end end
 for _,c in ipairs(C.list) do add(c.item);for _,input in ipairs(C.inputs(c)) do add(input.item) end end
 for _,item in pairs(require('src.ore').items) do add(item) end
 add(require('src.reactor_fuel').item())
 add(Food.item)
 table.sort(list)
 return list
end
E.goods=goods
local function stations(food)
 local list={}
 for _,area in ipairs(Fields.list) do
  for _,id in ipairs(food and L.stations(area) or tradeStations(area)) do list[#list+1]=id end
 end
 return list
end

-- Distance between two stations, for picking the nearest supplier: the AU
-- between their planets (a moon counts as its planet), and 0 for the same.
local function root(area) local m=Fields.moons[area];return m and m.parent or area end
local function distance(a,b,clock)
 local ra,rb=root(L.byId[a].area),root(L.byId[b].area)
 if ra==rb then return 0 end
 if not Fields.orbits[ra] or not Fields.orbits[rb] then return 50 end
 return Fields.distance(ra,rb,clock)
end
local function reachable(a,b,clock)
 return a~=b and require('src.travelgraph').itinerary(a,b,clock)~=nil
end

-- Orders -----------------------------------------------------------------

function E.update(u,clock)
 if clock<(u.economyNext or 0) then return end
 u.economyNext=clock+E.tick
 local state=Tasks.state(u)
 -- count what's ordered or on the way; an order nobody has taken in
 -- E.expire seconds is withdrawn, to be placed again from wherever the
 -- stock is now
 local inbound,committed={},{}
 for id,o in pairs(state.offers) do
  if o.layoutScope==E.scope then
   if o.state=='available' and clock-(o.placed or clock)>E.expire then state.offers[id]=nil
   else
    local k=o.target..'|'..o.item;inbound[k]=(inbound[k] or 0)+o.amount
    if o.state~='available' then committed[k]=(committed[k] or 0)+o.amount end
   end
  end
 end
 local reach={}
 local all=stations()
 local inhabited=stations(true)
 require('src.chemical_economy').update(u,clock,all,committed)
 -- what buyers wanted that no station could supply, by good
 local unmet={}
 for _,item in ipairs(goods()) do
  -- One rule for every good. A station that makes it keeps E.reserveHours
  -- of its own use and offers the rest. Any other station wants E.hours of
  -- its use; below that it buys back up to twice that, and anything over
  -- twice that is spare (a mine, a quarry, a hub that collected stock).
  local spare,buyers={},{}
  local participants=item==Food.item and inhabited or all
  for _,s in ipairs(participants) do
   local have=math.max(0,Stock.count(u,s,item)-Transport.reserved(u,s,item,nil,true))
   if makes(s,item) then spare[s]=have-E.target(u,s,item,true)
   else
    local want=E.target(u,s,item)
    spare[s]=have-want*2
    local coming=have+(inbound[s..'|'..item] or 0)
    if want>0 and coming<want then buyers[#buyers+1]={c=s,short=want*2-coming,need=want-coming,fill=coming/want} end
   end
  end
  -- neediest first: the emptiest shelf against its target gets first call
  table.sort(buyers,function(a,b) return a.fill<b.fill or a.fill==b.fill and a.c<b.c end)
  for _,entry in ipairs(buyers) do
   local c,short=entry.c,entry.short;local need=entry.need
   while short>0 do
    local best,bestScore
    for _,s in ipairs(participants) do
     if s~=c and spare[s]>=math.min(T.orderMinLoad,short) then
      local k=s..'>'..c
      if reach[k]==nil then reach[k]=reachable(s,c,clock) end
      if reach[k] then
       local score=distance(s,c,clock)*100-spare[s]
       local Chemicals=require('src.chemical_economy')
       if Chemicals.items[item] then
        score=Chemicals.price(u,s,item)+Transport.quote({source=s,target=c,amount=1},clock).creditsPerUnit-spare[s]*1e-6
       end
       if not bestScore or score<bestScore then best,bestScore=s,score end
      end
     end
    end
    if not best then
     -- only real scarcity counts: spare stock that just can't reach this
     -- buyer is a hauling problem, not a reason to make or dig more
     local anywhere=false
     for _,s in ipairs(participants) do if s~=c and spare[s]>=math.min(T.orderMinLoad,short) then anywhere=true;break end end
     -- counted against its target, not the reorder level
     if not anywhere then unmet[item]=(unmet[item] or 0)+math.max(0,need-(entry.short-short)) end
     break
    end
    local n=math.min(math.max(1,math.floor(30/require('src.data').items[item].volume)),short,spare[best])
    -- a bare shelf before a low one
    local priority=Stock.count(u,c,item)==0 and 1 or 0
    local critical=item==Food.item or item==require('src.reactor_fuel').item()
    local production=capacityUse(u,c,item)>0
    local urgency=(critical and 3 or production and 2 or 1)*math.max(0,1-entry.fill)
    Tasks.post(u,Transport.quote({kind='transport',source=best,target=c,item=item,amount=n,stocked=true,
     layoutScope=E.scope,order=true,priority=priority,urgency=urgency,cooldown=30,placed=clock},clock,u))
    spare[best]=spare[best]-n;short=short-n
   end
  end
 end
 u.economyUnmet=unmet
 adjust(u,unmet)
end

return E
