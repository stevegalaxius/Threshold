return function(game)
 local Ship,T,Engine=require('src.ship'),require('src.tuning'),require('src.engine_visual')
 local checks=0
 local function check(ok,msg)assert(ok,msg);checks=checks+1 end
 local function near(a,b)return math.abs(a-b)<.001 end
 local physics=love.physics.newWorld(0,0,true)
 local context={world=physics,nextId=function()return 0 end}
 local e=Ship.new(context,{hull='halcyon_wisp',x=100000,y=100000})
 local reserve=e.stats.powerCap*T.boostRelight
 e.intent.boost=true;e.intent.aimX=101000;e.intent.aimY=100000
 local entered=false
 for _=1,120*30 do
  Ship.fly(e,1/120);physics:update(1/120)
  check(e.power>=reserve-.001,'held afterburner drained below the reserve floor')
  if e.burnerLocked then entered=true end
  if entered then check(e.burnerLocked and near(e.power,reserve),'held boost cycled out of reserve') end
 end
 check(entered,'afterburner never entered reserve')
 -- Releasing the button allows recharge and rearms full boost.
 e.intent.boost=false;Ship.fly(e,1/120);physics:update(1/120)
 check(e.power>reserve and not e.burnerLocked,'release failed to recharge and rearm')
 for _=1,120*10 do Ship.fly(e,1/120);physics:update(1/120) end
 check(near(e.power,e.stats.powerCap),'released capacitor did not recharge fully')
 e.intent.boost=true;Ship.fly(e,1/120);physics:update(1/120)
 check(not e.burnerLocked and e.power<e.stats.powerCap,'rearmed full boost did not consume charge')
 -- Weapons or a power deficit can still spend the protected charge.
 e.power=reserve/2;e.burnerLocked=true
 Ship.fly(e,1/120);physics:update(1/120)
 check(e.power<reserve and e.power>reserve/2,'reserve mode created charge or prevented reactor recovery')
 e.power=reserve;e.stats.powerNet=-10
 Ship.fly(e,1/120);physics:update(1/120)
 check(e.power<reserve,'reserve mode hid a passive power deficit')
 -- Even a large simulation interval cannot overspend boost reserve.
 e.stats.powerNet=0;e.power=reserve+.01;e.burnerLocked=false
 Ship.fly(e,1);physics:update(1/120)
 check(near(e.power,reserve) and e.burnerLocked,'boost crossed the floor during a large step')
 -- Flame sizing tracks actual boost mode for every engine hardpoint.
 local nozzle=Engine.emitters(e)[1]
 e.afterburn=false;local normalLevel=Engine.boostLevel(e)
 e.afterburn=true;e.burnerLocked=true;local reserveLevel=Engine.boostLevel(e)
 e.burnerLocked=false;local fullLevel=Engine.boostLevel(e)
 local _,_,_,normal=Engine.geometry(nozzle,1,normalLevel,0)
 local _,_,_,reduced=Engine.geometry(nozzle,1,reserveLevel,0)
 local _,_,_,full=Engine.geometry(nozzle,1,fullLevel,0)
 check(normal<reduced and reduced<full,'reserve and full boost flames have the same size')
 check(near((reduced-normal)/(full-normal),T.boostReserve),'reserve flame does not track extra thrust fraction')
 local _,_,_,glow=Engine.geometry(nozzle,1,reserveLevel,0,true)
 check(near(glow,reduced*1.3),'reserve exhaust damage bounds differ from visible glow')
 local old=T.boostReserve;T.boostReserve=0;e.burnerLocked=true
 check(Engine.boostLevel(e)==0,'zero extra reserve thrust still displayed boosted flames')
 T.boostReserve=old
 -- Compare actual forces: reserve accelerates harder than normal, less than full boost.
 local function velocity(boost,locked,power)
  e.stats.powerNet=0;e.spool=1;e.burnerLocked=locked;e.power=power
  e.intent.boost=boost;e.intent.thrust=1;e.intent.strafe=0
  e.body:setAngle(0);e.body:setLinearVelocity(0,0)
  Ship.fly(e,1/120);physics:update(1/120)
  return e.body:getLinearVelocity()
 end
 local v0=velocity(false,false,e.stats.powerCap)
 local vr=velocity(true,true,reserve)
 local vf=velocity(true,false,e.stats.powerCap)
 check(v0<vr and vr<vf,'reserve flame sizes do not correspond to actual thrust')
 physics:destroy()
 print(('AFTERBURNER TEST PASSED (%d checks)'):format(checks))
end
