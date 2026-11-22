--[[
	Station needs: what a station uses up just by having people aboard,
	as opposed to its industry (src/industry.lua), which turns inputs into
	goods. Two of them, food and water:

	  food   src/food.lua: farms grow it, everyone eats it
	         (place.food.use, world_layout defaults.foodUse)
	  water  the 'water' facility every station gets (world_layout's
	         drinks: defaults.waterUse), on the use_water recipe

	Both burn a base rate a game hour, plus what crews on shore leave there
	eat and drink (src/crew_fatigue.lua): T.restFoodPerCrew and
	T.restWaterPerCrew for each one. What they use is bought from the
	station's own shelf like any other consumption (src/economy.lua
	E.consume), so a station whose dock is busy runs short sooner and the
	freight board carries the difference.

	The Manage tab's Services pane reads S.status.
]]
local L=require('src.locations')
local T=require('src.tuning')
local S={}

local function Food() return require('src.food') end
local function water() return require('src.commodities').byId.use_water end

S.list={
 {id='food',name='Food',item='food_crate',unit='crates',perCrew=function() return T.restFoodPerCrew end},
 {id='water',name='Water',item='water',unit='tanks',perCrew=function() return T.restWaterPerCrew end},
}
S.byId={};for _,s in ipairs(S.list) do S.byId[s.id]=s end

-- Is this facility a station service rather than an industry line?
function S.isService(facilityId) return facilityId=='water' end

-- The station's own use a game hour, without resting crews.
function S.baseUse(key,id)
 key=L.canonical(key)
 if id=='food' then return (Food().rates(key)) end
 if id=='water' then local c=water();return c and c.use[key] or 0 end
 return 0
end
function S.resting(u,key) return require('src.crew_fatigue').resting(u,key) end
-- Extra use a game hour from crews on shore leave here.
function S.residentUse(u,key,id)
 if S.baseUse(key,id)<=0 and id=='water' then return 0 end   -- (a station that doesn't drink at all serves no water)
 return S.resting(u,key)*S.byId[id].perCrew()
end
function S.use(u,key,id) return S.baseUse(key,id)+S.residentUse(u,key,id) end

-- Stockpile catch-up's water pass (src/stockpile.lua S.flow), once per
-- interval: the station and its resting crews drink.
function S.flowWater(u,key,shop,dt)
 local c=water()
 if not c or not shop then return 0 end
 local use=S.use(u,key,'water')
 if use<=0 then return 0 end
 return require('src.industry').flow(u,key,c,shop,dt,-use)
end

-- One row per service, for the Services pane.
function S.status(u,key)
 key=L.canonical(key)
 local Stock=require('src.stockpile')
 local out={}
 for _,s in ipairs(S.list) do
  local base=S.baseUse(key,s.id)
  if base>0 then
   local resident=S.residentUse(u,key,s.id)
   local have=Stock.count(u,key,s.item)
   local use=base+resident
   local hours=use>0 and have/use or math.huge
   local make=s.id=='food' and select(2,Food().rates(key)) or 0
   out[#out+1]={id=s.id,name=s.name,item=s.item,unit=s.unit,base=base,resident=resident,use=use,make=make,stock=have,hours=hours,
    condition=have==0 and 'Out' or hours<1 and 'Short' or 'Supplied'}
  end
 end
 return out
end
-- Shore leave here: crews resting now and what it's taken in.
function S.shoreLeave(u,key)
 key=L.canonical(key)
 local F=require('src.crew_fatigue')
 return {resting=S.resting(u,key),kind=F.kind(key).name,rate=F.rate(u,key,nil)}
end
return S
