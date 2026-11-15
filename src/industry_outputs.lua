-- Typed manufacturing destinations share the executor's input/time rules.
local O={}
function O.room(u,key,c,output)
 if output.kind=='ship' then return math.floor(require('src.dealers').room(u,key,output.hull)/output.n) end
 -- (what a surface shuttle is still carrying up counts as on the shelf)
 local have=require('src.stockpile').count(u,key,output.item)+require('src.shuttles').pending(u,key,output.item)
 return math.max(0,math.floor(((output.cap or c.cap)-have)/output.n))
end
function O.add(u,key,output,batches,c)
 if output.kind=='ship' then
  if c and batches>0 then require('src.industry').finished(u,key,c.id) end
  require('src.dealers').output(u,key,output.hull,batches*output.n)
  require('src.economy').stat(u,'madeShips',output.hull,batches*output.n)
 else
  -- surface industry with the player watching: it comes up by shuttle
  -- (src/shuttles.lua), which stocks it and counts it on arrival
  if require('src.shuttles').divert(u,key,output.item,batches*output.n,c) then return end
  require('src.stockpile').add(u,key,output.item,batches*output.n)
  require('src.economy').stat(u,'made',output.item,batches*output.n)
 end
end
return O
