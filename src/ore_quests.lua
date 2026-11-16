--[[
	Ore contracts: player mining work, posted by the station a drill field
	ships its ore home to (src/mining.lua sites' `home`). NPC miners keep
	their own board job ("mine": fly a packhorse to a drill rig, haul its
	output home); the player instead gets a quest in the same record shape as
	a shortage delivery: bring N units of the ore those drills produce, mined
	however you like (rig chunks, cracked rocks), and hand it over at the
	station for T.oreQuestPremium of its price. Delivered ore goes into the
	station's stock, exactly as a miner's delivery does, so freight ships it
	on from there.

	A station posts one while its ore stock is under what it keeps in reserve
	for the freight it supplies (economy.lua E.target with supplier=true),
	or under T.oreQuestReserve where that reserve is smaller.
]]
local Q=require('src.quests')
local T=require('src.tuning')
local L=require('src.locations')
local Stock=require('src.stockpile')
local data=require('src.data')

-- The ores each home station's drill fields produce.
local function ores(u,st)
 local out,seen={},{}
 for _,site in pairs(require('src.mining').state(u).sites or {}) do
  if site.home and L.canonical(site.home)==st and site.item and not seen[site.item] and data.items[site.item] then
   seen[site.item]=true;out[#out+1]=site.item
  end
 end
 table.sort(out)
 return out
end
local function short(u,st,item)
 -- (a home that ships all its ore straight on, like Phobos to Mars, keeps
 -- no reserve of its own: it still buys up to T.oreQuestReserve)
 local want=math.max(require('src.economy').target(u,st,item,true),T.oreQuestReserve)
 return want-Stock.count(u,st,item)
end
local function unit(u,st,item)
 return math.max(1,math.floor(require('src.markets').price(u,st,item)*T.oreQuestPremium+.5))
end

Q.order[#Q.order+1]='ore_delivery'
Q.deliveries.ore_delivery=true
Q.generators.ore_delivery={
 label='Ore contract',
 keep=function(u,q) q.unit=unit(u,q.giver,q.item);return short(u,q.giver,q.item)>0 end,
 propose=function(u,st,clock,ctx)
  local out={}
  for _,item in ipairs(ores(u,st)) do
   local need=short(u,st,item)
   if need>=T.oreQuestMin and not ctx.taken[st..'|'..item] then
    local cap=math.max(1,math.floor(T.questMaxVolume/math.max(.001,data.items[item].volume)))
    out[#out+1]={kind='ore_delivery',giver=st,item=item,amount=math.floor(math.min(need,cap)),unit=unit(u,st,item)}
   end
  end
  return out
 end,
}
