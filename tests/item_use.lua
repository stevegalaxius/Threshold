-- Item use (src/item_use.lua): casts, interrupts, cooldowns, field repair
-- limits, over-time restores and buffs, on the real player ship and hold.
return function(game)
 local U,Hold,events=require('src.item_use'),require('src.inventory.hold'),require('src.events')
 local data=require('src.data')
 local checks=0
 local function check(ok,msg) assert(ok,msg);checks=checks+1 end
 local p=game.player
 assert(p and p.hold,'test needs a player ship with a hold')
 game.state='flight';p.dockState=nil
 for id,n in pairs(Hold.totals(p.hold)) do Hold.take(p.hold,id,n) end
 p.cargo=Hold.totals(p.hold)
 local max=p.stats.armor
 local function give(id,n) assert(Hold.add(p.hold,id,n)==n,'no room for '..id);p.cargo=Hold.totals(p.hold) end
 local function run(t) local step=1/60;for _=1,math.ceil(t/step) do game.time=game.time+step;U.update(game,p,step) end end
 -- every usable item names only known effects
 for _,id in ipairs(data.list.items) do
  local cfg=data.items[id].use
  if cfg then for _,line in ipairs(cfg.effects) do check(U.effects[line[1]],id..' uses unknown effect '..tostring(line[1])) end end
 end
 -- Field repair: 3 s cast, 50 armor a plate, never past 75%.
 give('steel_plate',4)
 p.armor=max*.5
 check(U.begin(game,p,'steel_plate'),'could not start field repair')
 run(1.5);check(p.armor==max*.5 and p.cargo.steel_plate==4,'repair applied or spent before the cast finished')
 run(1.6);check(math.abs(p.armor-math.min(max*.75,max*.5+50))<1e-6 and p.cargo.steel_plate==3,'cast did not repair 50 or spend one plate')
 -- a hit interrupts and refunds nothing spent
 run(3)
 if p.armor<max*.75 then
  check(U.begin(game,p,'steel_plate'),'second repair refused')
  run(1);game:damage(p,1);check(not p.casting and p.cargo.steel_plate==3,'hit did not interrupt, or the plate was spent')
 end
 p.armor=max*.75
 local ok,why=U.can(game,p,'steel_plate')
 check(not ok and why:match('field limit'),'repair allowed above the field limit: '..tostring(why))
 -- docked: not usable
 p.armor=max*.5;p.dockState={}
 check(not U.can(game,p,'steel_plate'),'field repair allowed while docked');p.dockState=nil
 -- Patch kit shares the repair group's cooldown and goes to full armor.
 give('patch_kit',2)
 p.armor=max*.1
 check(U.begin(game,p,'patch_kit'),'patch kit refused');run(1.1)
 check(math.abs(p.armor-math.min(max,max*.1+150))<1e-6,'patch kit did not restore 150')
 ok,why=U.can(game,p,'patch_kit')
 check(not ok and why:match('Ready in'),'repair group cooldown not applied')
 ok=U.can(game,p,'steel_plate');check(not ok,'plates ignored the shared repair cooldown')
 run(21)
 -- Nanites: over time, through hits.
 -- (a big hull for room: 200 over 20 s needs armor to spare)
 p.stats.armor=1000;give('nanite_paste',1);p.armor=500
 check(U.begin(game,p,'nanite_paste') and not p.casting,'nanites should be instant')
 game:damage(p,1);run(10)
 check(math.abs(p.armor-599)<1,'nanites did not restore half over half the time: '..p.armor)
 run(11);check(math.abs(p.armor-699)<1 and not p.auras,'nanites did not finish cleanly')
 p.stats.armor=max;p.armor=max
 -- Overdrive: thrust buff that refreshes, then reverts exactly.
 local thrust=p.stats.thrust
 give('overdrive_cell',2)
 check(U.begin(game,p,'overdrive_cell'),'overdrive refused')
 check(math.abs(p.stats.thrust-thrust*1.5)<1e-6,'thrust not boosted')
 run(9);check(p.stats.thrust==thrust,'thrust buff did not revert: '..p.stats.thrust..' vs '..thrust)
 -- quick key finds a repair item; events fire
 local finished=0;events.on('use_finish',function(e,id) if e==p then finished=finished+1 end end)
 run(60);p.armor=max*.4
 check(U.quick(game,p,'repair'),'quick repair found nothing');run(3.1)
 check(finished==1,'use_finish not emitted')
 print(('item use: %d checks passed'):format(checks))
end
