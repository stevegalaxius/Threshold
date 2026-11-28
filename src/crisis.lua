--[[
	Station crises: what drives a station's appetite for the cartel's drugs.

	A station that takes a drug (a use_* facility in src/world_layout.lua
	whose recipe in data/industry.lua names a `crisis`) no longer burns it
	at a flat rate. The authored capacity is its peak: what it uses at the
	height of a crisis. Calm, it uses T.crisisBaseUse of that; in a crisis
	the rest scales in with the crisis's intensity.

	Each drug answers a different question about the station:
	  amphetamines      production pressure: more than T.crisisBusyDocked
	                    NPC ships docked there (a half hour's average).
	                    Crews pushing extra shifts.
	  fentanyl          food shortage: its food output down (src/food.lua),
	                    or its crates under T.crisisFoodHours of eating.
	  cannabinoid_moss  not a crisis but its opposite, a boom: the leisure
	                    drug runs at its authored rate, climbs toward
	                    T.mossBoomUse the longer its system has gone without
	                    wildcats (src/wildcats.lua), and drops to
	                    T.crisisThreatUse while they're about. A boom posts
	                    lounge_supply runs (smaller premium, recurring),
	                    makes the news, and frees the system's patrols to
	                    sweep for smugglers (Cr.heat). It cuts no trade:
	                    nothing it does feeds back into wildcats or docking.

	A condition has to hold for the drug's check hours before a crisis
	starts, and has to stay gone for its resolve hours before it ends.
	Intensity eases toward the condition's strength (T.crisisEase an hour)
	rather than jumping, and back to zero once it's over. Nothing ratchets:
	a station recovers completely.

	While a station is in crisis:
	  - it uses more of the drug (Crisis.useScale: src/industry.lua scale,
	    src/economy.lua targets), so its stock runs down, it posts freight
	    orders and its price climbs: the market signal.
	  - it keeps less of everything else on hand (Crisis.tradeScale in
	    E.target), so its board goes quieter. Food and its inputs are
	    never cut.
	  - it may post a drug_crisis delivery (src/crisis_quests.lua).
	  - in a power that outlaws the drug (src/contraband.lua), its
	    police sweep its area harder (Crisis.heat).
	News carries a crisis starting and ending.

	Saved per station: S.record(u,key).crisis[drug] = { held, calm, active,
	intensity, since }. u.crisisNext is the next tick.
]]
local T=require('src.tuning')
local L=require('src.locations')
local Fields=require('src.fields')
local Cr={}

Cr.AXES={
 production_pressure={drug='amphetamines',check='crisisBusyHours',resolve='crisisBusyResolveHours'},
 food_shortage={drug='fentanyl',check='crisisFoodCheckHours',resolve='crisisFoodResolveHours'},
 -- (moss is no crisis: wildcats about put a damper on a steady demand)
 wildcat_threat={drug='cannabinoid_moss',check='crisisThreatHours',resolve='crisisThreatResolveHours',damper=true},
}

-- The recipes that a crisis drives, by station: { [key] = { recipe, ... } }.
local consumers
function Cr.consumers()
 if consumers then return consumers end
 consumers={}
 for _,c in ipairs(require('src.commodities').list) do
  if c.crisis then for key,n in pairs(c.use or {}) do if n>0 then
   local list=consumers[key] or {};consumers[key]=list;list[#list+1]=c
  end end end
 end
 for _,list in pairs(consumers) do table.sort(list,function(a,b) return a.id<b.id end) end
 return consumers
end
function Cr.reset() consumers=nil end

local function system(area)
 local m=area and Fields.moons and Fields.moons[area]
 return m and m.parent or area
end
local function clamp(x) return math.max(0,math.min(1,x)) end

-- Signals: how strongly each condition holds right now, 0..1 --------------

local signal={}
function signal.production_pressure(u,key,ctx,dt)
 -- NPC ships docked there, averaged over half an hour so one arrival
 -- doesn't swing it: past T.crisisBusyDocked the crews are stretched
 local n=ctx.docked[key] or 0
 local e=Cr.entry(u,key,'amphetamines')
 e.busy=e.busy and e.busy+(n-e.busy)*(1-0.5^(dt/1800)) or n
 e.normal=nil
 return clamp((e.busy-T.crisisBusyDocked)/T.crisisBusyDocked*2)
end
function signal.food_shortage(u,key)
 local Food=require('src.food')
 local use=Food.rates(key)
 if use<=0 then return 0 end
 local hungry=clamp((1-Food.output(u,key))/(1-Food.minOutput))
 local hours=require('src.stockpile').count(u,key,Food.item)/use
 local low=hours<T.crisisFoodHours and clamp(1-hours/T.crisisFoodHours) or 0
 return math.max(hungry,low)
end
function signal.wildcat_threat(u,key,ctx)
 local place=L.byId[key]
 local n=ctx.wildcats[system(place and place.area)] or 0
 return n>T.crisisCalmWildcats and 1 or 0
end

-- Live wildcats by system, and docked NPCs by station: once a tick.
local function context(u)
 local ctx={docked={},wildcats={}}
 local homes={}
 for id,inst in pairs(require('src.sites').list(u)) do if not inst.done then homes[id]=system(inst.home) end end
 for _,r in pairs(u.npcs or {}) do
  if r.state~='dead' and r.state~='escaped' then
   if r.wildcat then
    local sys=homes[r.wildcat.site]
    if sys then ctx.wildcats[sys]=(ctx.wildcats[sys] or 0)+1 end
   elseif r.state=='docked' and r.node then
    local k=L.canonical(r.node);ctx.docked[k]=(ctx.docked[k] or 0)+1
   end
  end
 end
 return ctx
end
Cr.context=context
Cr.signal=signal

-- State --------------------------------------------------------------------

function Cr.entry(u,key,drug)
 local rec=require('src.stockpile').record(u,key)
 rec.crisis=rec.crisis or {}
 local e=rec.crisis[drug]
 if not e then e={held=0,calm=0,intensity=0};rec.crisis[drug]=e end
 return e
end
-- A station's crisis over one drug, if it has one on record.
function Cr.get(u,key,drug)
 local r=u.stations and u.stations[key]
 return r and r.crisis and r.crisis[drug]
end

local function placeName(key) return (L.byId[key] or {}).name or key end
local HEADLINES={
 production_pressure={start='Double shifts at %s: stim sales climb',stop='%s eases off the double shifts'},
 food_shortage={start='Short of food, crews at %s turn to fentanyl',stop='Food is back on the tables at %s'},
 boom={start='Safe skies, full lounges: moss flows at %s',stop='Wildcats about: the moss lounges at %s empty out'},
}
local function news(u,key,axis,what)
 local N=require('src.news');local Outlets=require('data.outlets')
 local place=L.byId[key];if not place then return end
 local text=HEADLINES[axis][what]
 local drug=axis=='boom' and 'cannabinoid_moss' or Cr.AXES[axis].drug
 local where=placeName(key)
 for _,o in ipairs(Outlets.order) do
  if N.covers(u,o,place.area) then
   N.publish(u,{outlet=o,kind='crisis',area=place.area,station=key,good=drug,headline=text:format(where),fact='crisis:'..key..':'..axis..':'..what})
  end
 end
end

-- One step of dt seconds for one station's crisis over one axis.
function Cr.step(u,key,axis,s,dt,clock)
 local def=Cr.AXES[axis]
 local e=Cr.entry(u,key,def.drug)
 local hours=dt/3600
 e.signal=s
 if s>0 then e.held=e.held+hours;e.calm=0
 else e.calm=e.calm+hours;e.held=math.max(0,e.held-hours*T.crisisHeldDecay) end
 if def.damper then
  -- safe skies: hours without wildcats build a boom, and they end it
  e.clear=s>0 and 0 or (e.clear or 0)+hours
  local was=e.boom or 0
  e.boom=s>0 and math.max(0,was-T.crisisEase*hours) or math.min(1,math.max(0,(e.clear-T.mossBoomHours)/T.mossBoomRamp))
  if was<.5 and e.boom>=.5 then news(u,key,'boom','start') elseif was>0 and e.boom==0 and s>0 then news(u,key,'boom','stop') end
 end
 if not e.active and e.held>=T[def.check] then
  e.active=true;e.since=clock;e.axis=axis
  if not def.damper then news(u,key,axis,'start') end
  require('src.simulation_history').note(u,'crisis_start',clock,(L.byId[key] or {}).area,{},{station=key,drug=def.drug,axis=axis},nil)
 elseif e.active and e.calm>=T[def.resolve] then
  e.active=false;e.since=nil;e.held=0
  if not def.damper then news(u,key,axis,'stop') end
 end
 local goal=e.active and math.max(s,T.crisisFloor) or 0
 local step=T.crisisEase*hours
 if e.intensity<goal then e.intensity=math.min(goal,e.intensity+step) else e.intensity=math.max(goal,e.intensity-step) end
 if e.intensity<1e-4 then e.intensity=0 end
 return e
end

function Cr.update(u,clock)
 clock=clock or u.clock or 0
 if u.crisisNext and clock<u.crisisNext then return end
 local last=u.crisisAt or clock
 u.crisisAt=clock;u.crisisNext=clock+T.crisisTick
 local dt=math.min(clock-last,T.crisisTick*4)
 if dt<=0 then return end
 local ctx=context(u)
 for key,list in pairs(Cr.consumers()) do
  for _,c in ipairs(list) do
   Cr.step(u,key,c.crisis,signal[c.crisis](u,key,ctx,dt),dt,clock)
  end
 end
end

-- Effects --------------------------------------------------------------------

-- How hard a station runs a crisis recipe: its share of the authored peak.
function Cr.useScale(u,key,c)
 if not c.crisis then return 1 end
 local e=u and Cr.get(u,key,c.item)
 local i=e and e.intensity or 0
 if Cr.AXES[c.crisis].damper then
  if i>0 then return 1-(1-T.crisisThreatUse)*i end
  return 1+(T.mossBoomUse-1)*(e and e.boom or 0)
 end
 return T.crisisBaseUse+(1-T.crisisBaseUse)*i
end
-- The worst crisis at a station right now (0 when none).
local function crisis(e) return not (e.axis and Cr.AXES[e.axis] and Cr.AXES[e.axis].damper) and e.axis~='low_threat' end
Cr.isCrisis=crisis
function Cr.intensity(u,key)
 local r=u and u.stations and u.stations[key]
 local best,drug=0
 for d,e in pairs(r and r.crisis or {}) do if crisis(e) and (e.intensity or 0)>best then best,drug=e.intensity,d end end
 return best,drug
end
-- What a station in crisis keeps of its usual stock of other goods.
local spared
function Cr.tradeScale(u,key,item)
 local i,drug=Cr.intensity(u,key)
 if i<=0 or item==drug then return 1 end
 if not spared then
  local Food=require('src.food');spared={[Food.item]=true,[Food.fertilizer]=true}
  for _,c in ipairs(require('src.commodities').list) do if c.crisis then spared[c.item]=true end end
 end
 if spared[item] then return 1 end
 return 1-T.crisisTradeCut*i
end
-- How hot an area is for smugglers: the worst crisis at a station in it
-- whose power outlaws the drug it's using.
function Cr.heat(u,area)
 local Rep=require('src.reputation')
 local best=0
 for _,key in ipairs(L.stations(area,'trade')) do
  local r=u.stations and u.stations[key]
  for drug,e in pairs(r and r.crisis or {}) do
   if require('src.contraband').illegal(u,Rep.ofNode(key),drug) then
    if e.active and crisis(e) then best=math.max(best,e.intensity or 0) end
    -- a moss boom: no wildcats to chase, so the patrols look at you
    if (e.boom or 0)>0 then best=math.max(best,e.boom*T.mossBoomHeat) end
   end
  end
 end
 return best
end
-- Every station's current crises, worst first (for debug and the quests).
function Cr.list(u)
 local out={}
 for key in pairs(Cr.consumers()) do
  local r=u.stations and u.stations[key]
  for drug,e in pairs(r and r.crisis or {}) do
   if e.active and crisis(e) then out[#out+1]={station=key,drug=drug,axis=e.axis,intensity=e.intensity,since=e.since} end
  end
 end
 table.sort(out,function(a,b) return a.intensity>b.intensity or a.intensity==b.intensity and a.station..a.drug<b.station..b.drug end)
 return out
end

return Cr
