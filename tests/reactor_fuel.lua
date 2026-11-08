return function(game)
 local Fuel,Ship,Hold=require('src.reactor_fuel'),require('src.ship'),require('src.inventory.hold')
 local Save,T,A=require('src.save'),require('src.tuning'),require('src.alife')
 local Supplies,L=require('src.supplies'),require('src.locations')
 local copy=require('src.persistence').copy
 local checks=0
 local function check(ok,msg) assert(ok,msg);checks=checks+1 end
 local function near(a,b) return math.abs(a-b)<1e-6 end
 local item=Fuel.item();local unit=T.reactorFuelEnergy
 local s={powerOut=20,powerDraw=0,powerCap=100,powerNet=20}
 local e={cargo={[item]=2},fuelInitialized=true,fuelCharge=0,power=100}
 Fuel.step(e,s,10,false)
 check(e.cargo[item]==2 and e.fuelCharge==0,'full idle capacitor consumed a fuel item')
 e.power=0;Fuel.step(e,s,1,false)
 check(e.cargo[item]==1 and near(e.fuelCharge,unit-20) and near(e.power,20),'fuel did not generate actual requested energy')
 e.power=100;local remaining=Fuel.remaining(e)
 Fuel.step(e,s,1,true)
 check(Fuel.remaining(e)<remaining and e.power<=100,'propulsion did not demand reactor energy')
 e.cargo[item]=0;e.fuelCharge=7;e.power=0
 Fuel.step(e,s,1,false)
 check(near(e.power,7) and near(e.fuelCharge,0),'partial last unit was lost or produced free energy')
 e.power=0;Fuel.step(e,s,20,true)
 check(e.power==0 and e.fuelCharge==0,'empty reactor generated power')
 local battery={cargo={},fuelCharge=0,power=10}
 Fuel.step(battery,{powerOut=0,powerDraw=0,powerCap=10,powerNet=0},1,true)
 check(battery.power<10,'propulsion without reactor output used no capacitor energy')
 -- A large work slice may cross units, but must conserve their total energy.
 e={cargo={[item]=2},fuelCharge=10,power=0}
 local bulk={powerOut=1e6,powerDraw=0,powerCap=0,powerNet=1e6}
 local _,delivered=Fuel.step(e,bulk,1,false,2*unit+100)
 check(near(delivered,2*unit+10) and e.cargo[item]==0 and e.fuelCharge==0,'cross-unit work overran available fuel')
 local grid=Hold.new({{name='fuel fixture',w=2,h=2}})
 assert(Hold.add(grid,item,2)==2)
 e={cargo=Hold.totals(grid),hold=grid,fuelCharge=0,power=0}
 Fuel.step(e,s,1,false)
 check(Hold.count(grid,item)==1 and e.cargo[item]==1,'reactor inventory and grid diverged')
 e.cargo[item]=0;Hold.take(grid,item,1);e.power=0
 local before=e.fuelCharge;Fuel.step(e,s,1,false)
 check(near(e.fuelCharge,before-20),'removing spares extinguished the active unit')
 -- Real force application: capacitor can supply thrust, but a dead power system cannot.
 local physics=love.physics.newWorld()
 local probe=Ship.new({world=physics,nextId=function()return 1 end},{hull=game.player.hull.id,
  loadout=game.player.loadout,cargo={},fuelInitialized=true,fuelCharge=0,power=0,grid=true})
 probe.intent=Ship.emptyIntent();probe.intent.thrust=1;probe.intent.aimX=100;probe.intent.aimY=0
 Ship.fly(probe,1/120);physics:update(1/120)
 local vx,vy=probe.body:getLinearVelocity()
 check(vx==0 and vy==0 and probe.body:getAngularVelocity()==0,'empty fuel and capacitor still powered propulsion')
 probe.power=probe.stats.powerCap;Ship.fly(probe,1/120);physics:update(1/120)
 vx,vy=probe.body:getLinearVelocity()
 check(vx*vx+vy*vy>0 and probe.power<probe.stats.powerCap,'capacitor could not power flight after fuel ran out')
 physics:destroy()
 local p=game.player
 p.cargo[item]=0;Hold.sync(p.hold,p.cargo)
 -- Ship records, replacement, save/load, and parked ships keep partial charge.
 p.fuelCharge=321.25;p.power=17
 local rec=Ship.record(p)
 p=game:spawnPlayer(rec)
 check(near(p.fuelCharge,321.25) and near(p.power,17) and (p.cargo[item] or 0)==0,'ship replacement refueled or reset the capacitor')
 local station=game:locationEntity(L.stations(game.fieldId)[1])
 local hangar=game:hangar(station)
 hangar[#hangar+1]=Ship.record(p)
 local snapshot=assert(Save.decode(Save.encode(game:saveState())))
 game:loadState(snapshot);p=game.player
 check(near(p.fuelCharge,321.25) and near(p.power,17),'player save/load lost partial fuel or capacitor')
 local parked=game:hangar(game:locationEntity(station.locationId))
 check(near(parked[#parked].fuelCharge,321.25),'hangar save/load lost active fuel charge')
 -- The same burn function applies to remote records and survives materialization.
 local r
 for _,record in pairs(game.universe.npcs) do if record.role=='trader' and record.area==game.fieldId and record.state~='dead' then r=record;break end end
 assert(r,'no local NPC fixture')
 game:captureALife(true)
 r.ship.cargo={[item]=1};r.ship.hold=nil;r.ship.fuelCharge=0;r.ship.fuelInitialized=true;r.power=0
 Fuel.withRecord(r,function(actor,stats) Fuel.step(actor,stats,1,true) end)
 local fuel,power=r.ship.fuelCharge,r.power
 check(fuel>0 and r.ship.cargo[item]==0,'offline reactor did not consume inventory fuel')
 local live=A.wake(game,r)
 check(near(live.fuelCharge,fuel) and near(live.power,power),'materialization refueled the NPC')
 A.capture(game,live,false)
 check(near(r.ship.fuelCharge,fuel) and near(r.power,power),'body capture lost active fuel')
 local stranded=copy(r);stranded.state='travel';stranded.depart=0;stranded.arrive=100;stranded.fuelClock=10
 stranded.ship.cargo={};stranded.ship.hold=nil;stranded.ship.fuelCharge=0;stranded.power=0
 Fuel.advance(stranded,15)
 check(stranded.depart==5 and stranded.arrive==105 and stranded.fuelStatus=='stranded','empty offline ship continued abstract travel')
 local refill=copy(stranded);local node=L.stations('earth','trade')[1]
 local Stock=require('src.stockpile')
 local had=Stock.count(game.universe,node,item);if had>0 then Stock.take(game.universe,node,item,had) end
 Stock.add(game.universe,node,item,10)
 Supplies.refill(refill,node,game.universe)
 local got=refill.ship.cargo[item] or 0
 check(got>0,'NPC dockside supplies omitted reactor fuel')
 check(Stock.count(game.universe,node,item)==10-got,'dockside fuel did not come out of station stock')
 -- an empty station still gives a dry NPC enough to move on
 local dry=copy(stranded);Stock.take(game.universe,node,item,Stock.count(game.universe,node,item))
 Supplies.refill(dry,node,game.universe)
 check((dry.ship.cargo[item] or 0)>0,'empty station stranded a dry NPC')
 Stock.add(game.universe,node,item,80)
 -- Initial fuel is a one-time migration, never a reward for going online again.
 local old={hull=rec.hull,loadout=rec.loadout,cargo={}}
 Fuel.initialize(old);old.cargo[item]=0;old.fuelCharge=0;Fuel.initialize(old)
 check(old.cargo[item]==0,'initialization repeatedly refueled an empty ship')
 require('src.hud').draw(game,0,0,false)
 require('tests.npc_fuel')(game)
 print(('REACTOR FUEL TEST PASSED (%d checks)'):format(checks))
end
