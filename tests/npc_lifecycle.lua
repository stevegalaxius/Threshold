return function(game)
 local A,G,L=require('src.alife'),require('src.travelgraph'),require('src.locations')
 local Tasks=require('src.tasks')
 local copy=require('src.persistence').copy
 local checks=0
 local function check(ok,msg)assert(ok,msg);checks=checks+1 end
 game.autosaveOff=true;game:loadField('earth')
 local template
 for _,r in pairs(game.universe.npcs) do if r.home=='earth' and r.role=='pirate' then template=copy(r);break end end
 assert(template)
 game:captureALife(true);game.universe.npcs={}
 game.travelGraphView=G.build('earth')
 local node=require('src.fields').earth.buoyIds[1]
 local x,y=L.position(node,game.universe.clock)
 local canvas=love.graphics.newCanvas(love.graphics.getDimensions())
 local function draw()
  love.graphics.setCanvas(canvas)
  local ok,err=pcall(require('src.ui.alife_overlay').draw,game,function(_,x,y) return x,y end)
  love.graphics.setCanvas()
  check(ok,'overlay used a stale body: '..tostring(err))
 end
 local function spawn(id)
  local r=copy(template)
  r.id=id;r.state='idle';r.route={node,node};r.index=1;r.node=node;r.untilTime=game.universe.clock+600
  r.task=nil;r.encounter=nil;r.pose=nil;r.offset=nil;r.fleeing=nil
  game.universe.npcs[id]=r
  game.player.body:setPosition(x+3000,y)
  local e=A.wake(game,r)
  Tasks.choose(game.universe,r,node,game.universe.clock)
  return r,e
 end
 -- Ordinary removal is immediately visible to drawing, before another tick.
 local r,e=spawn('removed-npc')
 local task=r.task and r.task.id
 game:remove(e)
 check(not game.alifeOnline[r.id] and r.state=='escaped','removal retained online ownership')
 check(e.body:isDestroyed(),'removal did not destroy physical body')
 check(not task or not game.universe.tasks.offers[task].owner,'removed NPC retained a task reservation')
 draw()
 -- The separate flee/reap path must detach too (it does not call remove).
 r,e=spawn('fleeing-npc');e.fleeing=true
 e.body:setPosition(game.arenaRadius+1000,0)
 game:reap()
 check(r.state=='escaped' and not game.alifeOnline[r.id],'fleeing NPC retained destroyed online body')
 draw()
 -- Death still makes exactly one wreck and releases online ownership now.
 r,e=spawn('dead-npc')
 local before=0;for _,o in ipairs(game.entities) do if o.kind=='husk' then before=before+1 end end
 e.dead=true;game:reap()
 local after=0;for _,o in ipairs(game.entities) do if o.kind=='husk' then after=after+1 end end
 check(r.state=='dead' and not game.alifeOnline[r.id],'death retained online ownership')
 check(after==before+1,'lifecycle cleanup lost normal death salvage')
 draw()
 -- Defensive draw/capture behavior if an external caller destroys a body.
 r,e=spawn('stale-body')
 for i,o in ipairs(game.entities) do if o==e then table.remove(game.entities,i);break end end
 e.body:destroy()
 draw()
 game:updateALife(true)
 check(not game.alifeOnline[r.id] and r.state=='escaped','sync did not clear stale destroyed body')
 -- Distance culling is an unload, not a despawn: duty and damage survive.
 r,e=spawn('culled-npc');e.armor=e.stats.armor*.8  -- above the repair threshold, so it keeps its duty
 e.body:setPosition(x+100,y)
 local armor=e.armor;task=r.task and r.task.id
 game.player.body:setPosition(0,0);game:updateALife(true)
 check(not game.alifeOnline[r.id] and r.state=='idle','culling marked a living NPC escaped')
 check(r.ship.armor==armor and (not task or r.task and r.task.id==task),'culling lost ship state or duty')
 draw()
 local xx,yy=A.point(r,game.universe.clock)
 game.player.body:setPosition(xx+1000,yy);game:updateALife(true)
 local awake=game.alifeOnline[r.id]
 check(awake and awake~=e and not awake.body:isDestroyed(),'culled NPC did not rematerialize')
 check(awake.armor==armor,'rematerialized NPC lost damage')
 game:remove(e)
 check(game.alifeOnline[r.id]==awake and r.state=='idle','stale removal detached a newer representation')
 draw()

 -- Unreferenced dead records are dropped after their linger; referenced ones stay.
 do
  local u={clock=0,npcs={}}
  u.npcs.a={id='a',state='dead'};u.npcs.b={id='b',state='dead'}
  u.npcs.c={id='c',state='idle',encounter={target='b'}}
  A.pruneGone(u,0);A.pruneGone(u,require('src.tuning').alifeGoneLinger+1)
  check(not u.npcs.a and u.npcs.b and u.npcs.c,'dead record cleanup removed a referenced record or kept a stale one')
 end
 print(('NPC LIFECYCLE TEST PASSED (%d checks)'):format(checks))
end
