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
	            everywhere (the Beltway).
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
 keep=160,            -- stories kept in the save
 shortRatio=1.35,     -- a price this far over list is a shortage story
 glutRatio=.7,        -- and this far under, a glut story
 shortAge=1800,       -- or a shortage left unserved this long
 standingDecay=2,     -- outlet standing, points per hour toward 0
 friendly=25,hostile=-25,
 smearOdds=.08,praiseOdds=.08, -- per run, from a hostile / friendly outlet
 smearHit=-3,praiseHit=2,      -- reported standing those move
 blameOdds=.25,       -- an NPC's kill pinned on the player (same hull class)
 blameHit=-5,
 secondhandWeight=.6, -- a copied deed weighs this much of a first-hand one
 rivalPraise=.25,     -- an outlet's owner warms to you for hitting its rivals
}

local function clamp(v,lo,hi) return math.max(lo,math.min(hi,v)) end
local function L() return require('src.locations') end
local function Rep() return require('src.reputation') end

function N.state(u)
 local s=u.news
 if not s then
  s={stories={},nextId=0,nudges={},shocks={},outlets={},deeds={}}
  u.news=s
 end
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
-- The news's multiplier on a station's price for a good. Story nudges are
-- capped together; quest shocks are not.
function N.factor(u,key,item)
 local s=u.news;if not s then return 1 end
 local clock=u.clock or 0;local f=1
 local k=s.nudges[key];local list=k and k[item]
 if list then f=1+clamp(sumNudges(list,clock),-N.T.nudgeCap,N.T.nudgeCap) end
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

-- Put a story in the feed. Fills in id, clock and a headline from the
-- outlet's templates when none is given. Returns the story.
function N.publish(u,st)
 local s=N.state(u)
 s.nextId=s.nextId+1
 st.id='story/'..s.nextId;st.clock=st.clock or u.clock or 0
 st.faction=st.faction or (st.station and Rep().ofNode(st.station))
 if not st.headline then
  local vars={good=st.good and itemName(st.good),station=st.station and placeName(st.station),
   area=st.area and areaName(st.area),pct=st.reported and pct(st.reported),who=st.who,faction=factionName(st.faction)}
  st.headline=fill(template(st.outlet,st.kind,s.nextId),vars)
 end
 s.stories[#s.stories+1]=st
 while #s.stories>N.T.keep do table.remove(s.stories,1) end
 if st.good and st.reported and st.area and not st.tip then
  nudge(u,st.area,st.outlet,st.good,clamp((st.reported-1)*N.T.nudgeScale,-N.T.nudgeCap,N.T.nudgeCap),st.id)
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
 return 1+dev
end

local function recentAbout(s,o,key,item,since)
 for i=#s.stories,1,-1 do
  local st=s.stories[i]
  if st.clock<since then break end
  if st.outlet==o and st.station==key and st.good==item then return true end
 end
 return false
end

-- Price facts on an outlet's beat, biggest (and most on-agenda) first.
local function priceFacts(u,o,clock)
 local Markets=require('src.markets');local E=require('src.economy')
 local prices=Markets.state(u).prices;local d=Outlets.outlets[o]
 local out={}
 for _,area in ipairs(d.beat) do
  for _,key in ipairs(L().stations(area,'trade')) do
   local p=prices[key]
   if p then
    for item,ratio in pairs(p) do
     local short=E.shortageAge(u,key,item,clock)>=N.T.shortAge
     if ratio>=N.T.shortRatio or ratio<=N.T.glutRatio or short then
      local score=math.abs(ratio-1)*(1+math.abs(d.agenda[item] or 0))+(short and .2 or 0)
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

-- Apply a story about a player deed to every faction that reads it.
local function report(u,st)
 local deed=st.deed;if not deed or not st.named then return end
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
 local d=Outlets.outlets[o];local p=d.smear*(firsthand and 1 or .5)
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
 s.deeds[#s.deeds+1]=deed
 while #s.deeds>40 do table.remove(s.deeds,1) end
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
      who=playerWho(u,named),named=named,subject='player',deed=deed}))
    end
   end
   -- nobody's beat: the everywhere outlets may still hear of it
   if not any then
    for _,o in ipairs(Outlets.order) do
     if Outlets.outlets[o].everywhere and rng(u)<N.T.secondhandOdds then
      local named=rng(u)<naming(u,o,false)
      report(u,N.publish(u,{outlet=o,kind=deed.delta<0 and 'killed' or 'praise',area=deed.area,faction=deed.faction,
       who=playerWho(u,named),named=named,subject='player',deed=deed,secondhand=true}))
     end
    end
   end
  end
 end
 for i=#s.deeds,1,-1 do if clock-s.deeds[i].clock>N.T.storyLife then table.remove(s.deeds,i) end end
end

-- NPC killings of faction ships on an outlet's beat. If the killer flew
-- what the player flies, a careless outlet may pin it on the player.
local function deathStories(u,s,o,since,clock)
 local H=require('src.simulation_history');local d=Outlets.outlets[o]
 local printed=0
 for _,e in ipairs(H.recent(u,{kind='npc_died',since=since},40)) do
  if printed>=1 then break end
  local victim=u.npcs and u.npcs[e.participants[1]]
  local killer=e.result and e.result.killer
  local f=victim and Rep().ofRecord(victim)
  if f and killer and killer~='player' and e.area and N.covers(o,e.area) then
   local k=u.npcs and u.npcs[killer]
   local hull=k and k.ship and k.ship.hull
   local playerHull=s.playerHullId
   local blame=hull and playerHull and hull==playerHull and rng(u)<N.T.blameOdds*(d.smear+.2)
   local st={outlet=o,kind='killed',area=e.area,faction=f,fact=e.id}
   if blame then
    st.who=playerWho(u,true);st.named=true;st.subject='player';st.blamed=true
    st.deed={faction=f,delta=N.T.blameHit,area=e.area,clock=clock}
   else
    local hd=hull and require('src.data').hulls[hull]
    st.who=hd and ('a '..hd.name) or 'raiders'
   end
   report(u,N.publish(u,st));printed=printed+1
  end
 end
end

local function copyStories(u,s,o,clock)
 local d=Outlets.outlets[o];local copied=0
 for i=#s.stories,1,-1 do
  local st=s.stories[i]
  if clock-st.clock>N.T.storyLife then break end
  if copied>=1 then break end
  if st.outlet~=o and not st.secondhand and not st.tip and not st.quest and st.area and not N.covers(o,st.area)
   and clock-st.clock>=N.T.secondhandDelay then
   st.copies=st.copies or {}
   if not st.copies[o] then
    st.copies[o]=true
    local odds=d.everywhere and .8 or N.T.secondhandOdds
    if rng(u)<odds then
     local c={outlet=o,kind=st.kind,area=st.area,station=st.station,good=st.good,faction=st.faction,
      secondhand=true,from=st.outlet,subject=st.subject,deed=st.deed,blamed=st.blamed}
     if st.reported then c.reported=spin(o,st.good,st.reported,st.station) end
     if st.kind=='shortage' or st.kind=='glut' then
      if c.reported then c.kind=c.reported>=1 and 'shortage' or 'glut' end
     end
     if not (st.reported and not c.reported) then
      if st.subject=='player' then
       c.named=st.named and rng(u)<.7 or false
       c.who=playerWho(u,c.named)
      else c.who=st.who end
      report(u,N.publish(u,c));copied=copied+1
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
  if printed>=N.T.perTick then break end
  if not recentAbout(s,o,fact.key,fact.item,clock-N.T.storyLife) then
   if mood=='friendly' then
    N.publish(u,{outlet=o,kind='tip',tip=true,area=fact.area,station=fact.key,good=fact.item,reported=fact.ratio,real=fact.ratio,
     headline=('Tip: %s at %s is really %s'):format(itemName(fact.item),placeName(fact.key),pct(fact.ratio))})
   end
   local r=spin(o,fact.item,fact.ratio,fact.key)
   if r then
    N.publish(u,{outlet=o,kind=r>=1 and 'shortage' or 'glut',area=fact.area,station=fact.key,good=fact.item,
     real=fact.ratio,reported=r})
    printed=printed+1
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
function N.update(u,clock,game)
 local s=N.state(u)
 if game and game.player and game.player.hull then
  s.playerHull=game.player.hull.name;s.playerHullId=game.player.hull.id
 end
 if clock<(s.nextTick or 0) then return end
 local since=s.lastTick or clock-N.T.tick
 s.lastTick=clock;s.nextTick=clock+N.T.tick
 prune(s.nudges,clock);prune(s.shocks,clock)
 deedStories(u,s,clock)
 for _,o in ipairs(Outlets.order) do run(u,s,o,since,clock) end
end

---------------------------------------------------------------- the player's view

-- Outlets the player can read right now: what's carried at the station
-- they're docked at (nodeId) or in the system they're flying in (area).
function N.reading(u,nodeId,area)
 local out,seen={},{}
 for _,o in ipairs(N.carried(nodeId,area)) do if not seen[o] then seen[o]=true;out[#out+1]=o end end
 return out
end
-- The feed, newest first: stories from the outlets read. Tips from
-- friendly outlets always come through.
function N.feed(u,nodeId,area,limit)
 local s=N.state(u);local clock=u.clock or 0
 local reading={};for _,o in ipairs(N.reading(u,nodeId,area)) do reading[o]=true end
 local out={}
 for i=#s.stories,1,-1 do
  local st=s.stories[i]
  if clock-st.clock>N.T.storyLife then break end
  if reading[st.outlet] or st.tip then out[#out+1]=st end
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
    local hyped=st.rumour or (st.reported or 1)-(st.real or 1)>.3
    if hyped and n>=20 then N.addStanding(u,st.outlet,-math.min(10,n/10))
    elseif not hyped then N.addStanding(u,st.outlet,math.min(5,n/20)) end
   end
  end
  -- the owner's own shortage, story or not
  local o=N.ofFaction(Rep().ofNode(key))
  if o and E.shortageAge(u,key,item,clock)>0 then N.addStanding(u,o,math.min(3,n/40)) end
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
