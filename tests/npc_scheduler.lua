-- Planning is staggered; actuation and important state changes stay responsive.
return function()
 local S=require('src.npc_scheduler')
 local r={state='travel',action={kind='travel'}}
 local e={alifeId='npc/1',route={},routeIndex=1,intent={},fuelStatus='normal'}
 local game={universe={clock=0,npcs={['npc/1']=r}}}
 local plans,decisions,controls=0,0,0
 local AI={driveVelocity=function()controls=controls+1 end}
 local function plan()
  plans=plans+1;if e.aiDecision then decisions=decisions+1 end
  e.aiVelocity={x=100,y=0,mx=1,my=0,throttle=1}
 end
 for i=0,119 do game.universe.clock=i/120;S.update(game,e,1/120,AI,plan) end
 assert(plans==2 and decisions==2,'ordinary cruising did not use staggered one-second plans')
 assert(controls==118,'flight control did not continue between plans')
 e.aggressor={};e.lastHitTime=game.universe.clock
 S.update(game,e,1/120,AI,plan)
 assert(plans==3,'new aggression waited for the planning deadline')
 game.universe.clock=game.universe.clock+1/120;e.lastHitTime=game.universe.clock
 S.update(game,e,1/120,AI,plan)
 assert(plans==3,'repeated hits restarted planning every physics tick')
 local g={};e.route={{driver=g}}
 S.update(game,e,1/120,AI,plan);local before=plans
 g.driverShip={}
 S.update(game,e,1/120,AI,plan)
 assert(plans==before+1,'driver occupancy change waited for the planning deadline')
 r.action.completed=true
 S.update(game,e,1/120,AI,function(...)plan(...);r.action=nil end)
 assert(not e.aiNextPlan,'completed action did not open its next decision')
 -- Aim follows an existing target between plans, without another target search.
 e.aggressor=nil;e.route={};r.action=nil
 local tx=100;local target={body={getPosition=function()return tx,0 end,getLinearVelocity=function()return 0,0 end}}
 e.body={getPosition=function()return 0,0 end,getLinearVelocity=function()return 0,0 end,getAngle=function()return 0 end}
 e.def={ai={accuracy=1,range=1000}};e.hull={mount='turret'};e.weapons={};e.combatTarget=target
 S.update(game,e,1/120,AI,function()e.aiAimTarget=target end)
 tx=200;game.universe.clock=game.universe.clock+1/120
 S.update(game,e,1/120,AI,function()error('aim tracking reran planning')end)
 assert(e.intent.aimX==200 and e.intent.firePrimary,'fast actuation lost target tracking or firing')
 print('NPC SCHEDULER: cadence, continuous control and immediate interrupts passed')
end
