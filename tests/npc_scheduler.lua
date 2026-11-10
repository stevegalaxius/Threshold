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
 -- Physical flight between one-second plans must retain forward route aim.
 local Ship=require('src.ship');local flightAI=require('src.ai');local data=require('src.data')
 for _,turning in ipairs({false,true}) do
  local hull
  for _,candidate in pairs(data.hulls) do
   local stats=require('src.stats').compute(candidate,candidate.loadout)
   if (candidate.helm=='turn')==turning and stats.thrust>0 then hull=candidate;break end
  end
  assert(hull,'missing navigation fixture hull')
  local scene={world=love.physics.newWorld(0,0,true),universe={clock=0,npcs={}},nextId=function()return 1 end}
  local actor=Ship.new(scene,{hull=hull,angle=turning and math.pi or 0})
  actor.def={ai={throttle=.8}}
  if not turning then actor.body:setLinearVelocity(700,0) end
  local function route()
   flightAI.driveVelocity(actor,900,0,1,0,.8)
   if not turning then actor.intent.aimX,actor.intent.aimY=actor.routeAimX,actor.routeAimY end
  end
  if turning then
   route();assert(actor.intent.thrust==0,'ship accelerated backwards instead of turning toward its route')
  end
  local worst=1
  for i=1,1920 do
   scene.universe.clock=i/120
   S.update(scene,actor,1/120,flightAI,route)
   Ship.fly(actor,1/120);scene.world:update(1/120)
   if not turning or i>1440 then worst=math.min(worst,math.cos(actor.body:getAngle())) end
  end
  assert(worst>.98,'ship turned backwards or rocked between scheduled route plans')
  assert(actor.body:getX()>0,'ship did not make forward route progress')
  scene.world:destroy()
 end
 print('NPC SCHEDULER: cadence, continuous control and immediate interrupts passed')
end
