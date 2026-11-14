-- Two saved traits, 0..1, generated without changing the world's random stream.
-- Profiles favor kinds of work; traits adjust choices within eligible work.
local T=require('src.tuning')
local P={}
function P.ensure(r)
 if r.ambition~=nil and r.aggression~=nil then return r end
 local seed=7193
 for i=1,#r.id do seed=(seed*31+r.id:byte(i))%2147483647 end
 -- Mix several times so adjacent numeric IDs do not get adjacent ambitions.
 for _=1,3 do seed=seed*48271%2147483647 end
 if r.ambition==nil then r.ambition=seed/2147483647 end
 seed=seed*48271%2147483647
 if r.aggression==nil then r.aggression=seed/2147483647 end
 return r
end
-- Neutral ambition preserves the old pickup preference. At either extreme,
-- reward and distance can outweigh convenience, but never station urgency.
function P.freightScore(r,rate,au,remote)
 local drive=P.ensure(r).ambition*2-1
 local reward=(rate-T.freightCreditsPerM3)/math.max(1,rate,T.freightCreditsPerM3)
 local distance=au/(1+au)
 return 1000000*(drive*(reward+distance)/2-(remote and (1-.5*drive) or 0))
end
-- An aggressive NPC accepts closer odds and breaks later, within safe bounds.
function P.engageOdds(r)
 local aggression=r and P.ensure(r).aggression or .5
 local nerve=r and require('src.npc_rank').get(r).nerve or 0
 return math.max(.5,math.min(.9,T.offlineEngageOdds+(.5-aggression)*.2-nerve))
end
function P.breakPoint(r,base)
 local aggression=r and P.ensure(r).aggression or .5
 local nerve=r and require('src.npc_rank').get(r).nerve or 0
 return math.max(.05,math.min(.9,base+(.5-aggression)*.1-nerve))
end
return P
