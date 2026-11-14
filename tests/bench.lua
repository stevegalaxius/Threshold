-- Frame-cost benchmark: love . --benchtest [npcs]
-- Fills the start area with A-Life traders, then times fixed sim steps and
-- (with a window) world draws, listing the costliest functions.
return function(game)
 local P=require('src.population');local Prof=require('src.profiler');local Game=require('src.game')
 local Render=require('src.render')
 local want=tonumber(os.getenv('BENCH_NPCS') or '') or 200
 local roles={'trader','miner','trader'}
 local made,tries=0,0
 if not game.player then game:spawnPlayer(game.playerHull) end
 game.alifeOnline=game.alifeOnline or {}
 while made<want and tries<want*20 do
  tries=tries+1
  local role=roles[tries%#roles+1]
  local r=P.spawn(game,game.fieldId,role,false)
  if r then made=made+1 end
 end
 local A=require('src.alife');local px,py=game.player.body:getPosition();local clock0=game.universe.clock
 local woke=0;local wakeCap=tonumber(os.getenv('BENCH_ONLINE') or '') or math.huge
 for _,r in pairs(game.universe.npcs) do
  if r.area==game.fieldId and r.state=='travel' and not game.alifeOnline[r.id] and woke<wakeCap then
   local a=love.math.random()*math.pi*2;local d=1500+love.math.random()*9000
   r.pose={x=px+math.cos(a)*d,y=py+math.sin(a)*d,a=a,vx=0,vy=0,w=0,clock=clock0}
   A.wake(game,r);woke=woke+1
  end
 end
 print('bench: woke',woke)
 local online=0;for _ in pairs(game.alifeOnline or {}) do online=online+1 end
 print(('bench: spawned %d records (%d tries), field %s'):format(made,tries,tostring(game.fieldId)))
 local STEP=1/120
 for _=1,240 do game:step(STEP) end -- settle: wake ships, build bodies
 online=0;for _ in pairs(game.alifeOnline or {}) do online=online+1 end
 local ships=0;for _,e in ipairs(game.entities) do if e.kind=='ship' then ships=ships+1 end end
 print(('bench: %d online, %d ship entities, %d entities'):format(online,ships,#game.entities))
 local clock=love.timer.getTime
 do local c={} for _,b in ipairs(game.world:getBodies()) do for _,f in ipairs(b:getFixtures()) do if not f:isSensor() then local sh=f:getShape();local k=b:getType()..'/'..sh:getType();local n=sh:getType()=='chain' and sh:getChildCount() or 1;c[k]=(c[k] or 0)+n end end end
 for k,v in pairs(c) do print('  fix',k,v) end end
 local n=tonumber(os.getenv("BENCH_STEPS") or "") or 600
 local times={};local t=clock()
 for i=1,n do local t0=clock();game:step(STEP);times[i]=(clock()-t0)*1000 end
 local stepMs=(clock()-t)*1000/n
 table.sort(times)
 print(('bench: step median %.2f ms, p99 %.2f ms, worst %.2f ms'):format(times[math.ceil(n/2)],times[math.ceil(n*.99)],times[n]))
 local drawMs
 if love.graphics and love.window and love.window.isOpen() then
  t=clock()
  for _=1,120 do game:frame(STEP) love.graphics.clear() Render.world(game) love.graphics.present() end
  drawMs=(clock()-t)*1000/120
 end
 print(('bench: step %.3f ms (x1.2 steps/frame at 144fps = %.2f ms), draw %s ms, budget 6.94 ms'):format(stepMs,stepMs*1.2,drawMs and ('%.3f'):format(drawMs) or 'n/a'))
 -- sampling profile (LuaJIT jit.profile): where the time really goes
 local function sample(label,run)
  local ok,prof=pcall(require,'jit.profile')
  if not ok then return end
  local hits,total={},0
  prof.start('fi1',function(th,samples)
   local stack=prof.dumpstack(th,'pl\n',4)
   for line in stack:gmatch('[^\n]+') do hits[line]=(hits[line] or 0)+samples;break end
   local key='  '..prof.dumpstack(th,'f<',3);hits[key]=(hits[key] or 0)+samples
   total=total+samples
  end)
  run()
  prof.stop()
  local list={};for k,v in pairs(hits) do list[#list+1]={k,v} end
  table.sort(list,function(a,b) return a[2]>b[2] end)
  print('bench: '..label..' hot lines/stacks ('..total..' samples)')
  for i=1,math.min(30,#list) do print(('%6.1f%%  %s'):format(list[i][2]*100/total,list[i][1])) end
 end
 do -- what the slow steps spend their time on
  Prof.toggle(Game)
  local spike,slow={},0
  for _=1,1200 do
   local before={};for k,v in pairs(Prof.acc) do before[k]=v end
   local t0=clock();game:step(STEP);local ms=(clock()-t0)*1000
   if ms>12 then slow=slow+1;for k,v in pairs(Prof.acc) do spike[k]=(spike[k] or 0)+v-(before[k] or 0) end end
  end
  Prof.toggle(Game)
  local list={};for k,v in pairs(spike) do list[#list+1]={k,v*1000/math.max(1,slow)} end
  table.sort(list,function(a,b) return a[2]>b[2] end)
  print('bench: '..slow..' slow steps (>12 ms), average per slow step:')
  for i=1,math.min(30,#list) do print(('  %-40s %8.2f ms'):format(list[i][1],list[i][2])) end
 end
 sample('step',function() for _=1,120 do game:step(STEP) end end)
 if drawMs then sample('draw',function() for _=1,120 do game:frame(STEP) Render.world(game) end end) end
 -- breakdown
 do local W=getmetatable(game.world).__index;local up=W.update;local acc=0
  W.update=function(w,...) local t0=clock();local a,b=up(w,...);acc=acc+clock()-t0;return a,b end
  for _=1,120 do game:step(STEP) end
  W.update=up;print(('bench: box2d world:update %.3f ms/step'):format(acc*1000/120))
 end
 Prof.toggle(Game)
 for k in pairs(Prof.acc) do Prof.acc[k]=nil end
 for _=1,n do game:step(STEP) end
 if drawMs then for _=1,120 do game:frame(STEP) Render.world(game) end end
 local list={}
 for k,v in pairs(Prof.acc) do list[#list+1]={k,v*1000,Prof.calls[k]} end
 table.sort(list,function(a,b) return a[2]>b[2] end)
 for i=1,math.min(45,#list) do print(('  %-40s %8.1f ms total  %7d calls'):format(list[i][1],list[i][2],list[i][3])) end
 Prof.toggle(Game)
end
