--[[
	The news. The economy and the A-Life are the truth; the player (and the
	NPC traders) only see what the outlets print about it, and every outlet
	leans toward what its owner sells (data/outlets.lua).

	  stories   each outlet tick picks a few facts from its beat (prices and
	            shortages from src/markets.lua and src/economy.lua, deaths
	            and the player's deeds), spins the numbers by its agenda and
	            prints a headline. Off its beat it can only copy another
	            outlet's story, later, with its own spin stacked on. Now and
	            then it prints a rumour with nothing behind it.
	  coverage  a station carries its owner's outlet plus any outlet read
	            everywhere (the Beltway). Docked, you read what the station carries;
	            in flight, only the papers you subscribe to.
	  subs      a subscription is taken out at a paper's press desk (any
	            station its owner runs), is refused while the paper is
	            hostile to you, and is a standing order: T.subscribeFee
	            every hour out of your credits until you cancel, can't
	            pay, or the paper turns on you.
	            Docked or in flight, you read what's carried where you are
	            (the station, or the system you're flying in).
	  prices    a story nudges the price of its good at the stations in its
	            area that carry the outlet: speculation. The nudges decay and
	            are capped at T.nudgeCap together. Markets.price reads them,
	            so NPC traders (src/merchants.lua) react to the news for the
	            cost of a table lookup. Big swings are quest-only
	            (News.shock): nothing the simulation prints can reach them.
	  standing  per outlet, how useful you are to its owner (-100..100,
	            decays). It sets how the outlet writes about you: hostile
	            outlets name you and smear you, friendly ones flatter you
	            and pass you tips.
	  deeds     what the player did out of a faction's sight
	            (src/reputation.lua). It reaches that faction only as
	            reported, through Rep.addReported (floored and rate-capped).

	All of it runs on the universe clock, so it works offline. State lives
	in u.news.
]]
local Outlets=require('data.outlets')
local N={}

N.T={
 tick=600,            -- seconds of universe clock between outlet runs
 storyLife=2*3600,    -- a story stays in the feed this long
 nudgeLife=2*3600,    -- a story's price nudge decays to nothing over this
 nudgeScale=.35,      -- nudge = (reported ratio - 1) * this
 nudgeCap=.3,         -- all story nudges on one good at one station, together
 secondhandDelay=1200,-- a copied story prints this long after the original
 secondhandOdds=.5,
 perTick=1,           -- price stories an outlet prints per run, at most
 priceGap=1800,       -- and at least this long between them
 copyGap=3600,        -- an outlet copies another's story at most this often
 copyJuice=.45,       -- and only if it moves the price this much, or is about
                      -- a deed, or the good is on the copier's agenda
 offAgenda=1.5,       -- a good off the outlet's agenda needs this much more
                      -- deviation (or this much longer unserved) to print
 keep=80,             -- stories kept in the save
 shortRatio=1.35,     -- a price this far over list is a shortage story
 glutRatio=.7,        -- and this far under, a glut story
 shortAge=1800,       -- or a shortage left unserved this long
 subscribeFee=150,    -- credits per hour of universe clock, per paper
 standingDecay=2,     -- outlet standing, points per hour toward 0
 friendly=25,hostile=-25,
 smearOdds=.08,praiseOdds=.08, -- per run, from a hostile / friendly outlet
 smearHit=-3,praiseHit=2,      -- reported standing those move
 blameOdds=.25,       -- an NPC's kill pinned on the player (same hull class)
 blameHit=-5,
 secondhandWeight=.6, -- a copied deed weighs this much of a first-hand one
 nameBase=.25,        -- first-hand: odds of naming you = this + smear*(1-this)
 hitDelta=-5,         -- shooting a faction ship out of its sight, once per ship
 spinFloor=.5,spinCeil=1.6, -- spin keeps a move between these multiples of the truth
 rivalPraise=.25,     -- an outlet's owner warms to you for hitting its rivals
}

local function clamp(v,lo,hi) return math.max(lo,math.min(hi,v)) end
local function L() return require('src.locations') end
local function Rep() return require('src.reputation') end

function N.state(u)
 local s=u.news
 if not s then
  s={stories={},nextId=0,nudges={},shocks={},outlets={},deeds={},subs={}}
  u.news=s
 end
 s.subs=s.subs or {}
 return s
end

N.outlets=Outlets.outlets
N.order=Outlets.order

---------------------------------------------------------------- coverage

local beats={}
for id,o in pairs(Outlets.outlets) do
 beats[id]={};for _,a in ipairs(o.beat) do beats[id][a]=true end
end
function N.covers(o,area) return beats[o] and beats[o][area] or false end
-- The outlet a faction owns (first in order), or nil.
local owned={}
for _,id in ipairs(Outlets.order) do local f=Outlets.outlets[id].owner;if f and not owned[f] then owned[f]=id end end
function N.ofFaction(f) return f and owned[f] or nil end

-- Outlets a station (or satellite) carries: its owner's, plus the ones
-- read everywhere.
function N.carried(nodeId,area)
 local out={}
 local mine=N.ofFaction(nodeId and Rep().ofNode(nodeId) or Rep().ofArea(area))
 if mine then out[#out+1]=mine end
 for _,id in ipairs(Outlets.order) do
  if Outlets.outlets[id].everywhere and id~=mine then out[#out+1]=id end
 end
 return out
end
local function carries(nodeId,o)
 for _,id in ipairs(N.carried(nodeId)) do if id==o then return true end end
 return false
end
-- The paper whose press desk is at this station: its owner's, if any.
function N.desk(nodeId) return nodeId and N.ofFaction(Rep().ofNode(nodeId)) or nil end
-- Factions that read an outlet: its owner, and everyone if it's read
-- everywhere.
local function readers(o)
 local d=Outlets.outlets[o]
 if d.everywhere then return Rep().ORDER end
 return {d.owner}
end
local function reads(f,o)
 local d=Outlets.outlets[o]
 return d.everywhere or d.owner==f
end

---------------------------------------------------------------- outlet standing

local function now(cell,clock)
 if not cell then return 0 end
 local d=N.T.standingDecay*math.max(0,clock-(cell.t or clock))/3600
 if cell.v>0 then return math.max(0,cell.v-d) end
 return math.min(0,cell.v+d)
end
function N.standing(u,o) return now(N.state(u).outlets[o],u.clock or 0) end
function N.addStanding(u,o,by)
 if not o or by==0 then return end
 local s=N.state(u);local clock=u.clock or 0
 s.outlets[o]={v=clamp(now(s.outlets[o],clock)+by,-100,100),t=clock}
end
function N.mood(u,o)
 local v=N.standing(u,o)
 if v>=N.T.friendly then return 'friendly' end
 if v<=N.T.hostile then return 'hostile' end
 return 'neutral'
end

---------------------------------------------------------------- prices

local function sumNudges(list,clock)
 local v=0
 for _,n in ipairs(list) do
  local left=1-(clock-n.t)/n.life
  if left>0 then v=v+n.v*left end
 end
 return v
end
-- Story nudges on one good at one station: the strongest counts in full,
-- each next one half as much again, so a pile of copies of one story
-- doesn't run the price to the cap.
local scratch={}
local function stackNudges(list,clock)
 local n=0
 for _,x in ipairs(list) do
  local left=1-(clock-x.t)/x.life
  if left>0 then n=n+1;scratch[n]=x.v*left end
 end
 for i=n+1,#scratch do scratch[i]=nil end
 table.sort(scratch,function(a,b) return math.abs(a)>math.abs(b) end)
 local v,w=0,1
 for i=1,n do v=v+scratch[i]*w;w=w*.5 end
 return v
end
-- The news's multiplier on a station's price for a good. Story nudges are
-- capped together; quest shocks are not.
function N.factor(u,key,item)
 local s=u.news;if not s then return 1 end
 local clock=u.clock or 0;local f=1
 local k=s.nudges[key];local list=k and k[item]
 if list then f=1+clamp(stackNudges(list,clock),-N.T.nudgeCap,N.T.nudgeCap) end
 k=s.shocks[key];list=k and k[item]
 if list then f=f*math.max(.05,1+sumNudges(list,clock)) end
 return f
end
local function nudge(u,area,o,item,v,storyId)
 if v==0 then return end
 local s=N.state(u)
 for _,key in ipairs(L().stations(area,'trade')) do
  if carries(key,o) then
   s.nudges[key]=s.nudges[key] or {}
   local list=s.nudges[key][item] or {};s.nudges[key][item]=list
   list[#list+1]={v=v,t=u.clock or 0,life=N.T.nudgeLife,story=storyId}
  end
 end
end
local function prune(map,clock)
 for key,items in pairs(map) do
  for item,list in pairs(items) do
   for i=#list,1,-1 do if clock-list[i].t>=list[i].life then table.remove(list,i) end end
   if #list==0 then items[item]=nil end
  end
  if next(items)==nil then map[key]=nil end
 end
end

-- Quest-only: a crash (size < 0) or spike (size > 0) on a good, at one
-- station or every trade station in an area, decaying over duration
-- seconds. Not capped. Optional story = { outlet=, headline= } prints an
-- authored headline with it.
function N.shock(u,where,item,size,duration,story)
 local s=N.state(u)
 local keys=L().byId[where] and {where} or L().stations(where,'trade')
 for _,key in ipairs(keys) do
  s.shocks[key]=s.shocks[key] or {}
  local list=s.shocks[key][item] or {};s.shocks[key][item]=list
  list[#list+1]={v=size,t=u.clock or 0,life=duration or N.T.nudgeLife}
 end
 if story then
  local key=keys[1]
  N.publish(u,{outlet=story.outlet,kind=story.kind or 'quest',headline=story.headline,body=story.body,
   area=L().byId[where] and L().byId[where].area or where,station=key,good=item,quest=true})
 end
end

---------------------------------------------------------------- stories

local function itemName(item)
 local d=require('src.data').items[item];return d and d.name or item
end
local function placeName(id)
 local p=L().byId[id];return p and p.name or id
end
local function areaName(a)
 local F=require('src.fields')[a];return F and F.name or a
end
local function factionName(f)
 local d=f and Rep().FACTIONS[f];return d and (d.name:gsub('^The ','')) or 'independent'
end
local function pick(list,seed)
 return list[(seed%#list)+1]
end
local function fill(t,v)
 return (t:gsub('{(%w+)}',function(k) return v[k] and tostring(v[k]) or '' end))
end
local function template(o,kind,seed)
 local d=Outlets.outlets[o]
 local list=d and d.templates and d.templates[kind] or Outlets.default[kind] or {'{good} at {station}'}
 return pick(list,seed)
end
local function pct(ratio) return ('%+d%%'):format(math.floor((ratio-1)*100+.5)) end

-- A story's headline. Authored ones (quests, notices) carry their own;
-- the rest are filled from the outlet's templates each time they're read,
-- so edits to data/outlets.lua show up in stories already printed.
function N.headline(st)
 if st.headline then return st.headline end
 local vars={good=st.good and itemName(st.good),station=st.station and placeName(st.station),
  area=st.area and areaName(st.area),pct=st.reported and pct(st.reported),who=st.who,faction=factionName(st.faction),
  victim=st.victim or 'ship'}
 return fill(template(st.outlet,st.kind,st.pick or 0),vars)
end
-- Put a story in the feed. Fills in id and clock. Returns the story.
function N.publish(u,st)
 local s=N.state(u)
 s.nextId=s.nextId+1
 st.id='story/'..s.nextId;st.clock=st.clock or u.clock or 0
 st.faction=st.faction or (st.station and Rep().ofNode(st.station))
 st.pick=st.pick or s.nextId
 s.stories[#s.stories+1]=st
 while #s.stories>N.T.keep do table.remove(s.stories,1) end
 N.tell(u,st)
 require('src.events').emit('news_published',require('src.persistence').copy(st))
 if st.good and st.reported and st.area and not st.tip then
  local v=(st.reported-1)*N.T.nudgeScale*(st.secondhand and .5 or 1)
  nudge(u,st.area,st.outlet,st.good,clamp(v,-N.T.nudgeCap,N.T.nudgeCap),st.id)
 end
 return st
end

-- An outlet's lean on a price move: agenda goods it pushes further, goods
-- it talks down it pulls back; its owner's own troubles it hides or
-- softens; a rival major faction's it plays up.
local function spin(o,item,ratio,nodeId)
 local d=Outlets.outlets[o];local dev=ratio-1
 local a=d.agenda[item] or 0
 if a*dev>0 then dev=dev*(1+d.lean) elseif a*dev<0 then dev=dev*(1-d.lean*.5) end
 local f=Rep().ofNode(nodeId)
 -- the owner's shortage of something it sells is good news for it
 if dev>0 and f==d.owner and a<=0 then
  if d.hush=='suppress' then return nil end
  dev=dev*.5
 elseif dev>0 and f and Rep().FACTIONS[f] and Rep().FACTIONS[f].major and f~=d.owner then
  dev=dev*(1+d.lean*.5)
 end
 -- however it leans, the printed move stays near the real one, so a
 -- reader who knows the paper can still learn something from it
 local real=ratio-1
 if real~=0 then
  local lo,hi=real*N.T.spinFloor,real*N.T.spinCeil
  if lo>hi then lo,hi=hi,lo end
  dev=clamp(dev,lo,hi)
 end
 return 1+dev
end

local function recentAbout(s,o,key,item,since)
 for i=#s.stories,1,-1 do
  local st=s.stories[i]
  if st.clock<since then break end
  if (o==nil or st.outlet==o) and st.station==key and st.good==item then return true end
 end
 return false
end

-- Price facts on an outlet's beat, biggest (and most on-agenda) first.
local function priceFacts(u,o,clock)
 local Markets=require('src.markets');local E=require('src.economy')
 local prices=Markets.state(u).prices;local d=Outlets.outlets[o]
 local out={}
 -- what the papers have been on about lately: each story makes the same
 -- good less interesting for a while, so one good can't fill the feed
 local s=N.state(u);local seen={}
 for i=#s.stories,1,-1 do
  local st=s.stories[i];if clock-st.clock>N.T.storyLife then break end
  if st.good then seen[st.good]=(seen[st.good] or 0)+1 end
 end
 local hi,lo,age=N.T.shortRatio,N.T.glutRatio,N.T.shortAge
 for _,area in ipairs(d.beat) do
  for _,key in ipairs(L().stations(area,'trade')) do
   local p=prices[key]
   if p then
    for item,ratio in pairs(p) do
     local on=(d.agenda[item] or 0)~=0
     local m=on and 1 or N.T.offAgenda
     local short=E.shortageAge(u,key,item,clock)>=age*m
     if ratio>=1+(hi-1)*m or ratio<=1-(1-lo)*m or short then
      local score=(math.abs(ratio-1)*(1+math.abs(d.agenda[item] or 0))+(short and .2 or 0))/(1+(seen[item] or 0))
      out[#out+1]={key=key,area=area,item=item,ratio=math.max(ratio,short and 1.1 or 0),score=score}
     end
    end
   end
  end
 end
 table.sort(out,function(a,b) if a.score~=b.score then return a.score>b.score end return a.key..a.item<b.key..b.item end)
 return out
end

local function playerWho(u,named)
 local hull=u.news and u.news.playerHull
 if named then return hull and ('the '..hull..' captain') or 'a known captain' end
 return hull and ('an unknown '..hull) or 'unknown raiders'
end

-- Deeds are kept once, in s.deeds, and stories point at them by id, so
-- every story about one deed shares one record of who has heard (and a
-- save, which copies tables apart, can't split it).
local function findDeed(s,id)
 if not id then return nil end
 for i=#s.deeds,1,-1 do if s.deeds[i].id==id then return s.deeds[i] end end
end
local function addDeed(s,deed)
 s.nextDeed=(s.nextDeed or 0)+1;deed.id=s.nextDeed
 s.deeds[#s.deeds+1]=deed
 while #s.deeds>60 do table.remove(s.deeds,1) end
 return deed
end
-- Apply a story about a player deed to every faction that reads it.
local function report(u,st)
 local deed=findDeed(N.state(u),st.deedId);if not deed or not st.named then return end
 deed.applied=deed.applied or {}
 local weight=st.secondhand and N.T.secondhandWeight or 1
 local mood=N.mood(u,st.outlet)
 local spinFor=mood=='hostile' and 1.5 or mood=='friendly' and .5 or 1
 local owner=Outlets.outlets[st.outlet].owner
 for _,f in ipairs(readers(st.outlet)) do
  if not deed.applied[f] then
   local by=0
   if f==deed.faction and not deed.witnessed then
    by=deed.delta*weight*(deed.delta<0 and spinFor or 1/spinFor)
   elseif f==owner and f~=deed.faction and deed.delta<0 and Outlets.outlets[st.outlet].outlaw then
    by=-deed.delta*N.T.rivalPraise*2*weight   -- the pirates love it
   elseif f==owner and f~=deed.faction and deed.delta<0 and deed.faction and Rep().FACTIONS[deed.faction] and Rep().FACTIONS[deed.faction].major then
    by=-deed.delta*N.T.rivalPraise*weight
   end
   if by~=0 then deed.applied[f]=true;Rep().addReported(u,f,by,st.id) end
  end
 end
end

local function naming(u,o,firsthand)
 local d=Outlets.outlets[o]
 local p=firsthand and N.T.nameBase+d.smear*(1-N.T.nameBase) or d.smear*.5
 local mood=N.mood(u,o)
 if mood=='hostile' then p=p+.3 elseif mood=='friendly' then p=p-.3 end
 return p
end

local function rng(u)
 local s=N.state(u)
 s.seed=((s.seed or 12345)*1103515245+12345)%2147483648
 return s.seed/2147483648
end

---------------------------------------------------------------- deeds

-- The player did something to a faction out of its sight (or in it:
-- witnessed=true, already counted by src/reputation.lua, printed anyway).
-- deed = { faction=, delta=, area=, kind='killed'|'hit', witnessed= }
function N.deed(u,deed)
 local s=N.state(u)
 deed.clock=u.clock or 0
 addDeed(s,deed)
 -- the victim's paper takes it personally
 local o=N.ofFaction(deed.faction)
 if o and deed.delta<0 then N.addStanding(u,o,deed.delta*.5) end
 -- and the pirate sheets drink to it
 if deed.delta<0 then
  for _,id in ipairs(Outlets.order) do if Outlets.outlets[id].outlaw then N.addStanding(u,id,-deed.delta*.3) end end
 end
end

local function deedStories(u,s,clock)
 for i=#s.deeds,1,-1 do
  local deed=s.deeds[i]
  if not deed.printed then
   deed.printed=true
   local any=false
   for _,o in ipairs(Outlets.order) do
    if N.covers(o,deed.area) then
     any=true
     local named=rng(u)<naming(u,o,true)
     report(u,N.publish(u,{outlet=o,kind=deed.delta<0 and 'killed' or 'praise',area=deed.area,faction=deed.faction,
      who=playerWho(u,named),named=named,subject='player',deedId=deed.id}))
    end
   end
   -- nobody's beat: the everywhere outlets may still hear of it
   if not any then
    for _,o in ipairs(Outlets.order) do
     if Outlets.outlets[o].everywhere and rng(u)<N.T.secondhandOdds then
      local named=rng(u)<naming(u,o,false)
      report(u,N.publish(u,{outlet=o,kind=deed.delta<0 and 'killed' or 'praise',area=deed.area,faction=deed.faction,
       who=playerWho(u,named),named=named,subject='player',deedId=deed.id,secondhand=true}))
     end
    end
   end
  end
 end
 for i=#s.deeds,1,-1 do if clock-s.deeds[i].clock>N.T.storyLife*1.5 then table.remove(s.deeds,i) end end
end

-- NPC killings of faction ships on an outlet's beat. If the killer flew
-- what the player flies, a careless outlet may pin it on the player.
-- A faction's dead always make its beat's papers, as loudly as they
-- like; independents (most ships) one a run, with nobody's standing on it.
-- Deaths as they happen (src/simulation_history.lua H.death), kept here:
-- the shared history log turns over in minutes, the papers look every ten.
function N.onDeath(u,e)
 local s=N.state(u);s.deaths=s.deaths or {}
 s.deaths[#s.deaths+1]={id=e.id,clock=e.clock,area=e.area,participants={e.participants[1]},result=e.result}
 while #s.deaths>80 do table.remove(s.deaths,1) end
end
local function deathStories(u,s,o,since,clock)
 local d=Outlets.outlets[o]
 local printed=0
 local list=s.deaths or {}
 for i=#list,1,-1 do
  local e=list[i]
  if e.clock<since then break end
  -- the entry carries the victim's faction and the killer's hull; the
  -- records themselves are usually pruned by the time the papers look
  local res=e.result or {}
  local victim=u.npcs and u.npcs[e.participants[1]]
  local killer=res.killer
  local f=res.faction or victim and Rep().ofRecord(victim)
  local vh=res.hull or victim and victim.ship and victim.ship.hull
  local vd=vh and require('src.data').hulls[vh]
  -- (a death with no killer on record is still news: 'a raider')
  if not f and killer~='player' and e.area and N.covers(o,e.area) and printed==0 then
   -- an independent: a story, no standing
   local k=u.npcs and u.npcs[killer]
   local hull=res.killerHull or k and k.ship and k.ship.hull
   local hd=hull and require('src.data').hulls[hull]
   local blame=hull and s.playerHullId and hull==s.playerHullId and rng(u)<N.T.blameOdds*(d.smear+.2)
   N.publish(u,{outlet=o,kind='lost',area=e.area,fact=e.id,victim=vd and vd.name or 'trader',
    who=blame and playerWho(u,true) or hd and ('a '..hd.name) or 'a raider',
    named=blame or nil,subject=blame and 'player' or nil,blamed=blame or nil})
   printed=printed+1
  elseif f and killer~='player' and e.area and N.covers(o,e.area) then
   local k=u.npcs and u.npcs[killer]
   local hull=res.killerHull or k and k.ship and k.ship.hull
   local playerHull=s.playerHullId
   local blame=hull and playerHull and hull==playerHull and rng(u)<N.T.blameOdds*(d.smear+.2)
   local st={outlet=o,kind='killed',area=e.area,faction=f,fact=e.id}
   if blame then
    st.who=playerWho(u,true);st.named=true;st.subject='player';st.blamed=true
    -- at home the faction saw who really did it; away, it has only the papers
    st.deedId=addDeed(s,{faction=f,delta=N.T.blameHit,area=e.area,clock=clock,printed=true,blamed=true,
     witnessed=Rep().ofArea(e.area)==f}).id
   else
    local hd=hull and require('src.data').hulls[hull]
    st.who=hd and ('a '..hd.name) or 'a raider'
   end
   report(u,N.publish(u,st))
  end
 end
end

local function juicy(st,d)
 if st.deedId or st.kind=='killed' or st.kind=='lost' or st.rumour then return true end
 if st.good and (d.agenda[st.good] or 0)~=0 then return true end
 return st.reported and math.abs(st.reported-1)>=N.T.copyJuice
end
local function copyStories(u,s,o,clock)
 local d=Outlets.outlets[o];local copied=0
 s.lastCopy=s.lastCopy or {}
 if clock-(s.lastCopy[o] or -math.huge)<N.T.copyGap then return end
 for i=#s.stories,1,-1 do
  local st=s.stories[i]
  if clock-st.clock>N.T.storyLife then break end
  if copied>=1 then break end
  if st.outlet~=o and not st.secondhand and not st.tip and not st.quest and st.area and not N.covers(o,st.area)
   and clock-st.clock>=N.T.secondhandDelay and juicy(st,d) then
   st.copies=st.copies or {}
   if not st.copies[o] then
    st.copies[o]=true
    local odds=d.everywhere and .8 or N.T.secondhandOdds
    if rng(u)<odds then
     local c={outlet=o,kind=st.kind,area=st.area,station=st.station,good=st.good,faction=st.faction,
      secondhand=true,from=st.outlet,subject=st.subject,deedId=st.deedId,blamed=st.blamed,victim=st.victim}
     if st.reported then c.reported=spin(o,st.good,st.reported,st.station) end
     if st.kind=='shortage' or st.kind=='glut' then
      if c.reported then c.kind=c.reported>=1 and 'shortage' or 'glut' end
     end
     if not (st.reported and not c.reported) then
      if st.subject=='player' then
       c.named=st.named and rng(u)<.7 or false
       c.who=playerWho(u,c.named)
      else c.who=st.who end
      report(u,N.publish(u,c));copied=copied+1;s.lastCopy[o]=clock
     end
    end
   end
  end
 end
end

-- One outlet's run: its beat's prices, a rumour now and then, deaths,
-- copies of other outlets' stories, and whatever it thinks of you.
local function run(u,s,o,since,clock)
 local d=Outlets.outlets[o]
 local printed=0
 local mood=N.mood(u,o)
 for _,fact in ipairs(priceFacts(u,o,clock)) do
  if printed>=N.T.perTick or clock-((s.lastPrice or {})[o] or -math.huge)<N.T.priceGap then break end
  if not recentAbout(s,nil,fact.key,fact.item,clock-N.T.storyLife) then
   if mood=='friendly' then
    N.publish(u,{outlet=o,kind='tip',tip=true,area=fact.area,station=fact.key,good=fact.item,reported=fact.ratio,real=fact.ratio,
     headline=('Tip: %s at %s is really %s'):format(itemName(fact.item),placeName(fact.key),pct(fact.ratio))})
   end
   local r=spin(o,fact.item,fact.ratio,fact.key)
   if r then
    N.publish(u,{outlet=o,kind=r>=1 and 'shortage' or 'glut',area=fact.area,station=fact.key,good=fact.item,
     real=fact.ratio,reported=r})
    printed=printed+1
    s.lastPrice=s.lastPrice or {};s.lastPrice[o]=clock
   end
  end
 end
 -- a rumour: an agenda good talked up where nothing's wrong with it
 if rng(u)<d.rumour then
  local goods={};for item,a in pairs(d.agenda) do if a>0 then goods[#goods+1]=item end end
  table.sort(goods)
  local area=d.beat[1+math.floor(rng(u)*#d.beat)]
  local stations=L().stations(area,'trade')
  if #goods>0 and #stations>0 then
   local key=stations[1+math.floor(rng(u)*#stations)];local item=goods[1+math.floor(rng(u)*#goods)]
   if not recentAbout(s,o,key,item,clock-N.T.storyLife) then
    N.publish(u,{outlet=o,kind='shortage',area=area,station=key,good=item,real=nil,rumour=true,reported=1.4+rng(u)*.4})
   end
  end
 end
 deathStories(u,s,o,since,clock)
 copyStories(u,s,o,clock)
 -- what it thinks of you, printed with nothing new behind it
 local area=d.beat[1]
 if mood=='hostile' and rng(u)<N.T.smearOdds then
  local st=N.publish(u,{outlet=o,kind='smear',area=area,who=playerWho(u,true),named=true,subject='player'})
  for _,f in ipairs(readers(o)) do if f==d.owner then Rep().addReported(u,f,N.T.smearHit,st.id) end end
 elseif mood=='friendly' and rng(u)<N.T.praiseOdds then
  local st=N.publish(u,{outlet=o,kind='praise',area=area,who=playerWho(u,true),named=true,subject='player'})
  for _,f in ipairs(readers(o)) do if f==d.owner then Rep().addReported(u,f,N.T.praiseHit,st.id) end end
 end
end

-- Run every outlet when it's due. Cheap between runs: a clock compare.
-- Spread out: the tick's start does the bills and deeds, then each call
-- after runs the next outlet, so no one call does all six.
function N.update(u,clock,game)
 local s=N.state(u)
 if game and game.player and game.player.hull then
  s.playerHull=game.player.hull.name;s.playerHullId=game.player.hull.id
 end
 local q=s.queue
 if q then
  local o=table.remove(q.left,1)
  if o then run(u,s,o,q.since,clock) end
  if #q.left==0 then s.queue=nil end
  return
 end
 if clock<(s.nextTick or 0) then return end
 local since=s.lastTick or clock-N.T.tick
 s.lastTick=clock;s.nextTick=clock+N.T.tick
 prune(s.nudges,clock);prune(s.shocks,clock)
 -- a story past its life can't be copied any more: drop who copied it
 for _,st in ipairs(s.stories) do if st.copies and clock-st.clock>N.T.storyLife then st.copies=nil end end
 while s.deaths and s.deaths[1] and clock-s.deaths[1].clock>N.T.storyLife do table.remove(s.deaths,1) end
 N.bill(u,s,clock)
 deedStories(u,s,clock)
 local left={};for i,o in ipairs(Outlets.order) do left[i]=o end
 s.queue={since=since,left=left}
end
-- Everything due now, at once (tests).
function N.flush(u,clock,game)
 N.update(u,clock,game)
 while N.state(u).queue do N.update(u,clock,game) end
end

---------------------------------------------------------------- quest hooks
--[[
	For quests (src/quests.lua) and authored story arcs. Conditions and
	effects are plain tables, so they can sit in quest data and be saved.

	  News.find(u, filter, limit)  stories, newest first. filter fields:
	      outlet, kind, good, station, area, faction, since (clock),
	      within (seconds back), about='player', named, rumour, secondhand
	  News.check(u, cond)  is the condition true now? cond is one of:
	      { story = filter }                      a story like this exists
	      { standing = { outlet=, min=, max= } }  your standing with an outlet
	      { mood = { outlet=, is='friendly'|'neutral'|'hostile' } }
	      { named = { within=, outlet= } }        you were named in print
	      { factor = { station=, good=, min=, max= } }  news price multiplier
	      { subscribed = outlet }
	      { all = {cond...} } { any = {cond...} } { none = {cond...} }
	  News.apply(u, effect, ctx)  do it. effect is one of, or a list of:
	      { publish = { outlet=, headline=, kind=, good=, station=, area=,
	                    about='player', reported= } }   an authored story
	      { shock = { where=, good=, size=, duration=, outlet=, headline= } }
	      { outletStanding = { outlet=, by= } }
	      { standing = { faction=, by= } }   witnessed: quests may make a
	                                         faction hostile, news can't
	      { reported = { faction=, by= } }   as if read: capped and floored
	      { notify = { title=, text=, icon=, kind= } }
	  The events bus gets 'news_published' (a copy of each story) for
	  scripts that want to wait on one.
]]

local function matches(st,f,clock)
 if f.outlet and st.outlet~=f.outlet then return false end
 if f.kind and st.kind~=f.kind then return false end
 if f.good and st.good~=f.good then return false end
 if f.station and st.station~=f.station then return false end
 if f.area and st.area~=f.area then return false end
 if f.faction and st.faction~=f.faction then return false end
 if f.since and st.clock<f.since then return false end
 if f.within and clock-st.clock>f.within then return false end
 if f.about=='player' and st.subject~='player' then return false end
 if f.named~=nil and (st.named or false)~=f.named then return false end
 if f.rumour~=nil and (st.rumour or false)~=f.rumour then return false end
 if f.secondhand~=nil and (st.secondhand or false)~=f.secondhand then return false end
 return true
end
function N.find(u,f,limit)
 local s=N.state(u);local clock=u.clock or 0;local out={}
 f=f or {}
 for i=#s.stories,1,-1 do
  local st=s.stories[i]
  if matches(st,f,clock) then out[#out+1]=st;if limit and #out>=limit then break end end
 end
 return out
end

function N.check(u,c)
 if not c then return true end
 if c.all then for _,x in ipairs(c.all) do if not N.check(u,x) then return false end end return true end
 if c.any then for _,x in ipairs(c.any) do if N.check(u,x) then return true end end return false end
 if c.none then for _,x in ipairs(c.none) do if N.check(u,x) then return false end end return true end
 if c.story then return #N.find(u,c.story,1)>0 end
 if c.standing then
  local v=N.standing(u,c.standing.outlet)
  return v>=(c.standing.min or -math.huge) and v<=(c.standing.max or math.huge)
 end
 if c.mood then return N.mood(u,c.mood.outlet)==c.mood.is end
 if c.named then return #N.find(u,{about='player',named=true,within=c.named.within,outlet=c.named.outlet},1)>0 end
 if c.factor then
  local v=N.factor(u,c.factor.station,c.factor.good)
  return v>=(c.factor.min or -math.huge) and v<=(c.factor.max or math.huge)
 end
 if c.subscribed then return N.subscribed(u,c.subscribed) end
 error('unknown news condition')
end

function N.apply(u,e,ctx)
 if not e then return end
 if e[1] then for _,x in ipairs(e) do N.apply(u,x,ctx) end return end
 if e.publish then
  local p=e.publish
  local place=p.station and L().byId[p.station]
  local st={outlet=p.outlet,kind=p.kind or 'quest',headline=p.headline,good=p.good,station=p.station,
   area=p.area or (place and place.area),reported=p.reported,quest=true}
  if p.about=='player' then st.subject='player';st.named=true end
  return N.publish(u,st)
 end
 if e.shock then
  local x=e.shock
  return N.shock(u,x.where,x.good,x.size,x.duration,x.headline and {outlet=x.outlet,headline=x.headline} or nil)
 end
 if e.outletStanding then return N.addStanding(u,e.outletStanding.outlet,e.outletStanding.by) end
 if e.standing then return Rep().addStanding(u,e.standing.faction,e.standing.by) end
 if e.reported then return Rep().addReported(u,e.reported.faction,e.reported.by) end
 if e.notify then
  local n={};for k,v in pairs(e.notify) do n[k]=v end
  return require('src.notify').post(u,n)
 end
 error('unknown news effect')
end

---------------------------------------------------------------- the player's view

-- Outlets the player can read right now: docked (nodeId), what the
-- station carries plus their subscriptions; in flight, only their
-- subscriptions.
function N.reading(u,nodeId)
 local out,seen={},{}
 if nodeId then for _,o in ipairs(N.carried(nodeId)) do seen[o]=true;out[#out+1]=o end end
 for _,o in ipairs(Outlets.order) do if N.subscribed(u,o) and not seen[o] then seen[o]=true;out[#out+1]=o end end
 return out
end
-- The feed, newest first: stories from the outlets read (tips from a
-- friendly one among them), and notices meant for the player alone.
function N.feed(u,nodeId,limit)
 local s=N.state(u);local clock=u.clock or 0
 local reading={};for _,o in ipairs(N.reading(u,nodeId)) do reading[o]=true end
 local out={}
 for i=#s.stories,1,-1 do
  local st=s.stories[i]
  if clock-st.clock>N.T.storyLife then break end
  if reading[st.outlet] or st.notice then out[#out+1]=st end
  if limit and #out>=limit then break end
 end
 return out
end

---------------------------------------------------------------- the player's trades

-- Selling into a story: feeding a real shortage the owner needs helps;
-- flooding one the outlet blew up (or made up) wrecks its story.
function N.onTrade(u,key,sold)
 local s=N.state(u);local clock=u.clock or 0
 local E=require('src.economy')
 for item,n in pairs(sold) do
  for i=#s.stories,1,-1 do
   local st=s.stories[i]
   if clock-st.clock>N.T.storyLife then break end
   if st.station==key and st.good==item and st.kind=='shortage' and not st.tip and not st.quest then
    -- hype is selling into a story that isn't true: a rumour, or a
    -- shortage the station doesn't really have now
    local now=(require('src.markets').state(u).prices[key] or {})[item] or 1
    local hyped=st.rumour or now<1.15 and E.shortageAge(u,key,item,clock)<=0
    if hyped and n>=20 then N.addStanding(u,st.outlet,-math.min(10,n/10))
    elseif not hyped then N.addStanding(u,st.outlet,math.min(5,n/20)) end
   end
  end
  -- the owner's own shortage, story or not
  local o=N.ofFaction(Rep().ofNode(key))
  if o and E.shortageAge(u,key,item,clock)>0 then N.addStanding(u,o,math.min(3,n/40)) end
 end
end

-- Stories the player should hear about straight away (one naming them, a
-- notice about their subscription) go to their notifications too, if
-- they can read that paper right now.
function N.tell(u,st)
 if not (st.notice or st.subject=='player' and st.named) then return end
 local g=N.game
 local key
 if g and g.state=='docked' and g.player and g.player.dockState and g.player.dockState.station then
  key=require('src.stockpile').key(g.player.dockState.station)
  if not L().byId[key] then key=nil end
 end
 local reading=false
 for _,o in ipairs(N.reading(u,key)) do if o==st.outlet then reading=true end end
 if not (reading or st.notice) then return end
 require('src.notify').post(u,{kind=st.notice and 'subscription' or 'news',title=Outlets.outlets[st.outlet].name,text=N.headline(st)})
end

---------------------------------------------------------------- subscriptions

function N.subscribed(u,o) return N.state(u).subs[o]~=nil end
-- Can the player subscribe to o here? Returns ok, or nil and why not.
function N.canSubscribe(u,o,nodeId)
 if N.subscribed(u,o) then return nil,'Already subscribed' end
 if N.desk(nodeId)~=o then return nil,'Subscribe at the paper\'s own press desk' end
 if N.mood(u,o)=='hostile' then return nil,Outlets.outlets[o].name..' won\'t take your money' end
 if (u.credits or 0)<N.T.subscribeFee then return nil,'Not enough credits' end
 return true
end
-- Take out a subscription at the press desk: the first hour is paid now.
function N.subscribe(u,o,nodeId)
 local ok,why=N.canSubscribe(u,o,nodeId)
 if not ok then return false,why end
 u.credits=u.credits-N.T.subscribeFee
 N.state(u).subs[o]={since=u.clock or 0,paidUntil=(u.clock or 0)+3600}
 return true
end
function N.cancel(u,o) N.state(u).subs[o]=nil end
local function notice(u,o,text) N.publish(u,{outlet=o,kind='notice',notice=true,headline=text}) end
-- Bill every subscription that's due; lapse the ones you can't pay or
-- whose paper has turned on you.
function N.bill(u,s,clock)
 for _,o in ipairs(Outlets.order) do
  local sub=s.subs[o]
  while sub and clock>=sub.paidUntil do
   local name=Outlets.outlets[o].name
   if N.mood(u,o)=='hostile' then
    s.subs[o]=nil;sub=nil;notice(u,o,name..' has cancelled your subscription')
   elseif (u.credits or 0)<N.T.subscribeFee then
    s.subs[o]=nil;sub=nil;notice(u,o,'Your subscription to '..name..' lapsed: not enough credits')
   else
    u.credits=u.credits-N.T.subscribeFee;sub.paidUntil=sub.paidUntil+3600
   end
  end
 end
end

-- Hook the listeners once (the universe can be swapped on load).
function N.listen(game)
 N.game=game
 if N.listening then return end
 local events=require('src.events')
 N.listening=true
 events.on('trade',function(st,sold)
  local g=N.game
  if g and g.universe and st then N.onTrade(g.universe,require('src.stockpile').key(st),sold) end
 end)
end

return N
