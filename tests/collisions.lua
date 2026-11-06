-- Crash damage: measured once per crash from closing speed; each side takes
-- ramDamage x mass x (speed change - grace)^2 / toughness.
return function(game)
 local Ship=require('src.ship')
 local checks=0
 local function check(ok,msg) assert(ok,msg);checks=checks+1 end
 local function crash(hullA,hullB,speed,ang,toughA)
  for i=#game.entities,1,-1 do local e=game.entities[i]; if e.isTest then e.body:destroy(); table.remove(game.entities,i) end end
  local X,Y=60000,60000
  local a=Ship.new(game,{hull=hullA,x=X-400,y=Y,angle=0})
  local b=Ship.new(game,{hull=hullB,x=X+400,y=Y,angle=ang or 0})
  if toughA then local h={}; for k,v in pairs(a.hull) do h[k]=v end; h.toughness=toughA; a.hull=h end
  for _,e in ipairs({a,b}) do e.isTest=true; e.ai=nil; e.intent={}; local f=false; for _,o in ipairs(game.entities) do if o==e then f=true end end; if not f then table.insert(game.entities,e) end end
  a.body:setLinearVelocity(speed,0)
  local a0,b0=a.armor,b.armor
  for _=1,300 do game.world:update(1/60); game:resolveContacts(); game.time=game.time+1/60 end
  return a0-a.armor,b0-b.armor
 end
 local last=-1
 for _,v in ipairs({150,250,350,450,600}) do
  local d=crash('brute_anvil','brute_anvil',v)
  check(d>=last,'damage should grow smoothly with speed ('..v..')'); last=d
 end
 check(crash('brute_anvil','brute_anvil',90)==0,'a gentle bump should be free')
 local h1=crash('brute_anvil','brute_anvil',600,0); local h2=crash('brute_anvil','brute_anvil',600,1.57)
 check(math.abs(h1-h2)<0.05*h1,'head-on and side-on crashes at the same speed should match')
 local pony,anvil=crash('ferrous_pony','brute_anvil',600)
 check(pony>anvil*2,'the light ship should take the brunt')
 local t1=crash('brute_anvil','brute_anvil',600,0,1); local t2=crash('brute_anvil','brute_anvil',600,0,2)
 check(math.abs(t2-t1/2)<0.05*t1,'toughness 2 should halve crash damage')
 print(('collisions: %d checks passed'):format(checks))
end
