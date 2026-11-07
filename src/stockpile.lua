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
local S={}

function S.key(st) return L.canonical(type(st)=='table' and st.key or st) end

function S.definition(st)
 if type(st)~='table' then st={key=st,locationId=st} end
 local place=st.locationId and L.byId[st.locationId]
 local id=place and place.marketId or st.marketId or st.def and st.def.marketId or require('src.world_layout').defaults.marketId
 return data.markets[id]
end

function S.shops(st)
 local mk=S.definition(st);local shops={};local supplied=false
 local existing=mk and mk.shops or {{name='Station stock',description='',sells=mk and mk.sells or {}}}
 for _,shop in ipairs(existing) do shops[#shops+1]=shop;supplied=supplied or shop.id=='supplies' end
 if not supplied then shops[#shops+1]=require('src.supplies').shop() end
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
 if not place or not place.uses or not place.uses.trade then return end
 local now=u.clock;local last=m.flowAt or now;m.flowAt=now
 local dt=now-last;if dt<=0 then return end
 local C=require('src.commodities')
 for _,c in ipairs(C.list) do
  local rate=C.rate(c,place.area)
  if rate~=0 and S.shopFor(key,c.item)==i then
   local stock=m.stock;local have=stock[c.item] or 0
   m.flowCarry=m.flowCarry or {}
   local carry=(m.flowCarry[c.item] or 0)+rate*dt/3600
   local whole=carry>=0 and math.floor(carry) or math.ceil(carry)
   if rate>0 then whole=math.max(0,math.min(whole,c.cap-have)) end
   local inputs=C.inputs(c)
   if rate>0 and #inputs>0 then
    -- making it uses up its inputs from the same station's stock
    for _,input in ipairs(inputs) do
     local can=math.floor(S.count(u,key,input.item)/input.n)
     if can<whole then whole=can;carry=whole end
    end
    if whole>0 then for _,input in ipairs(inputs) do
     S.take(u,key,input.item,whole*input.n);require('src.economy').consume(u,key,input.item,whole*input.n)
    end end
   end
   if rate<0 then whole=math.max(whole,-have);require('src.economy').consume(u,key,c.item,-whole) end
   if rate>0 then require('src.economy').stat(u,'made',c.item,whole) end
   if rate>0 and have>=c.cap then carry=0 end
   m.flowCarry[c.item]=carry-whole
   have=have+whole
   stock[c.item]=have>0 and have or nil
  end
 end
end

function S.count(u,st,id,i)
 local stock=S.stock(u,st,i or S.shopFor(st,id))
 return stock and stock[id] or 0
end
function S.add(u,st,id,n,i)
 local stock=S.stock(u,st,i or S.shopFor(st,id))
 if not stock then return false end
 stock[id]=(stock[id] or 0)+n
 return true
end
function S.take(u,st,id,n,i)
 if n<=0 then return true end
 local stock=S.stock(u,st,i or S.shopFor(st,id))
 if not stock or (stock[id] or 0)<n then return false end
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
    local _,_,cap=Shapes.of(id)
    while have<want do
     local n=math.min(cap,want-have)
     if not Hold.placeStack(hold,{id=id,n=n}) then break end
     have=have+n
    end
   end
  end
 end
end

return S
