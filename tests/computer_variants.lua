return function(game)
 local data,Ship=require('src.data'),require('src.ship')
 local copy=require('src.persistence').copy
 local p=game.player
 p.hull=copy(p.hull)
 p.hull.slots={{family='primary',size='S'},{family='computer',size='any'}}
 p.loadout={'px2_autogun',false};p.team=1;p.dockState=nil
 p.body:setPosition(0,0);p.body:setAngle(0)
 p.intent.aimX=1000;p.intent.aimY=0
 local checks=0
 local function check(ok,msg) assert(ok,msg);checks=checks+1 end
 local function variant(base)
  local m=copy(data.modules[base]);m.id='test_'..base
  data.modules[m.id]=m;p.loadout[2]=m.id;Ship.refit(p)
  p.navThreat=nil;p.navWarn=0;p.lock=nil
  return m
 end
 local nav=variant('nav_computer')
 game.entities={p}
 local rock=game:spawnAsteroid(500,0,20,'rock');rock.body:setLinearVelocity(0,0)
 p.body:setLinearVelocity(1000,0)
 nav.radarRange=100;nav.lookahead=2;game:updateComputers(.2)
 check(not p.navThreat,'short-range nav saw distant rock')
 nav.radarRange=1000;game:updateComputers(.2)
 check(p.navThreat and p.navThreat.target==rock,'long-range nav did not see rock')
 nav.lookahead=.1;game:updateComputers(.2)
 check(not p.navThreat,'short lookahead warned too early')
 nav.lookahead=1;game:updateComputers(.2)
 check(p.navThreat~=nil,'extended lookahead failed')
 local t={kind='ship',team=2,body=love.physics.newBody(game.world,1000,0,'dynamic'),halfLength=20}
 t.body:setLinearVelocity(0,100)
 game.entities={p,t};p.body:setLinearVelocity(0,0)
 local ord=variant('fire_computer')
 local function pip()
  local circle=love.graphics.circle;local found=false
  love.graphics.circle=function(mode,x,y,r) if mode=='line' and r==9 then found=true end end
  local ok,err=pcall(function()game:drawComputers(1)end)
  love.graphics.circle=circle;assert(ok,err);return found
 end
 ord.radarRange=500;p.lock=t
 check(not pip(),'guidance lock bypassed ordnance range')
 p.lock=nil;ord.radarRange=2000;ord.predictionTime=4
 check(pip(),'ordnance acquisition ignored longer range')
 ord.predictionTime=.01
 check(not pip(),'ordnance ignored prediction horizon')
 ord.predictionTime=4;check(pip(),'longer prediction horizon did not restore solution')
 local guidance=variant('guidance_computer')
 guidance.radarRange=500;game:updateComputers(.2)
 check(not p.lock,'guidance ignored range')
 guidance.radarRange=2000;game:updateComputers(.2)
 check(p.lock==t,'guidance longer range failed')
 local a=math.rad(10);t.body:setPosition(math.cos(a)*1000,math.sin(a)*1000)
 p.lock=nil;guidance.lockCone=5;game:updateComputers(.2)
 check(not p.lock,'narrow guidance cone acquired off-axis target')
 guidance.lockCone=20;game:updateComputers(.2)
 check(p.lock==t,'wide guidance cone did not acquire target')
 guidance.radarRange=500;game:updateComputers(.2)
 check(not p.lock,'existing guidance lock survived range limit')
 local uplink=variant('drone_uplink')
 local drone={kind='ship',team=1,drone=true,owner=p,control=2,body=love.physics.newBody(game.world,800,0,'dynamic')}
 game.entities={p,drone}
 uplink.uplinkRange=500;uplink.controlLimit=2;game:toggleDroneControl()
 check(not game.piloting,'drone piloting ignored range')
 uplink.uplinkRange=1000;uplink.controlLimit=1;game:toggleDroneControl()
 check(not game.piloting,'low-capacity uplink controlled larger drone')
 uplink.controlLimit=2;game:toggleDroneControl()
 check(game.piloting==drone,'eligible drone did not enter direct control')
 uplink.uplinkRange=500;game:updateComputers(.2)
 check(not game.piloting and not drone.piloted,'out-of-range drone retained direct control')
 uplink.uplinkRange=1000;game:toggleDroneControl()
 uplink.controlLimit=1;game:updateComputers(.2)
 check(not game.piloting,'lower-capacity refit retained ineligible drone')
 -- Old mod computers inherit safe defaults when the new fields are absent.
 local old=variant('fire_computer');old.radarRange=nil;old.predictionTime=nil
 game.entities={p,t};t.body:setPosition(1000,0)
 check(pip(),'legacy ordnance computer lost compatibility')
 print(('COMPUTER VARIANT TEST PASSED (%d checks)'):format(checks))
end
