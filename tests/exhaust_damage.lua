return function(game)
 local Exhaust=require('src.exhaust_damage')
 local data=require('src.data')
 local module=require('src.persistence').copy(data.modules.flit_engine)
 module.id='test_damage_engine';module.exhaust.width=3;module.exhaust.length=18
 data.modules[module.id]=module
 local checks=0
 local function check(ok,msg) assert(ok,msg);checks=checks+1 end
 local world=love.physics.newWorld(0,0,true)
 local source={kind='ship',hull={slots={{family='engine',x=0,y=-8},{family='engine',x=0,y=8}}},
  loadout={'test_damage_engine','test_damage_engine'},mainBurn=1,body=love.physics.newBody(world,0,0,'dynamic'),
  team=1,armor=100,tailX=0}
 local own=love.physics.newFixture(source.body,love.physics.newCircleShape(2))
 own:setUserData(source)
 local sim=setmetatable({world=world,entities={source},time=1},{__index=game})
 local function target(x,y,r,polygon)
  local t={kind='container',hp=1000,body=love.physics.newBody(world,x,y,'static')}
  local shape=polygon and love.physics.newRectangleShape(8,24) or love.physics.newCircleShape(r or .5)
  love.physics.newFixture(t.body,shape):setUserData(t)
  sim.entities[#sim.entities+1]=t
  return t
 end
 local top=target(-7,-8)
 local bottom=target(-7,8)
 local front=target(5,-8)
 local outside=target(-17,-10)
 local spanning=target(-7,0,1,true)
 -- Multiple fixtures on one entity must not multiply one engine's damage.
 love.physics.newFixture(spanning.body,love.physics.newRectangleShape(7,23)):setUserData(spanning)
 local grazing=target(-5,-4,3)
 local distant=target(-30,-8)
 Exhaust.update(sim,1)
 check(top.hp==970 and bottom.hp==970,'one of the two engine plumes does not damage')
 check(front.hp==1000,'exhaust damaged an object ahead of the nozzle')
 check(outside.hp==1000,'bounding-box-only contact caused damage outside the flame')
 check(spanning.hp==940,'overlapping engines or multiple fixtures counted incorrectly')
 check(grazing.hp==970,'circle edge touching plume did not take damage')
 check(source.armor==100,'engine damaged its own ship')
 check(distant.hp==1000,'normal exhaust reached beyond the visible plume')
 source.afterburn=true;Exhaust.update(sim,1)
 check(distant.hp==970,'afterburner flame extension did not damage')
 local Engine=require('src.engine_visual')
 local nozzle=Engine.emitters(source)[1]
 local _,_,_,fullLength=Engine.geometry(nozzle,1,1,sim.time,true)
 local _,_,_,reserveLength=Engine.geometry(nozzle,1,require('src.tuning').boostReserve,sim.time,true)
 local edge=target(-(fullLength+reserveLength)/2,-8,.1)
 source.burnerLocked=true;Exhaust.update(sim,1)
 check(edge.hp==1000,'reserve exhaust damaged beyond its shorter visible flame')
 source.burnerLocked=false;Exhaust.update(sim,1)
 check(edge.hp==970,'full boost exhaust failed to reach its visible extension')
 source.afterburn=false;source.mainBurn=0
 local before=top.hp;Exhaust.update(sim,1)
 check(top.hp==before,'idle engine caused damage')
 source.mainBurn=1;source.loadout[1]=false
 before=top.hp;Exhaust.update(sim,1)
 check(top.hp==before,'empty engine slot caused damage')
 source.loadout[1]='test_damage_engine';source.dockState={}
 before=top.hp;Exhaust.update(sim,1)
 check(top.hp==before,'docked ship caused exhaust damage')
 source.dockState=nil;source.mainBurn=.5
 before=top.hp;Exhaust.update(sim,.25)
 check(math.abs(top.hp-(before-3.75))<.001,'damage is not scaled by throttle and elapsed time')
 source.mainBurn=1;source.body:setAngle(math.pi/2)
 local rotated=target(8,-7)
 Exhaust.update(sim,1)
 check(rotated.hp==970,'rotated ship exhaust did not follow its hardpoint')
 source.body:setAngle(0)
 local victim={kind='ship',team=3,armor=1000,body=love.physics.newBody(world,-7,-8,'static')}
 love.physics.newFixture(victim.body,love.physics.newCircleShape(.5)):setUserData(victim)
 sim.entities[#sim.entities+1]=victim
 Exhaust.update(sim,.1)
 check(victim.lastHitBy==source and victim.aggressor==source,'exhaust lost attribution or neutral retaliation')
 local module=data.modules.test_damage_engine
 local damage=module.exhaust.damage;module.exhaust.damage=0
 before=top.hp;Exhaust.update(sim,1)
 check(top.hp==before,'module damage zero did not disable exhaust damage')
 module.exhaust.damage=damage
 -- Real asteroid factory/fixtures must take damage, not only test containers.
 local rock=sim:spawnAsteroid(-7,-8,3,'rock')
 rock.body:setLinearVelocity(0,0);rock.body:setAngularVelocity(0)
 local hp=rock.hp
 Exhaust.update(sim,1/120)
 check(rock.hp<hp,'real asteroid did not take exhaust damage')
 check(rock.exhaustHit==sim.time,'asteroid exhaust damage has no visible heat feedback')
 for _=1,240 do Exhaust.update(sim,1/120) end
 check(rock.dead,'sustained exhaust failed to destroy a real asteroid')
 -- A small rock touching only the outer visible plume must also burn.
 local Engine=require('src.engine_visual')
 local nozzle=Engine.emitters(source)[1]
 local x,y,w,length=Engine.geometry(nozzle,1,false,sim.time)
 local glowRock=sim:spawnAsteroid(x-length*1.15,y, .3,'rock')
 local hpGlow=glowRock.hp
 Exhaust.update(sim,1/120)
 check(glowRock.hp<hpGlow,'outer visible flame contact did not burn asteroid')
 world:destroy()
 -- Verify the normal game step dispatches exhaust damage to actual asteroids.
 game:loadField('asteroids')
 for i=#game.entities,1,-1 do if game.entities[i]~=game.player then game:remove(game.entities[i]) end end
 game.sleepers={}
 local player=game.player
 player.body:setPosition(3000,3000);player.body:setAngle(0)
 player.intent.thrust=1
 local active=require('src.engine_visual').emitters(player)[1]
 local rock2=game:spawnAsteroid(3000+active.x-10,3000+active.y,3,'rock')
 rock2.body:setLinearVelocity(0,0)
 local hp2=rock2.hp
 game:step(1/120)
 check(rock2.hp<hp2,'normal game update did not apply exhaust damage to asteroid')
 print(('EXHAUST DAMAGE TEST PASSED (%d checks)'):format(checks))
end
