--[[
	Wildcats: the crews of instanced sites (data/sites.lua, src/sites.lua),
	and the bounty hunters who clear them.

	A wildcat is an A-Life record that does one thing. Its site rolls its
	crew once when it spawns: each ship is a hull rolled the way a pirate's
	is (src/npc_ship_supply.lua), with the raider's combat profile. Nobody
	is ever recruited from the NPC pool, and the crew never grows.

	  r.wildcat   { site, pocket, x, y, tag, nextSortie, out, homing,
	                fencing }   who it is, kept for life
	  r.garrison  { site, pocket, field, x, y, tag }   set while it is at its
	                post in the site; A-Life treats it as parked there

	The loop:
	  posted   it holds its post in its pocket. Offline it slowly patches
	           its hull. Every T.wildcatSortieEvery it goes out.
	  sortie   it comes off its planet's mass driver and runs the raider
	           brain: raid legs round the planet, robbery demands, fights
	           (src/security.lua, src/robbery.lua, src/encounters.lua).
	  home     with loot, hurt, or after T.wildcatSortieTime, it flies back
	           to the driver and returns to its post. Stolen cargo goes on
	           the site's hoard (inst.hoard).
	  fence    when the hoard passes T.hoardFenceAt, one wildcat carries it
	           to a dark station and sells it there
	           (src/piracy.lua fencing), so it turns up as shadow stock.
	           While docked it trades a worn hull in on the used lot and
	           flies back in a new one.

	Wildcats are raiders, so Milliways and the other dark raiders leave
	them alone and the dark stations deal with them. They never belong to
	Milliways and never touch its standing.

	Bounties: every wildcat site is under bounty from the moment it opens,
	paid by its system's paying station (src/wreck_bounty.lua payer): the
	site shows on the mass driver for everyone, and each wildcat of that
	site is worth W.perHead to whoever lands the last hit on it, paid
	straight into their credits (the player gets a periodic notice:
	src/wreck_bounty.lua B.notice).

	Hunters: a small population of armed NPCs (template 'hunter') take
	the bounty off the board ('site_bounty'), fly to the driver and go in.
	  r.assault   { site, pocket, x, y }   while it is inside a site
	Offline, W.tick rolls the fight pocket by pocket with the offline
	combat rule (src/encounters.lua E.damage). A broken hunter pulls out.
	When the player is in the pocket, both sides are live ships and fight
	there instead (src/ai.lua pickTarget).

	A site whose crew is all gone is done (inst.done) and closes once
	you're out of it. If hunters cleared it, what was left of the hoard is
	handed back to the station that paid the bounty; if you did, it drops
	in containers in the pocket where the last one died.
]]
local data=require('src.data')
local T=require('src.tuning')
local L=require('src.locations')
local Fields=require('src.fields')
local Stats=require('src.stats')
local Hold=require('src.inventory.hold')
local Tasks=require('src.tasks')
local copy=require('src.persistence').copy
local W={}

local random=function(...) return love.math.random(...) end
local function alive(r) return r and r.state~='dead' and r.state~='escaped' end
local function sites(u) return require('src.sites').list(u) end
local function fieldId(site,n) return require('src.sites').fieldId(site,n) end
local function maxArmor(r)
 local hull=r.ship and data.hulls[r.ship.hull]
 return hull and Stats.compute(hull,r.ship.loadout).armor or 1
end
local function driverOf(area) return Fields[area] and Fields[area].driverId end
-- The planet an area belongs to (a moon's or a dark grid's parent).
local function systemOf(area)
 local m=area and Fields.moons and Fields.moons[area]
 return m and m.parent or area
end
local function trace(r,clock,what) require('src.alife_trace').note(r,clock,'wildcat',what) end

-- Crew -------------------------------------------------------------------------

-- Every living wildcat of a site, posted or out.
function W.crew(u,site)
 local out={}
 for _,r in pairs(u.npcs or {}) do
  if r.wildcat and r.wildcat.site==site and alive(r) then out[#out+1]=r end
 end
 table.sort(out,function(a,b) return a.id<b.id end)
 return out
end
-- Wildcats at their posts in one pocket's field (optionally one tag).
function W.members(u,field,tag)
 local out={}
 for _,r in pairs(u.npcs or {}) do
  local g=r.garrison
  if g and g.field==field and alive(r) and (tag==nil or g.tag==tag) then out[#out+1]=r end
 end
 table.sort(out,function(a,b) return a.id<b.id end)
 return out
end
function W.held(u,field) return #W.members(u,field)>0 end
-- Posted crew anywhere in the site.
function W.posted(u,site)
 local n=0
 for _,r in pairs(u.npcs or {}) do
  if r.garrison and r.garrison.site==site and alive(r) then n=n+1 end
 end
 return n
end
function W.hunters(u,site)
 local out={}
 for _,r in pairs(u.npcs or {}) do
  if r.assault and r.assault.site==site and alive(r) then out[#out+1]=r end
 end
 table.sort(out,function(a,b) return a.id<b.id end)
 return out
end

local function post(r,inst,clock)
 local w=r.wildcat
 r.garrison={site=inst.id,pocket=w.pocket,field=fieldId(inst.id,w.pocket),x=w.x,y=w.y,tag=w.tag}
 r.area=r.garrison.field;r.state='garrison';r.untilTime=clock
 r.route={};r.index=1;r.node=nil;r.transit=nil;r.encounter=nil
 r.pose,r.offset,r.savedOnline,r.docking,r.action=nil,nil,nil,nil,nil
 r.piracy,r.service,r.serviced=nil,nil,nil
 w.out,w.homing,w.fencing=nil,nil,nil
 w.nextSortie=clock+T.wildcatSortieEvery*(.6+.8*random())
end

-- A new wildcat for pocket n of a site, at (x, y): a rolled raider hull.
function W.recruit(u,inst,n,x,y,tag)
 local Supply=require('src.npc_ship_supply')
 local ship,policy=Supply.seed(u,inst.home,'wildcat')
 if not ship then
  local def=data.npcProfiles.raider;local hull=data.hulls[def.hull]
  local loadout=copy(def.loadout or hull.loadout)
  ship={hull=def.hull,loadout=loadout,cargo={},armor=Stats.compute(hull,loadout).armor}
 end
 local clock=u.clock or 0
 u.nextNpcId=(u.nextNpcId or 0)+1
 local r={id='npc/'..u.nextNpcId,home=inst.home,aiProfile='raider',spread=0,ship=ship,
  wildcat={site=inst.id,pocket=n,x=x,y=y,tag=tag or nil},
  spawnedAt=clock,spawnOrigin='wildcat'}
 r.speed=require('src.npc').cruise(r.ship)
 require('src.npc_templates').apply(r,'wildcat',inst.home)
 require('src.personality').ensure(r)
 require('src.npc_home').choose(u,r)
 Supply.settle(r,policy)
 post(r,inst,clock)
 -- the first sorties are staggered, so a new site doesn't empty at once
 r.wildcat.nextSortie=clock+T.wildcatSortieEvery*(.3+random())
 u.npcs[r.id]=r
 trace(r,clock,'crew of '..inst.id..' pocket '..n)
 return r
end

-- Roll a new site's whole crew from its template's enemy pieces.
function W.roll(u,inst)
 local def=require('src.sites').template(inst)
 if not def or inst.crew then return end
 inst.crew=true
 for n,pk in ipairs(def.pockets) do
  for _,pc in ipairs(pk.pieces or {}) do
   if pc.type=='enemies' then
    local c=pc.crew or {1,1}
    local count=random(c[1],c[2] or c[1])
    for _=1,count do
     local a,d=random()*math.pi*2,random()*(pc.r or 0)
     W.recruit(u,inst,n,(pc.x or 0)+math.cos(a)*d,(pc.y or 0)+math.sin(a)*d,pc.tag)
    end
   end
  end
 end
end

-- A pocket is being built: move posts that landed inside a rock.
function W.settle(game,inst,n)
 for _,r in ipairs(W.members(game.universe,fieldId(inst.id,n))) do
  local g=r.garrison
  if not game:isClear(g.x,g.y,150) then
   for _=1,20 do
    local a,d=random()*math.pi*2,300+random()*1500
    local x,y=g.x+math.cos(a)*d,g.y+math.sin(a)*d
    if game:isClear(x,y,150) then g.x,g.y=x,y;r.wildcat.x,r.wildcat.y=x,y;break end
   end
  end
 end
end

-- The site closed: posted crew scatter with it, hunters inside pull out.
-- Wildcats out raiding find nothing when they get home, and scatter then.
function W.disband(u,site,game)
 for _,r in pairs(u.npcs or {}) do
  if alive(r) and r.garrison and r.garrison.site==site then
   r.state='escaped';r.garrison=nil
   Tasks.release(u,r,'site closed',u.clock or 0)
  elseif alive(r) and r.assault and r.assault.site==site then
   W.endAssault(game,u,r,'site closed')
  end
 end
 for id,o in pairs(Tasks.state(u).offers) do
  if o.kind=='site_bounty' and o.site==site and o.state=='available' then Tasks.state(u).offers[id]=nil end
 end
end

-- Hoard ------------------------------------------------------------------------

function W.hoardUnits(inst)
 local n=0
 for _,k in pairs(inst.hoard or {}) do n=n+k end
 return n
end
local function addHoard(inst,id,n)
 if n<=0 or not data.items[id] then return end
 inst.hoard=inst.hoard or {}
 inst.hoard[id]=(inst.hoard[id] or 0)+n
end
local function stashInner(inst,inner)
 local h=type(inner)=='string' and Hold.deserialize(inner) or inner
 if not h then return end
 for _,g in ipairs(h.grids) do for _,s in ipairs(g.stacks) do
  addHoard(inst,s.id,s.n)
  if s.inner then stashInner(inst,s.inner) end
 end end
end
-- Unload what a wildcat stole onto its site's hoard.
function W.stash(u,r,inst)
 local Grid=require('src.inventory.grid')
 local h=r.ship.hold and Hold.deserialize(r.ship.hold,function(id) return data.items[id]~=nil end)
 local cargo=h and Hold.totals(h) or r.ship.cargo or {}
 local before=W.hoardUnits(inst)
 if h then
  for _,g in ipairs(h.grids) do for i=#g.stacks,1,-1 do
   local s=g.stacks[i]
   if s.stolen then
    addHoard(inst,s.id,s.n)
    if s.inner then stashInner(inst,s.inner) end
    if r.stolenCargo then r.stolenCargo[s.id]=math.max(0,(r.stolenCargo[s.id] or 0)-s.n) end
    Grid.remove(g,s)
   end
  end end
  cargo=Hold.totals(h)
 end
 for id,count in pairs(r.stolenCargo or {}) do
  local n=math.min(count,cargo[id] or 0)
  if n>0 then
   if h then Hold.take(h,id,n) else cargo[id]=cargo[id]-n;if cargo[id]==0 then cargo[id]=nil end end
   addHoard(inst,id,n)
  end
 end
 if h then r.ship.hold=Hold.serialize(h);cargo=Hold.totals(h) end
 r.ship.cargo=cargo;r.stolenCargo={};r.lootUntil=nil
 return W.hoardUnits(inst)-before
end
-- Load as much of the hoard as fits into r's hold, marked stolen so the
-- fence buys it (src/piracy.lua P.unload).
local function loadHoard(r,inst)
 local h=r.ship.hold and Hold.deserialize(r.ship.hold,function(id) return data.items[id]~=nil end)
 local cargo=h and Hold.totals(h) or r.ship.cargo or {}
 local room=math.max(0,(Stats.compute(data.hulls[r.ship.hull],r.ship.loadout).hold or 0))
 for id,n in pairs(cargo) do room=room-(data.items[id] and data.items[id].volume or 1)*n end
 local moved=0
 local ids={};for id in pairs(inst.hoard or {}) do ids[#ids+1]=id end;table.sort(ids)
 for _,id in ipairs(ids) do
  local n=inst.hoard[id];local v=data.items[id] and data.items[id].volume or 1
  local k=math.min(n,math.floor(room/math.max(.001,v)))
  if h and k>0 then k=Hold.add(h,id,k) elseif k>0 then cargo[id]=(cargo[id] or 0)+k end
  if k>0 then
   inst.hoard[id]=n-k;if inst.hoard[id]<=0 then inst.hoard[id]=nil end
   r.stolenCargo=r.stolenCargo or {};r.stolenCargo[id]=(r.stolenCargo[id] or 0)+k
   room=room-k*v;moved=moved+k
  end
 end
 if h then r.ship.hold=Hold.serialize(h);cargo=Hold.totals(h) end
 r.ship.cargo=cargo
 return moved
end

-- Out and home ---------------------------------------------------------------

-- A pirate haven's station that buys stolen goods, reachable from `from`: any of
-- them, picked at random, so the hoard isn't always sold at the same one.
local function fenceFor(u,home,from,clock)
 local out={}
 for _,area in ipairs(require('src.dark').havens()) do
  for _,id in ipairs(require('src.security').bases(area)) do
   if require('src.travelgraph').live(from,id,clock) then out[#out+1]=id end
  end
 end
 table.sort(out)
 return out[1] and out[math.floor(random()*#out)+1]
end

-- Off the post and out of the site through its planet's mass driver.
local function leave(game,r,clock)
 local driver=driverOf(r.home)
 if not driver then return false end
 r.garrison=nil;r.area=r.home;r.node=driver;r.route={driver,driver};r.index=1
 r.state='idle';r.untilTime=clock;r.nextDecisionAt=nil
 r.pose,r.offset,r.savedOnline=nil,nil,nil
 r.taskWorker=true;r.wildcat.out=clock;r.wildcat.homing=nil
 require('src.supplies').provision(r)
 return driver
end

-- Out to raid round the site's planet.
function W.sortie(game,r)
 local u=game.universe;local clock=u.clock or 0
 local driver=leave(game,r,clock)
 if not driver then return false end
 require('src.security').ensureRaids(u,r.home)
 trace(r,clock,'out raiding round '..r.home)
 if not require('src.piracy').deploy(game,r,driver,r.home) then
  -- no rally point: hunt from the driver itself
  r.taskStatus='raiding'
 end
 return true
end

-- Out to sell the hoard at a dark station.
function W.fenceRun(game,r,inst)
 local u=game.universe;local clock=u.clock or 0
 local driver=driverOf(r.home);if not driver then return false end
 local base=fenceFor(u,r.home,driver,clock);if not base then return false end
 if loadHoard(r,inst)<=0 then return false end
 leave(game,r,clock)
 r.wildcat.fencing=true;inst.fencer=r.id
 r.piracy={phase='escape',base=base,origin=driver,started=clock}
 r.task={id='fence/'..r.id..'/'..clock,kind='fence',source=driver,target=base}
 r.taskStatus='fencing at '..L.get(base).name
 trace(r,clock,'fence run to '..base)
 return require('src.npc').travel(game,r,base,clock)
end

-- Back to the site: fly to the planet's driver; W.advance posts it there.
function W.goHome(game,r,reason)
 local u=game.universe;local clock=u.clock or 0
 if r.garrison or r.assault then return true end
 if r.encounter then require('src.encounters').finish(u,r,u.npcs[r.encounter.target],clock,r) end
 local driver=driverOf(r.home)
 if not driver then r.state='escaped';return false end
 Tasks.release(u,r,reason or 'heading home',clock)
 r.piracy=nil;r.service=nil;r.serviced=nil
 r.wildcat.homing=clock
 local source=r.state=='travel' and r.route[r.index] or r.node or r.route[r.index] or driver
 r.task={id='wildcat_home/'..r.id..'/'..clock,kind='wildcat_home',source=source,target=driver}
 r.taskWorker=true;r.taskStatus='back to its site'
 trace(r,clock,'heading back to '..r.wildcat.site..' ('..(reason or 'done')..')')
 if L.canonical(source)==L.canonical(driver) and r.state~='travel' and r.state~='transit' then return true end
 return require('src.npc').travel(game,r,driver,clock)
end
Tasks.register('wildcat_home',{
 docks=function() return false end,
 stay=function() return 2 end,
 complete=function() return false end,
 continue=function(c)
  local t=c.r.task
  if L.canonical(c.node)~=L.canonical(t.target) then
   local path=require('src.travelgraph').live(c.node,t.target,c.clock)
   if path and #path>1 then return {route=path} end
  end
  return {wait=2}
 end,
})

-- Arrived back at the driver: through the lane and onto its post.
function W.arrive(u,r)
 local clock=u.clock or 0
 local inst=sites(u)[r.wildcat.site]
 Tasks.release(u,r,'home',clock)
 if not inst or inst.done then
  r.state='escaped'
  trace(r,clock,'its site is gone: scattered')
  return
 end
 local got=W.stash(u,r,inst)
 if inst.fencer==r.id then inst.fencer=nil end
 post(r,inst,clock)
 r.taskStatus='at its post'
 trace(r,clock,('back at its post%s'):format(got>0 and (' with '..got..' stolen') or ''))
end

-- At the fence (src/piracy.lua, after unloading): the same docked shop
-- every NPC does (src/npc_refit.lua), so a wildcat with the money can
-- swap its hull for a better one off this station's used lot.
function W.atFence(u,r,base)
 if not r.wildcat then return end
 require('src.npc_refit').dock(r,base,u,u.clock or 0)
end

-- The fence run is over (src/piracy.lua): head back to the site.
function W.fenced(c)
 local r=c.r
 r.wildcat.fencing=nil
 local driver=driverOf(r.home)
 r.piracy=nil;Tasks.release(c.u,r,'fenced',c.clock)
 r.wildcat.homing=c.clock
 r.task={id='wildcat_home/'..r.id..'/'..c.clock,kind='wildcat_home',source=c.node,target=driver}
 r.taskWorker=true;r.taskStatus='back to its site'
 if L.canonical(c.node)~=L.canonical(driver) then
  local path=require('src.travelgraph').live(c.node,driver,c.clock)
  if path and #path>1 then return {route=path} end
 end
 return {wait=2}
end

-- Offline tick ----------------------------------------------------------------

local function postedAdvance(r,clock,u,game)
 local g=r.garrison
 local inst=sites(u)[g.site]
 if not inst then r.state='escaped';r.garrison=nil;return true end
 -- patching the hull up at the site
 local full=maxArmor(r)
 local last=r.wildcat.patchedAt or clock
 r.wildcat.patchedAt=clock
 -- (not while hunters are inside: a fight wears a crew down over trips)
 if r.ship.armor<full and #W.hunters(u,g.site)==0 and not (game and game.alifeOnline and game.alifeOnline[r.id]) then
  r.ship.armor=math.min(full,r.ship.armor+full*T.wildcatPatchRate*math.max(0,clock-last)/3600)
 end
 if not game or clock<(r.wildcat.nextSortie or 0) then return true end
 -- the site's stores rearm whoever is at a post between fights
 if #W.hunters(u,g.site)==0 then require('src.supplies').provision(r) end
 r.wildcat.nextSortie=clock+T.wildcatSortieEvery*(.6+.8*random())
 -- nobody leaves while the site is under attack or someone is in this pocket
 if game.fieldId==g.field or #W.hunters(u,g.site)>0 then return true end
 if require('src.sites').of(game.fieldId)==g.site then return true end
 -- the site is never left empty
 if W.posted(u,g.site)<=1 then return true end
 if r.ship.armor<full*T.wildcatSortieHealth then return true end
 if W.hoardUnits(inst)>=T.hoardFenceAt and not (inst.fencer and alive(u.npcs[inst.fencer])) then
  if W.fenceRun(game,r,inst) then return true end
 end
 W.sortie(game,r)
 return true
end

-- Out in the world: home when hurt or the sortie is up. Returns nothing:
-- the shared NPC loop carries on.
local function outAdvance(r,clock,u,game)
 local w=r.wildcat
 if w.homing then
  local t=r.task
  if t and t.kind=='wildcat_home' and (r.state=='idle' or r.state=='docked')
   and r.node and L.canonical(r.node)==L.canonical(t.target)
   and not (game and game.alifeOnline and game.alifeOnline[r.id]) then
   W.arrive(u,r);return true
  end
  -- (a homing record with no task: lost it to a save from before; again)
  if not t and game then W.goHome(game,r,'resumed') end
  return
 end
 if w.fencing or not game or r.state=='transit' or r.encounter then return end
 local full=maxArmor(r)
 if clock>=(w.out or clock)+T.wildcatSortieTime or (r.ship.armor or full)<full*T.pirateRetreatHealth then
  W.goHome(game,r,'sortie over')
 elseif not r.task and not r.piracy and (r.state=='idle' or r.state=='docked') then
  -- nothing to raid here right now: it waits a little, then goes home
  -- (never off to some station of its own: its site is its home)
  w.idleSince=w.idleSince or clock
  if clock-w.idleSince>=T.wildcatIdleHome then w.idleSince=nil;W.goHome(game,r,'no prey') end
 else w.idleSince=nil end
end

-- Called from A-Life (src/alife.lua A.advance). True: handled, skip the
-- shared NPC loop this time.
function W.advance(r,clock,u,game)
 if r.garrison then return postedAdvance(r,clock,u,game) end
 if r.assault then return true end
 if r.wildcat then return outAdvance(r,clock,u,game) end
 return false
end

function W.point(r)
 local g=r.garrison or r.assault
 if g then return g.x,g.y end
end

-- A posted wildcat or a hunter inside a site comes online: it fights as a
-- site ship (src/ai.lua pickTarget), not on a route.
-- Is x, y clear of rock and structure for a ship of half-length m?
local function rockFree(game,x,y,m)
 if not game:areaObjectClear(x,y,m) then return false end
 for _,o in ipairs(game.entities) do
  local k=o.kind
  if (k=='asteroid' or k=='structure' or k=='station' or k=='planet') and o.body then
   local ox,oy=o.body:getPosition();ox,oy=ox+(o.cx or 0),oy+(o.cy or 0)
   if (ox-x)^2+(oy-y)^2<((o.radius or 0)+m)^2 then return false end
  end
 end
 return true
end
-- A site ship that comes up inside a rock is moved to clear space nearby
-- (posts and assault spots are picked offline, where the rocks aren't
-- known, and rocks drift); its post or spot moves with it.
local function unstick(game,e,r)
 local x,y=e.body:getPosition()
 local m=(e.halfLength or e.hull and e.hull.radius or 60)+80
 if rockFree(game,x,y,m) then return end
 for i=1,40 do
  local a,d=random()*math.pi*2,200+i*60
  local nx,ny=x+math.cos(a)*d,y+math.sin(a)*d
  if rockFree(game,nx,ny,m) then
   e.body:setPosition(nx,ny)
   local g=r.garrison or r.assault
   if g then g.x,g.y=nx,ny end
   if r.garrison then r.wildcat.x,r.wildcat.y=nx,ny end
   return
  end
 end
end
function W.unstick(game)
 for _,e in ipairs(game.entities) do
  local r=e.kind=='ship' and e.alifeId and game.universe.npcs[e.alifeId]
  if r and (r.garrison or r.assault) and e.body and not e.dead and not e.removed then unstick(game,e,r) end
 end
end
-- Which group a posted wildcat fights with: its pocket's crew in id
-- order, split into threes (a piece's crew are recruited together, so a
-- group holds posts near each other). One of a group aggroing brings the
-- rest (src/ai.lua).
local function groupOf(u,r)
 local g=r.garrison
 local crew=W.members(u,g.field)
 for i,o in ipairs(crew) do
  if o==r then return g.field..'/'..math.floor((i-1)/T.siteGroupSize) end
 end
end
function W.woke(game,e,r)
 if (r.garrison or r.assault) and e.body then unstick(game,e,r) end
 if r.garrison then
  e.team=2;e.aggro=false
  e.siteEnemy,e.siteTag=true,r.garrison.tag or nil
  e.siteGroup=groupOf(game.universe,r)
  e.route=nil
  return true
 end
 if r.assault then
  e.team=3;e.aggro=true;e.siteHunter=true;e.route=nil
  return true
 end
 return false
end

-- A live ship ran off the edge of its pocket. A wildcat regroups at its
-- post; a hunter gives up on the site.
function W.fled(game,r)
 local u=game.universe
 if r.garrison then
  r.garrison.x,r.garrison.y=r.wildcat.x,r.wildcat.y;r.pose=nil
  return true
 end
 if r.assault then W.endAssault(game,u,r,'fled');return true end
 return false
end

-- Bounties ---------------------------------------------------------------------

function W.perHead(r)
 return math.floor(T.bountyPerHead+maxArmor(r)*T.bountyPerArmor+.5)
end
local function news(u,inst,headline,named)
 local N=require('src.news')
 local Outlets=require('data.outlets')
 for _,o in ipairs(Outlets.order) do
  if N.covers(o,inst.home) then
   N.publish(u,{outlet=o,kind='site',area=inst.home,headline=headline,fact='site:'..inst.id..':'..named})
  end
 end
end
W.news=news
local function siteName(inst) return require('src.sites').name(inst) end
local function areaName(a) return Fields[a] and Fields[a].name or a end

-- The station posts a bounty on the site: it goes on the driver for
-- everyone, and on the board for the hunters.
function W.postBounty(u,inst)
 if inst.bounty or inst.done then return end
 local station=require('src.wreck_bounty').payer(inst.home)
 if not station then return end
 local clock=u.clock or 0
 inst.bounty={station=station,postedAt=clock}
 require('src.sites').discover(u,inst)
 local driver=driverOf(inst.home)
 -- a big crew draws more hunters: a slot per two wildcats, at least bountySlots
 local crew=W.posted(u,inst.id)
 for slot=1,math.max(T.bountySlots,math.ceil(crew/2)) do
  Tasks.post(u,{kind='site_bounty',source=station,target=driver,site=inst.id,slot=slot,cooldown=60})
 end
 news(u,inst,('Bounty posted on the wildcats of %s off %s'):format(siteName(inst),areaName(inst.home)),'posted')
 require('src.notify').post(u,{kind='news',title='Bounty posted',
  text=('%s pays for every wildcat of %s, off %s. It is on the mass driver now.'):format(L.byId[station] and L.byId[station].name or station,siteName(inst),areaName(inst.home)),
  key='bounty:'..inst.id})
 require('src.simulation_history').note(u,'site_bounty',clock,inst.home,{},{site=inst.id,station=station},station)
end
-- A wildcat robbed or killed someone round its planet.
function W.harm(u,r)
 local inst=r and r.wildcat and sites(u)[r.wildcat.site]
 if not inst then return end
 inst.harm=(inst.harm or 0)+1
end

-- A ship died. killer: 'player', an NPC id or nil. Pays a wildcat's bounty
-- to whoever landed the last hit, and counts a wildcat's kill against its
-- site. Returns what the player was owed for it, if anything.
function W.death(u,r,killer)
 if not r then return end
 local k=killer and killer~='player' and u.npcs and u.npcs[killer]
 if k and k.wildcat and not r.wildcat then W.harm(u,k) end
 local inst=r.wildcat and sites(u)[r.wildcat.site]
 if not inst or not inst.bounty or not killer then return end
 local station=inst.bounty.station
 local pay=W.perHead(r)
 inst.bounty.paid=(inst.bounty.paid or 0)+1
 if killer=='player' then
  return require('src.wreck_bounty').payPlayer(u,station,pay,'head')
 end
 if k then
  pay=require('src.accounts').pay(u,station,pay,'bounty')
  k.credits=(k.credits or 0)+pay;k.bountyEarnings=(k.bountyEarnings or 0)+pay
  u.siteBountiesPaid=(u.siteBountiesPaid or 0)+1
 end
end

-- Hunters ----------------------------------------------------------------------

-- The first pocket that still has crew at its posts.
local function frontPocket(u,inst)
 local def=require('src.sites').template(inst)
 for n=1,#def.pockets do
  if W.held(u,fieldId(inst.id,n)) then return n end
 end
end

-- Where a hunter fights from: in among the crew's posts, on the side it
-- came in from, so a pilot who warps in finds the fight already on.
local function assaultSpot(u,inst,n,r)
 local field=fieldId(inst.id,n)
 local f=Fields[field]
 local sx,sy=f and f.spawn[1] or 0,f and f.spawn[2] or 0
 local id=tonumber(tostring(r.id):match('%d+$')) or 0
 local a=id*2.399963
 local crew=W.members(u,field)
 local c=crew[1+id%math.max(1,#crew)]
 if c then
  local gx,gy=c.garrison.x,c.garrison.y
  local dx,dy=sx-gx,sy-gy;local d=math.max(1,math.sqrt(dx*dx+dy*dy))
  return gx+dx/d*1400+math.cos(a)*400,gy+dy/d*1400+math.sin(a)*400
 end
 return sx+math.cos(a)*700,sy+math.sin(a)*700
end
local function enterPocket(u,r,inst,n)
 local x,y=assaultSpot(u,inst,n,r)
 r.assault={site=inst.id,pocket=n,x=x,y=y,since=r.assault and r.assault.since or u.clock or 0}
 r.area=fieldId(inst.id,n);r.state='assault'
 r.route={};r.index=1;r.node=nil;r.transit=nil;r.encounter=nil
 r.pose,r.offset,r.savedOnline,r.docking,r.action=nil,nil,nil,nil,nil
 r.taskStatus='clearing '..siteName(inst)
end
-- At the driver with a site bounty: in through the lane.
function W.beginAssault(u,r)
 local clock=u.clock or 0
 local inst=sites(u)[r.task.site]
 local n=inst and not inst.done and frontPocket(u,inst)
 if not n then Tasks.release(u,r,'site gone',clock);return false end
 enterPocket(u,r,inst,n)
 trace(r,clock,'went into '..inst.id..' pocket '..n)
 return true
end
-- Out of the site and back at its planet's driver, task done or dropped.
function W.endAssault(game,u,r,reason)
 local clock=u.clock or 0
 local inst=sites(u)[r.assault.site]
 local home=inst and inst.home or r.home
 local driver=driverOf(home)
 local online=game and game.alifeOnline and game.alifeOnline[r.id]
 if online then
  require('src.alife').capture(game,online,false)
  if not online.removed then game:remove(online,true) end
  game.alifeOnline[r.id]=nil
 end
 r.assault=nil
 r.area=home;r.node=driver;r.route={driver,driver};r.index=1
 r.state='idle';r.untilTime=clock;r.nextDecisionAt=nil
 r.pose,r.offset,r.savedOnline=nil,nil,nil
 Tasks.release(u,r,reason,clock)
 r.taskWorker=true;r.taskStatus=nil
 trace(r,clock,'came out of the site ('..reason..')')
end

-- The last of the crew is gone.
function W.cleared(game,u,inst,by)
 if inst.done then return end
 local clock=u.clock or 0
 inst.done=true;inst.clearedAt=clock;inst.clearedBy=by
 u.sitesCleared=(u.sitesCleared or 0)+1
 local def=require('src.sites').template(inst)
 for n=1,#def.pockets do inst.pockets[n]=inst.pockets[n] or {};inst.pockets[n].cleared=true end
 if by~='player' then
  -- hunters bring what's left of the hoard back to the station that paid
  local to=inst.bounty and inst.bounty.station or require('src.wreck_bounty').payer(inst.home)
  if to then for id,n in pairs(inst.hoard or {}) do require('src.stockpile').add(u,to,id,n) end end
  inst.hoard={}
 end
 for _,r in ipairs(W.hunters(u,inst.id)) do W.endAssault(game,u,r,'completed') end
 for id,o in pairs(Tasks.state(u).offers) do
  if o.kind=='site_bounty' and o.site==inst.id then Tasks.state(u).offers[id]=nil end
 end
 news(u,inst,(by=='player' and 'Wildcats of %s off %s wiped out by a lone pilot' or 'Bounty hunters clear the wildcats out of %s off %s'):format(siteName(inst),areaName(inst.home)),'cleared')
 require('src.simulation_history').note(u,'site_cleared',clock,inst.home,{},{site=inst.id,by=by},nil)
end

-- An offline wreck inside a site: no wreck record (the pocket keeps its
-- own), but the death is logged and paid like any other.
local function kill(u,r,clock,killer)
 -- it wrecks where it was fighting, in its pocket: the same saved wreck an
 -- offline lane fight leaves (src/encounters.lua), so arriving after the
 -- fight finds the husks you'd have seen if you'd watched it
 local spot=r.garrison or r.assault
 local w
 if spot and spot.x then
  u.alifeWrecks=u.alifeWrecks or {}
  w={id=r.id,label=r.label,area=fieldId(spot.site,spot.pocket),worldPosition={x=spot.x,y=spot.y},
   clock=clock,expires=clock+T.alifeWreckLifetime,ship=copy(r.ship),archetype=r.archetype,aiProfile=r.aiProfile}
  u.alifeWrecks[r.id]=w
 end
 r.state='dead';r.ship.armor=0;r.garrison=nil;r.assault=nil
 trace(r,clock,'destroyed'..(killer and (' by '..killer) or ''))
 local History=require('src.simulation_history')
 History.death(u,r,clock,r.area,killer)
 W.death(u,r,killer)
 if w then w.historyWreckId=History.wreck(u,r,clock,r.area) end
 Tasks.release(u,r,'destroyed',clock)
end

local function roll(fight)
 fight.seed=((fight.seed or 7193)*48271)%2147483647
 return fight.seed/2147483647
end
-- One offline round of a site assault in pocket n.
local function assaultRound(game,u,inst,n,hunters,clock)
 local E=require('src.encounters')
 local field=fieldId(inst.id,n)
 local crew=W.members(u,field)
 local fight=inst.fight or {seed=(#inst.id*7919+math.floor(clock))%2147483647}
 inst.fight=fight
 local dealt={}
 local function hit(a,b) dealt[b]=dealt[b] or {}; local d=E.damage(a,T.offlineCombatTick,roll(fight),b);dealt[b][#dealt[b]+1]={a.id,d} end
 for _,h in ipairs(hunters) do hit(h,crew[1+math.floor(roll(fight)*#crew)%#crew]) end
 for _,c in ipairs(crew) do hit(c,hunters[1+math.floor(roll(fight)*#hunters)%#hunters]) end
 for target,list in pairs(dealt) do
  local total,last=0,nil
  for _,d in ipairs(list) do total=total+d[2];if d[2]>0 then last=d[1] end end
  target.ship.armor=math.max(0,target.ship.armor-total)
  if target.ship.armor<=0 then kill(u,target,clock,last) end
 end
 for _,h in ipairs(hunters) do
  -- out of ammunition, or in there too long: it pulls out while it can
  if alive(h) and (E.profile(h).dps<=0 or clock-(h.assault.since or clock)>=T.hunterAssaultTime) then
   W.endAssault(game,u,h,E.profile(h).dps<=0 and 'out of ammunition' or 'gave up')
  elseif alive(h) and h.ship.armor<=maxArmor(h)*E.breakPoint(h) then
   -- a hunter that breaks pulls out; it doesn't always make it
   if roll(fight)<T.hunterBreakKill then
    kill(u,h,clock,crew[1] and crew[1].id)
   else W.endAssault(game,u,h,'retreated') end
  end
 end
end

-- Hunters into the next pocket, or the site is clear.
local function advanceAssault(game,u,inst,hunters)
 local n=frontPocket(u,inst)
 if not n then W.cleared(game,u,inst,'hunters');return end
 for _,h in ipairs(hunters) do
  local online=game.alifeOnline and game.alifeOnline[h.id]
  if online then
   require('src.alife').capture(game,online,false)
   if not online.removed then game:remove(online,true) end
   game.alifeOnline[h.id]=nil
  end
  enterPocket(u,h,inst,n)
 end
end

-- Sites --------------------------------------------------------------------------

-- Each A-Life tick (src/alife.lua): bounties, fence runs, hunters going
-- in, and the fights inside sites.
function W.tick(game,clock)
 local u=game.universe
 local online=game.alifeOnline or {}
 -- every wildcat site is under bounty from the moment it opens
 for _,inst in pairs(sites(u)) do
  if not inst.bounty and not inst.done and inst.crew then
   local def=require('src.sites').template(inst)
   if def and def.wild then W.postBounty(u,inst) end
  end
 end
 require('src.wreck_bounty').notice(u,clock)
 -- live ships at the end of a road into a site go through the lane
 for id,r in pairs(u.npcs or {}) do
  if alive(r) and r.task and (r.state=='idle' or r.state=='docked') and r.node
   and L.canonical(r.node)==L.canonical(r.task.target or '') then
   local kind=r.task.kind
   if kind=='wildcat_home' or kind=='site_bounty' then
    local e=online[id]
    if e then
     require('src.alife').capture(game,e,false)
     if not e.removed then game:remove(e,true) end
     online[id]=nil
    end
    if kind=='wildcat_home' then W.arrive(u,r) else W.beginAssault(u,r) end
   end
  end
 end
 if clock<(u.siteFightNext or 0) then return end
 u.siteFightNext=clock+T.offlineCombatTick
 for id,inst in pairs(sites(u)) do
  if not inst.done and inst.crew then
   local hunters=W.hunters(u,id)
   -- each pocket with hunters in it fights its own round; hunters in a
   -- pocket that's already beaten move on to the next
   local by,pockets,onward={},{},{}
   for _,h in ipairs(hunters) do
    local n=h.assault.pocket
    if not by[n] then by[n]={};pockets[#pockets+1]=n end
    table.insert(by[n],h)
   end
   table.sort(pockets)
   for _,n in ipairs(pockets) do
    local field=fieldId(id,n)
    if not W.held(u,field) then
     for _,h in ipairs(by[n]) do onward[#onward+1]=h end
    elseif game.fieldId~=field then
     local away={}
     for _,h in ipairs(by[n]) do if not online[h.id] then away[#away+1]=h end end
     if #away>0 and not inst.done then assaultRound(game,u,inst,n,away,clock) end
    end
   end
   if #onward>0 and not inst.done then advanceAssault(game,u,inst,onward) end
   if not inst.done and W.posted(u,id)==0 then
    -- every post is empty (the crew died out, at the hands of hunters,
    -- patrols or you): the site is done
    W.cleared(game,u,inst,game.fieldId and require('src.sites').of(game.fieldId)==id and 'player' or 'attrition')
   end
  end
 end
end

-- Older saves: garrison records from before wildcats, and sites rolled the
-- old way. The records go; the sites close (src/sites.lua restore).
function W.migrate(u)
 for _,r in pairs(u.npcs or {}) do
  if r.garrison and not r.wildcat then r.state='escaped';r.garrison=nil end
 end
end

-- The board ----------------------------------------------------------------------

-- AU between the system a hunter is in (or calls home) and a site's system
local function hunterDistance(r,inst,clock)
 local here=systemOf(r.area or r.home);local there=systemOf(inst.home)
 if not here or not there or here==there then return 0 end
 return Fields.distance(here,there,clock) or math.huge
end

Tasks.register('site_bounty',{
 requires={capabilities={'armed'}},
 eligible=function(u,r,o,node,clock)
  local inst=sites(u)[o.site]
  if not inst or inst.done or not inst.bounty then return false end
  -- hunters go where the bounties are, out to T.hunterRangeAU from where
  -- they are now (their own system's first: score)
  if hunterDistance(r,inst,clock)>T.hunterRangeAU then return false end
  if require('src.encounters').profile(r).dps<=0 then return false end
  return (r.ship.armor or 0)>=maxArmor(r)*T.hunterReadyHealth
 end,
 feasible=function(u,r,o,node,clock) return require('src.travelgraph').live(node,o.target,clock)~=nil end,
 score=function(u,r,o,node,clock)
  local inst=sites(u)[o.site]
  return -(inst and hunterDistance(r,inst,clock) or 0)*10-(o.slot or 0)
 end,
 prepare=function(u,r,t) t.phase='hunting';return true end,
 plan=function(t,node,clock) return require('src.travelgraph').live(node,t.target,clock) end,
 docks=function() return false end,
 stay=function() return 2 end,
 complete=function() return false end,
 continue=function(c)
  local t=c.r.task
  if not sites(c.u)[t.site] or sites(c.u)[t.site].done then Tasks.release(c.u,c.r,'site gone',c.clock);return end
  if L.canonical(c.node)~=L.canonical(t.target) then
   local path=require('src.travelgraph').live(c.node,t.target,c.clock)
   if path and #path>1 then return {route=path} end
  end
  return {wait=2}
 end,
})

-- Bounty hunters: a few armed freelancers per system who live off site
-- bounties, and sweep wrecks when there are none.
local Population=require('src.population')
Population.register('hunter',{
 target=function(f,area)
  return f.alifeSecurity and require('src.npc_access').owner(area) and L.station(area,'trade') and T.huntersPerSystem or 0
 end,
 -- the whole hunter population follows the wildcats alive: about
 -- T.huntersPerWildcat of them, spawned where the system targets allow
 budget=function()
  local u=Population.universe;local n=0
  for _,r in pairs(u and u.npcs or {}) do if r.wildcat and alive(r) then n=n+1 end end
  return math.ceil(n*T.huntersPerWildcat)
 end,
 nodes=function(game,area) return L.stations(area,'trade') end,
 -- counted at home, wherever it is (inside a site, say)
 where=function(r) return r.home end,
 create=function(game,area,node,clock)
  local u=game.universe
  local def=data.npcProfiles.police;local hull=data.hulls[def.hull]
  local loadout=copy(def.loadout or hull.loadout)
  u.nextNpcId=u.nextNpcId+1
  local r={id='npc/'..u.nextNpcId,home=area,area=area,aiProfile='police',spread=0,
   route={node,node},index=1,node=node,state='idle',untilTime=clock,
   ship={hull=def.hull,loadout=loadout,cargo={},armor=Stats.compute(hull,loadout).armor}}
  if game.arrivalShip then r.ship=copy(game.arrivalShip) end
  r.speed=require('src.npc').cruise(r.ship)
  require('src.npc_templates').apply(r,'hunter',area)
  require('src.personality').ensure(r)
  require('src.npc_home').choose(u,r)
  r.taskWorker=true
  -- (no first decision here: the arrival's ship sale is completed after
  -- create returns, and a refit at its first stop could take that lot)
  u.npcs[r.id]=r
  return r
 end,
})

return W
