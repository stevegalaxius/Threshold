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
 -- old saved designs read as the new families
 local old=data.migrateSlot({family='secondary',size='M'})
 check(old.family=='hardpoint' and old.trigger=='secondary','old secondary slot not migrated')
 check(data.migrateSlot({family='auxiliary',size='M'}).family=='bay','old auxiliary slot not migrated')
 print(('FIRE GROUP TEST PASSED (%d checks)'):format(checks))
end
