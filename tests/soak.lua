-- Long economy soak: love . --soak (SOAK_HOURS=24, SOAK_DT=1/60).
-- Not part of --test. Plays the start map with the player parked and
-- prints one line of economy numbers per game hour, then a closing table
-- of how each good's stock moved. Read it for drift: money piling up or
-- draining, stock running to zero or to the cap, idle ships, broke stations.
--   SOAK_NEWS=0         run with the news off (no stories, no price nudges),
--                       to compare against a run with it on
--   SOAK_NEWS_PLAYER=1  a scripted player: a faction ship killed out of
--                       sight every 3 h, and 40 units sold into a running
--                       shortage story every hour, to watch standing move
-- With the news on, each hour also prints a news line: stories by outlet
-- and kind, price nudges and how many sit at the cap, reported standing,
-- outlet standing, the saved size and News.update timing.
return function(game)
 local Fields=require('src.fields')
 local L=require('src.locations')
 local Stock=require('src.stockpile')
 local Econ=require('src.economy')
 local data=require('src.data')
 local hours=tonumber(os.getenv('SOAK_HOURS') or '') or 24
 local dt=tonumber(os.getenv('SOAK_DT') or '') or 1/60
 local out=os.getenv('SOAK_OUT')
 local fh=out and io.open(out,'w')
 local function say(s) print(s);if fh then fh:write(s,'\n');fh:flush() end end
 game.autosaveOff=true
 game:loadField(os.getenv('SOAK_FIELD') or Fields.start)
 local u=game.universe
 local stations={}
 for _,area in ipairs(Fields.list) do for _,id in ipairs(L.stations(area,'trade')) do stations[#stations+1]=id end end
 local function stockTotals()
  local t={}
  for _,id in ipairs(stations) do for item in pairs(data.items) do
   local n=Stock.count(u,id,item);if n>0 then t[item]=(t[item] or 0)+n end
  end end
  return t
 end
 local function zeroes(items)
  local z={}
  for _,item in ipairs(items) do local c=0
   for _,id in ipairs(stations) do if Stock.count(u,id,item)<=0 then c=c+1 end end
   z[#z+1]=item..'='..c
  end
  return table.concat(z,' ')
 end
 local watch={'deuterium_canister','steel_plate','flare'}
 for _,id in ipairs({'ammo_kinetic','missile','ammo_small','slug'}) do if data.items[id] then watch[#watch+1]=id end end
 local function sumShort() local n=0 for _,v in pairs(u.accountShort or {}) do n=n+v end return n end
 local sample
 sample=function(h,wall)
  local groups,alive,credits,broke,cr={},0,0,0,{}
  for _,r in pairs(u.npcs or {}) do if r.state~='dead' then
   alive=alive+1;local g=r.populationGroup or '?';groups[g]=(groups[g] or 0)+1
   local c=r.credits or 0;credits=credits+c;cr[#cr+1]=c;if c<100 then broke=broke+1 end
  end end
  table.sort(cr);local med=cr[math.max(1,math.floor(#cr/2))] or 0
  local st,fa,lowSt=0,0,0
  for id,v in pairs(u.accounts or {}) do if id:match('^faction:') then fa=fa+v else st=st+v;if v<1000 then lowSt=lowSt+1 end end end
  local houses,insolvent=0,0
  local ms=u.merchants and u.merchants.houses or (require('src.merchants').state(u).houses)
  for _,rec in pairs(ms or {}) do houses=houses+(rec.credits or 0);if rec.insolvent then insolvent=insolvent+1 end end
  local open,claimed,kinds=0,0,{}
  for _,o in pairs(require('src.tasks').state(u).offers) do
   if o.state=='available' then open=open+1;kinds[o.kind]=(kinds[o.kind] or 0)+1 else claimed=claimed+1 end
  end
  local kk={} for k,v in pairs(kinds) do kk[#kk+1]=k..'='..v end table.sort(kk)
  local lh=u.economyLedger and u.economyLedger.hours[math.floor(u.clock/3600)-1] or {}
  local gg={} for k,v in pairs(groups) do gg[#gg+1]=k..'='..v end table.sort(gg)
  say(('h%02d wall=%.0fs npcs=%d [%s] npcCr=%.0f med=%.0f broke=%d | stations=%.0f low=%d faction=%.0f short=%.0f | houses=%.0f insolv=%d | player=%.0f | ledger freight=%.0f bought=%.0f sold=%.0f | tasks open=%d claimed=%d [%s] | zero %s')
   :format(h,wall,alive,table.concat(gg,' '),credits,med,broke,st,lowSt,fa,sumShort(),houses,insolvent,u.credits or 0,
   lh.freight or 0,lh.bought or 0,lh.sold or 0,open,claimed,table.concat(kk,' '),zeroes(watch)))
 end
 -- open every account now, so the totals move with money, not with
 -- accounts opening on first use
 local A=require('src.accounts')
 for _,id in ipairs(stations) do A.balance(u,id) end
 for f in pairs(require('src.reputation').FACTIONS) do A.balance(u,'faction:'..f) end
 local function top(lh,kind,n)
  local t={} for k,v in pairs(lh.items or {}) do local kd,item=k:match('^(%a+):(.+)$') if kd==kind then t[#t+1]={item,v} end end
  table.sort(t,function(a,b) return a[2]>b[2] end)
  local o={} for i=1,math.min(n,#t) do o[i]=t[i][1]..'='..math.floor(t[i][2]) end
  return table.concat(o,' ')
 end
 local prevSample=sample
 local lastShort={}
 sample=function(h,wall)
  prevSample(h,wall)
  local lh=u.economyLedger and u.economyLedger.hours[math.floor(u.clock/3600)-1] or {}
  say(('    sold: %s'):format(top(lh,'sold',6)))
  say(('    bought: %s'):format(top(lh,'bought',6)))
  say(('    freight: %s'):format(top(lh,'freight',4)))
  -- who can't pay (unpaid this hour, by account) and who holds the money
  local sh={} for id,v in pairs(u.accountShort or {}) do local d=v-(lastShort[id] or 0);if d>0 then sh[#sh+1]={id,d} end;lastShort[id]=v end
  table.sort(sh,function(a,b) return a[2]>b[2] end)
  local o={} for i=1,math.min(6,#sh) do o[i]=sh[i][1]..'='..math.floor(sh[i][2])..'(has '..math.floor((u.accounts or {})[sh[i][1]] or 0)..')' end
  say('    unpaid: '..table.concat(o,' '))
  local byG={} for _,r in pairs(u.npcs or {}) do if r.state~='dead' then local g=r.populationGroup or '?';byG[g]=(byG[g] or 0)+(r.credits or 0) end end
  local gg={} for k,v in pairs(byG) do gg[#gg+1]=k..'='..math.floor(v) end table.sort(gg)
  say('    npc credits: '..table.concat(gg,' ')..(' | ships lost %d'):format(u.shipsLost or 0))
 end
 -- the news: off, or measured
 local News,Rep,Markets=require('src.news'),require('src.reputation'),require('src.markets')
 local newsOn=os.getenv('SOAK_NEWS')~='0'
 local scripted=newsOn and os.getenv('SOAK_NEWS_PLAYER')=='1'
 local realUpdate=News.update
 local nt={time=0,max=0,calls=0}
 if newsOn then
  News.update=function(...)
   local t0=love.timer.getTime();realUpdate(...)
   local d=love.timer.getTime()-t0;nt.time=nt.time+d;nt.max=math.max(nt.max,d);nt.calls=nt.calls+1
  end
 else
  News.update=function() end;News.factor=function() return 1 end
 end
 local rng=love.math.newRandomGenerator(99)
 local deedAreas={'belt','mars','earth','saturn','jupiter','milliways','venus','titan'}
 local function newsMinute(h,m)
  if not scripted then return end
  if m==30 and h%3==0 then
   local area=deedAreas[1+math.floor(rng:random()*#deedAreas)]
   Rep.shipKilled(u,{affiliation=({'estates','zhuhai','diwan','jove'})[1+math.floor(rng:random()*4)]},area)
  end
  if m==45 then
   local list=News.find(u,{kind='shortage',within=1800},5)
   local st=list[1+math.floor(rng:random()*math.max(1,#list))]
   if st and st.station then News.onTrade(u,st.station,{[st.good]=40}) end
  end
 end
 local function kv(t) local o={} for k,v in pairs(t) do o[#o+1]=k..'='..v end table.sort(o) return table.concat(o,' ') end
 local function newsSample(h)
  if not newsOn then return end
  local s=News.state(u);local since=u.clock-3600
  local byO,byK,second,mine,named,total={},{},0,0,0,0
  for i=#s.stories,1,-1 do
   local st=s.stories[i];if st.clock<=since then break end
   total=total+1;byO[st.outlet]=(byO[st.outlet] or 0)+1;byK[st.kind]=(byK[st.kind] or 0)+1
   if st.secondhand then second=second+1 end
   if st.subject=='player' then mine=mine+1;if st.named then named=named+1 end end
  end
  local nudged,capped=0,0
  for _,key in ipairs(stations) do for _,item in ipairs(Markets.products) do
   local f=News.factor(u,key,item)
   if f~=1 then nudged=nudged+1;if math.abs(f-1)>=News.T.nudgeCap-.005 then capped=capped+1 end end
  end end
  say(('    news: stories %d [%s] [%s] copies %d about-you %d named %d | nudged %d capped %d | kept %d save %dB | update %.2f ms mean %.1f worst')
   :format(total,kv(byO),kv(byK),second,mine,named,nudged,capped,#s.stories,#require('src.save').encode(u.news or {}),
   1000*nt.time/math.max(1,nt.calls),1000*nt.max))
  local o={} for _,f in ipairs(Rep.ORDER) do o[#o+1]=('%s %.0f/%.0f'):format(f,Rep.witnessed(u,f),Rep.reported(u,f)) end
  local q={} for _,x in ipairs(News.order) do q[#q+1]=('%s %.0f'):format(x,News.standing(u,x)) end
  say('    standing (witnessed/reported): '..table.concat(o,' ')..' | outlets: '..table.concat(q,' '))
  nt.time,nt.max,nt.calls=0,0,0
 end
 local first=stockTotals()
 local made0=require('src.persistence').copy(u.economyStats or {})
 local t0=os.clock()
 local steps=math.floor(3600/dt)
 say(('soak: %d h at dt=%.4f on %s, %d trade stations, news %s'):format(hours,dt,game.fieldId,#stations,newsOn and (scripted and 'on, scripted player' or 'on') or 'off'))
 sample(0,0)
 for h=1,hours do
  local per=math.floor(steps/60)
  local ok,err=xpcall(function() for m=1,60 do for _=1,per do game:step(dt) end newsMinute(h,m) end end,debug.traceback)
  if not ok then say('CRASH in hour '..h..': '..tostring(err));break end
  sample(h,os.clock()-t0)
  newsSample(h)
 end
 local last=stockTotals()
 local items={} for k in pairs(data.items) do if (first[k] or 0)>0 or (last[k] or 0)>0 then items[#items+1]=k end end
 table.sort(items,function(a,b) return ((last[a] or 0)-(first[a] or 0))<((last[b] or 0)-(first[b] or 0)) end)
 local s=u.economyStats or {}
 say('item stock_start stock_end made used hauled')
 for _,k in ipairs(items) do
  local function d(kind) return ((s[kind] or {})[k] or 0)-((made0[kind] or {})[k] or 0) end
  say(('%s %d %d %.0f %.0f %.0f'):format(k,first[k] or 0,last[k] or 0,d('made'),d('used'),d('hauled')))
 end
 -- what the economy made, valued at list price, and fuel's share of it
 local value,fuel=0,0
 for _,k in ipairs(items) do
  local made=((s.made or {})[k] or 0)-((made0.made or {})[k] or 0)
  local v=made*(data.items[k].price or 0);value=value+v
  if k==require('src.reactor_fuel').item() then fuel=v end
 end
 say(('output value %.0f, fuel %.0f (%.0f%%)'):format(value,fuel,value>0 and 100*fuel/value or 0))
 say(('ships lost %d'):format(u.shipsLost or 0))
 -- what NPC pilots earned, and the share of it that went on fuel
 local earned,fuelSpent,supplies=0,0,0
 for _,r in pairs(u.npcs or {}) do
  for _,k in ipairs({'freightEarnings','miningEarnings','wageEarnings','salvageEarnings','bountyEarnings','rareEarnings'}) do earned=earned+(r[k] or 0) end
  fuelSpent=fuelSpent+(r.fuelSpent or 0);supplies=supplies+(r.suppliesSpent or 0)
 end
 say(('npc earnings %.0f, fuel bought %.0f (%.0f%%), all supplies %.0f'):format(earned,fuelSpent,earned>0 and 100*fuelSpent/earned or 0,supplies))
 if os.getenv('SOAK_SAVE') then require('src.save').write(os.getenv('SOAK_SAVE'),game:saveState());say('saved '..os.getenv('SOAK_SAVE')) end
 if fh then fh:close() end
end
