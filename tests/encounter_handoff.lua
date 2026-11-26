return function()
 local Game,Ship=require('src.game'),require('src.ship')
 local A,E=require('src.alife'),require('src.encounters')
 local Security,Squads=require('src.security'),require('src.squads')
 local data,T=require('src.data'),require('src.tuning')
 local H=require('src.simulation_history')
 local Aggression=require('src.aggression')
 local game=Game.new({preview=true})
 game.world:destroy()
 game.world=love.physics.newWorld()
 game.entities,game.alifeOnline,game.projectiles={},{},{}
 game.fieldId='earth'
 local u=game.universe
 u.npcs={};u.clock=100;u.encounterNext=nil;u.simulationHistory=nil
 local ammo=data.ammoFor(data.modules.gun_s_base)
 local node='earth/trade_buoy_a'
 local function record(id,faction,guard)
  local loadout=require('src.persistence').copy(data.hulls.intaki_wisp.loadout)
  loadout[1]=false
  local e=Ship.new(game,{hull='intaki_wisp',loadout=loadout,cargo={[ammo]=120}})
  local ship=Ship.record(e);e.body:destroy()
  ship.fuelCharge=T.reactorFuelEnergy;ship.fuelInitialized=true
  local r={id=id,ship=ship,affiliation=faction,area='earth',state='idle',node=node,
   route={node,node},index=1,speed=600,untilTime=math.huge,taskStatus='patrolling',fuelClock=u.clock}
  if guard then r.authorizations={{kind='police',issuer='estates',jurisdiction='earth'}} end
  u.npcs[id]=r
  return r
 end
 local patrol=record('npc/9001','estates',true)
 local courier=record('npc/9002','milliways')
 E.update(game,u.clock)
 assert(patrol.encounter and patrol.encounter.target==courier.id, 'offline patrol missed a hostile crew at its node')
 local battle=H.state(u).fights[patrol.id..'|'..courier.id].id
 u.clock=u.clock+T.offlineCombatTick
 E.update(game,u.clock)
 assert(patrol.encounter.round==1 and courier.ship.armor<120 and patrol.ship.cargo[ammo]<120,
  'offline round did not spend ammunition and apply damage')
 local sharedIncident=Aggression.find(u,patrol.id,courier.id,'earth',u.clock)
 assert(sharedIncident and sharedIncident.cause=='combat','offline damage did not record an incident')
 local armor,stock=courier.ship.armor,patrol.ship.cargo[ammo]
 local x,y=A.point(patrol,u.clock)
 local observer=Ship.new(game,{hull='intaki_wisp',x=x,y=y+800,grid=true})
 observer.isPlayer=true;game.player=observer
 game.entities[#game.entities+1]=observer
 game:alifeVisit(patrol.id,patrol,u.clock,x,y+800,false,true)
 assert(game.alifeOnline[patrol.id] and not game.alifeOnline[courier.id], 'test did not wake just the first ship')
 E.syncOnline(game)
 local p,c=game.alifeOnline[patrol.id],game.alifeOnline[courier.id]
 assert(p.combatTarget==c and c.combatTarget==p, 'visible encounter did not wake both sides in combat')
 assert(c.armor==armor and p.cargo[ammo]==stock, 'waking restored armor or ammunition')
 local px,py=p.body:getPosition()
 local cx,cy=c.body:getPosition()
 assert((px-cx)^2+(py-cy)^2>(p.halfLength+c.halfLength)^2, 'waking put both ships on top of each other')
 game:damage(c,3,p,'laser')
 assert(Aggression.find(u,patrol.id,courier.id,'earth',u.clock)==sharedIncident and sharedIncident.cause=='laser',
  'live damage did not update the same incident')
 local liveArmor=c.armor
 p.power=p.power*.4
 p.cargo[ammo]=p.cargo[ammo]-3
 p.fuelCharge=p.fuelCharge*.8
 local livePower,liveStock,liveFuel=p.power,p.cargo[ammo],p.fuelCharge
 local escort=record('npc/9000','estates',true)
 escort.ship.loadout[2]=false
 local helper=A.wake(game,escort)
 helper.combatTarget=c
 -- Fly past both ships and let the normal range-based unload take over.
 observer.body:setPosition(x+T.alifeFar*2,y)
 game.alifeStage=5
 game:alifeChore(u.clock,true)
 assert(not game.alifeOnline[patrol.id] and patrol.encounter.round==1 and courier.ship.armor==liveArmor
  and patrol.power==livePower and patrol.ship.cargo[ammo]==liveStock and patrol.ship.fuelCharge==liveFuel,'unload did not capture the current fight and ship state')
 assert(escort.encounter and escort.encounter.support and escort.encounter.target==courier.id,
  'unload dropped the supporting ship')
 assert(H.state(u).fights[patrol.id..'|'..courier.id].id==battle, 'unload created a second history event')
 u.clock=u.clock+T.offlineCombatTick
 E.update(game,u.clock)
 assert(courier.ship.armor<liveArmor and patrol.ship.cargo[ammo]<liveStock and patrol.encounter.round==2,
  'fight did not continue offline')
 local lost=courier.ship.armor
 A.wake(game,courier);E.syncOnline(game)
 assert(game.alifeOnline[courier.id].armor==lost and game.alifeOnline[patrol.id].combatTarget==game.alifeOnline[courier.id],
  'second wake did not continue the same fight')
 assert(game.alifeOnline[escort.id].combatTarget==game.alifeOnline[courier.id],
  'wake dropped the supporting ship')

 game:captureALife(true)
 u.npcs={}
 local primary=record('npc/9003',nil)
 local raider=record('npc/9004',nil)
 raider.wildcat={site='test'};raider.task={kind='raid'}
 local bounty={station='station:earth_3'}
 require('src.sites').list(u).test={bounty=bounty}
 local backup=record('npc/9005','estates',true)
 local group=Squads.ensureGroup(u,'police','earth','estates')
 local q={id='squad/test',goal='patrol',leader=backup.id,members={backup.id}}
 group.squads={q.id};u.squads.squads[q.id]=q
 backup.squad=q.id
 local entry=Aggression.record(u,raider.id,primary.id,primary.area,u.clock,'raid',node)
 Security.reportRaid(game,raider,primary,entry)
 assert(q.goal=='respond' and q.respond.node==node,'civilian raid did not dispatch a squad')
 assert(Security.reportedRaid(u,raider,primary,'earth',u.clock),'raid report lost its victim')
 assert(not Security.reportedRaid(u,raider,backup,'earth',u.clock),'raid report applied to an unrelated ship')
 raider.task={kind='wildcat_home'}
 assert(not Security.intercepts(u,backup,raider,'earth'),'a past raid authorized a new interception')
 local observerPatrol={kind='ship',alifeRecord=backup}
 local suspect={kind='ship',alifeRecord=raider,aggressedAt=game.time}
 local victim={kind='ship',alifeRecord=primary}
 suspect.aiFightTarget=victim
 assert(Security.hostile(game,observerPatrol,suspect),'patrol ignored the attack still in progress')
 suspect.aiFightTarget=nil
 raider.task={kind='raid'}
 assert(not Security.hostile(game,observerPatrol,suspect),'patrol chased a wildcat after combat ended')
 raider.task={kind='wildcat_home'}
 u.clock=u.clock+T.offlineCombatTick
 E.update(game,u.clock)
 assert(not backup.encounter and not raider.encounter,'offline patrol hunted after a raid ended')
 E.begin(primary,raider,u.clock)
 local damage=E.damage
 E.damage=function(source) return source==backup and 1000 or 0 end
 local ok,err=pcall(function()
  u.clock=u.clock+T.offlineCombatTick
  E.update(game,u.clock)
  assert(backup.encounter and backup.encounter.support and backup.encounter.target==raider.id,
   'offline patrol ignored a confirmed attack still in progress')
  u.clock=u.clock+T.offlineCombatTick
  E.update(game,u.clock)
 end)
 E.damage=damage
 assert(ok,err)
 assert(raider.state=='dead' and raider.deathKiller==backup.id, 'offline support kill credited the wrong ship')
 assert(bounty.paid==1 and backup.bountyEarnings and backup.bountyEarnings>0 and not primary.bountyEarnings,
  'wildcat bounty was not paid to the supporting patrol')
 local drone={kind='ship',drone=true,owner={kind='ship',alifeId=backup.id}}
 assert(H.entityId(drone)==backup.id, 'live drone kill lost its owner')
 u.npcs={}
 local overdueA=record('npc/9010',nil)
 local overdueB=record('npc/9011',nil)
 E.begin(overdueA,overdueB,u.clock)
 local started=u.clock
 u.clock=started+T.offlineCombatTick*3
 E.damage=function() return 1 end
 local stepped,stepError=pcall(E.update,game,u.clock)
 E.damage=damage
 assert(stepped,stepError)
 assert(overdueA.encounter.round==3 and overdueA.ship.armor==117
  and overdueA.encounter.nextAt==started+T.offlineCombatTick*4,
  'clock jump skipped pending combat rounds')
 game.world:destroy()
 print('ok  encounter handoff: offline patrol, live wake, unload, damage and ammo, raid pursuit, dispatch and kill credit')
end
