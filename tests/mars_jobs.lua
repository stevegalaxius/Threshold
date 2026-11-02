return function(game)
 local A=require('src.alife');local J=require('src.jobs');local Save=require('src.save')
 local checks=0
 local function check(ok,msg) assert(ok,msg);checks=checks+1 end
 game:loadField('phobos')
 for _,area in ipairs({'phobos','deimos'}) do
  game:loadField(area)
  local st=game:locationEntity(area..'/strip_mine')
  check(st and st.surfaceMine,'missing surface mine')
  check(st.body:getAngularVelocity()==0,'mine rotates independently of terrain')
  check(st.dock.a<0,'mine dock does not face space')
 end
 game:loadField('venus');game:captureALife(true)
 local u=game.universe
 local traders={}
 for _,r in pairs(u.npcs) do if r.home=='mars' then traders[#traders+1]=r end end
 table.sort(traders,function(a,b)return a.id<b.id end)
 for _,r in ipairs(traders) do A.advance(r,100,u) end
 local active,waiting=0,0
 for _,r in ipairs(traders) do if r.job then active=active+1 else waiting=waiting+1 end end
 check(active==4 and waiting==5,'reservations failed to limit mine traffic')
 local r=traders[1]
 for _=1,50 do
  local t=(r.state=='docked' and r.untilTime or r.arrive)+.01
  A.advance(r,t,u)
  if (u.jobs.delivered[r.tradeHome] or 0)>0 then break end
 end
 check((u.jobs.delivered[r.tradeHome] or 0)>0,'ore never reached Mars')
 check((r.ship.cargo.martian_ore or 0)==0,'delivery did not unload cargo')
 local encoded=Save.encode(game:saveState());local state=assert(Save.decode(encoded))
 check(state.jobs and state.jobs.delivered[r.tradeHome]>0,'save lost mine economy')
 local dead=traders[2];dead.state='dead'
 J.state(u,10000)
 for _,m in pairs(u.jobs.mines) do check(not m.reservations[dead.id],'dead trader held reservation') end
 -- Exercise physical tractor docking and job pickup on both actual mines.
 for _,area in ipairs({'phobos','deimos'}) do
  game:loadField(area);game:captureALife(true)
  u.npcs={[r.id]=r};r.state='travel';r.area=area;r.home='mars'
  r.tradeHome='mars/station_alpha';r.tripDestination=area;r.onRoundTrip=true
  r.route=A.roundTrip('mars',area,u.clock,r.tradeHome)
  for i,id in ipairs(r.route) do if id==area..'/strip_mine' then r.index=i;break end end
  r.job={mine=area,home=r.tradeHome,amount=10,phase='pickup'}
  u.jobs.mines[area].stock=20;u.jobs.mines[area].reservations[r.id]=10
  r.depart=u.clock;r.arrive=u.clock+100;r.pose=nil;r.offset=nil
  r.ship.cargo={}
  local st=game:locationEntity(area..'/strip_mine')
  local x,y=require('src.ai').stopPoint(st)
  r.pose={x=x,y=y,a=st.dock.a+math.pi,vx=0,vy=0,w=0,clock=u.clock}
  local e=A.wake(game,r)
  game.player.body:setPosition(x+3000,y)
  game:beginDocking(e,st,1)
  for _=1,2400 do
   game:step(1/120)
   if e.dockState and e.dockState.done then break end
  end
  check(not e.dead and e.dockState and e.dockState.done,area..': tractor docking failed')
  game:updateDockedShip(e,100)
  check(not e.dockState and r.job.phase=='delivery',area..': pickup failed to launch')
  check(e.cargo.martian_ore==10 and r.ship.cargo.martian_ore==10,area..': physical cargo differs from job')
 end
 print(('MARS JOBS TEST PASSED (%d checks)'):format(checks))
end
