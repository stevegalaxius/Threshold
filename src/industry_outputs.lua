-- Typed manufacturing destinations share the executor's input/time rules.
local O={}
function O.room(u,key,c,output)
 if output.kind=='ship' then return math.floor(require('src.dealers').room(u,key,output.hull)/output.n) end
 local have=require('src.stockpile').count(u,key,output.item)
 return math.max(0,math.floor(((output.cap or c.cap)-have)/output.n))
end
function O.add(u,key,output,batches,c)
 if output.kind=='ship' then
  if c and batches>0 then require('src.industry').finished(u,key,c.id) end
  require('src.dealers').output(u,key,output.hull,batches*output.n)
  require('src.economy').stat(u,'madeShips',output.hull,batches*output.n)
 else
  require('src.stockpile').add(u,key,output.item,batches*output.n)
  -- what each station has actually made, for makers that size their run on
  -- their own sales (E.adjust's price-driven branch)
  local made=u.madeAt or {};u.madeAt=made
  local k=key..'|'..output.item;made[k]=(made[k] or 0)+batches*output.n
  require('src.economy').stat(u,'made',output.item,batches*output.n)
 end
end
return O
