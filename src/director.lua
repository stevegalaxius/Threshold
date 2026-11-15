-- The A-Life director: background work done once for everybody, a little
-- each step, so that no single ship has to do it in the middle of its own
-- decision. Game:updateALife calls Director.update every step.
--
-- What it does now: keeps every station's stock caught up to the clock
-- (production and use, src/stockpile.lua S.flow), in turn, one whole round
-- every Director.round seconds of game time. Ships reading the job board
-- then just read the numbers.
local L=require('src.locations')
local Fields=require('src.fields')
local Stock=require('src.stockpile')
local D={}
D.round=4   -- game seconds for one pass over every station (well inside Stock.flowLate)
local turn={}
function D.update(u)
 local clock=u and u.clock
 if not clock then return end
 if turn.u~=u or not turn.at or clock<turn.at then turn.u,turn.at,turn.owed,turn.i,turn.list=u,clock,0,1,nil end
 if not turn.list then
  local list={}
  for _,area in ipairs(Fields.list) do
   for _,id in ipairs(L.stations(area)) do list[#list+1]=id end
  end
  turn.list=list
 end
 local list=turn.list
 if #list==0 then return end
 -- (by the clock, not by the step: the same pace at any frame rate)
 turn.owed=math.min(8,turn.owed+(clock-turn.at)/D.round*#list)
 turn.at=clock
 while turn.owed>=1 do
  turn.owed=turn.owed-1
  local key=list[turn.i]
  turn.i=turn.i+1
  if turn.i>#list then turn.i,turn.list=1,nil end   -- (a fresh list each round: maps can change)
  for index,shop in ipairs(Stock.shops(key)) do
   if not shop.unlimited then
    Stock.directed=true
    local ok,err=pcall(Stock.stock,u,key,index)
    Stock.directed=nil
    if not ok then error(err,0) end
    break
   end
  end
  if not turn.list then break end
 end
end
return D
