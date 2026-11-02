-- Engine exhaust in ship-local coordinates (+x is forward). Shared by all ships.
local data=require('src.data')
local Engine={}
local WIDTH={S=3,M=5,L=8}
function Engine.emitters(e)
 local result,unplaced={},{}
 for i,slot in ipairs(e.hull.slots or {}) do
  local m=e.loadout[i] and data.modules[e.loadout[i]]
  if slot.family=='engine' and m and m.family=='engine' and (m.thrust or 0)>0 then
   local nozzle={x=slot.x,y=slot.y or 0,width=WIDTH[m.size] or 3}
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
  result[1]={x=e.tailX,y=0,width=math.max(3,e.hull.radius*.15)}
 end
 return result
end
function Engine.draw(e)
 local burn=e.mainBurn or 0
 if burn<=.05 then return end
 local lg=love.graphics
 for _,nozzle in ipairs(Engine.emitters(e)) do
  local x,y,w=nozzle.x,nozzle.y,nozzle.width
  local length=w*(2+burn*4)*(.85+love.math.random()*.3)
  if e.afterburn then length=length*2.2 end
  lg.setColor(1,.35,.08,.25)
  lg.polygon('fill',x,y-w*1.4,x,y+w*1.4,x-length*1.3,y)
  lg.setColor(1,.6,.25,.9)
  lg.polygon('fill',x,y-w,x,y+w,x-length,y)
  lg.setColor(1,.92,.65,.95)
  lg.polygon('fill',x,y-w*.45,x,y+w*.45,x-length*.45,y)
 end
end
return Engine
