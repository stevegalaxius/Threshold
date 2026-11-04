-- Ore logistics uses the same saved station stock as miner deliveries.
-- Legacy u.jobs.mines counters are deliberately ignored: elapsed time is not ore.
local L=require('src.locations')
local J={mines={'phobos','deimos'},oreTo='mars',item='iron_ore'}
function J.isMine(area) return area=='phobos' or area=='deimos' end
function J.state(u)
 u.mining=u.mining or {sites={},resources={},stock={},seeded={}}
 return u.mining
end
function J.stock(u,station)
 local stock=J.state(u).stock
 station=L.canonical(station)
 stock[station]=stock[station] or {}
 return stock[station]
end
function J.available(u,station,item) return J.stock(u,station)[item] or 0 end
function J.take(u,station,item,amount)
 local stock=J.stock(u,station)
 if (stock[item] or 0)<amount then return false end
 stock[item]=stock[item]-amount
 return true
end
function J.deliver(u,station,item,amount)
 local stock=J.stock(u,station)
 stock[item]=(stock[item] or 0)+amount
end
return J
