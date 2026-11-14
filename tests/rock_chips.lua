-- Rock chips and rare ore (src/rock_chips.lua): rock sheds chips under
-- fire, chips pop into ore (twice as much drilled), veins give rare chips.
return function(game)
 local T=require('src.tuning')
 local checks=0
 local function check(ok,msg) assert(ok,msg);checks=checks+1 end
 local X,Y=70000,70000
 local function chipsOf() local n,list=0,{};for _,e in ipairs(game.entities) do if e.chip and not e.removed then n=n+1;list[#list+1]=e end end;return n,list end
 local function clear() for i=#game.entities,1,-1 do local e=game.entities[i];if e.isTest or e.chip then e.body:destroy();e.removed=true;table.remove(game.entities,i) end end;game.pickups={} end
 local function rock(kind,r) local e=game:spawnAsteroid(X,Y,r,kind);e.isTest=true;e.rare=nil;e.body:setLinearVelocity(0,0);return e end
 local function hit(e,amount,cause) game:damage(e,amount,game.player,cause,X+e.radius,Y);game:reap() end
 local function count(item) local n=0;for _,k in ipairs(game.pickups) do if k.item==item then n=n+k.count end end;return n end
 -- shooting a rock: chips come off, it shrinks, and it never splits
 clear()
 local e=rock('rock',100);local r0,hp=e.radius,e.hp
 hit(e,hp*0.25,'laser')
 local n=chipsOf()
 check(n>=2,'a quarter of its health should knock off chips ('..n..')')
 check(e.radius<r0,'the rock should shrink as it chips')
 for _=1,20 do if not e.removed then hit(e,hp*0.1,'laser') end end
 check(e.removed,'the rock should crumble at the end')
 local n2,list=chipsOf()
 check(n2<=T.chipMax+2,'no more chips than the cap allows ('..n2..')')
 for _,o in ipairs(game.entities) do check(not(o.debris=='rock' and o.isTest==nil and not o.chip and o.radius>T.chipRadius*2 and (o.body:getX()-X)^2+(o.body:getY()-Y)^2<300^2),'no split rocks near it') end
 -- a shot chip pops into one ore, a drilled one into two
 local before=count('iron_ore');hit(list[1],100,'laser')
 check(count('iron_ore')==before+1,'a shot chip gives one iron ore')
 before=count('iron_ore');hit(list[2],100,'drill')
 check(count('iron_ore')==before+2,'a drilled chip gives two')
 -- bumps neither chip a rock nor break a chip
 clear()
 e=rock('ice',80);hit(e,e.hp*0.3,'ram')
 check(chipsOf()==0,'a bump should not chip a rock')
 e=rock('ice',80);hit(e,e.hp*0.3,'laser');local _,ice=chipsOf()
 check(#ice>0 and ice[1].chip=='water_ice','ice chips are water ice')
 hit(ice[1],100,'ram');check(not ice[1].removed,'a bump should not break a chip')
 -- a vein: plain chips until it's reached, then rare ones
 clear()
 e=rock('rock',100);e.rare='gold_ore';e.rareAt=0.7;e.rareArt={vein={0,0,0.1,0.1},flecks={},crystal={}}
 hit(e,e.hp*0.2,'laser');local _,early=chipsOf()
 for _,c in ipairs(early) do check(c.chip=='iron_ore','chips before the vein are iron') end
 hit(e,e.hp*0.5,'laser');local gold=0
 for _,c in ipairs(select(2,chipsOf())) do if c.chip=='gold_ore' then gold=gold+1 end end
 check(gold>0,'chips past the vein are gold')
 -- mining-site rock keeps the drill rule
 clear()
 e=rock('rock',60);e.miningId='test';hit(e,e.hp*0.5,'laser')
 check(chipsOf()==0,'mining-site rock does not chip')
 -- rare rolls: only big rocks, at about the set chance
 clear()
 local big,small=0,0
 for _=1,400 do local a=game:spawnAsteroid(X,Y,90,'rock');if a.rare then big=big+1 end;a.isTest=true end
 clear()
 for _=1,200 do local a=game:spawnAsteroid(X,Y,30,'rock');if a.rare then small=small+1 end;a.isTest=true end
 clear()
 check(small==0,'small rocks never carry a vein')
 check(big>4 and big<60,'big rocks carry one now and then ('..big..'/400)')
 print('rock chips: '..checks..' checks passed')
end
