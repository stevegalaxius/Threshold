return function(game)
 local W=require('src.wreck_salvage');local T=require('src.tuning')
 local A=require('src.npc_actions');local Ship=require('src.ship');local Hold=require('src.inventory.hold')
 local Weapons=require('src.weapons');local copy=require('src.persistence').copy
 local roll=0
 assert(W.survivors(8,false,function()roll=roll+1;return roll%2==0 and .75 or .25 end)==4,'shooting did not roll each cargo unit at 50%')
 assert(W.survivors(8,true,function()error('drilling rolled for cargo loss')end)==8,'drilling lost cargo')
 assert(not W.weapon({loadout={},cargo={}}),'unarmed ships can strip wrecks')
 assert(W.weapon({loadout={'drill_s_base'},cargo={}}).w.kind=='drill','drill was not selected')
 game:loadField('earth');game:captureALife(true)
 local r
 for _,n in pairs(game.universe.npcs) do
  local w=W.weapon(n.ship)
  if n.home=='earth' and n.populationGroup=='trader' and w and w.w.kind=='cannon' then r=copy(n);break end
 end
 assert(r,'missing gun-equipped NPC fixture')
 for _,e in pairs(game.alifeOnline) do game:remove(e,true) end
 game.alifeOnline={};game.universe.npcs={}
 local node=require('src.fields').earth.buoyIds[1]
 r.id='salvage/gun';r.area='earth';r.state='idle';r.route={node,node};r.index=1;r.node=node
 r.task={id='salvage/fixture',kind='salvage'};r.service=nil;r.action=nil
 r.pose={x=100000,y=0,a=0,vx=0,vy=0,w=0,clock=game.universe.clock}
 game.universe.npcs[r.id]=r
 local e=require('src.alife').wake(game,r);local weapon=assert(W.weapon(e))
 local carriedScrap=e.cargo.scrap or 0
 weapon.group='secondary';weapon.stagger=0
 local function wreck()
  local hold=Hold.new({{key='cargo',w=8,h=8}});Hold.add(hold,'scrap',8)
  local h=game:spawnHusk(e,100700,0,0,0,0,0,hold)
  h.pieces=nil;h.hp=1;h.origin={id='test'};return h
 end
 local h=wreck();local oldChance=T.wreckShotRecovery;T.wreckShotRecovery=0
 local ctx={game=game,u=game.universe,r=r,e=e,clock=game.universe.clock,dt=1/120,AI=require('src.ai')}
 local target={provider='loot',source='live',id=h.id,area='earth'}
 A.request(ctx,{kind='work',operation='recover',target=target,clearWreck=true})
 local sawSecondary=false
 for _=1,240 do
  ctx.clock=ctx.clock+1/120;game.universe.clock=ctx.clock
  A.step(ctx)
  sawSecondary=sawSecondary or e.intent.fireSecondary and not e.intent.firePrimary
  Ship.fly(e,1/120);Weapons.update(game,e,1/120);game.world:update(1/120)
  Weapons.updateProjectiles(game,1/120);game:reap()
  if h.removed then break end
 end
 assert(sawSecondary and h.removed,'gun-only recovery did not fire its assigned trigger and break the wreck')
 assert((e.cargo.scrap or 0)==carriedScrap,'gun-equipped cleaner bypassed shooting by transferring intact wreck cargo')
 local scrap=0
 for _,p in ipairs(game.pickups) do if p.item=='scrap' then scrap=scrap+p.count end end
 assert(scrap==0,'shot wreck ignored recovery loss')
 A.cancel(ctx,'fixture finished')
 local drilled=wreck();game:damage(drilled,10,e,'drill');game:reap()
 for _,p in ipairs(game.pickups) do if p.item=='scrap' then scrap=scrap+p.count end end
 T.wreckShotRecovery=oldChance
 assert(scrap==8,'drilled wreck did not preserve its contents')
 print('WRECK SALVAGE: gun-only recovery, trigger selection and cargo yield passed')
end
