-- Prospecting (src/prospect.lua): a live miner passing a rock with a gold
-- core cuts into it and collects the gold; NPCs sell rare ore when they
-- dock; offline legs through belts sometimes turn some up.
return function(game)
 local A=require('src.alife');local data=require('src.data');local copy=require('src.persistence').copy
 local Stats=require('src.stats');local Fuel=require('src.reactor_fuel');local L=require('src.locations')
 local P=require('src.prospect');local RC=require('src.rock_chips');local T=require('src.tuning')
 local checks=0
 local function check(ok,msg) assert(ok,msg);checks=checks+1 end
 -- keenness by what it is
 check(P.eagerness({populationGroup='miner'})==1,'miners always go for it')
 check(P.eagerness({populationGroup='patrol'})==0,'patrols never do')
 check(P.eagerness({populationGroup='trader',piracy=true})==1,'pirates always do')
 -- live: a miner with nothing to mine cuts into a gold rock nearby
 game:loadField('phobos');game:captureALife(true)
 local u=game.universe;u.npcs={};u.populationSpawns={};u.economyNext=math.huge;u.encounterNext=math.huge
 local def=data.enemies.miner_packhorse;local site=require('src.fields').phobos.drillIds[1]
 local r={id='live/prospector',archetype=def.id,home='phobos',area='phobos',homeStation=L.get(site).motion.home,speed=600,spread=0,
  populationGroup='miner',state='idle',node=site,route={site,site},index=1,untilTime=u.clock+1000,
  ship={hull=def.hull,loadout=copy(def.loadout),cargo={[Fuel.item()]=30},fuelInitialized=true,fuelCharge=2500,armor=Stats.compute(data.hulls[def.hull],def.loadout).armor},
  pose={x=20000,y=0,a=0,vx=0,vy=0,w=0,clock=u.clock}}
 u.npcs[r.id]=r;game.player.body:setPosition(21000,1000)
 require('src.mining').state(u).resources={}
 local e=A.wake(game,r)
 local rock=game:spawnAsteroid(21200,300,60,'rock');rock.body:setLinearVelocity(0,0);RC.giveCore(rock,'gold_ore')
 rock.hp=rock.hp*0.3
 local saw=false
 for _=1,120*90 do
  local x,y=e.body:getPosition();game.player.body:setPosition(x+1500,y+1500)
  game:step(1/120)
  if r.action and r.action.operation=='prospect' then saw=true end
  if (e.cargo.gold_ore or 0)>0 then break end
 end
 check(saw,'the miner should turn to prospect the gold rock')
 check((e.cargo.gold_ore or 0)>0,'the miner should come away with gold ('..tostring(e.cargo.gold_ore)..')')
 -- selling: rare ore goes on the shelf, for its own credits
 local home=L.get(site).motion.home
 local Stock=require('src.stockpile')
 local before=Stock.count(u,L.canonical(home),'gold_ore')
 local seller={id='seller',ship={hull=def.hull,cargo={gold_ore=3,iron_ore=2}}}
 local got=P.sell(u,seller,home)
 check(got==3*data.items.gold_ore.price and seller.credits==got,'it is paid for the gold')
 check(seller.ship.cargo.gold_ore==nil and seller.ship.cargo.iron_ore==2,'only rare ore is sold')
 check(Stock.count(u,L.canonical(home),'gold_ore')==before+3,'the gold goes on the station shelf')
 -- offline: a keen ship through a belt sometimes finds some; a patrol never
 local found=0
 for _=1,2000 do
  local q={populationGroup='miner',ship={hull=def.hull,cargo={}}}
  if P.offlineFind(u,q,'belt') then found=found+1 end
 end
 check(found>40 and found<250,'offline legs through the belt turn up rare ore now and then ('..found..'/2000)')
 local none=0
 for _=1,500 do if P.offlineFind(u,{populationGroup='patrol',ship={hull=def.hull,cargo={}}},'belt') then none=none+1 end end
 check(none==0,'patrols never prospect')
 print('prospect: '..checks..' checks passed')
end
