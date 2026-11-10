return function(game)
 local A=require('src.alife');local M=require('src.mining');local data=require('src.data');local copy=require('src.persistence').copy
 local Stats=require('src.stats');local Fuel=require('src.reactor_fuel');local L=require('src.locations');local AI=require('src.ai')
 game:loadField('phobos');game:captureALife(true)
 local u=game.universe;u.npcs={};u.populationSpawns={};u.economyNext=math.huge;u.encounterNext=math.huge
 local def=data.enemies.miner_packhorse;local site=require('src.fields').phobos.drillIds[1]
 local r={id='live/miner',archetype=def.id,home='phobos',area='phobos',homeStation=L.get(site).motion.home,speed=600,spread=0,
  state='idle',node=site,route={site,site},index=1,untilTime=u.clock+1000,
  task={id='live/mine',kind='mine',phase='mining',source=L.get(site).motion.home,target=site,item='iron_ore',retainedCargo=0},
  ship={hull=def.hull,loadout=copy(def.loadout),cargo={[Fuel.item()]=30},fuelInitialized=true,fuelCharge=2500,armor=Stats.compute(data.hulls[def.hull],def.loadout).armor},
  pose={x=20000,y=0,a=0,vx=0,vy=0,w=0,clock=u.clock}}
 u.npcs[r.id]=r;game.player.body:setPosition(21000,1000)
 local e=A.wake(game,r);local rx=20000+e.noseX+45
 local rock=game:spawnAsteroid(rx,0,20,'rock');rock.miningId='live/rock';rock.hp=5;rock.body:setLinearVelocity(0,0)
 local state=M.state(u);state.resources={['live/rock']={id='live/rock',site=site,area='phobos',kind='rock',item='iron_ore',yield=3,
  x=rx,y=0,vx=0,vy=0,radius=20,hp=5,clock=u.clock,angle=0,spin=0}}
 game.miningLive={['live/rock']={kind='rock',object=rock}}
 for _=1,600 do
  local x,y=e.body:getPosition();game.player.body:setPosition(x+1000,y+1000)
  game:step(1/120)
  if (e.cargo.iron_ore or 0)>0 then break end
 end
 assert(not state.resources['live/rock'],'physical drilling did not break the resource')
 assert((e.cargo.iron_ore or 0)>0,'physical mining did not tractor its resulting ore')
 print('LIVE MINING: drilled and collected with Box2D')
end
