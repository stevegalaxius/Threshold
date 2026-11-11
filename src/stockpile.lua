--[[
	Station stockpiles: one per shop. A station's market definition
	(data/markets.lua) lists its shops; each shop keeps its own count of
	goods (u.stations[key].shops[i].stock = { id = n }). The market shelf
	the player trades on is a view of that count (src/market.lua), and NPC
	hauling and mining take from and deliver to it (src/jobs.lua).

	  shopFor   NPC goods go to the first stocked shop that lists the
	            item, else the station's first shop.
	  seeding   a shop's stock starts at its full catalogue (max stacks of
	            each entry). A save from before stockpiles counts the stock
	            on its shelf instead, and the old per-station ore stock
	            (u.mining.stock) is folded in once.
	  unlimited the Supplies shop has no stockpile.

	Works on the universe table alone, so offline A-Life can use it.
]]
local data=require('src.data')
local L=require('src.locations')
local Shapes=require('src.inventory.shapes')
local Hold=require('src.inventory.hold')
local T=require('src.tuning')
local S={shopCache={}}

function S.key(st) return L.canonical(type(st)=='table' and st.key or st) end

function S.definition(st)
 if type(st)~='table' then st={key=st,locationId=st} end
 local place=st.locationId and L.byId[st.locationId]
 local id=place and place.marketId or st.marketId or st.def and st.def.marketId or require('src.world_layout').defaults.marketId
 return data.markets[id]
end

function S.shops(st)
 local mk=S.definition(st);local cacheKey=S.key(st) or mk
 if S.shopCache[cacheKey] then return S.shopCache[cacheKey] end
 local shops={};local supplied,fueled,food,steel,chemicals=false,false,false,false,false
 local ammo=false
 local fuel=require('src.reactor_fuel').item()
 local existing=mk and mk.shops or {{name='Station stock',description='',sells=mk and mk.sells or {}}}
 for _,shop in ipairs(existing) do
  shops[#shops+1]=shop;supplied=supplied or shop.id=='supplies'
  fueled=fueled or not shop.unlimited and S.lists(shop,fuel)
  food=food or not shop.unlimited and S.lists(shop,'food_crate')
  steel=steel or not shop.unlimited and S.lists(shop,'steel_plate')
  chemicals=chemicals or not shop.unlimited and S.lists(shop,'nitrates') and S.lists(shop,'explosives')
  ammo=ammo or shop.id=='ammunition'
 end
 if not food then shops[#shops+1]=require('src.food').shop() end
 if not steel then shops[#shops+1]=require('src.repair_materials').shop() end
 if not chemicals then shops[#shops+1]=require('data.industry').shops.chemicals end
 if not ammo then shops[#shops+1]=require('src.ammunition').shop() end
 -- Any new industry good gets a real shelf without changing market code.
 local missing,seen={},{}
 for _,recipe in ipairs(require('src.commodities').list) do
  local entries={}
  if recipe.storefront==false then goto continue end
  for _,output in ipairs(require('src.commodities').outputs(recipe)) do entries[#entries+1]=output.item end
  for _,input in ipairs(require('src.commodities').inputs(recipe)) do entries[#entries+1]=input.item end
  for _,item in ipairs(entries) do
   local listed=false
   for _,shop in ipairs(shops) do if not shop.unlimited and S.lists(shop,item) then listed=true;break end end
   if not listed and not seen[item] then missing[#missing+1]={item,0};seen[item]=true end
  end
  ::continue::
 end
 if #missing>0 then shops[#shops+1]={id='industry',name='Industrial goods',sells=missing} end
 -- the real fuel storefront, unless a shop here already stocks fuel
 if not fueled then shops[#shops+1]=require('src.supplies').fuelShop() end
 if not supplied then shops[#shops+1]=require('src.supplies').shop() end
 S.shopCache[cacheKey]=shops
 return shops
end

function S.record(u,key)
 u.stations=u.stations or {}
 local r=u.stations[key]
 if not r then
  r={storage=Hold.new({{key='storage',name='Station storage',w=T.storageW,h=T.storageH}}),hangar={}}
  u.stations[key]=r
 end
 return r
end

function S.lists(shop,id)
 for _,e in ipairs(shop.sells or {}) do if e[1]==id then return true end end
 return false
end

-- Which shop an NPC's goods of this item go to and come from.
function S.shopFor(st,id)
 local shops=S.shops(st)
 for i,shop in ipairs(shops) do if not shop.unlimited and S.lists(shop,id) then return i end end
 return 1
end

local function shelfCount(hold,id)
 local n=0
 for _,g in ipairs(hold.grids) do for _,s in ipairs(g.stacks) do
  if s.id==id and not s.resale and not s.inner then n=n+s.n end
 end end
 return n
end

-- Shop i's stock table, seeded the first time. nil for an unlimited shop.
function S.stock(u,st,i)
 local key=S.key(st);local shops=S.shops(type(st)=='table' and st or key)
 local shop=shops[i];if not shop or shop.unlimited then return nil end
 local r=S.record(u,key);r.shops=r.shops or {}
 local m=r.shops[i];if not m then m={next={}};r.shops[i]=m end
 if not m.stock then
  local stock={}
  if m.hold then
   for _,g in ipairs(m.hold.grids) do for _,s in ipairs(g.stacks) do
    if not s.resale and not s.inner then stock[s.id]=(stock[s.id] or 0)+s.n end
   end end
  else
   for _,e in ipairs(shop.sells or {}) do
    local _,_,cap=Shapes.of(e[1]);stock[e[1]]=(stock[e[1]] or 0)+e[2]*cap
   end
  end
  -- a station with Supplies opens with its fuel floor on hand
  local fuel=require('src.reactor_fuel').item();local floor=require('src.economy').floor[fuel]
  if floor and S.shopFor(key,fuel)==i and L.byId[key] and require('src.supplies').supports(key) then
   stock[fuel]=math.max(stock[fuel] or 0,floor*2)
  end
  -- a new world opens part-stocked (a quarter to three quarters, fixed per
  -- station and good), so stations are ordering from the first minutes
  if not m.hold then
   for id,n in pairs(stock) do
    local h=0;local k=key..'|'..id
    for c=1,#k do h=(h*31+k:byte(c))%1000003 end
    stock[id]=math.floor(n*(.25+.5*(h%1000)/999))
   end
   if S.shopFor(key,'food_crate')==i then stock.food_crate=require('src.food').initial(key) end
   if S.shopFor(key,'fertilizer')==i then stock.fertilizer=require('src.food').initialFertilizer(key) end
  end
  local initial=require('src.industry').initial(key)
  for item,n in pairs(initial) do if S.shopFor(key,item)==i then stock[item]=n end end
  if S.shopFor(key,'explosives')==i then stock.explosives=nil end
  m.stock=stock
  -- fold in the old per-station logistics stock once
  local legacy=u.mining and u.mining.stock and u.mining.stock[key]
  if legacy and next(legacy) then
   u.mining.stock[key]=nil
   for id,n in pairs(legacy) do
    if n>0 then local j=S.shopFor(key,id);local into=j==i and stock or S.stock(u,key,j);into[id]=(into[id] or 0)+n end
   end
  end
 end
 if u.clock then S.flow(u,key,i,m) end
 return m.stock
end

-- Commodity production and use (src/commodities.lua), caught up to the
-- clock whenever the stock is looked at. Goods land in, and are used from,
-- the shop that holds them for NPCs (shopFor).
function S.flow(u,key,i,m)
 local place=L.byId[key]
 if not place or place.kind~='station' then return end
 local now=u.clock;local last=m.flowAt or now;m.flowAt=now
 local dt=now-last;if dt<=0 then return end
 local Food=require('src.food')
 local foodShop=S.shopFor(key,Food.item)
 if i==foodShop then Food.flow(u,key,m,dt)
 else S.stock(u,key,foodShop) end
 if not place.uses or not place.uses.trade then return end
 local C=require('src.commodities')
 -- Reading a co-product must settle its recipe's primary shop as well.
 for _,c in ipairs(C.list) do
  if c.make[key] and c.outputs then
   for _,output in ipairs(c.outputs) do
    local primary=S.shopFor(key,c.item)
    if S.shopFor(key,output.item)==i and primary~=i then S.stock(u,key,primary) end
   end
  end
 end
 for _,c in ipairs(C.list) do
  local rate=C.rate(c,key)*require('src.economy').scale(u,key,c)
  if rate>0 and not c.foodIndependent then rate=rate*Food.output(u,key) end
  if not c.consumption and rate~=0 and S.shopFor(key,c.item)==i then
   require('src.industry').flow(u,key,c,m,dt,rate)
  end
 end
end

function S.count(u,st,id,i)
 local stock=S.stock(u,st,i or S.shopFor(st,id))
 return stock and stock[id] or 0
end
-- Physical stock remains authoritative for storage; consumers see only
-- goods not committed to a freight pickup.
function S.reserved(u,st,id,except)
 local n=0;local key=S.key(st)
 for _,o in pairs(u.tasks and u.tasks.offers or {}) do
  if o.order and o.source==key and o.item==id and not o.loaded and o.state~='available'
   and (not except or o.id~=except and o.manifestRoot~=except) then n=n+o.amount end
 end
 return n
end
function S.available(u,st,id,i,except)
 return math.max(0,S.count(u,st,id,i)-S.reserved(u,st,id,except))
end
function S.shelf(u,st,i)
 local stock=S.stock(u,st,i);if not stock then return end
 local result={}
 for id,n in pairs(stock) do result[id]=math.max(0,n-S.reserved(u,st,id)) end
 return result
end
function S.add(u,st,id,n,i)
 local stock=S.stock(u,st,i or S.shopFor(st,id))
 if not stock then return false end
 stock[id]=(stock[id] or 0)+n
 return true
end
function S.take(u,st,id,n,i,reservation)
 if n<=0 then return true end
 local stock=S.stock(u,st,i or S.shopFor(st,id))
 if not stock or S.available(u,st,id,i,reservation)<n then return false end
 stock[id]=stock[id]-n
 if stock[id]==0 then stock[id]=nil end
 return true
end

-- Make the shelf grid show what the stock holds, less what's out on the
-- trade grid (away = { id = n }). Only touches items whose count changed,
-- so stacks don't jump around.
function S.syncShelf(hold,stock,away)
 local ids={}
 for id in pairs(stock) do ids[id]=true end
 for _,g in ipairs(hold.grids) do for _,s in ipairs(g.stacks) do
  if not s.resale and not s.inner then ids[s.id]=true end
 end end
 local Grid=require('src.inventory.grid')
 for id in pairs(ids) do
  if data.items[id] then
   local want=math.max(0,(stock[id] or 0)-(away and away[id] or 0))
   -- fold a shelf from before unlimited stacks into one stack per item
   local first
   for _,g in ipairs(hold.grids) do for k=#g.stacks,1,-1 do
    local s=g.stacks[k]
    if s.id==id and not s.resale and not s.inner then
     if first then first.n=first.n+s.n;Grid.remove(g,s) else first=s end
    end
   end end
   local have=shelfCount(hold,id)
   if have>want then
    for _,g in ipairs(hold.grids) do for k=#g.stacks,1,-1 do
     local s=g.stacks[k]
     if have>want and s.id==id and not s.resale and not s.inner then
      local cut=math.min(s.n,have-want)
      if cut==s.n then Grid.remove(g,s) else s.n=s.n-cut end
      have=have-cut
     end
    end end
   end
   if have<want then
    -- the shelf stacks without limit: one stack per item, topped up
    local top
    for _,g in ipairs(hold.grids) do for _,s in ipairs(g.stacks) do
     if not top and s.id==id and not s.resale and not s.inner then top=s end
    end end
    if top then top.n=top.n+(want-have)
    else Hold.placeStack(hold,{id=id,n=want-have}) end
   end
  end
 end
end

return S
