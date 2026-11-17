-- Satellite jobs for the player, built on site jobs (src/quest_sites.lua).
-- The same work NPCs take from the task board (src/sat_jobs.lua): whoever
-- gets there first does it.
--   sat_launch  a destroyed satellite: take the satellite package the job
--               gives you to the old satellite's spot and use it there
--   sat_refuel  a satellite low on fuel: use a deuterium canister beside it
local Q=require('src.quests')
local T=require('src.tuning')
local J=require('src.sat_jobs')
local function Sat() return require('src.satellites') end
local function record(u,q) return u.satellites and u.satellites[q.subject] end
local function planet(area) local F=require('src.fields')[area];return F and F.name or area end

local function candidates(u,want)
 local out={}
 for id,r in pairs(u.satellites or {}) do
  if want(r) then
   local giver=J.places(r.field)
   if giver then out[#out+1]={giver=giver,area=r.field,subject=id,reward=r.owner=='player' and 0 or J.pay,name=r.name or id} end
  end
 end
 return out
end

-- The satellite's home spot on its map, from its seeded layout slot.
local function home(game,q)
 if not q.home then
  for _,slot in ipairs(Sat().layout(q.area,game.field)) do
   if slot.id==q.subject then q.home={slot.alt,slot.angle} end
  end
  if not q.home then return end
 end
 local w=game.well;local cx,cy=w and w.x or 0,w and w.y or 0
 return cx+math.cos(q.home[2])*q.home[1],cy+math.sin(q.home[2])*q.home[1]
end
local seen=setmetatable({},{__mode='v'})
local function husk(game,id)
 local e=seen[id]
 if e and not e.removed and e.sat==id and e.body and not e.body:isDestroyed() then return e end
 for _,o in ipairs(game.entities) do
  if o.sat==id and not o.removed and o.body and not o.body:isDestroyed() then seen[id]=o;return o end
 end
end

Q.site('sat_launch',{
 label='Satellite launch',item='satellite_package',give=true,
 busy=function(u,q) return J.npcHolds(u,'satlaunch',q.subject) end,
 candidates=function(u)
  local list=candidates(u,function(r) return r.lost end)
  for _,c in ipairs(list) do
   c.title='Launch a replacement for '..c.name
   c.detail='package provided · launch it at the old spot in '..planet(c.area)..' orbit'
  end
  return list
 end,
 open=function(u,q) local r=record(u,q);return r and r.lost or false end,
 where=function(game,q)
  local x,y=home(game,q)
  if x then return x,y,T.siteRange,'Launch site: '..(record(game.universe,q) or {}).name end
 end,
 apply=function(game,q)
  if Sat().relaunch(game.universe,q.subject,'player') then Sat().populate(game) end
 end,
})

Q.site('sat_refuel',{
 label='Satellite refuel',item='deuterium_canister',
 busy=function(u,q) return J.npcHolds(u,'satrefuel',q.subject) end,
 candidates=function(u)
  local list=candidates(u,function(r) return not r.lost and r.fuel and r.fuel<Sat().refuelAt end)
  for _,c in ipairs(list) do
   c.title='Refuel '..c.name
   c.detail='bring a deuterium canister · use it beside the satellite in '..planet(c.area)..' orbit'
  end
  return list
 end,
 open=function(u,q) local r=record(u,q);return r and not r.lost and (r.fuel or 1)<Sat().refuelAt or false end,
 where=function(game,q)
  local e=husk(game,q.subject)
  if e then local x,y=e.body:getPosition();return x,y,(e.radius or 300)+800,e.name end
 end,
 apply=function(game,q) Sat().refuel(game.universe,q.subject,'player') end,
})
