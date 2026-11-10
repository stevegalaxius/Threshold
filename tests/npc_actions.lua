-- One action lifecycle: approach, contention, interruption, resume and collect.
return function(game)
 local A=require('src.npc_actions')
 local L=require('src.locations')
 local Loose=require('src.loose')
 local Save=require('src.save')
 local node=require('src.fields').earth.buoyIds[1]
 local x,y=L.position(node,0)
 local function worker(id)
  return {id=id,area='earth',state='idle',node=node,route={node,node},index=1,speed=600,untilTime=100,
   task={id='action-job/'..id,kind='salvage'},ship={hull='ferrous_mule',loadout={},cargo={}}}
 end
 local first,second=worker('actions/1'),worker('actions/2')
 local u={clock=0,npcs={[first.id]=first,[second.id]=second}}
 local scene=setmetatable({universe=u},{__index=game})
 local resource={id='action-loot',kind='loot',area='earth',item='scrap',count=3,x=x+1200,y=y,vx=0,vy=0,clock=0}
 Loose.records(u)[resource.id]=resource
 local spec={kind='work',operation='collect',target={provider='resource',id=resource.id}}
 local function ctx(r,clock) u.clock=clock;return {game=scene,u=u,r=r,clock=clock} end
 A.request(ctx(first,0),spec);A.step(ctx(first,0))
 assert(resource.count==3 and resource.actionOwner==first.id,'approach reserves without taking cargo early')
 A.request(ctx(second,0),spec);A.step(ctx(second,0))
 assert(not second.action and second.lastAction.status=='failed','a competitor cannot execute the same claim')
 A.pause(ctx(first,1),'combat')
 assert(not resource.actionOwner and first.action.pausedAt==1,'interruptions release claims')
 A.request(ctx(second,1),spec);A.step(ctx(second,1));A.cancel(ctx(second,1.5),'new job')
 assert(resource.count==3 and not resource.actionOwner,'cancellation releases resources without transferring them')
 first.action=assert(Save.decode(Save.encode(first.action)))
 A.step(ctx(first,10));local arrival=first.action.arriveAt
 assert(resource.count==3 and arrival>10,'resume continues approach without charging paused time as work')
 A.step(ctx(first,arrival+1))
 assert(not Loose.records(u)[resource.id] and first.ship.cargo.scrap==3 and first.salvageCargo.scrap==3,'completion transfers one authoritative resource')
 -- Recovery uses the same approach runner and preserves nested cargo.
 local Hold=require('src.inventory.hold')
 scene.fieldId='pluto';scene.entities={};scene.pickups={};scene.sideScenes=function()return {}end
 local bx,by=A.actorPosition(ctx(second,15))
 local inner=Hold.new({{key='box',w=8,h=4}});Hold.add(inner,'rounds_s',25)
 u.areas={earth={capturedAt=15,objects={{id=1002,kind='container',item='cargo_container',x=bx,y=by,vx=0,vy=0,
  hold=Hold.serialize(inner),mass={0,0,20,200},hp=90,radius=30}}}}
 A.request(ctx(second,15),{kind='work',operation='recover',target={provider='loot',source='objects',id=1002,area='earth'}})
 A.step(ctx(second,15));A.step(ctx(second,17))
 local recovered=Hold.deserialize(second.ship.hold).grids[1].stacks[1]
 assert(#u.areas.earth.objects==0 and recovered.inner and Hold.count(recovered.inner,'rounds_s')==25,'recovery transfers the intact container once')
 -- A new action requires registration only, with no controller branch.
 A.register('test_signal',{update=function(c,a)
  if c.clock<a.untilTime then return 'running' end
  c.r.signals=(c.r.signals or 0)+1;return 'done'
 end})
 A.request(ctx(first,20),{kind='test_signal',untilTime=21})
 A.step(ctx(first,20));A.step(ctx(first,21));A.step(ctx(first,22))
 assert(first.signals==1 and first.lastAction.status=='done','registered actions complete once through the same runner')
 A.definitions.test_signal=nil
 -- Route actions initialize navigation themselves, including new job types.
 A.request(ctx(first,23),{kind='travel',target={provider='location',id=L.station('earth','trade')}})
 assert(first.state=='travel' and first.route[#first.route]==L.station('earth','trade'),'a route action starts shared navigation')
 A.cancel(ctx(first,23),'fixture ended')
 -- A normal route must steer once, even when no job supplies nextAction.
 local traveller=worker('actions/route');traveller.task=nil;traveller.state='travel'
 traveller.index=2;u.npcs[traveller.id]=traveller
 A.request(ctx(traveller,24),{kind='travel',target={provider='location',id=node}})
 local steering=0
 local actor={alifeId=traveller.id,intent={},body={getPosition=function()return x,y end}}
 require('src.npc').thinkWork(scene,actor,1/120,{trade=function()steering=steering+1 end})
 assert(steering==1,'ordinary travel executed steering more than once in one NPC update')
 -- Stay alongside a tractored object without chasing its pull velocity.
 local wanted
 local e={body={getPosition=function()return 0,0 end,getLinearVelocity=function()return 10,20 end},intent={},def={ai={throttle=1}}}
 A.move({e=e,AI={driveVelocity=function(_,vx,vy)wanted={vx,vy}end}},{x=50,y=0,vx=-200,vy=0},100,false)
 assert(wanted[1]==10 and wanted[2]==20,'collection coasts inside working range while the beam closes the gap')
 print('npc actions: lifecycle ok')
end
