-- Whole cargo units feed a saved reactor charge. No separate tank inventory.
local T=require('src.tuning')
local Hold=require('src.inventory.hold')
local data=require('src.data')
local Stats=require('src.stats')
local F={}
function F.item() return T.reactorFuelItem end
function F.initialize(ship)
 if ship.fuelInitialized then return end
 ship.fuelInitialized=true
 ship.fuelCharge=ship.fuelCharge or 0
 ship.cargo=ship.cargo or {}
 -- New ships and older saves receive a one-time starter allowance.
 local n=math.max(0,T.reactorFuelStart-(ship.cargo[F.item()] or 0))
 if ship.hold then
  n=Hold.add(ship.hold,F.item(),n)
  ship.cargo=Hold.totals(ship.hold)
 else
  local s=Stats.compute(type(ship.hull)=='table' and ship.hull or data.hulls[ship.hull],ship.loadout)
  local volume=Stats.cargo(ship.cargo)
  n=math.min(n,math.max(0,math.floor((s.hold-volume)/data.items[F.item()].volume)))
  ship.cargo[F.item()]=(ship.cargo[F.item()] or 0)+n
 end
end
function F.remaining(e)
 return (e.fuelCharge or 0)+(e.cargo[F.item()] or 0)*T.reactorFuelEnergy
end
local labels={normal='normal',low='low reactor fuel',empty='fuel empty; capacitor available',stranded='stranded: no reactor fuel or power'}
function F.condition(r,e)
 local ship=e or r.ship
 local stats=e and e.stats or Stats.compute(data.hulls[ship.hull],ship.loadout)
 local fuel=F.remaining(ship)
 local power=e and e.power or r.power or stats.powerCap
 if fuel<=1e-6 then return power<=1e-6 and 'stranded' or 'empty' end
 if fuel<stats.powerOut*T.reactorFuelReserveSeconds*T.npcFuelLow then return 'low' end
 return 'normal'
end
function F.label(r) return r.fuelStatus and labels[r.fuelStatus] end
-- What the ship is doing, for debug views: a fuel emergency outranks any
-- earlier activity text such as a post-combat withdrawal.
function F.activity(r)
 if r.fuelStatus=='stranded' then return 'out of fuel: stranded, waiting for fuel' end
 if r.service then return require('src.upkeep').label(r) end
 if r.fuelStatus=='empty' then return 'out of fuel: running on capacitor' end
 return r.taskStatus
end
function F.needsPropulsion(r)
 return r.state~='docked' and not r.driverState
  and not (r.state=='transit' and r.transit and r.transit.kind=='driver')
end
function F.observe(u,r,clock,e)
 if not r or r.state=='dead' or r.state=='escaped' or e and e.dead then return end
 local status=F.condition(r,e)
 local previous=r.fuelStatus
 -- Pause timed idle duties, too; a fuel stop must not complete a patrol or
 -- discard an assignment simply because its ordinary wait timer elapsed.
 if previous=='stranded' and r.fuelObservedAt and r.state=='idle' and r.untilTime then
  r.untilTime=r.untilTime+math.max(0,clock-r.fuelObservedAt)
 end
 r.fuelObservedAt=clock
 if previous=='stranded' and status~='stranded' and r.role=='miner' then
  r.fuelClock=clock;r.nextMiningAt=clock+T.miningOfflineEvery
 end
 if status=='stranded' and r.role=='miner' then r.fuelClock=clock end
 if status~=previous then
  r.fuelStatus=status;r.fuelStatusSince=clock
  if previous then require('src.alife_trace').note(r,clock,'fuel',previous..' -> '..status..(' (%.0f fuel)'):format(F.remaining(e or r.ship))) end
  if u and (previous or status~='normal') then
   require('src.simulation_history').fuelCondition(u,r,clock,previous or 'normal',status,
    F.remaining(e or r.ship),e and e.power or r.power or 0)
  end
 end
 if e then e.fuelStatus=status end
 -- Clear only the old prototype's fuel-owned activity text, never a duty.
 if r.taskStatus=='out of reactor fuel' then r.taskStatus=nil end
 -- A finished retreat must not linger as the ship's activity.
 if r.taskStatus=='withdrawing after combat' and (r.retreatUntil or 0)<=clock then r.taskStatus=nil end
 return status
end
local function burn(e,need)
 local generated=0
 while need>1e-9 do
  if (e.fuelCharge or 0)<=1e-9 then
   local n=e.cargo[F.item()] or 0
   if n<1 then break end
   if e.hold and Hold.take(e.hold,F.item(),1)~=1 then break end
   e.cargo[F.item()]=n-1
   e.fuelCharge=T.reactorFuelEnergy;e.massDirty=true
  end
  local n=math.min(need,e.fuelCharge)
  e.fuelCharge=e.fuelCharge-n;need=need-n;generated=generated+n
 end
 return generated
end
-- Both physical flight and remote estimates use this energy balance. Idle
-- reactors throttle down at full capacitor; movement creates electrical demand.
-- moving is true/1 for the main drive, a fraction for a lighter load (turning
-- in place); modules' standing draw is scaled by T.idleDrain.
function F.step(e,s,dt,moving,work)
 if dt<=0 then return 1,0 end
 work=math.max(0,work or 0)
 local passive=math.max(0,s.powerDraw)*T.idleDrain*dt
 local load=moving==true and 1 or type(moving)=='number' and moving or 0
 local drive=load>0 and math.max(1,s.powerNet*(1-T.thrustRecharge))*load*dt or 0
 local request=math.min(math.max(0,s.powerOut)*dt,passive+drive+work+math.max(0,s.powerCap-e.power))
 local generated=burn(e,request)
 e.reactorOutput=generated/dt
 local available=math.max(0,e.power+generated-passive)
 local used=math.min(drive,available)
 local delivered=math.min(work,available-used)
 e.power=math.min(s.powerCap,math.max(0,available-used-delivered))
 if drive>0 then return used/drive,delivered end
 return e.power>0 and 1 or 0,delivered
end
function F.withRecord(r,fn)
 local s=r.ship
 local e={hull=s.hull,loadout=s.loadout,cargo=s.cargo or {},
  hold=s.hold and Hold.deserialize(s.hold),fuelCharge=s.fuelCharge,
  fuelInitialized=s.fuelInitialized,power=r.power}
 if e.hold then e.cargo=Hold.totals(e.hold) end
 F.initialize(e)
 local stats=Stats.compute(data.hulls[s.hull],s.loadout)
 e.power=e.power or stats.powerCap
 local result=fn(e,stats)
 s.fuelCharge,s.fuelInitialized=e.fuelCharge,e.fuelInitialized
 s.cargo=e.cargo;if e.hold then s.hold=Hold.serialize(e.hold) end
 r.power=e.power
 return result
end
function F.advance(r,clock,u)
 if r.state=='dead' or r.state=='escaped' then return end
 if not r.ship.fuelInitialized then F.withRecord(r,function() end);r.fuelClock=clock end
 -- Mining accounts for its continuous drill load in its own work slice.
 if r.role=='miner' and r.task and r.task.phase=='mining' and r.state=='idle' then
  return F.observe(u,r,clock)
 end
 local previous=r.fuelClock or clock;r.fuelClock=clock
 local seconds=math.max(0,clock-previous)
 local moving=r.state=='travel' or r.state=='transit' and r.transit and r.transit.kind~='driver'
 if r.state=='docked' then return F.observe(u,r,clock) end -- dockside maintenance, no flight load
 local scale=F.withRecord(r,function(e,s)return F.step(e,s,seconds,moving) end)
 if moving and scale<1 then
  -- Freeze abstract route progress for the time propulsion could not be powered.
  local delay=seconds*(1-scale)
  r.depart=(r.depart or clock)+delay;r.arrive=(r.arrive or clock)+delay
 end
 return F.observe(u,r,clock)
end
return F
