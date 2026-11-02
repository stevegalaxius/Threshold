return function(game)
 local Index=require('src.sleeper_index')
 local T=require('src.tuning')
 local checks=0
 local function check(ok,msg) assert(ok,msg);checks=checks+1 end
 game.autosaveOff=true
 love.math.setRandomSeed(157)
 game:loadField('saturn')
 game:updateSleepers()
 check(#game.sleepers>9000,'fixture no longer contains Saturn dense rings')
 local count=0
 for _,e in ipairs(game.entities) do if e.kind=='asteroid' then count=count+1 end end
 count=count+#game.sleepers
 local function verifyPopulation()
  local seen,n={},0
  for _,e in ipairs(game.entities) do
   if e.kind=='asteroid' then check(not e.sleep,'active rock still marked asleep');seen[e]=true;n=n+1 end
  end
  for i,e in ipairs(game.sleepers) do
   check(not seen[e] and e.sleep and e.sleepSlot==i,'sleeper lost, duplicated or assigned stale slot')
   seen[e]=true;n=n+1
  end
  check(n==count,'sleep/wake changed the rock population')
 end
 verifyPopulation()
 local firstIndex
 for _,position in ipairs({{0,-70500},{0,-55200},{55000,0},{0,0},{0,-90000}}) do
  local cx,cy=unpack(position)
  for _,zoom in ipairs({T.minZoom,.5,1.6}) do
   local sw,sh=love.graphics.getDimensions()
   local hw,hh=sw/2/zoom+300,sh/2/zoom+300
   for _,time in ipairs({0,500,20000}) do
    game.time=time
    local expected,actual={},{}
    for _,e in ipairs(game.sleepers) do
     local x,y=game:sleeperPos(e)
     if math.abs(x-cx)<hw and math.abs(y-cy)<hh then expected[e]=true end
    end
    for _,e in ipairs(Index.candidates(game,cx,cy,math.sqrt(hw*hw+hh*hh))) do
     local x,y=game:sleeperPos(e)
     if math.abs(x-cx)<hw and math.abs(y-cy)<hh then actual[e]=true end
    end
    for e in pairs(expected) do check(actual[e],'index culled visible orbiting rock') end
    for e in pairs(actual) do check(expected[e],'index moved a visible rock') end
   end
  end
  firstIndex=firstIndex or game.sleeperIndex
  check(game.sleeperIndex==firstIndex,'unchanged sleeper list rebuilt the index')
 end
 -- Teleport the observer between ring bands, including onto the last list
 -- element. Compare wakes against a brute-force distance check each time.
 game.time=100
 for pass=1,4 do
  local target=game.sleepers[#game.sleepers]
  local px,py=game:sleeperPos(target)
  local wake={}
  for _,e in ipairs(game.sleepers) do
   local x,y=game:sleeperPos(e)
   if (x-px)^2+(y-py)^2<T.sleepNear^2 then wake[e]=true end
  end
  game.player.body:setPosition(px,py)
  game.sleepTick=T.sleepEvery
  game:updateSleepers()
  for e in pairs(wake) do check(not e.sleep and not e.body:isDestroyed(),'nearby rock failed to wake') end
  verifyPopulation()
 end
 -- An empty set of orbital bands should require no orbit evaluation.
 local n=0
 for _ in ipairs(Index.candidates(game,0,-200000,2000)) do n=n+1 end
 check(n==0,'empty radial range scanned distant rocks')
 print(('SLEEPER INDEX TEST PASSED (%d checks; %d rocks retained)'):format(checks,count))
end
