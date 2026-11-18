-- News soak: love . --newssoak (not part of --test).
--   NEWS_SOAK_HOURS=48   game hours per run
--   NEWS_SOAK_OUT=path   also write the report to a file
--   NEWS_SOAK_FULL=1     also run the full game (A-Life, flight) for
--                        NEWS_SOAK_FULL_HOURS (default 6) with news on
-- Runs the economy offline twice from the same fresh universe, once with
-- the news and once without, and compares them hour by hour: what the
-- papers print, how far stories push prices, whether NPC traders chase
-- them, whether shortages get better or worse. It also plays a scripted
-- player (kills out of sight, trades into stories) to watch standing
-- drift, caps and floors, and times News.update and price lookups.
return function(game)
 local Game=require('src.game')
 local Fields=require('src.fields')
 local L=require('src.locations')
 local Stock=require('src.stockpile')
 local Econ=require('src.economy')
 local Markets=require('src.markets')
 local News=require('src.news')
 local Rep=require('src.reputation')
 local Save=require('src.save')
 local data=require('src.data')
 local hours=tonumber(os.getenv('NEWS_SOAK_HOURS') or '') or 48
 local out=os.getenv('NEWS_SOAK_OUT')
 local fh=out and io.open(out,'w')
 local function say(s) print(s);if fh then fh:write(s,'\n');fh:flush() end end
 local stations={}
 for _,area in ipairs(Fields.list) do for _,id in ipairs(L.stations(area,'trade')) do stations[#stations+1]=id end end

 local realUpdate,realFactor=News.update,News.factor
 local function fresh()
  local g=Game.new();g.autosaveOff=true;g:loadField(Fields.start)
  for _=1,60 do g:step(1/60) end
  require('src.supplies').universe=g.universe
  return g
 end

 -- one offline run; withNews=false turns the papers off entirely
 local function run(withNews,label,player)
  News.update=withNews and realUpdate or function() end
  News.factor=withNews and realFactor or function() return 1 end
  local g=fresh();local u=g.universe
  math.randomseed(1234);if love and love.math then love.math.setRandomSeed(1234) end
  local stats={hours={},label=label,newsTime=0,newsMax=0,newsCalls=0}
  local priceCalls=0;local realPrice=Markets.price
  Markets.price=function(...) priceCalls=priceCalls+1;return realPrice(...) end
  local start=u.clock
  local lastStory=0
  local rng=love.math.newRandomGenerator(99)
  local deedAreas={'belt','mars','earth','saturn','jupiter','milliways','venus','titan'}
  for h=1,hours do
   local hs={stories={},kinds={},rumour=0,second=0,player=0,named=0,blamed=0,quest=0}
   for m=1,60 do
    local clock=start+(h-1)*3600+m*60
    u.clock=clock
    Econ.update(u,clock)
    local t0=love.timer.getTime()
    News.update(u,clock,g)
    local dt=love.timer.getTime()-t0
    stats.newsTime=stats.newsTime+dt;stats.newsMax=math.max(stats.newsMax,dt);stats.newsCalls=stats.newsCalls+1
    -- the scripted player: a kill out of sight every few hours, and
    -- selling into whatever story is running at a station
    if player and withNews then
     if m==30 and h%3==0 then
      local area=deedAreas[1+math.floor(rng:random()*#deedAreas)]
      local victim={affiliation=({'estates','zhuhai','diwan','jove'})[1+math.floor(rng:random()*4)]}
      Rep.shipKilled(u,victim,area)
     end
     if m==45 then
      local list=News.find(u,{kind='shortage',within=1800},5)
      local st=list[1+math.floor(rng:random()*math.max(1,#list))]
      if st and st.station then News.onTrade(u,st.station,{[st.good]=40}) end
     end
    end
   end
   -- what was printed this hour
   local s=News.state(u)
   for i=#s.stories,1,-1 do
    local st=s.stories[i]
    if st.clock<=start+(h-1)*3600 then break end
    hs.stories[st.outlet]=(hs.stories[st.outlet] or 0)+1
    hs.kinds[st.kind]=(hs.kinds[st.kind] or 0)+1
    if st.rumour then hs.rumour=hs.rumour+1 end
    if st.secondhand then hs.second=hs.second+1 end
    if st.subject=='player' then hs.player=hs.player+1;if st.named then hs.named=hs.named+1 end;if st.blamed then hs.blamed=hs.blamed+1 end end
   end
   -- prices: the news multiplier everywhere, and the quoted price vs list
   local nf,capped,sumDev,maxF,minF=0,0,0,1,1
   for _,key in ipairs(stations) do for _,item in ipairs(Markets.products) do
    local f=realFactor(u,key,item)
    if f~=1 then nf=nf+1;sumDev=sumDev+math.abs(f-1);if math.abs(f-1)>=News.T.nudgeCap-.005 then capped=capped+1 end end
    maxF=math.max(maxF,f);minF=math.min(minF,f)
   end end
   hs.nudged,hs.capped,hs.meanDev,hs.maxF,hs.minF=nf,capped,nf>0 and sumDev/nf or 0,maxF,minF
   -- shortages and the market's own price spread
   local shortages,ratioSum,ratioN,hi=0,0,0,0
   for _,key in ipairs(stations) do
    for item,since in pairs(Stock.record(u,key).shortages or {}) do shortages=shortages+1 end
    for item,r in pairs((Markets.state(u).prices[key]) or {}) do ratioSum=ratioSum+math.abs(r-1);ratioN=ratioN+1;if r>=1.8 then hi=hi+1 end end
   end
   hs.shortages,hs.priceDev,hs.priceHi=shortages,ratioN>0 and ratioSum/ratioN or 0,hi
   local lh=u.economyLedger and u.economyLedger.hours[math.floor(u.clock/3600)-1] or {}
   hs.bought,hs.sold,hs.freight=lh.bought or 0,lh.sold or 0,lh.freight or 0
   -- standing
   hs.rep={};for _,f in ipairs(Rep.ORDER) do hs.rep[f]={w=Rep.witnessed(u,f),r=Rep.reported(u,f)} end
   hs.outlets={};for _,o in ipairs(News.order) do hs.outlets[o]=News.standing(u,o) end
   hs.storyCount=#s.stories
   local nudgeEntries=0;for _,items in pairs(s.nudges) do for _,list in pairs(items) do nudgeEntries=nudgeEntries+#list end end
   hs.nudgeEntries=nudgeEntries
   hs.saveBytes=#Save.encode(u.news or {})
   hs.priceCalls=priceCalls;priceCalls=0
   stats.hours[h]=hs
  end
  Markets.price=realPrice
  News.update,News.factor=realUpdate,realFactor
  stats.u=u
  return stats
 end

 local function kv(t) local o={} for k,v in pairs(t) do o[#o+1]=k..'='..(type(v)=='number' and (v%1==0 and v or ('%.1f'):format(v)) or tostring(v)) end table.sort(o) return table.concat(o,' ') end

 say(('news soak: %d h offline, %d trade stations, %d market goods'):format(hours,#stations,#Markets.products))
 local wall=os.clock()
 local off=run(false,'no news',false)
 local on=run(true,'news',true)
 say(('wall %.0fs'):format(os.clock()-wall))
 say('')
 say('h | stories by outlet | kinds | rumour 2nd-hand about-you(named,blamed) | nudged capped meanDev min..max | shortages on/off | priceDev on/off | >=1.8x on/off | bought on/off | sold on/off | stories kept, nudges, save bytes | price calls on/off')
 for h=1,hours do
  local a,b=on.hours[h],off.hours[h]
  say(('h%02d | %s | %s | %d %d %d(%d,%d) | %d %d %.3f %.2f..%.2f | %d/%d | %.3f/%.3f | %d/%d | %.0f/%.0f | %.0f/%.0f | %d %d %d | %d/%d'):format(h,
   kv(a.stories),kv(a.kinds),a.rumour,a.second,a.player,a.named,a.blamed,
   a.nudged,a.capped,a.meanDev,a.minF,a.maxF,a.shortages,b.shortages,a.priceDev,b.priceDev,a.priceHi,b.priceHi,
   a.bought,b.bought,a.sold,b.sold,a.storyCount,a.nudgeEntries,a.saveBytes,a.priceCalls,b.priceCalls))
 end
 say('')
 say('standing (witnessed/reported) every 6 h with the scripted player:')
 for h=6,hours,6 do
  local a=on.hours[h];local o={}
  for _,f in ipairs(Rep.ORDER) do o[#o+1]=('%s %.0f/%.0f'):format(f,a.rep[f].w,a.rep[f].r) end
  say(('h%02d %s'):format(h,table.concat(o,'  ')))
  say(('    outlets %s'):format(kv(a.outlets)))
 end
 say('')
 -- headline accuracy: how far the printed numbers sit from the truth
 local s=News.state(on.u);local n,err,over,under,rum,byOutlet=0,0,0,0,0,{}
 for _,st in ipairs(s.stories) do
  if st.reported and st.real then
   n=n+1;local e=st.reported-st.real;err=err+math.abs(e)
   if e>.05 then over=over+1 elseif e<-.05 then under=under+1 end
   local b=byOutlet[st.outlet] or {n=0,e=0};byOutlet[st.outlet]=b;b.n=b.n+1;b.e=b.e+e
  elseif st.rumour then rum=rum+1 end
 end
 say(('accuracy over the last %d stories: %d with a fact, mean |printed-real| %.2f, %d inflated, %d played down, %d rumours'):format(#s.stories,n,n>0 and err/n or 0,over,under,rum))
 local o={} for k,b in pairs(byOutlet) do o[#o+1]=('%s mean bias %+.2f over %d'):format(k,b.e/b.n,b.n) end table.sort(o)
 say('  '..table.concat(o,' | '))
 -- which goods and stations the papers obsess over
 local goods,places={},{}
 for _,st in ipairs(s.stories) do if st.good then goods[st.good]=(goods[st.good] or 0)+1 end;if st.station then places[st.station]=(places[st.station] or 0)+1 end end
 local function topn(t,k) local a={} for x,v in pairs(t) do a[#a+1]={x,v} end table.sort(a,function(p,q) return p[2]>q[2] end) local o={} for i=1,math.min(k,#a) do o[i]=a[i][1]..'='..a[i][2] end return table.concat(o,' ') end
 say('  goods in the news: '..topn(goods,10))
 say('  stations in the news: '..topn(places,10))
 say(('news update: %d calls, %.2f ms mean, %.2f ms worst'):format(on.newsCalls,1000*on.newsTime/math.max(1,on.newsCalls),1000*on.newsMax))
 -- totals
 local function total(st,key) local t=0 for h=1,hours do t=t+st.hours[h][key] end return t end
 say(('totals on/off: bought %.0f/%.0f  sold %.0f/%.0f  freight %.0f/%.0f  shortage-hours %d/%d'):format(
  total(on,'bought'),total(off,'bought'),total(on,'sold'),total(off,'sold'),total(on,'freight'),total(off,'freight'),total(on,'shortages'),total(off,'shortages')))

 -- the full game with news on, if asked: catches anything online-only
 if os.getenv('NEWS_SOAK_FULL') then
  local fh2=tonumber(os.getenv('NEWS_SOAK_FULL_HOURS') or '') or 6
  local g=fresh();local u=g.universe
  say(('full game: %d h at 1/30 s'):format(fh2))
  local t0=os.clock()
  for h=1,fh2 do
   local ok,e=xpcall(function() for _=1,3600*30 do g:step(1/30) end end,debug.traceback)
   if not ok then say('CRASH in hour '..h..': '..tostring(e));break end
   local s=News.state(u);local byK={};local mine=0
   for _,st in ipairs(s.stories) do byK[st.kind]=(byK[st.kind] or 0)+1;if st.subject=='player' then mine=mine+1 end end
   say(('  h%d wall %.0fs stories %d [%s] about you %d, deaths reported %d'):format(h,os.clock()-t0,#s.stories,kv(byK),mine,byK.killed or 0))
  end
 end
 if fh then fh:close() end
end
