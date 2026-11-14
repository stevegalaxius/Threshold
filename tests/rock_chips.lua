-- Rock chips and rare ore (src/rock_chips.lua): a rock is cut down facet by
-- facet, pieces fly off in all sizes, chips pop into ore (twice as much
-- drilled), and cutting into a gold core throws off gold.
return function(game)
 local T=require('src.tuning')
 local checks=0
 local function check(ok,msg) assert(ok,msg);checks=checks+1 end
 local X,Y=70000,70000
 local function live() local list={};for _,e in ipairs(game.entities) do if e.kind=='asteroid' and not e.giant and not e.removed and (e.body:getX()-X)^2+(e.body:getY()-Y)^2<2000^2 then list[#list+1]=e end end;return list end
 local function chips() local l={};for _,e in ipairs(live()) do if e.chip then l[#l+1]=e end end;return l end
 local function clear() for _,e in ipairs(live()) do e.body:destroy();e.removed=true;for i,o in ipairs(game.entities) do if o==e then table.remove(game.entities,i);break end end end;game.pickups={} end
 local function rock(kind,r) local e=game:spawnAsteroid(X,Y,r,kind);e.rare,e.core,e.veins=nil,nil,nil;e.body:setLinearVelocity(0,0);return e end
 local function hit(e,amount,cause) local x,y=e.body:getPosition();game:damage(e,amount,game.player,cause,x+e.radius,y);game:reap() end
 local function count(item) local n=0;for _,k in ipairs(game.pickups) do if k.item==item then n=n+k.count end end;return n end
 local function area(p) local s=0;for i=1,#p,2 do local j=i+2>#p and 1 or i+2;s=s+p[i]*p[j+1]-p[j]*p[i+1] end;return math.abs(s)/2 end
 -- shooting a rock cuts facets off it, and the pieces come in all sizes
 clear()
 local e=rock('rock',100);local a0,hp=area(e.verts),e.hp
 hit(e,hp*0.3,'laser')
 check(area(e.verts)<a0*0.95,'the rock should lose area as it is cut')
 check(#live()>=3,'cuts should throw off pieces ('..#live()..')')
 for _,p in ipairs(live()) do check(#p.verts<=16 and love.math.isConvex(p.verts),'every piece is a valid convex shape') end
 local sizes={}
 for _=1,30 do if not e.removed then hit(e,hp*0.06,'laser') end end
 for _,p in ipairs(live()) do sizes[#sizes+1]=p.radius end
 table.sort(sizes)
 check(sizes[#sizes]>sizes[1]*1.8,'pieces should vary in size ('..sizes[1]..'..'..sizes[#sizes]..')')
 -- grind everything down: it all ends as chips, then ore
 for _=1,200 do
  local any=false
  for _,p in ipairs(live()) do if not p.chip then any=true;hit(p,p.hp*0.5+1,'laser') end end
  if not any then break end
 end
 local list=chips()
 check(#list>0,'everything should end as chips')
 for _,c in ipairs(list) do check(c.chip=='iron_ore','plain rock chips are iron') end
 local before=count('iron_ore');hit(list[1],100,'laser')
 check(count('iron_ore')==before,'a shot iron chip gives nothing: only drills recover iron')
 before=count('iron_ore');hit(list[2],100,'drill')
 check(count('iron_ore')==before+2,'a drilled chip gives two')
 -- bumps neither cut a rock nor break a chip
 clear()
 e=rock('ice',80);hit(e,e.hp*0.3,'ram')
 check(#live()==1,'a bump should not cut a rock')
 hit(e,e.hp*0.9,'laser')
 for _=1,100 do local any=false;for _,p in ipairs(live()) do if not p.chip then any=true;hit(p,p.hp*0.5+1,'laser') end end;if not any then break end end
 local ice=chips()
 check(#ice>0 and ice[1].chip=='water_ice','ice chips are water ice')
 hit(ice[1],100,'ram');check(not ice[1].removed,'a bump should not break a chip')
 -- a gold core: hidden until a cut reaches it, then gold comes off
 clear()
 local gold=0
 for _=1,20 do
  e=rock('rock',100);e.rare='gold_ore';local core={};for j=0,6 do local a=j/7*math.pi*2;core[#core+1]=math.cos(a)*40;core[#core+1]=math.sin(a)*40 end;e.core=core
  check(not e.opened,'the core starts hidden')
  for _=1,200 do local any=false;for _,p in ipairs(live()) do if not p.chip then any=true;hit(p,p.hp*0.3+1,'laser') end end;if not any then break end end
  for _,c in ipairs(chips()) do if c.chip=='gold_ore' then gold=gold+1 end end
  clear()
 end
 e=rock('rock',20);e.rare='gold_ore'
 local g=game:spawnAsteroid(X,Y,5,'rock');g.chip,g.rare,g.hp='gold_ore','gold_ore',1
 local gb=count('gold_ore');hit(g,10,'laser')
 check(count('gold_ore')==gb+1,'a shot gold chip gives one gold ore')
 check(gold>=20,'cutting through a core gives gold ('..gold..' chips over 20 rocks)')
 -- mining-site rock keeps the drill rule
 clear()
 e=rock('rock',60);e.miningId='test';hit(e,e.hp*0.5,'laser')
 check(#live()==1,'mining-site rock is not cut')
 clear()
 -- rare rolls: only big rocks, at about the set chance
 local big,small=0,0
 for _=1,400 do local a=game:spawnAsteroid(X,Y,90,'rock');if a.rare then big=big+1 end end
 clear()
 for _=1,200 do local a=game:spawnAsteroid(X,Y,30,'rock');if a.rare then small=small+1 end end
 clear()
 check(small==0,'small rocks never carry a core')
 local ice=0
 for _=1,400 do local a=game:spawnAsteroid(X,Y,35,'ice');if a.rare then ice=ice+1 end end
 clear()
 check(ice>8,'ring-sized ice can hold a crystal ('..ice..'/400)')
 check(big>4 and big<60,'big rocks carry one now and then ('..big..'/400)')
 print('rock chips: '..checks..' checks passed')
end
