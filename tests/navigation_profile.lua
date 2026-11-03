-- Reproducible simulation-only timings; rendering and display FPS are excluded.
return function(game)
 local Nav,M,T=require('src.local_navigation'),require('src.mining'),require('src.tuning')
 local originals={waypoint=Nav.waypoint,steer=Nav.steer,position=M.position}
 local times,calls,peaks={},{},{}
 local function wrap(owner,name)
  local fn=owner[name]
  owner[name]=function(...)
   local start=love.timer.getTime()
   local a,b,c,d,e=fn(...)
   local elapsed=love.timer.getTime()-start
   times[name]=(times[name] or 0)+elapsed;calls[name]=(calls[name] or 0)+1
   peaks[name]=math.max(peaks[name] or 0,elapsed)
   return a,b,c,d,e
  end
 end
 wrap(Nav,'waypoint');wrap(Nav,'steer');wrap(M,'position')
 T.dev.god=true;game.autosaveOff=true
 for _,area in ipairs({'phobos','deimos','earth'}) do
  love.math.setRandomSeed(8128);game:newUniverse();game:loadField(area)
  local callbacks,unique,chains=0,{},0
  local extent=game.arenaRadius
  game.world:queryBoundingBox(-extent,-extent,extent,extent,function(fixture)
   callbacks=callbacks+1
   if fixture:getShape():getType()=='chain' then chains=chains+1 end
   unique[fixture]=true;return true
  end)
  local count=0;for _ in pairs(unique) do count=count+1 end
  print(('%s broad phase: %d callbacks, %d unique fixtures, %d chain callbacks'):format(area,callbacks,count,chains))
  times,calls,peaks={},{},{}
  local steps={};local total=love.timer.getTime()
  for i=1,60*120 do
   local start=love.timer.getTime();game:step(1/120)
   steps[i]=(love.timer.getTime()-start)*1000
  end
  total=love.timer.getTime()-total;table.sort(steps)
  print(('%s simulation: total %.3fs mean %.3fms p99 %.3fms max %.3fms'):format(
   area,total,total/#steps*1000,steps[math.floor(#steps*.99)],steps[#steps]))
  for _,name in ipairs({'waypoint','steer','position'}) do
   print(('  %s: %d calls total %.3fs max %.3fms'):format(name,calls[name] or 0,times[name] or 0,(peaks[name] or 0)*1000))
  end
 end
 Nav.waypoint,Nav.steer,M.position=originals.waypoint,originals.steer,originals.position
end
