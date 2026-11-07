-- Ore logistics uses the same shop stockpiles the station markets sell from
-- (src/stockpile.lua). Legacy u.jobs.mines counters are deliberately ignored:
-- elapsed time is not ore.
local L=require('src.locations')
local Stock=require('src.stockpile')
local J={mines={'phobos','deimos'},oreTo='mars',item='iron_ore'}
-- Freight ore: quarries ship their ore to a logistics station, which ships
-- it on to Mars to be pressed into canisters. { from = area, via = station }.
J.freight={{from='ceres_quarry',via='station:belt_2'}}
function J.isMine(area) return area=='phobos' or area=='deimos' end
function J.state(u)
 u.mining=u.mining or {sites={},resources={},stock={},seeded={}}
 return u.mining
end
function J.available(u,station,item) return Stock.count(u,L.canonical(station),item) end
function J.take(u,station,item,amount) return Stock.take(u,L.canonical(station),item,amount) end
function J.deliver(u,station,item,amount) return Stock.add(u,L.canonical(station),item,amount) end
return J
