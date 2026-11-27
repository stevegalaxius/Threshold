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
--   SOAK_FAST=1         no physics: every ship goes off-screen and A-Life
--                       advances the records by clock (every SOAK_STEP
--                       seconds, default 2, as off-screen ships are in
--                       play), with the minute chores (drills, arrivals,
--                       the economy, quests, news) run as A-Life runs them.
--                       Nothing happens on the parked map itself.
--   SOAK_PROFILE=1      sample where the time goes (LuaJIT's profiler) and
--                       print the top functions and call sites at the end
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
 -- SOAK_AGENDA=0: one job per ship, as before the agenda, to compare
 if os.getenv('SOAK_AGENDA')=='0' then require('src.tuning').agendaMaxJobs=1 end
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
 local function sumShort() local n=0 for _,v in pairs(u.accountSubsidy or {}) do n=n+v end return n end
 -- Tally the ledger per soak hour as it is written. Game hours don't track
 -- soak hours (a side scene stops the clock; the player's interplanetary
 -- flight jumps it), so reading u.economyLedger by u.clock repeated or
 -- skipped hours in physics runs.
 local Economy=require('src.economy')
 local soakLedger={items={}}
 local rawLedger=Economy.ledger
 Economy.ledger=function(uu,key,kind,n,item)
  rawLedger(uu,key,kind,n,item)
  if uu~=u or not n or n<=0 or not key then return end
  soakLedger[kind]=(soakLedger[kind] or 0)+n
  if item then local k=kind..':'..item;soakLedger.items[k]=(soakLedger.items[k] or 0)+n end
 end
 local sampleCount=0
 local ledgerAt,ledgerLast=nil,{items={}}
 local function ledgerSince()
  if ledgerAt==sampleCount then return ledgerLast end
  ledgerAt=sampleCount;ledgerLast=soakLedger;soakLedger={items={}}
  return ledgerLast
 end
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
  local lh=ledgerSince()
  local gg={} for k,v in pairs(groups) do gg[#gg+1]=k..'='..v end table.sort(gg)
  -- wildcat sites: open (bountied), crew posted/out, hoard, hunters in/out, cleared
  do
   local open,bountied,posted,out,hoard,cleared,hin,hall,fenced=0,0,0,0,0,u.sitesCleared or 0,0,0,0
   for _,inst in pairs(u.sites or {}) do if inst.crew then
    open=open+1;if inst.bounty then bountied=bountied+1 end
    for _,n in pairs(inst.hoard or {}) do hoard=hoard+n end
   end end
   for _,r in pairs(u.npcs or {}) do if r.state~='dead' and r.state~='escaped' then
    if r.wildcat then if r.garrison then posted=posted+1 else out=out+1 end end
    if r.populationGroup=='hunter' then hall=hall+1;if r.assault then hin=hin+1 end end
   end end
   local W=require('src.wildcats')
   say(('    sites open=%d bountied=%d cleared=%d | wildcats posted=%d out=%d hoard=%d | hunters=%d inside=%d | bounties paid npc=%d'):format(open,bountied,cleared,posted,out,hoard,hall,hin,u.siteBountiesPaid or 0))
  end
  say(('h%02d wall=%.0fs npcs=%d [%s] npcCr=%.0f med=%.0f broke=%d | stations=%.0f low=%d faction=%.0f subsidy=%.0f | houses=%.0f insolv=%d | player=%.0f | ledger freight=%.0f bought=%.0f sold=%.0f | tasks open=%d claimed=%d [%s] | zero %s')
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
  sampleCount=sampleCount+1
  prevSample(h,wall)
  local lh=ledgerSince()
  say(('    sold: %s'):format(top(lh,'sold',6)))
  say(('    bought: %s'):format(top(lh,'bought',6)))
  say(('    freight: %s'):format(top(lh,'freight',4)))
  do -- haulers: how many carry a load, and how many jobs at once (src/npc_agenda.lua)
   local loaded,multi,max,jobs=0,0,0,0
   for _,r in pairs(u.npcs or {}) do
    local t=r.task
    if r.state~='dead' and t and t.kind=='transport' and t.phase=='delivery' then
     local n=1+#(r.agenda or {});loaded=loaded+1;jobs=jobs+n
     if n>1 then multi=multi+1 end;if n>max then max=n end
    end
   end
   say(('    haulers loaded=%d holding several=%d jobs/loaded=%.2f max=%d'):format(loaded,multi,loaded>0 and jobs/loaded or 0,max))
  end
  -- who needed outside money this hour, by account, and what it holds
  local sh={} for id,v in pairs(u.accountSubsidy or {}) do local d=v-(lastShort[id] or 0);if d>0 then sh[#sh+1]={id,d} end;lastShort[id]=v end
  table.sort(sh,function(a,b) return a[2]>b[2] end)
  local o={} for i=1,math.min(6,#sh) do o[i]=sh[i][1]..'='..math.floor(sh[i][2])..'(has '..math.floor((u.accounts or {})[sh[i][1]] or 0)..')' end
  say('    subsidy: '..table.concat(o,' '))
  -- each faction's rolling surplus (+) or deficit (-), credits per hour
  local Acc=require('src.accounts');local fl={}
  for _,p in ipairs(Acc.parties(u)) do local f=Acc.flow(u,p);if not p:match('^station:') or math.abs(f.net)>=1000 then fl[#fl+1]=p:gsub('^station:','')..'='..math.floor(f.net) end end
  say('    flow/h: '..table.concat(fl,' '))
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
  local tick,wire={},0
  for _,x in ipairs(News.order) do local n=0 for _,l in pairs(News.tickerOf(u,x).lines) do n=n+1;if l.wire then wire=wire+1 end end tick[x]=n end
  local nudged,capped=0,0
  for _,key in ipairs(stations) do for _,item in ipairs(Markets.products) do
   local f=News.factor(u,key,item)
   if f~=1 then nudged=nudged+1;if math.abs(f-1)>=News.T.nudgeCap-.005 then capped=capped+1 end end
  end end
  say('    ticker lines: '..kv(tick)..(' (wire %d)'):format(wire))
  say(('    news: headlines %d [%s] [%s] copies %d about-you %d named %d | nudged %d capped %d | kept %d save %dB | update %.2f ms mean %.1f worst')
   :format(total,kv(byO),kv(byK),second,mine,named,nudged,capped,#s.stories,#require('src.save').encode(u.news or {}),
   1000*nt.time/math.max(1,nt.calls),1000*nt.max))
  -- this hour's deaths, as the papers see them: area, killer, faction,
  -- and which outlets cover that area
  local dd={}
  for _,e in ipairs(News.state(u).deaths or {}) do if e.clock>since then
   local cov={} for _,x in ipairs(News.order) do if News.covers(u,x,e.area) then cov[#cov+1]=x end end
   local r=e.result or {}
   dd[#dd+1]=('%s killer=%s faction=%s covered=%s'):format(tostring(e.area),tostring(r.killer),tostring(r.faction),#cov>0 and table.concat(cov,',') or 'none')
  end end
  if #dd>0 then say('    deaths: '..table.concat(dd,' | ')) end
  local o={} for _,f in ipairs(Rep.ORDER) do o[#o+1]=('%s %.0f/%.0f'):format(f,Rep.witnessed(u,f),Rep.reported(u,f)) end
  local q={} for _,x in ipairs(News.order) do q[#q+1]=('%s %.0f'):format(x,News.standing(u,x)) end
  say('    standing (witnessed/reported): '..table.concat(o,' ')..' | outlets: '..table.concat(q,' '))
  nt.time,nt.max,nt.calls=0,0,0
 end
 -- the profiler: counts samples by function and by a short call stack
 local prof
 if os.getenv('SOAK_PROFILE') then
  local P=require('jit.profile')
  prof={fn={},stack={},n=0,P=P}
  P.start('fi2',function(th,samples,vmstate)
   prof.n=prof.n+samples
   local f=P.dumpstack(th,'pl',1);prof.fn[f]=(prof.fn[f] or 0)+samples
   local st=P.dumpstack(th,'pl;',-6);prof.stack[st]=(prof.stack[st] or 0)+samples
  end)
 end
 -- the fast mode: the records only, by clock
 local fast=os.getenv('SOAK_FAST')=='1'
 local fstep=tonumber(os.getenv('SOAK_STEP') or '') or 2
 local Encounters,Squads,History=require('src.encounters'),require('src.squads'),require('src.simulation_history')
 local Director,Sats,Stalls,Rent=require('src.director'),require('src.satellites'),require('src.stalls'),require('src.berth_rent')
 if fast then game:captureALife(true);game.alifeOnline={} end
 -- where the fast mode's time goes, by part (stage1 drills, stage2
 -- arrivals, stage3 the board and arbiter, stage4 economy, quests, news)
 local ft={visits=0,encounters=0,history=0,background=0}
 local function fastMinute()
  local base=u.clock;local clk=os.clock;local t
  for c=base+fstep,base+60,fstep do
   u.clock=c
   t=clk();for id,r in pairs(u.npcs or {}) do game:alifeVisit(id,r,c,nil,nil,true,true) end;ft.visits=ft.visits+clk()-t
   t=clk();Encounters.update(game,c);Squads.update(game,c);require('src.wildcats').tick(game,c);ft.encounters=ft.encounters+clk()-t
   t=clk();History.update(game);ft.history=ft.history+clk()-t
  end
  u.clock=base+60
  game.alifeStage=1
  while game.alifeStage and game.alifeStage<=4 do
   local st=game.alifeStage;t=clk();game:alifeChore(u.clock,true);ft['stage'..st]=(ft['stage'..st] or 0)+clk()-t
  end
  game.alifeStage=nil
  t=clk();Director.update(u);Sats.tick(u);Stalls.tick(u,game);Rent.tick(u,game);ft.background=ft.background+clk()-t
 end
 -- Who died, doing what, carrying what, and to whom; and what the freight
-- fleet did with its time. Printed each hour and summed at the end.
 local lossLog,lossAll={},{}
 local tripLog={jobs={},trips=0,volume=0,vols={}}
 do
  local death=History.death
  History.death=function(u_,r,clock,area,killer,...)
   if r and not r.deathOutcomeId then
    local work=r.task or r.lastTask
    local k=killer and killer~='player' and u_.npcs and u_.npcs[killer]
    local hold=0;for item,n in pairs(r.ship and r.ship.cargo or {}) do hold=hold+n*((data.items[item] or {}).volume or 1) end
    local e={role=r.populationGroup or '?',task=work and work.kind or 'idle',area=tostring(area),
     killer=killer=='player' and 'player' or k and (k.populationGroup or '?') or (killer and 'other' or 'none'),cargo=hold}
    lossLog[#lossLog+1]=e;lossAll[#lossAll+1]=e
   end
   return death(u_,r,clock,area,killer,...)
  end
  local Tasks=require('src.tasks');local choose=Tasks.choose;local seen=setmetatable({},{__mode='k'})
  Tasks.choose=function(u_,r,...)
   local t=choose(u_,r,...)
   if t and seen[r]~=t then
    seen[r]=t
    local k=(r.populationGroup or '?')..':'..t.kind;tripLog.jobs[k]=(tripLog.jobs[k] or 0)+1
    if t.kind=='transport' then
     local v=0;for _,l in ipairs(t.manifest or {t}) do v=v+(l.amount or 0)*((data.items[l.item] or {}).volume or 1) end
     tripLog.trips=tripLog.trips+1;tripLog.volume=tripLog.volume+v;tripLog.vols[#tripLog.vols+1]=v
    end
   end
   return t
  end
 end
 local function tally(list,field)
  local c={} for _,e in ipairs(list) do c[e[field]]=(c[e[field]] or 0)+1 end
  local o={} for k,v in pairs(c) do o[#o+1]={k,v} end table.sort(o,function(a,b) return a[2]>b[2] or a[2]==b[2] and a[1]<b[1] end)
  local q={} for _,x in ipairs(o) do q[#q+1]=x[1]..'='..x[2] end return table.concat(q,' ')
 end
 local function lossLine(tag,list)
  if #list==0 then say(tag..' none');return end
  local cargo=0 for _,e in ipairs(list) do cargo=cargo+e.cargo end
  for _,e in ipairs(list) do e.roleTask=e.role..':'..e.task;e.matchup=e.killer..'>'..e.role end
  say(('%s %d | victim %s | doing %s | killer>victim %s | where %s | cargo lost %.0f m3'):format(tag,#list,tally(list,'role'),tally(list,'roleTask'),tally(list,'matchup'),tally(list,'area'),cargo))
 end
 local function freightLine()
  local v=tripLog.vols;table.sort(v)
  local function q(f) return v[math.max(1,math.floor(#v*f))] or 0 end
  local o={} for k,n in pairs(tripLog.jobs) do o[#o+1]={k,n} end table.sort(o,function(a,b) return a[2]>b[2] or a[2]==b[2] and a[1]<b[1] end)
  local j={} for i=1,math.min(10,#o) do j[i]=o[i][1]..'='..o[i][2] end
  say(('    freight: %d runs, %.0f m3, per run p25 %.1f p50 %.1f p75 %.1f m3 | jobs taken %s'):format(tripLog.trips,tripLog.volume,q(.25),q(.5),q(.75),table.concat(j,' ')))
  tripLog={jobs={},trips=0,volume=0,vols={}}
 end
 -- Who is broke (under 100 cr), by role, and what each role earned this
-- hour from freight and salvage, with what it spent on fuel and supplies.
 local lastEarn=setmetatable({},{__mode='k'})
 local function walletLine()
  local g={}
  local jobs={}
  for _,r in pairs(u.npcs or {}) do if r.state~='dead' and r.state~='escaped' then
   local grp=r.populationGroup or '?'
   local e=g[grp] or {n=0,broke=0,freight=0,salvage=0,spent=0,credits=0,trade=0,sales=0,rest=0,delta=0,brokeDoing={}};g[grp]=e
   local c=r.credits or 0;e.n=e.n+1;e.credits=e.credits+c
   local f,sv,x=r.freightEarnings or 0,r.salvageEarnings or 0,r.suppliesSpent or 0 -- (fuel is already inside suppliesSpent)
   local tr,z,ts=r.tradeSpent or 0,r.restSpend or 0,r.tradeEarnings or 0
   local by={} for k,v in pairs(r.suppliesByJob or {}) do by[k]=v end
   -- a record first seen this sample is its own baseline: no deltas yet
   local last=lastEarn[r] or {f=f,s=sv,x=x,t=tr,z=z,c=c,ts=ts,by=by}
   e.sales=e.sales+math.max(0,ts-last.ts)
   if grp=='hauler' then for k,v in pairs(by) do jobs[k]=(jobs[k] or 0)+math.max(0,v-(last.by[k] or 0)) end end
   e.trade=e.trade+math.max(0,tr-last.t);e.rest=e.rest+math.max(0,z-last.z);e.delta=e.delta+(c-(last.c or c))
   e.freight=e.freight+math.max(0,f-last.f);e.salvage=e.salvage+math.max(0,sv-last.s);e.spent=e.spent+math.max(0,x-last.x)
   lastEarn[r]={f=f,s=sv,x=x,t=tr,z=z,c=c,ts=ts,by=by}
   if c<100 then e.broke=e.broke+1;local k=r.task and r.task.kind or 'idle';e.brokeDoing[k]=(e.brokeDoing[k] or 0)+1 end
  end end
  local o={} for k in pairs(g) do o[#o+1]=k end table.sort(o)
  local q={}
  for _,k in ipairs(o) do local e=g[k]
   local d={} for kk,n in pairs(e.brokeDoing) do d[#d+1]=kk..'='..n end table.sort(d)
   -- other = everything the named lines miss (trade sales, fares, wages,
   -- bounties minus refits, ship buys...): net change minus what is named
   local other=e.delta-(e.freight+e.salvage+e.sales-e.spent-e.trade-e.rest)
   q[#q+1]=('%s %d broke of %d (mean %.0f cr, freight +%.0f, salvage +%.0f, fuel and supplies -%.0f, trade goods -%.0f, trade sales +%.0f, shore leave -%.0f, other %+.0f, net %+.0f%s)'):format(k,e.broke,e.n,e.credits/math.max(1,e.n),e.freight,e.salvage,e.spent,e.trade,e.sales,e.rest,other,e.delta,#d>0 and ('; broke doing '..table.concat(d,',')) or '')
  end
  say("    wallets (alive ships; a ship's first sample is its baseline): "..table.concat(q,' | '))
  local jj={} for k,v in pairs(jobs) do jj[#jj+1]=k..'='..math.floor(v) end table.sort(jj)
  say('    hauler supplies by job: '..table.concat(jj,' '))
 end
 -- the full event log (tests/soak_log.lua), when SOAK_LOG names a file
 local SoakLog=require('tests.soak_log')
 if os.getenv('SOAK_LOG') then SoakLog.start(game,os.getenv('SOAK_LOG')) end
 local first=stockTotals()
 local made0=require('src.persistence').copy(u.economyStats or {})
 local t0=os.clock()
 local steps=math.floor(3600/dt)
 say(('soak: %d h at dt=%.4f on %s, %d trade stations, news %s%s'):format(hours,dt,game.fieldId,#stations,newsOn and (scripted and 'on, scripted player' or 'on') or 'off',fast and (', FAST (no physics, records every %gs)'):format(fstep) or ''))
 sample(0,0)
 local stepCarry=0
 for h=1,hours do
  -- Step whole minutes of game time: floor(60/dt) steps fell ~0.9 s short
  -- each hour at dt=1/60, so the hour index read from u.clock lagged and a
  -- later hour reported the previous hour's ledger again.
  local ok,err=xpcall(function() for m=1,60 do if fast then fastMinute() else
   stepCarry=stepCarry+60/dt;local n=math.floor(stepCarry+1e-6);stepCarry=stepCarry-n
   for _=1,n do game:step(dt) end end newsMinute(h,m) SoakLog.minute() end end,debug.traceback)
  if not ok then say('CRASH in hour '..h..': '..tostring(err));break end
  sample(h,os.clock()-t0)
  newsSample(h)
  lossLine('    losses:',lossLog);lossLog={}
  freightLine()
  walletLine()
  if fast then
   local o={} for k,v in pairs(ft) do o[#o+1]={k,v} end table.sort(o,function(a,b) return a[2]>b[2] end)
   local q={} for i,x in ipairs(o) do q[i]=('%s %.1fs'):format(x[1],x[2]) end
   say('    fast time: '..table.concat(q,' '))
   for k in pairs(ft) do ft[k]=0 end
  end
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
 lossLine('losses, all hours:',lossAll)
 SoakLog.finish()
 -- what NPC pilots earned, and the share of it that went on fuel
 local earned,fuelSpent,supplies=0,0,0
 for _,r in pairs(u.npcs or {}) do
  for _,k in ipairs({'freightEarnings','miningEarnings','wageEarnings','salvageEarnings','bountyEarnings','rareEarnings'}) do earned=earned+(r[k] or 0) end
  fuelSpent=fuelSpent+(r.fuelSpent or 0);supplies=supplies+(r.suppliesSpent or 0)
 end
 say(('npc earnings %.0f, fuel bought %.0f (%.0f%%), all supplies %.0f'):format(earned,fuelSpent,earned>0 and 100*fuelSpent/earned or 0,supplies))
 if prof then
  prof.P.stop()
  local function top(t,k)
   local a={} for x,v in pairs(t) do a[#a+1]={x,v} end table.sort(a,function(p,q) return p[2]>q[2] end)
   for i=1,math.min(k,#a) do say(('  %5.1f%%  %s'):format(100*a[i][2]/math.max(1,prof.n),a[i][1])) end
  end
  say(('profile: %d samples; top functions'):format(prof.n));top(prof.fn,40)
  say('top call stacks (innermost last)');top(prof.stack,30)
 end
 if os.getenv('SOAK_SAVE') then require('src.save').write(os.getenv('SOAK_SAVE'),game:saveState());say('saved '..os.getenv('SOAK_SAVE')) end
 if fh then fh:close() end
end
