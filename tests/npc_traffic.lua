return function(game)
 local Traffic=require('src.ui.npc_traffic')
 local Save=require('src.save')
 local copy=require('src.persistence').copy
 local checks=0
 local function check(ok,msg) assert(ok,msg);checks=checks+1 end
 game.autosaveOff=true
 -- Use explicit diagnostic records to cover both directions and moon filtering.
 local template
 for _,r in pairs(game.universe.npcs) do template=r;break end
 local function record(id,from,to,kind,depart,arrive)
  local r=copy(template);r.id=id;r.state='transit';r.area=nil
  r.transit={kind=kind,from=from,to=to,length=100000,speed=1000}
  r.depart=depart;r.arrive=arrive;r.task=nil;r.ship.cargo={scrap=5};r.ship.hold=nil
  return r
 end
 game:captureALife(true)
 game.universe.clock=100
 game.universe.npcs={
  outward=record('outward','earth','mars','driver',50,150),
  inward=record('inward','mars','earth','driver',0,200),
  moon=record('moon','mars','phobos',nil,50,150),
  late=record('late','earth','venus','driver',0,90)
 }
 game.alifeOnline={}
 local before=Save.encode(game.universe)
 local bodies=game.world:getBodyCount()
 local model=Traffic.snapshot(game,false)
 check(#model.rows==3 and model.transit==3,'interplanetary route filter is incorrect')
 check(model.npcs.outward.progress==.5 and model.npcs.outward.eta==50,'progress or ETA does not use saved journey clock')
 check(model.npcs.inward.from=='mars' and model.npcs.inward.to=='earth','return direction reversed')
 check(model.npcs.late.phase=='arrival pending' and model.overdue==1,'overdue arrival not shown honestly')
 check(model.npcs.outward.cargo:find('5')~=nil,'cargo manifest missing')
 check(#Traffic.snapshot(game,true).rows==4,'moon filter omitted moon transit')
 check(Save.encode(game.universe)==before and game.world:getBodyCount()==bodies,'reading monitor changed simulation')
 Traffic.toggle(game);game.npcTraffic.selected='outward'
 local w,h=love.graphics.getDimensions()
 local canvas=love.graphics.newCanvas(w,h)
 love.graphics.push('all');love.graphics.setCanvas(canvas)
 Traffic.draw(game)
 love.graphics.setCanvas();love.graphics.pop()
 canvas:newImageData():encode('png','npc-interplanetary-traffic.png')
 check(Save.encode(game.universe)==before,'drawing monitor advanced or mutated NPC records')
 local hit
 for _,candidate in ipairs(game.npcTraffic.hits) do if candidate.id=='inward' then hit=candidate end end
 check(hit~=nil,'return journey has no visual marker')
 Traffic.mousepressed(game,hit.x,hit.y,1)
 check(game.npcTraffic.selected=='inward','click did not select NPC marker')
 Traffic.keypressed(game,'space');Traffic.draw(game)
 local frozen=game.npcTraffic.model.clock
 game.universe.clock=125;Traffic.draw(game)
 check(game.npcTraffic.model.clock==frozen,'frozen view kept advancing')
 Traffic.keypressed(game,'space');Traffic.draw(game)
 check(game.npcTraffic.model.clock==125,'live view failed to resume')
 Traffic.keypressed(game,'tab');Traffic.draw(game)
 check(game.npcTraffic.model.npcs.moon~=nil,'moon toggle did not refresh route view')
 -- High-resolution mouse wheels must not create fractional row indexes.
 local view=game.npcTraffic;view.frozen=true
 for i=#view.model.rows+1,20 do view.model.rows[i]=view.model.rows[1] end
 local mouseX=love.mouse.getX;love.mouse.getX=function()return 0 end
 Traffic.wheelmoved(game,-.5)
 love.mouse.getX=mouseX
 check(view.scroll==math.floor(view.scroll) and view.scroll>0,'fractional wheel broke route paging')
 Traffic.draw(game)
 Traffic.keypressed(game,'escape')
 check(not Traffic.isOpen(game),'Escape did not close monitor')
 check(game.world:getBodyCount()==bodies,'monitor instantiated remote physics')
 -- Also render the actual seeded population without creating fake journeys.
 game.universe.npcs={[template.id]=template}
 local real=Traffic.snapshot(game,true)
 check(real.total==1,'monitor omitted real seeded record')
 print(('NPC TRAFFIC TEST PASSED (%d checks)'):format(checks))
end
