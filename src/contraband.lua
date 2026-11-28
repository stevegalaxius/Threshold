--[[
	Contraband: cartel product (Rep.CONTRABAND) is illegal in the space of
	every power that bans it (T.drugBan: the Estates, the Diwan, Zhuhai and
	Jove). Their stations still buy and sell it (Rep.embargoed exempts it):
	the risk is the patrols on the way in.
	Jove's patrols fly without Deep Scanners (T.policeNoScanner), so they
	inspect by eye. Unowned space (Neptune) has nobody to enforce anything.

	Inspections happen where police already stop: a squad leader holding
	at a stop of its sweep (src/squads.lua, squad_sweep) hails the player
	if they're in range, through comms (src/dialogs/inspection.lua).
	Comply and they scan the hold: contraband found is seized and fined,
	and costs standing. A bribe may work. Running, or ignoring the hail,
	makes the player wanted by that power for a while: its police treat
	them as hostile (src/security.lua S.hostile).

	Saved: u.contraband = { wanted = { [faction] = untilClock } }.
	Not saved: which squad stops have already inspected (Contraband.seen).
]]
local T=require('src.tuning')
local data=require('src.data')
local Rep=require('src.reputation')
local C={seen=setmetatable({},{__mode='k'}),next=0}

function C.state(u)
 u.contraband=u.contraband or {wanted={}}
 u.contraband.wanted=u.contraband.wanted or {}
 return u.contraband
end

-- Does this power ban the drugs? (T.drugBan, or any other power hostile to
-- the cartel; never the cartel itself or unowned space.)
function C.bans(u,faction)
 if not faction or faction==Rep.CARTEL then return false end
 return T.drugBan[faction] or Rep.stance(faction,Rep.CARTEL,u)=='hostile' or false
end
function C.illegal(u,faction,item)
 return Rep.CONTRABAND[item] and C.bans(u,faction) or false
end
function C.inspects(u,faction) return C.bans(u,faction) end

-- Everything in a hold by item, with what's packed in containers carried
-- in it counted separately: open[id], packed[id]. A ship with no grid hold
-- has only e.cargo (all open).
function C.contents(e)
 local open,packed={},{}
 local function walk(h,into)
  for _,g in ipairs(h.grids) do
   for _,st in ipairs(g.stacks) do
    if st.inner then walk(st.inner,packed) end
    into[st.id]=(into[st.id] or 0)+st.n
   end
  end
 end
 if e.hold then walk(e.hold,open)
 else for id,k in pairs(e.cargo or {}) do open[id]=k end end
 return open,packed
end

-- What a ship carries that faction outlaws: { {id,n,packed}, ... }, units,
-- value. deep: also what's packed inside containers (a Deep Scanner sees it;
-- a look without one doesn't).
function C.manifest(u,faction,e,deep)
 local list,n,value={},0,0
 local open,packed=C.contents(e)
 local function add(t,isPacked)
  for id,k in pairs(t) do
   if k>0 and C.illegal(u,faction,id) then
    list[#list+1]={id=id,n=k,packed=isPacked or nil};n=n+k;value=value+k*(data.items[id].price or 0)
   end
  end
 end
 add(open)
 if deep~=false then add(packed,true) end
 table.sort(list,function(a,b) if a.id~=b.id then return a.id<b.id end return not a.packed and b.packed end)
 return list,n,value
end
function C.describe(list)
 local count,order={},{}
 for _,s in ipairs(list) do
  if not count[s.id] then order[#order+1]=s.id end
  count[s.id]=(count[s.id] or 0)+s.n
 end
 local parts={}
 for _,id in ipairs(order) do parts[#parts+1]=('%d %s'):format(count[id],data.items[id].name) end
 return #parts>0 and table.concat(parts,', ') or 'nothing'
end

-- Take the listed goods out of e's hold for good (seized, not ejected),
-- from containers in it too.
local function takeDeep(h,id,n)
 local Hold=require('src.inventory.hold')
 local got=Hold.take(h,id,n)
 for _,g in ipairs(h.grids) do
  for _,st in ipairs(g.stacks) do
   if got>=n then return got end
   if st.inner then got=got+takeDeep(st.inner,id,n-got) end
  end
 end
 return got
end
function C.seize(e,list)
 local Hold=require('src.inventory.hold');local Ship=require('src.ship')
 for _,s in ipairs(list) do
  if e.hold then takeDeep(e.hold,s.id,s.n)
  else e.cargo[s.id]=nil end
 end
 if e.hold then e.cargo=Hold.totals(e.hold) end
 e.massDirty=true
 if e.body then Ship.updateMass(e) end
end

-- The Deep Scanner a ship carries (data/modules.lua, computer 'scanner'):
-- it reads ship holds as well as wrecks and containers.
function C.scanner(game,e) return game:computer(e,'scanner') end

-- Wanted: that power's police shoot on sight until it lapses.
function C.wanted(u,faction)
 local t=faction and C.state(u).wanted[faction]
 return t and (u.clock or 0)<t or false
end
function C.flag(u,faction)
 local s=C.state(u)
 s.wanted[faction]=math.max(s.wanted[faction] or 0,(u.clock or 0)+T.wantedTime)
end
function C.prune(u)
 local s=u.contraband;if not s then return end
 for f,t in pairs(s.wanted) do if (u.clock or 0)>=t then s.wanted[f]=nil end end
end

-- Pay what you can; returns what was paid.
function C.charge(u,amount)
 local paid=math.max(0,math.min(u.credits or 0,math.floor(amount)))
 u.credits=(u.credits or 0)-paid
 return paid
end

-- A police ship holding at a sweep stop, and the power it answers to.
local function inspector(game,e)
 if e.dead or e.removed or e.dockState or not e.alifeId then return end
 local r=game.universe.npcs[e.alifeId]
 if not r or r.state~='idle' or not r.task or r.task.kind~='squad_sweep' then return end
 local grant=require('src.npc_access').policeGrant(r,game.fieldId)
 if not grant or not C.inspects(game.universe,grant.issuer) then return end
 return r,grant.issuer
end

-- Can the player be stopped right now? Never mid-dock, in a lane or on a
-- driver, and not while another conversation is open.
local function stoppable(game,p)
 return p and not p.dead and not p.removed and not p.dockState and not p.launch and not p.driverTractor
  and not p.cruise and not game.flight and not game.sideScene and game.state~='docked' and not p.comms
end

function C.update(game)
 if game.time<C.next then return end
 C.next=game.time+1
 local u=game.universe
 C.prune(u)
 local p=game.player
 if not stoppable(game,p) then return end
 local px,py=p.body:getPosition()
 for id,e in pairs(game.alifeOnline or {}) do
  local r,faction=inspector(game,e)
  if r and C.seen[r.task]==nil and not C.wanted(u,faction) then
   local x,y=e.body:getPosition()
   if (x-px)^2+(y-py)^2<T.inspectRange^2 then
    C.seen[r.task]=true
    -- a station here burning through an outlawed drug has its police
    -- looking harder (src/crisis.lua heat)
    local chance=math.min(T.inspectChanceMax,T.inspectChance+T.crisisInspectBoost*require('src.crisis').heat(u,game.fieldId))
    if math.random()<chance then return C.inspect(game,e,p,faction) end
   end
  end
 end
end

-- Police scoop a dumped stack up: it leaves space for good.
function C.scoop(game,pickup)
 if not pickup or pickup.count<=0 then return end
 pickup.count=0
 for i,k in ipairs(game.pickups or {}) do if k==pickup then table.remove(game.pickups,i);break end end
 if pickup.looseId then
  require('src.loose').remove(game.universe,pickup.looseId)
  if game.miningLive then game.miningLive[pickup.looseId]=nil end
 end
end

-- Contraband dumped while police are inspecting you counts as found: they
-- note it (ch.v.dumped) and pull it in. The scan's result fines it like
-- anything still aboard.
-- A dumped container: the patrol takes the whole box.
function C.scoopBox(game,box)
 for i,e in ipairs(game.entities) do if e==box then table.remove(game.entities,i);break end end
 if box.body and not box.body:isDestroyed() then box.body:destroy() end
 box.removed=true
end
local function noteDump(ch,id,n)
 local v=ch.v
 v.dumped=v.dumped or {}
 v.dumped[#v.dumped+1]={id=id,n=n}
 v.dumpedValue=(v.dumpedValue or 0)+n*(data.items[id].price or 0)
end
require('src.events').on('eject',function(e,id,count,pickup,boxes)
 local ch=e.comms
 if not ch or ch.closed or ch.scriptId~='inspection' or ch.listener~=e then return end
 local u=ch.game.universe
 if boxes then
  -- containers: what's packed inside them, the same as if loose
  local any
  for _,box in ipairs(boxes) do
   local found=false
   for inner,k in pairs(require('src.inventory.hold').totals(box.hold)) do
    if C.illegal(u,ch.v.faction,inner) then noteDump(ch,inner,k);found=true end
   end
   -- packed containers inside the box
   local _,packed=C.contents({hold=box.hold})
   for inner,k in pairs(packed) do
    if C.illegal(u,ch.v.faction,inner) then noteDump(ch,inner,k);found=true end
   end
   if found then C.scoopBox(ch.game,box);any=true end
  end
  if any and e.isPlayer then ch.game:toast('PATROL SEIZED THE DUMPED CONTAINER',2) end
  return
 end
 if not C.illegal(u,ch.v.faction,id) then return end
 noteDump(ch,id,count)
 C.scoop(ch.game,pickup)
 if e.isPlayer then ch.game:toast(('PATROL SEIZED THE DUMPED %s'):format(data.items[id].name:upper()),2) end
end)

-- Is the inspected ship still where the police can scan it?
function C.inRange(ch)
 local a,b=ch.speaker,ch.listener
 if not a.body or not b.body then return true end
 local x1,y1=a.body:getPosition();local x2,y2=b.body:getPosition()
 return (x1-x2)^2+(y1-y2)^2<T.inspectLeash^2
end

-- How a patrol looks: with a Deep Scanner it reads the hold (and into
-- containers when the scanner has depth) in its scanTime; without one it's
-- a slower, patchier look by eye that misses packed containers.
function C.method(game,police)
 local sc=C.scanner(game,police)
 if sc then return {deep=sc.depth==true,time=sc.scanTime or T.inspectScanTime,detect=T.inspectDetect,scanner=true} end
 return {deep=false,time=T.inspectScanTime*2,detect=T.inspectDetectByEye,scanner=false}
end

function C.inspect(game,police,ship,faction)
 local u=game.universe
 local how=C.method(game,police)
 local list,n,value=C.manifest(u,faction,ship,how.deep)
 return require('src.comms').open(game,'inspection',police,ship,{
  faction=faction,list=list,units=n,value=value,deep=how.deep,scanTime=how.time,detect=how.detect,scanner=how.scanner,
  bribe=math.floor(math.max(T.bribeMin,value*T.bribeShare)),
  fine=0,seized='nothing'})
end

return C
