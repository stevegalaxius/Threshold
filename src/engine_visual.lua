-- Engine exhaust in ship-local coordinates (+x is forward). Shared by all ships.
local data=require('src.data')
local T=require('src.tuning')
local Engine={}
-- Compatibility for old mod engines and built-in hull thrust.
local DEFAULT={width=3,length=18,color={1,.6,.25},coreColor={1,.92,.65},
 glowColor={1,.35,.08},afterburnScale=2.2,flicker=.15}
function Engine.emitters(e)
 local result,unplaced={},{}
 for i,slot in ipairs(e.hull.slots or {}) do
  local m=e.loadout[i] and data.modules[e.loadout[i]]
  if slot.family=='engine' and m and m.family=='engine' and (m.thrust or 0)>0 then
   local effect=m.exhaust or DEFAULT
   local nozzle={x=slot.x,y=slot.y or 0,width=effect.width or DEFAULT.width,effect=effect}
   result[#result+1]=nozzle
   if slot.x==nil then unplaced[#unplaced+1]=nozzle end
  end
 end
 -- Compatibility for slots made before hardpoint placement was available.
 for i,nozzle in ipairs(unplaced) do
  nozzle.x=e.tailX
  nozzle.y=(i-(#unplaced+1)/2)*nozzle.width*3
 end
 -- A hull may supply built-in thrust without an engine module.
 if #result==0 and (e.hull.thrust or 0)>0 then
  result[1]={x=e.tailX,y=0,width=DEFAULT.width,effect=DEFAULT}
 end
 return result
end
-- Fraction of the full afterburner's extra thrust, shared by drawing and
-- exhaust collisions. Normal burn is zero, full boost one.
function Engine.boostLevel(e)
 if not e.afterburn or T.boostThrust<=1 then return 0 end
 return e.burnerLocked and T.boostReserve or 1
end
-- Deterministic plume geometry shared by rendering and damage.
function Engine.geometry(nozzle,burn,boost,time,outer)
 local effect=nozzle.effect
 local flicker=effect.flicker or DEFAULT.flicker
 local jitter=math.sin((time or 0)*53+nozzle.x*.7+nozzle.y*1.3)
 local length=(effect.length or DEFAULT.length)*(1/3+burn*2/3)*(1+jitter*flicker)
 local level=type(boost)=="number" and math.max(0,math.min(1,boost)) or (boost and 1 or 0)
 length=length*(1+((effect.afterburnScale or DEFAULT.afterburnScale)-1)*level)
 if outer then return nozzle.x,nozzle.y,nozzle.width*1.4,length*1.3 end
 return nozzle.x,nozzle.y,nozzle.width,length
end
function Engine.draw(e,time)
 local burn=e.mainBurn or 0
 if burn<=.05 then return end
 local lg=love.graphics
 local boost=Engine.boostLevel(e)
 for _,nozzle in ipairs(Engine.emitters(e)) do
  local x,y,w,length=Engine.geometry(nozzle,burn,boost,time)
  local effect=nozzle.effect
  local glow=effect.glowColor or DEFAULT.glowColor
  local color=effect.color or DEFAULT.color
  local core=effect.coreColor or DEFAULT.coreColor
  lg.setColor(glow[1],glow[2],glow[3],.25)
  local gx,gy,gw,gl=Engine.geometry(nozzle,burn,boost,time,true)
  lg.polygon('fill',gx,gy-gw,gx,gy+gw,gx-gl,gy)
  lg.setColor(color[1],color[2],color[3],.9)
  lg.polygon('fill',x,y-w,x,y+w,x-length,y)
  lg.setColor(core[1],core[2],core[3],.95)
  lg.polygon('fill',x,y-w*.45,x,y+w*.45,x-length*.45,y)
 end
end
return Engine
