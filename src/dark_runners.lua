--[[
	Dark runners: who flies to the dark stations.

	Only crews that belong to a dark grid work there: the raiders, anyone
	born on a dark grid, and haulers who signed on with Milliways. Ordinary
	haulers go no further than a fence. The dark fleet sizes itself:

	  recruit  while dark freight sits unclaimed on the board for
	           T.darkRecruitWait, an idle white hauler (the poorest one)
	           signs on, moves its home to Milliways and becomes a runner
	  retire   a runner with no dark work for T.darkRetireIdle goes back
	           to honest work

	Both are written to the shared history and printed by the papers, so
	every ship at a dark station has a story behind it.
]]
local T=require('src.tuning')
local R={}
local function state(u) u.darkRunners=u.darkRunners or {backlog=0,lastRecruit=-math.huge,last=nil};return u.darkRunners end
R.state=state
local function darkOffer(o) return require('src.npc_access').darkOffer(o) end
local function home() return T.darkRunnerHome end

local function publish(u,headline,area)
 local News=require('src.news');local Outlets=require('data.outlets')
 for _,o in ipairs(Outlets.order or {}) do
  if News.covers(o,area) then
   News.publish(u,{outlet=o,kind='quest',headline=headline,area=area})
  end
 end
end

local function runners(u)
 local n,list=0,{}
 for _,r in pairs(u.npcs or {}) do
  if r.darkRunner and r.state~='dead' and r.state~='escaped' then n=n+1;list[#list+1]=r end
 end
 return n,list
end
R.count=function(u) return (runners(u)) end

local function recruit(u,clock)
 local best
 for _,r in pairs(u.npcs or {}) do
  if r.populationGroup=='hauler' and not r.darkAccess and not r.task and r.state=='docked'
   and r.ship and not require('src.dark').isDarkArea(r.area or '') then
   if not best or (r.credits or 0)<(best.credits or 0) or (r.credits or 0)==(best.credits or 0) and r.id<best.id then best=r end
  end
 end
 if not best then return end
 best.darkAccess=true;best.darkRunner=true;best.darkWorkAt=clock;best.darkJoinedAt=clock
 require('src.npc_home').assign(best,home())
 local s=state(u);s.lastRecruit=clock;s.backlog=0;s.recruited=(s.recruited or 0)+1
 local place=require('src.locations').byId[home()]
 require('src.simulation_history').note(u,'joined_runners',clock,best.area,{best.id},{home=home(),credits=math.floor(best.credits or 0)},best.node)
 publish(u,('%s signs on with the Milliways runners'):format(best.label or 'A hauler'),place and place.area or 'pluto')
 return best
end

local function retire(u,r,clock)
 r.darkAccess=false;r.darkRunner=nil;r.darkJoinedAt=nil
 local s=state(u);s.retired=(s.retired or 0)+1
 r.homeStation=nil;require('src.npc_home').choose(u,r)
 require('src.simulation_history').note(u,'left_runners',clock,r.area,{r.id},{home=r.homeStation},r.node)
 local place=require('src.locations').byId[home()]
 publish(u,('%s quits the dark lanes and goes straight'):format(r.label or 'A runner'),place and place.area or 'pluto')
end

-- Each economy update (once a game minute).
function R.update(u,clock)
 local s=state(u)
 local dt=s.last and math.max(0,clock-s.last) or 0;s.last=clock
 local waiting=0
 for _,o in pairs(require('src.tasks').state(u).offers) do
  if o.order and o.state=='available' and not o.owner and darkOffer(o) then waiting=waiting+1 end
 end
 s.backlog=waiting>0 and s.backlog+dt or 0
 local n,list=runners(u)
 for _,r in ipairs(list) do
  if r.task and darkOffer(r.task) then r.darkWorkAt=clock end
 end
 -- the longer and deeper the backlog, the more sign on: one runner for
 -- every T.darkOrdersPerRunner orders waiting, a few at a time
 if s.backlog>=T.darkRecruitWait and clock-s.lastRecruit>=T.darkRecruitEvery then
  local want=math.min(T.darkRecruitBatch,math.ceil(waiting/T.darkOrdersPerRunner),T.darkRunnerMax-n)
  for _=1,want do if not recruit(u,clock) then break end end
 end
 for _,r in ipairs(list) do
  if not r.task and clock-(r.darkWorkAt or clock)>=T.darkRetireIdle then retire(u,r,clock) end
 end
end
return R
