-- Ship offers are references, never cargo items or removed ownership records.
local data=require('src.data')
local E={}
local T=require("src.tuning")
function E.item(id)
 local hull=type(id)=='string' and id:match('^ship:(.+)$')
 local h=hull and data.hulls[hull]
 if not h then return end
 local x1,y1,x2,y2=0,0,0,0
 for i=1,#h.shape,2 do
  x1,y1=math.min(x1,h.shape[i]),math.min(y1,h.shape[i+1])
  x2,y2=math.max(x2,h.shape[i]),math.max(y2,h.shape[i+1])
 end
 return {id=id,kind='ship',hull=hull,name=h.name,maker=h.maker,mass=h.mass,price=h.price,
  volume=0,w=math.ceil((x2-x1)/T.hangarCell),h=math.ceil((y2-y1)/T.hangarCell),stack=1}
end
return E
