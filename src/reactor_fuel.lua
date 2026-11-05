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
function F.step(e,s,dt,moving,work)
 if dt<=0 then return 1,0 end
 work=math.max(0,work or 0)
 local passive=math.max(0,s.powerDraw)*dt
 local drive=moving and math.max(1,s.powerNet*(1-T.thrustRecharge))*dt or 0
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
function F.advance(r,clock)
 -- Mining accounts for its continuous drill load in its own work slice.
 if r.role=='miner' and r.task and r.task.phase=='mining' and r.state=='idle' then return end
 local previous=r.fuelClock or clock;r.fuelClock=clock
 if r.state=='dead' or r.state=='escaped' then return end
 local seconds=math.max(0,clock-previous)
 local moving=r.state=='travel' or r.state=='transit' and r.transit and r.transit.kind~='driver'
 if r.state=='docked' then return end -- dockside maintenance, no flight load
 local scale=F.withRecord(r,function(e,s)return F.step(e,s,seconds,moving) end)
 if moving and scale<1 then
  -- Freeze abstract route progress for the time propulsion could not be powered.
  local delay=seconds*(1-scale)
  r.depart=(r.depart or clock)+delay;r.arrive=(r.arrive or clock)+delay
  r.taskStatus='out of reactor fuel'
 end
end
return F
