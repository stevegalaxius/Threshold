--[[
	Crisis supply: a station in a drug crisis (src/crisis.lua) asks the
	player for the drug it's burning through, on top of the freight orders
	it posts for it. The same record shape as an ore contract: bring N
	units, handed over at the station (Q.deliver), paid per unit at a
	premium over the local price that grows with the crisis's intensity.

	Lounge supply is moss's own: while a station's moss boom (safe skies)
	is at T.loungeMin or more it posts a run at a smaller premium,
	T.loungePremium, and posts the next one after its cooldown for as long
	as the boom lasts. It's withdrawn when wildcats end the boom.

	Only while the crisis is at T.crisisQuestMin or worse.
	In a power that outlaws the drug (Elysium (Earth), say),
	the run in is a smuggling run: its police sweep harder while the
	crisis lasts (src/contraband.lua). Such a job is off the books: it
	makes and costs no standing with that power (q.quiet).

	The offer is withdrawn when the crisis ends.
]]
local Q=require('src.quests')
local T=require('src.tuning')
local L=require('src.locations')
local Stock=require('src.stockpile')
local Cr=require('src.crisis')
local data=require('src.data')

local function unit(u,st,item,intensity)
 local premium=T.crisisQuestPremium+T.crisisQuestUrgency*intensity
 return math.max(1,math.floor(require('src.markets').price(u,st,item)*premium+.5))
end
local function peak(st,item)
 for _,c in ipairs(Cr.consumers()[st] or {}) do if c.item==item then return c.use[st] or 0 end end
 return 0
end

local WHY={
 production_pressure='crews on double shifts need stims',
 food_shortage='hungry crews are getting through on fentanyl',
}

Q.order[#Q.order+1]='drug_crisis'
Q.deliveries.drug_crisis=true
Q.generators.drug_crisis={
 label='Crisis supply',
 keep=function(u,q)
  local e=Cr.get(u,q.giver,q.item)
  if not e or not e.active or not Cr.isCrisis(e) then return false end
  q.unit=unit(u,q.giver,q.item,e.intensity);return true
 end,
 propose=function(u,st,clock,ctx)
  local out={}
  local Rep=require('src.reputation')
  for _,c in ipairs(Cr.consumers()[st] or {}) do
   local e=Cr.get(u,st,c.item)
   if e and e.active and Cr.isCrisis(e) and e.intensity>=T.crisisQuestMin and not ctx.taken[st..'|'..c.item]
    and not Rep.embargoed(st,st,c.item) then
    local rate=peak(st,c.item)*Cr.useScale(u,st,c)
    local need=math.max(T.crisisQuestMinAmount,math.ceil(rate*T.crisisQuestHours)-Stock.count(u,st,c.item))
    local cap=math.max(1,math.floor(T.questMaxVolume/math.max(.001,data.items[c.item].volume)))
    local name=(L.byId[st] or {}).name or st
    out[#out+1]={kind='drug_crisis',giver=st,item=c.item,amount=math.floor(math.min(need,cap)),unit=unit(u,st,c.item,e.intensity),
     headline=('Crisis supply: %s for %s'):format(data.items[c.item].name,name),why=WHY[c.crisis],
     quiet=require('src.contraband').illegal(u,Rep.ofNode(st),c.item) or nil}
   end
  end
  table.sort(out,function(a,b) return a.item<b.item end)
  return out
 end,
}

Q.order[#Q.order+1]='lounge_supply'
Q.deliveries.lounge_supply=true
local function boom(u,st)
 for _,c in ipairs(Cr.consumers()[st] or {}) do
  if Cr.AXES[c.crisis].damper then local e=Cr.get(u,st,c.item);return e and e.boom or 0,c end
 end
 return 0
end
Q.generators.lounge_supply={
 label='Lounge supply',
 keep=function(u,q) return boom(u,q.giver)>0 end,
 propose=function(u,st,clock,ctx)
  local b,c=boom(u,st)
  if b<T.loungeMin or not c or ctx.taken[st..'|'..c.item] then return {} end
  if require('src.reputation').embargoed(st,st,c.item) then return {} end
  local Rep=require('src.reputation')
  local need=math.max(T.crisisQuestMinAmount,math.ceil(peak(st,c.item)*Cr.useScale(u,st,c)*T.loungeHours))
  local cap=math.max(1,math.floor(T.questMaxVolume/math.max(.001,data.items[c.item].volume)))
  return {{kind='lounge_supply',giver=st,item=c.item,amount=math.floor(math.min(need,cap)),
   unit=math.max(1,math.floor(require('src.markets').price(u,st,c.item)*T.loungePremium+.5)),
   why='safe skies, full lounges',quiet=require('src.contraband').illegal(u,Rep.ofNode(st),c.item) or nil}}
 end,
}
