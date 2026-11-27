--[[
	Contraband: cartel product (Rep.CONTRABAND) is illegal in the space of
	a power hostile to the cartel (Rep.stance(owner, Rep.CARTEL) ==
	'hostile': the Estates and the Diwan). Ambivalent powers (Jove, Zhuhai)
	look the other way and don't inspect for it.

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

function C.illegal(u,faction,item)
 return Rep.CONTRABAND[item] and faction and Rep.stance(faction,Rep.CARTEL,u)=='hostile' or false
end
function C.inspects(u,faction) return faction and Rep.stance(faction,Rep.CARTEL,u)=='hostile' or false end

-- What a ship carries that faction outlaws: { {id,n}, ... }, units, value.
function C.manifest(u,faction,e)
 local list,n,value={},0,0
 for id,k in pairs(e.cargo or {}) do
  if k>0 and C.illegal(u,faction,id) then
   list[#list+1]={id=id,n=k};n=n+k;value=value+k*(data.items[id].price or 0)
  end
 end
 table.sort(list,function(a,b) return a.id<b.id end)
 return list,n,value
end
function C.describe(list)
 local parts={}
 for _,s in ipairs(list) do parts[#parts+1]=('%d %s'):format(s.n,data.items[s.id].name) end
 return #parts>0 and table.concat(parts,', ') or 'nothing'
end

-- Take the listed goods out of e's hold for good (seized, not ejected).
function C.seize(e,list)
 local Hold=require('src.inventory.hold');local Ship=require('src.ship')
 for _,s in ipairs(list) do
  if e.hold then Hold.take(e.hold,s.id,s.n);e.cargo=Hold.totals(e.hold)
  else e.cargo[s.id]=nil end
 end
 Ship.updateMass(e)
end

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
    if math.random()<T.inspectChance then return C.inspect(game,e,p,faction) end
   end
  end
 end
end

function C.inspect(game,police,ship,faction)
 local u=game.universe
 local list,n,value=C.manifest(u,faction,ship)
 return require('src.comms').open(game,'inspection',police,ship,{
  faction=faction,list=list,units=n,value=value,
  bribe=math.floor(math.max(T.bribeMin,value*T.bribeShare)),
  fine=0,seized='nothing'})
end

return C
