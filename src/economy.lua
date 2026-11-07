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
	  orders    every E.tick seconds, each station short of its target
	            (counting what's already on the way) posts transport orders
	            of up to E.lot, each from the best supplier: the one with the
	            most to spare above its own target, nearer ones first. Old
	            unclaimed orders are withdrawn and placed again, so they
	            follow wherever the stock is now.
	  suppliers a good's makers (src/commodities.lua), the mines that dig
	            it, and freight hubs that collect it (src/jobs.lua). A
	            supplier never empties itself below its own target.

	Works on the universe table alone, so it runs the same offline.
]]
local L=require('src.locations')
local Fields=require('src.fields')
local Tasks=require('src.tasks')
local Stock=require('src.stockpile')
local C=require('src.commodities')
local J=require('src.jobs')
local T=require('src.tuning')
local E={tick=60,lot=120,hours=4,halfLife=4*3600,expire=1200,reserveHours=1,scope='economy'}
-- Every trade station keeps at least this much of these on hand.
E.floor={deuterium_canister=40}

-- Usage ----------------------------------------------------------------

local function record(u,key)
 local r=Stock.record(u,key);r.usage=r.usage or {};return r.usage
end
function E.consume(u,key,item,n)
 if n<=0 or not u.clock then return end
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
-- What a station's recipes would use an hour, running flat out.
local function capacityUse(key,item)
 local place=L.byId[key];if not place then return 0 end
 local n=0
 for _,c in ipairs(C.list) do
  n=n+(c.use[place.area] or 0)*(c.item==item and 1 or 0)
  for _,input in ipairs(C.inputs(c)) do
   if input.item==item then n=n+(c.make[place.area] or 0)*input.n end
  end
 end
 return n
end
-- A supplier keeps only E.reserveHours of its own use back: what it makes
-- is for shipping, and hoarding hours of local sales starves everyone else.
local function makes(key,item)
 local place=L.byId[key];if not place then return false end
 for _,c in ipairs(C.list) do if c.item==item and (c.make[place.area] or 0)>0 then return true end end
 return false
end
function E.target(u,key,item,supplier)
 local want=math.max(E.rate(u,key,item),capacityUse(key,item))*(supplier and E.reserveHours or E.hours)
 local floor=E.floor[item]
 if floor and supportsSupplies(key) then want=math.max(want,floor) end
 return math.ceil(want)
end
-- Goods and their consumers / suppliers, rebuilt when the world changes.
local function goods()
 local g={}
 local function good(item) g[item]=g[item] or {item=item,consumers={},suppliers={}};return g[item] end
 local function add(list,id) for _,x in ipairs(list) do if x==id then return end end list[#list+1]=id end
 for _,c in ipairs(C.list) do
  for area in pairs(c.make) do for _,id in ipairs(tradeStations(area)) do add(good(c.item).suppliers,id) end end
  for area in pairs(c.use) do for _,id in ipairs(tradeStations(area)) do add(good(c.item).consumers,id) end end
  for _,input in ipairs(C.inputs(c)) do
   for area in pairs(c.make) do for _,id in ipairs(tradeStations(area)) do add(good(input.item).consumers,id) end end
  end
 end
 -- fuel: every station with Supplies burns it
 local fuel=require('src.reactor_fuel').item()
 for _,area in ipairs(Fields.list) do
  for _,id in ipairs(tradeStations(area)) do
   -- and hands back the spent canisters to be refilled
   if supportsSupplies(id) then add(good(fuel).consumers,id);add(good('empty_canister').suppliers,id) end
  end
 end
 -- ore: dug at the mining moons, collected at the freight hubs
 for _,mine in ipairs(J.mines) do local id=L.station(mine,'mining');if id then add(good(J.item).suppliers,id) end end
 for _,route in ipairs(J.freight) do if L.byId[route.via] then add(good(J.item).suppliers,route.via) end end
 return g
end
E.goods=goods

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
 local inbound={}
 for id,o in pairs(state.offers) do
  if o.layoutScope==E.scope then
   if o.state=='available' and clock-(o.placed or clock)>E.expire then state.offers[id]=nil
   else local k=o.target..'|'..o.item;inbound[k]=(inbound[k] or 0)+o.amount end
  end
 end
 local reach={}
 local fuel=require('src.reactor_fuel').item()
 for item,g in pairs(goods()) do
  if #g.suppliers>0 then
   -- what each supplier can spare right now
   local spare={}
   for _,s in ipairs(g.suppliers) do
    spare[s]=Stock.count(u,s,item)-E.target(u,s,item,true)
   end
   for _,c in ipairs(g.consumers) do
    -- a maker of the good serves itself first, then ships what's over
    -- below its target a station orders back up to twice it, so each
    -- order is a real load rather than the last few units used
    local want=E.target(u,c,item);local have=Stock.count(u,c,item)+(inbound[c..'|'..item] or 0)
    local short=(makes(c,item) or have>=want) and 0 or want*2-have
    while short>0 do
     local best,bestScore
     for _,s in ipairs(g.suppliers) do
      if s~=c and spare[s]>=math.min(T.orderMinLoad,short) then
       local k=s..'>'..c
       if reach[k]==nil then reach[k]=reachable(s,c,clock) end
       if reach[k] then
        local score=distance(s,c,clock)*100-spare[s]
        if not bestScore or score<bestScore then best,bestScore=s,score end
       end
      end
     end
     if not best then break end
     local n=math.min(E.lot,short,spare[best])
     -- reactor fuel first (ships stop without it), and a bare shelf before a low one
     local priority=(item==fuel and 2 or 0)+(Stock.count(u,c,item)==0 and 1 or 0)
     Tasks.post(u,{kind='transport',source=best,target=c,item=item,amount=n,stocked=true,
      layoutScope=E.scope,order=true,priority=priority,cooldown=30,placed=clock})
     spare[best]=spare[best]-n;short=short-n
    end
   end
  end
 end
end

return E
