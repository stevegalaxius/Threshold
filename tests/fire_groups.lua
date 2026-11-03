-- Weapon slots: hardpoints take guns, bays take launchers, and each slot
-- fires on the trigger the player picks for it.
return function(game)
 local data,Ship,Weapons=require('src.data'),require('src.ship'),require('src.weapons')
 local copy=require('src.persistence').copy
 local checks=0
 local function check(ok,msg) assert(ok,msg);checks=checks+1 end
 local p=game.player
 p.hull=copy(p.hull)
 p.hull.slots={{family='hardpoint',size='S'},{family='bay',size='S'},{family='hardpoint',trigger='secondary',size='S'}}
 p.loadout={'px2_autogun','sparrow_rack','px2_autogun'};p.triggers={}
 Ship.refit(p)
 check(not data.fits(p.hull.slots[1],data.modules.sparrow_rack),'a launcher fit a hardpoint')
 check(not data.fits(p.hull.slots[2],data.modules.px2_autogun),'a gun fit a bay')
 local function group(i) for _,w in ipairs(p.weapons) do if w.index==i then return w.group end end end
 check(group(1)=='primary' and group(2)=='tertiary' and group(3)=='secondary','default triggers wrong')
 Ship.toggleTrigger(p,1)
 check(group(1)=='secondary','toggle did not step primary to secondary')
 Ship.toggleTrigger(p,1);Ship.toggleTrigger(p,1)
 check(group(1)=='primary','toggle did not cycle through all three groups')
 Ship.toggleTrigger(p,2)
 check(group(2)=='primary','bay did not move to the primary trigger')
 Ship.toggleTrigger(p,3);Ship.toggleTrigger(p,3)
 check(group(3)=='primary','hardpoint did not move to the primary trigger')
 local rec=Ship.record(p)
 check(rec.triggers[2]=='primary' and rec.triggers[3]=='primary','triggers not in the ship record')
 local e=Ship.new(game,{hull=p.hull,loadout=rec.loadout,triggers=rec.triggers})
 local g={} for _,w in ipairs(e.weapons) do g[w.index]=w.group end
 check(g[1]=='primary' and g[2]=='primary' and g[3]=='primary','triggers lost rebuilding the ship')
 e.body:destroy()
 -- the primary trigger now fires the missile rack
 p.cargo.missile_s=(p.cargo.missile_s or 0)+5
 local before=p.cargo.missile_s
 p.intent.firePrimary,p.intent.fireSecondary,p.intent.fireTertiary=true,false,false
 for _,w in ipairs(p.weapons) do w.cooldown=0;w.stagger=0 end
 Weapons.update(game,p,0.01)
 check(p.cargo.missile_s<before,'primary trigger did not launch the missile')
 -- a beam laser burns while held, taking power per second
 p.loadout={'thread_beam',false,false};p.triggers={};Ship.refit(p)
 p.power=1000
 local pw=p.power
 p.intent.firePrimary=true
 Weapons.update(game,p,0.1)
 check(p.weapons[1].beam and p.power<pw,'beam laser did not fire or draw power')
 p.intent.firePrimary=false
 -- a drill extends out of the nose while held and grinds rock into ore
 p.loadout={'bore_drill',false,false};p.triggers={};Ship.refit(p)
 p.body:setPosition(0,0);p.body:setAngle(0);p.body:setLinearVelocity(0,0)
 local reach=p.halfLength*2
 local rock=game:spawnAsteroid(reach*0.6+30,0,30,'rock');rock.body:setLinearVelocity(0,0)
 local hp=rock.hp
 p.power=1000;p.intent.firePrimary=true
 for _=1,10 do Weapons.update(game,p,0.05) end
 check((p.weapons[1].extend or 0)>0.9,'drill did not extend')
 check(rock.hp<hp,'drill did not damage the rock')
 check(p.power<1000,'drill drew no power')
 rock.dead=true;game:reap()
 local ore=false
 for _,o in ipairs(game.pickups) do if o.item=='iron_ore' then ore=true end end
 check(ore,'drilled rock dropped no ore')
 p.intent.firePrimary=false
 for _=1,20 do Weapons.update(game,p,0.05) end
 check((p.weapons[1].extend or 0)==0,'drill did not retract')
 -- flares: a flare pod fires them by itself at a missile closing in
 p.hull.slots[4]={family='utility',size='any'}
 p.loadout={false,false,false,'flare_pod'};p.triggers={};Ship.refit(p)
 p.cargo.flare=3
 local px,py=p.body:getPosition()
 game.projectiles={{kind='missile',team=2,x=px+500,y=py,px=px+500,py=py,vx=-100,vy=0,maxSpeed=3000,accel=0,turnRate=4,life=5,target=p,damage=1,knockback=0,burst=true,splash=10,fuse=5}}
 Weapons.updateProjectiles(game,0.016)
 check(p.cargo.flare==2,'flare pod did not use a flare')
 check(#(game.decoys or {})==3,'no flares in space')
 local m=game.projectiles[1]
 check(m and (m.target==p or m.target.kind=='decoy'),'missile lost its target oddly')
 -- the scanner is a computer the game can find
 p.hull.slots[5]={family='computer',size='any'}
 p.loadout[5]='scanner';Ship.refit(p)
 check(game:computer(p,'scanner'),'scanner computer not found')
 game.projectiles={}
 -- old saved designs read as the new families
 local old=data.migrateSlot({family='secondary',size='M'})
 check(old.family=='hardpoint' and old.trigger=='secondary','old secondary slot not migrated')
 check(data.migrateSlot({family='auxiliary',size='M'}).family=='bay','old auxiliary slot not migrated')
 print(('FIRE GROUP TEST PASSED (%d checks)'):format(checks))
end
