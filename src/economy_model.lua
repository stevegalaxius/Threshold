--[[
	A static model of the whole economy: what it has to make, where, and
	what has to be hauled where, worked out from the data files in a second
	instead of found out from a soak.

	  love . --econmodel            print the report (ECON_OUT=file.json
	                                also writes the model as JSON)
	  love . --econcapture          play SOAK_HOURS (default 2) fast hours and
	                                write data/economy_baseline.lua: the
	                                service demand the model can't derive
	                                (fuel, ammo, repairs, food eaten, ships
	                                sold) and what the miners bring in

	How it works
	  Final demand is what stations use up for their own sake: the use_*
	  facilities, food and water, plus the measured service demand and ship
	  sales from the baseline. It is pushed back up every recipe that makes
	  a good: each maker takes a share of the demand by its rated capacity,
	  and its inputs become demand in turn. Facilities that share a pool
	  (one installation, several recipes) share its processing units.

	  Then every unit is placed: made at its makers, used at its takers.
	  Within a planet system goods go maker to taker; between systems they
	  go hub to hub (src/economy.lua routing), nearest surplus first. Each
	  flow's volume times its trip time is hold the fleet has to have out
	  on the lanes, against what the haulers actually have.

	What it flags
	  pool over 100%     a facility can't make what's asked of it
	  no source          something is used that nothing makes or mines
	  start              a new game opens with a good short of its target
	                     (--econmodel only: a new world opens at equilibrium)
	  input short        a recipe's inputs exceed what can be made of them
	  fleet load         hold-hours an hour the lanes need, vs the fleet
	  freight share      freight pay per unit against the good's price:
	                     cheap bulk on a long lane is a lane haulers starve
	  slow lane          a flow whose trip time is long against its stock
	                     buffer (the system runs dry before it arrives)

	It's a capacity model, not a simulation: no prices, no timing, no
	storage. Anything it says is short is short however the economy plays;
	anything it says is fine can still go wrong in the timing.
]]
local M={}

local function hours(s) return s/3600 end
local function fmtN(n) return n>=10 and ('%.0f'):format(n) or ('%.1f'):format(n) end

-- Every installation in the world layout, with its pool of processing units.
local function installations()
 local W=require('src.world_layout')
 local D=require('data.industry')
 local out={}
 local function add(entry)
  for id,inst in pairs(entry.facilities or {}) do
   local def=D.facilities[inst.type or id]
   if def then
    out[#out+1]={station=entry.id,id=id,policy=def.policy,capacity=inst.capacity,
     recipes=inst.recipes or def.recipes,surface=inst.surface}
   end
  end
 end
 for _,entries in pairs(W.stations) do for _,e in ipairs(entries) do add(e) end end
 for _,e in pairs(W.specials) do if e.id then add(e) end end
 table.sort(out,function(a,b) return a.station..a.id<b.station..b.id end)
 return out
end

local function baseline()
 local ok,b=pcall(require,'data.economy_baseline')
 return ok and b or nil
end

-- Units per hour of each output and input when a recipe runs one
-- processing unit an hour.
local function perUnit(c)
 local C=require('src.commodities')
 local t=c.time or 1
 local outs,ins={},{}
 for _,o in ipairs(C.outputs(c)) do
  if o.item then outs[o.item]=(outs[o.item] or 0)+(o.n or 1)/t end
 end
 for _,i in ipairs(C.inputs(c)) do ins[i.item]=(ins[i.item] or 0)+i.n/t end
 return outs,ins
end

function M.build(opts)
 opts=opts or {}
 local C=require('src.commodities')
 local L=require('src.locations')
 local E=require('src.economy')
 local data=require('src.data')
 local Fields=require('src.fields')
 local Food=require('src.food')
 local base=opts.baseline or baseline()
 local clock=opts.clock or 0

 local m={goods={},stations={},pools={},flows={},systems={},issues={},fleet={},baseline=base and base.meta or nil}
 local function good(item)
  local g=m.goods[item]
  if not g then
   local d=data.items[item] or {}
   g={item=item,name=d.name or item,price=d.price or 0,volume=d.volume or 1,
    capacity=0,final=0,required=0,made=0,external=0,makers={},takers={}}
   m.goods[item]=g
  end
  return g
 end
 local function station(id)
  local s=m.stations[id]
  if not s then
   local p=L.byId[id]
   s={id=id,name=p and p.name or id,area=p and p.area or '?',system=p and E.hubRoot(p.area) or '?',hub=p and p.hub or false,make={},use={}}
   m.stations[id]=s
  end
  return s
 end
 local function demand(st,item,n,why)
  if n<=0 then return end
  local g=good(item);g.final=g.final+n
  local s=station(st);s.use[item]=(s.use[item] or 0)+n
  g.takers[st]=(g.takers[st] or 0)+n
  g.why=g.why or {};g.why[why]=(g.why[why] or 0)+n
 end

 -- 1. pools and what each can make
 local makersOf={}   -- item -> { {pool, recipe, out per unit} }
 for _,inst in ipairs(installations()) do
  local pool={key=inst.station..'|'..inst.id,station=inst.station,id=inst.id,policy=inst.policy,capacity=math.abs(inst.capacity),used=0,recipes={}}
  if inst.capacity<0 then
   -- a consumer: use_water, burn_hydrogen and the like
   for _,r in ipairs(inst.recipes) do
    local c=C.byId[r];local outs=perUnit(c)
    for item,n in pairs(outs) do demand(inst.station,item,-inst.capacity*n,'use') end
   end
  else
   m.pools[#m.pools+1]=pool
   for _,r in ipairs(inst.recipes) do
    local c=C.byId[r]
    if c and not c.stockless then
     local outs,ins=perUnit(c)
     pool.recipes[r]={outs=outs,ins=ins,made=0}
     for item,n in pairs(outs) do
      local g=good(item);g.capacity=g.capacity+inst.capacity*n
      -- what the cheapest way to make a unit costs in inputs at list price
      local cost=0;for input,k in pairs(ins) do cost=cost+k/n*((data.items[input] or {}).price or 0) end
      if next(ins) and (not g.recipeCost or cost<g.recipeCost) then g.recipeCost=cost end
      makersOf[item]=makersOf[item] or {}
      table.insert(makersOf[item],{pool=pool,recipe=r,per=n})
     end
    elseif c and c.stockless then
     pool.recipes[r]={outs={},ins=select(2,perUnit(c)),made=0,ship=c.outputs[1].hull}
    end
   end
  end
 end

 -- 2. final demand: food, the baseline's service use and ship sales
 for id,p in pairs(L.byId) do
  if p.kind=='station' and not p.accessOf then
   local use=Food.rates(id)
   if use>0 then demand(id,Food.item,use,'eaten') end
  end
 end
 -- service demand: measured live from the running economy (opts.live),
 -- or from the captured baseline
 if opts.live and opts.universe then
  local uu=opts.universe
  for id,p in pairs(L.byId) do
   if p.kind=='station' and not p.accessOf then
    for item in pairs(data.items) do
     if item~=Food.item then local n=E.serviceRate(uu,id,item);if n>0.01 then demand(id,item,n,'service') end end
    end
   end
  end
  m.live=true
 elseif base then
  for st,items in pairs(base.service or {}) do
   for item,n in pairs(items) do if item~=Food.item then demand(st,item,n,'service') end end
  end
 end
 -- ships sold: each assembly hall's share of its hulls' sales
 local shipDemand={}
 if base then for hull,n in pairs(base.ships or {}) do shipDemand[hull]=n end end
 for _,pool in ipairs(m.pools) do
  for r,rec in pairs(pool.recipes) do if rec.ship then
   local want=shipDemand[rec.ship] or 0
   if want>0 then
    shipDemand[rec.ship]=0
    rec.made=want
    pool.used=pool.used+want*(C.byId[r].time or 1)
    for item,n in pairs(rec.ins) do demand(pool.station,item,want*n*(C.byId[r].time or 1),'ships') end
   end
  end end
 end

 local routes={}
 local function routeHours(a,b)
  if a==b then return 0,0 end
  local k=a..'>'..b
  if routes[k] then return routes[k][1],routes[k][2] end
  local T=require('src.transport')
  local q=T.quote({source=a,target=b,item='steel_plate',amount=1},clock)
  routes[k]={hours(T.duration(q,nil,clock)),q.routeAU or 0}
  return routes[k][1],routes[k][2]
 end

 -- 3. push demand back up the recipes. Each round places what's newly
 -- required at each taker on makers: first its own system's (by spare
 -- capacity), then anyone's, and their inputs become required in turn
 -- at the maker. Mined goods (the baseline) cover what they can first,
 -- nearest first the same way. Cycles stop after enough rounds.
 local Wsys=function(st) return station(st).system end
 -- the dark grids keep to themselves as src/economy.lua routes them: a
 -- dark station serves dark stations and the fences (the cartel's goods
 -- reach the white network only there), and a white station serves white
 -- ones, or a dark one short of something no dark station makes
 local Dark=require('src.dark')
 local function side(st) return Dark.isDarkNode(st) end
 local darkMade={}
 for item,list in pairs(makersOf) do for _,mk in ipairs(list) do if side(mk.pool.station) then darkMade[item]=true end end end
 local function serves(from,to,item)
  local df,dt=side(from),side(to)
  if df==dt then return true end
  if df then return Dark.isFence(to) end
  return not darkMade[item]
 end
 local spare={}   -- maker -> units of output it can still make
 for item,list in pairs(makersOf) do for _,mk in ipairs(list) do spare[mk]=mk.pool.capacity*mk.per end end
 local mines={}   -- item -> { station -> units an hour left }
 if base then for st,items in pairs(base.minedAt or {}) do for item,n in pairs(items) do
  mines[item]=mines[item] or {};mines[item][st]=n;good(item).external=(good(item).external or 0)+n
 end end end
 -- Fixed plants (policy 'fixed') run at their rated pace whatever anyone
 -- wants, until their own storage fills: shipworks welding frames, the
 -- wells, the farms. Their output is on offer like a mine's, and their
 -- inputs are demand at full rate.
 local forced={}
 for item,list in pairs(makersOf) do for _,mk in ipairs(list) do
  if mk.pool.policy=='fixed' then
   local n=0;for _ in pairs(mk.pool.recipes) do n=n+1 end
   local units=mk.pool.capacity/math.max(1,n)
   local rec=mk.pool.recipes[mk.recipe]
   if next(rec.ins) then
    local out=units*mk.per
    spare[mk]=0
    mines[item]=mines[item] or {};mines[item][mk.pool.station]=(mines[item][mk.pool.station] or 0)+out
    mk.pool.used=mk.pool.used+units;rec.made=rec.made+out
    local g=good(item);g.made=g.made+out;g.forced=(g.forced or 0)+out
    local s=station(mk.pool.station);s.make[item]=(s.make[item] or 0)+out
    for input,k in pairs(rec.ins) do forced[#forced+1]={input,mk.pool.station,units*k} end
   end
  end
 end end
 local function place(item,taker,n,nextP)
  local g=good(item);g.required=g.required+n
  local left=n
  -- mined supply, own system first
  local mm=mines[item]
  if mm then
   -- (in station order, so the model comes out the same every run)
   local order={};for st in pairs(mm) do order[#order+1]=st end;table.sort(order)
   for pass=1,2 do for _,st in ipairs(order) do local have=mm[st]
    if left<=0 then break end
    if have>0 and serves(st,taker,item) and (pass==2 or Wsys(st)==Wsys(taker)) then
     local k=math.min(have,left);mm[st]=have-k;left=left-k
     g.externalUsed=(g.externalUsed or 0)+k
     g.makers[st]=(g.makers[st] or 0)+k
     g.links=g.links or {};g.links[#g.links+1]={st,taker,k}
    end
   end end
  end
  local makers=makersOf[item]
  if left<=1e-9 then return end
  if not makers or #makers==0 then g.unsourced=(g.unsourced or 0)+left;return end
  local function give(mk,share)
   local units=share/mk.per
   spare[mk]=spare[mk]-share
   mk.pool.used=mk.pool.used+units
   local rec=mk.pool.recipes[mk.recipe];rec.made=rec.made+share
   g.made=g.made+share
   local ms=mk.pool.station
   g.makers[ms]=(g.makers[ms] or 0)+share
   g.links=g.links or {};g.links[#g.links+1]={ms,taker,share}
   local s=station(ms);s.make[item]=(s.make[item] or 0)+share
   for input,k in pairs(rec.ins) do
    local need=units*k
    nextP[#nextP+1]={input,ms,need}
    local gi=good(input);gi.takers[ms]=(gi.takers[ms] or 0)+need
    local si=station(ms);si.use[input]=(si.use[input] or 0)+need
    gi.feeds=gi.feeds or {};gi.feeds[item]=true
   end
  end
  -- own system's spare, then anyone's spare, then (over capacity) by size
  for pass=1,3 do
   if left<=1e-9 then break end
   local pick,cap={},0
   for _,mk in ipairs(makers) do
    local room=pass<3 and math.max(0,spare[mk]) or mk.pool.capacity*mk.per
    if room>0 and serves(mk.pool.station,taker,item) and (pass~=1 or Wsys(mk.pool.station)==Wsys(taker)) then pick[#pick+1]={mk,room};cap=cap+room end
   end
   if cap>0 and pass==2 then
    -- anyone's spare: nearest first, as the freight board picks
    for _,p in ipairs(pick) do p[3]=routeHours(p[1].pool.station,taker) end
    table.sort(pick,function(a,b) return a[3]<b[3] end)
    for _,p in ipairs(pick) do
     if left<=1e-9 then break end
     local k=math.min(left,p[2]);give(p[1],k);left=left-k
    end
   elseif cap>0 then
    local take=pass<3 and math.min(left,cap) or left
    for _,p in ipairs(pick) do give(p[1],take*p[2]/cap) end
    left=left-take
   end
  end
 end
 local pending={}
 for item,g in pairs(m.goods) do for st,n in pairs(g.takers) do pending[#pending+1]={item,st,n} end end
 for _,f in ipairs(forced) do
  pending[#pending+1]=f
  local gi=good(f[1]);gi.takers[f[2]]=(gi.takers[f[2]] or 0)+f[3]
  gi.why=gi.why or {};gi.why['fixed plant']=(gi.why['fixed plant'] or 0)+f[3]
  local si=station(f[2]);si.use[f[1]]=(si.use[f[1]] or 0)+f[3]
 end
 table.sort(pending,function(a,b) return a[1]..a[2]<b[1]..b[2] end)
 for round=1,40 do
  local nextP={}
  for _,p in ipairs(pending) do place(p[1],p[2],p[3],nextP) end
  pending=nextP
  if #pending==0 then break end
 end

 -- 4. per system balance and the flows between them
 local function hubOf(system)
  for id,s in pairs(m.stations) do if s.system==system and s.hub then return id end end
  for _,p in pairs(L.byId) do if p.kind=='station' and p.hub and E.hubRoot(p.area)==system then return p.id end end
 end
 local lanes={}
 local function flow(item,a,b,n,kind)
  if n<=1e-6 or a==b then return end
  local key=a..'>'..b
  local lane=lanes[key]
  if not lane then
   local h,au=routeHours(a,b)
   lane={source=a,target=b,hours=h,au=au,kind=kind,items={},volume=0,units=0}
   lanes[key]=lane
  end
  local g=good(item)
  lane.items[item]=(lane.items[item] or 0)+n
  lane.volume=lane.volume+n*g.volume
  lane.units=lane.units+n
 end
 -- Every link (maker -> taker, units an hour) travels as the economy
 -- routes it: inside a system straight there; between systems maker ->
 -- its hub -> the taker's hub -> taker, skipping hubs a system hasn't got.
 for item,g in pairs(m.goods) do
  for _,l in ipairs(g.links or {}) do
   local a,b,n=l[1],l[2],l[3]
   local sa,sb=station(a).system,station(b).system
   if sa==sb then flow(item,a,b,n,'local')
   -- dark goods go to a fence straight from the dark station (src/economy.lua)
   elseif Dark.isDarkNode(a) and Dark.isFence(b) then flow(item,a,b,n,'fence')
   else
    local ha,hb=hubOf(sa),hubOf(sb)
    local path={a}
    if ha and ha~=a then path[#path+1]=ha end
    if hb and hb~=path[#path] then path[#path+1]=hb end
    if b~=path[#path] then path[#path+1]=b end
    for i=2,#path do flow(item,path[i-1],path[i],n,(path[i-1]==ha and path[i]==hb) and 'trunk' or (i==2 and 'to hub' or 'from hub')) end
   end
  end
  local sys={}
  for st,n in pairs(g.makers) do local s=station(st).system;sys[s]=sys[s] or {make=0,use=0};sys[s].make=sys[s].make+n end
  for st,n in pairs(g.takers) do local s=station(st).system;sys[s]=sys[s] or {make=0,use=0};sys[s].use=sys[s].use+n end
  for s,b in pairs(sys) do
   local row=m.systems[s] or {system=s,hub=hubOf(s),goods={}};m.systems[s]=row
   row.goods[item]={make=b.make,use=b.use}
  end
  g.links=nil
 end
 for _,lane in pairs(lanes) do m.flows[#m.flows+1]=lane end
 table.sort(m.flows,function(a,b) return a.volume*a.hours>b.volume*b.hours end)

 -- 5. the fleet: hold the haulers have, against hold-hours the lanes need
 local T=require('src.tuning')
 local need=0
 for _,f in ipairs(m.flows) do
  -- a round trip: out loaded, back (mostly) empty
  f.holdHours=f.volume*f.hours*2
  need=need+f.holdHours
  local pay=0
  for item,n in pairs(f.items) do
   local g=good(item)
   local per=g.volume*(T.freightCreditsPerM3+f.au*T.freightCreditsPerM3AU)+g.price*T.freightValueShare
   g.freight=g.freight or {};g.freight[#g.freight+1]={lane=f.source..'>'..f.target,per=per,share=g.price>0 and per/g.price or 0,n=n}
   pay=pay+per*n
  end
  f.pay=pay
 end
 local fleet={haulers=0,hold=0,byGroup={}}
 local u=opts.universe
 if u then
  for _,r in pairs(u.npcs or {}) do
   local grp=r.populationGroup or '?'
   local hull=r.ship and data.hulls[r.ship.hull]
   local hold=hull and hull.hold or 0
   if grp=='hauler' or grp=='courier' then fleet.haulers=fleet.haulers+1;fleet.hold=fleet.hold+hold end
   fleet.byGroup[grp]=(fleet.byGroup[grp] or 0)+1
  end
 end
 fleet.need=need
 m.fleet=fleet

 -- 5a. order sizes: the economy reorders a good when a station drops
 -- below its target, so a lane's typical order is about one target's
 -- worth (src/economy.lua; a trunk lot between hubs). What that order pays
 -- per hour of flying, against every other lane's, says whether haulers
 -- will ever pick it up: a tiny lot of a compact good sits on the board.
 local Tr=require('src.transport')
 local rates={}
 if u then
  -- hubs and moon customs stock for their stations (src/economy.lua hubWants)
  local all={}
  for _,area in ipairs(require('src.fields').list) do for _,st in ipairs(L.stations(area,'trade')) do all[#all+1]=st end end
  local plan=E.hubWants(u,all)
  for _,f in ipairs(m.flows) do
   f.lots={}
   local trunk=f.kind=='trunk'
   for item,n in pairs(f.items) do
    local g=good(item)
    local tgt=math.max(E.target(u,f.target,item) or 0,plan.want[f.target] and plan.want[f.target][item] or 0)
    local cap=math.max(1,math.floor((trunk and T.trunkLot or T.orderMaxVolume)/g.volume))
    -- a buyer below target orders up to max(2x target, target + its lot)
    local lot=math.max(1,math.min(cap,math.max(tgt,E.orderLot(u,f.target,item))))
    local q=Tr.quote({source=f.source,target=f.target,item=item,amount=lot},clock)
    local pay=Tr.payment(q)
    local perHour=pay/math.max(.1,f.hours*2)
    f.lots[item]={lot=lot,pay=pay,perHour=perHour,volume=lot*g.volume}
    rates[#rates+1]=perHour
   end
  end
  table.sort(rates)
  m.medianPayPerHour=rates[math.max(1,math.floor(#rates/2))] or 0
  -- 5a'. trips: the fleet's limit is trips as much as hold. Each order is
  -- a trip of its own (a lane's lots are counted apart; a hauler that
  -- takes two on one lane only helps), no bigger than a typical hold, and
  -- takes the round trip plus docking (src/transport.lua Transport.duration)
  local avgHold=fleet.haulers>0 and fleet.hold/fleet.haulers or 0
  local trips,tripHours=0,0
  for _,f in ipairs(m.flows) do
   f.trips=0
   for item,n in pairs(f.items) do local lot=f.lots[item] if lot then
    local g=good(item)
    local load=math.max(g.volume,avgHold>0 and math.min(lot.volume,avgHold) or lot.volume)
    local t=n*g.volume/load
    f.trips=f.trips+t
   end end
   f.tripHours=f.trips*(f.hours*2+.1)
   trips=trips+f.trips;tripHours=tripHours+f.tripHours
  end
  fleet.trips,fleet.tripHours,fleet.avgHold=trips,tripHours,avgHold
 end

 -- 5b. stock buffers: every station keeps hours of what it uses on hand
 -- (src/economy.lua E.target). Starting short of that is a one-off demand
 -- on top of the steady flow; spare capacity has to fill it.
 if u then
  local Stock=require('src.stockpile')
  for item,g in pairs(m.goods) do
   local want,have=0,0
   for _,area in ipairs(Fields.list) do for _,st in ipairs(L.stations(area,'trade')) do
    want=want+(E.target(u,st,item) or 0);have=have+Stock.count(u,st,item)
   end end
   g.buffer,g.stock=want,have
   local gap=math.max(0,want-have)
   local room=math.max(0,g.capacity+(g.external or 0)-g.required)
   g.fillHours=gap>0 and (room>0 and gap/room or math.huge) or 0
  end
 end

 -- 6. issues
 local function issue(kind,sev,text,item,where) m.issues[#m.issues+1]={kind=kind,severity=sev,text=text,item=item,where=where} end
 for _,p in ipairs(m.pools) do
  p.load=p.capacity>0 and p.used/p.capacity or 0
  if p.load>1.001 then issue('pool',p.load>2 and 3 or 2,('%s at %s needs %.0f%% of its capacity'):format(p.id,station(p.station).name,p.load*100),nil,p.station) end
 end
 for item,g in pairs(m.goods) do
  if (g.unsourced or 0)>0.01 then issue('source',3,('%s: %.1f/h used that nothing makes or mines'):format(g.name,g.unsourced),item) end
  if (g.unrouted or 0)>0.01 then issue('route',2,('%s: %.1f/h has no hub to travel through'):format(g.name,g.unrouted),item) end
  -- load is what the economy draws on, not what fixed plants turn out:
  -- a farm or a well runs flat out whether or not anyone wants it all
  g.load=g.capacity>0 and ((g.forced or 0)>0 and math.min(g.made,g.required) or g.made)/g.capacity or 0
  -- the price rule: a recipe sells at (inputs + its work) x T.priceMargin,
  -- so at list prices every recipe earns at least its inputs back
  if g.recipeCost and g.price>0 and g.recipeCost*require('src.tuning').priceMargin>g.price*1.001 then issue('price',2,('%s: list price %.0f is under its inputs x margin (%.0f)'):format(g.name,g.price,g.recipeCost*require('src.tuning').priceMargin),item) end
  -- a new world opens at equilibrium: nothing starts short of its target
  if opts.opening and (g.buffer or 0)-(g.stock or 0)>math.max(1,.02*(g.buffer or 0)) then issue('start',3,('%s: a new game opens with %.0f on hand against %.0f wanted'):format(g.name,g.stock,g.buffer),item) end
  if (g.fillHours or 0)>6 then issue('buffer',g.fillHours>24 and 2 or 1,('%s: stations want %.0f on hand and hold %.0f; spare capacity takes %s to fill the gap'):format(g.name,g.buffer,g.stock,g.fillHours==math.huge and 'forever' or ('%.0f h'):format(g.fillHours)),item) end
  -- lanes where hauling a unit pays more than the unit is worth: a buyer
  -- short of it can't price it high enough to cover the trip
  local over,worst,moved=0,nil,0
  for _,f in ipairs(g.freight or {}) do
   if f.share>1 and f.n>.5 then over=over+1;moved=moved+f.n;if not worst or f.share>worst.share then worst=f end end
  end
  if worst then issue('freight',1,('%s: %d lane%s (%.0f/h) cost more to haul than the goods are worth; worst %s at %.0f%%'):format(g.name,over,over>1 and 's' or '',moved,worst.lane:gsub('station:',''),worst.share*100),item) end
 end
 local floor_=(m.medianPayPerHour or 0)*.25
 local thin={}
 for _,f in ipairs(m.flows) do
  for item,l in pairs(f.lots or {}) do
   if l.perHour<floor_ and f.hours>.25 then
    local k=item;thin[k]=thin[k] or {n=0,worst=nil,units=0}
    local t=thin[k];t.n=t.n+1;t.units=t.units+f.items[item]
    if not t.worst or l.perHour<t.worst.perHour then t.worst={perHour=l.perHour,lot=l.lot,pay=l.pay,lane=f.source..'>'..f.target,hours=f.hours} end
   end
  end
 end
 for item,t in pairs(thin) do
  local w=t.worst
  issue('lot',t.units>5 and 2 or 1,('%s: %d lane%s (%.0f/h) order lots too small to be worth flying; worst %s, %s units for %.0f cr over %.1f h each way (%.0f cr/h, typical %.0f)'):format(
   good(item).name,t.n,t.n>1 and 's' or '',t.units,w.lane:gsub('station:',''),fmtN(w.lot),w.pay,w.hours,w.perHour,m.medianPayPerHour),item,w.lane)
 end
 for _,f in ipairs(m.flows) do
  if f.hours>2 then
   local names={};for item,n in pairs(f.items) do names[#names+1]=('%s %.0f/h'):format(good(item).name,n) end
   table.sort(names)
   issue('slow',f.hours>4 and 2 or 1,('%s -> %s takes %.1f h for %s'):format(station(f.source).name,station(f.target).name,f.hours,table.concat(names,', ')),nil,f.source..'>'..f.target)
  end
 end
 if fleet.hold>0 then
  local load=need/fleet.hold
  fleet.load=load
  if load>.6 then issue('fleet',load>1 and 3 or 2,('the lanes need %.0f m3 of hold out at all times; haulers have %.0f (%.0f%%)'):format(need,fleet.hold,load*100)) end
 end
 if fleet.haulers>0 and fleet.tripHours then
  local busy=fleet.tripHours/fleet.haulers
  fleet.tripLoad=busy
  if busy>.6 then
   local worst=m.flows[1]
   for _,f in ipairs(m.flows) do if (f.tripHours or 0)>(worst.tripHours or 0) then worst=f end end
   issue('trips',busy>.9 and 3 or 2,('steady flow alone takes %.0f trips an hour, %.0f%% of the %d haulers\' time; busiest lane %s>%s at %.0f trips/h'):format(fleet.trips,busy*100,fleet.haulers,(worst.source:gsub('station:','')),(worst.target:gsub('station:','')),worst.trips or 0))
  end
 end
 table.sort(m.issues,function(a,b) return a.severity>b.severity or a.severity==b.severity and a.text<b.text end)
 return m
end

-- The report, as plain text lines.
function M.report(m)
 local out={}
 local function say(f,...) out[#out+1]=select('#',...)>0 and f:format(...) or f end
 say('ECONOMY MODEL%s',m.baseline and (' (baseline: %s)'):format(m.baseline.note or '?') or ' (no baseline: service demand and ship sales left out)')
 say('')
 say('Issues, worst first:')
 for _,i in ipairs(m.issues) do say('  [%s] %-7s %s',({'.','!','!!'})[i.severity],i.kind,i.text) end
 say('')
 say('%-26s %9s %9s %9s %6s  %s','good','final/h','needed/h','cap/h','load','made at')
 local goods={};for _,g in pairs(m.goods) do goods[#goods+1]=g end
 table.sort(goods,function(a,b) if a.load~=b.load then return a.load>b.load end return a.name<b.name end)
 for _,g in ipairs(goods) do
  local at={};for st,n in pairs(g.makers) do at[#at+1]=('%s %.0f'):format((m.stations[st] or {}).name or st,n) end
  table.sort(at)
  say('%-26s %9.1f %9.1f %9.1f %5.0f%%  %s',g.name,g.final,g.required,g.capacity,g.load*100,table.concat(at,', '))
 end
 say('')
 say('Busiest lanes (hold-hours an hour, round trip):')
 for i=1,math.min(25,#m.flows) do
  local f=m.flows[i];local items={}
  for item,n in pairs(f.items) do items[#items+1]=('%s %.1f'):format(m.goods[item].name,n) end
  table.sort(items)
  say('  %7.0f  %-6s %s -> %s  %.1f h  %.1f m3/h  [%s]',f.holdHours,f.kind,(m.stations[f.source] or {}).name or f.source,(m.stations[f.target] or {}).name or f.target,f.hours,f.volume,table.concat(items,', '))
 end
 say('')
 local fl=m.fleet
 say('Fleet: %d haulers with %.0f m3 of hold; lanes need %.0f m3 out at all times%s',fl.haulers or 0,fl.hold or 0,fl.need or 0,fl.load and (' (%.0f%%)'):format(fl.load*100) or '')
 if fl.trips then say('Trips: steady flow takes %.0f trips an hour (%.0f hauler-hours, %.0f%% of the fleet; typical hold %.0f m3)',fl.trips,fl.tripHours,(fl.tripLoad or 0)*100,fl.avgHold or 0) end
 return out
end

-- Minimal JSON for the viewer.
local function json(v,seen)
 local t=type(v)
 if t=='table' then
  if #v>0 or next(v)==nil then
   local parts={};for i=1,#v do parts[i]=json(v[i]) end
   if #v>0 then return '['..table.concat(parts,',')..']' end
   return '{}'
  end
  local parts={}
  for k,x in pairs(v) do if type(x)~='function' then parts[#parts+1]=json(tostring(k))..':'..json(x) end end
  table.sort(parts)
  return '{'..table.concat(parts,',')..'}'
 elseif t=='string' then
  return '"'..v:gsub('[%c"\\]',function(c) return ({['"']='\\"',['\\']='\\\\',['\n']='\\n'})[c] or ('\\u%04x'):format(c:byte()) end)..'"'
 elseif t=='number' then
  if v~=v or v==math.huge or v==-math.huge then return '0' end
  return (('%.4g'):format(v))
 elseif t=='boolean' then return tostring(v) end
 return 'null'
end
M.json=json

function M.run(game)
 local m=M.build({universe=game.universe,clock=game.universe and game.universe.clock or 0,opening=true})
 for _,line in ipairs(M.report(m)) do print(line) end
 local path=os.getenv('ECON_OUT')
 if path then
  local f=assert(io.open(path,'w'));f:write(json(m));f:close()
  print('wrote '..path)
 end
 return m
end

-- In-game: the A-Life debug suite (F6) shows the model of the running
-- universe. Live mode reads service demand from the economy's own measured
-- rates instead of the baseline, so it follows the game as it plays.
M.view={live=true}
function M.panel(game,Slab)
 local v=M.view
 local function rebuild(live)
  v.live=live
  local t=os.clock()
  v.model=M.build({universe=game.universe,clock=game.universe.clock,live=live})
  v.at,v.ms=game.universe.clock,(os.clock()-t)*1000
 end
 if Slab.Button('Model live demand') then rebuild(true) end
 Slab.SameLine()
 if Slab.Button('Model baseline demand') then rebuild(false) end
 if v.model then
  Slab.SameLine()
  if Slab.Button('Save JSON') then
   love.filesystem.write('econ_model.json',json(v.model))
   v.saved=love.filesystem.getSaveDirectory()..'/econ_model.json'
  end
 end
 if v.saved then Slab.Text('Saved '..v.saved..' (open it in tools/econmodel/viewer.html)') end
 local m=v.model
 if not m then Slab.Text('Build the model to see what the economy has to make and haul, and where it falls short.');return end
 local age=(game.universe.clock-(v.at or 0))/60
 Slab.Text(('%s demand, built %.0f min ago of game time in %.0f ms'):format(v.live and 'Live' or 'Baseline',age,v.ms or 0))
 local fl=m.fleet
 if fl and fl.hold and fl.hold>0 then Slab.Text(('Haulers %d, hold %.0f m3; lanes keep %.0f m3 out (%.0f%%)'):format(fl.haulers,fl.hold,fl.need,(fl.load or 0)*100)) end
 if fl and fl.trips then Slab.Text(('Trips %.0f an hour, %.0f%% of the haulers\' time'):format(fl.trips,(fl.tripLoad or 0)*100)) end
 local red,amber,grey={1,.45,.4},{1,.75,.3},{.7,.75,.8}
 Slab.Separator()
 Slab.Text('Issues',{Color={1,1,1}})
 for i,iss in ipairs(m.issues) do
  if i>14 then Slab.Text(('  ... %d more'):format(#m.issues-14),{Color=grey});break end
  Slab.Text('  '..iss.text,{Color=iss.severity==3 and red or iss.severity==2 and amber or grey})
 end
 Slab.Separator()
 Slab.Text('Tightest goods (needed against capacity)',{Color={1,1,1}})
 local gs={};for _,g in pairs(m.goods) do if g.required>0 then gs[#gs+1]=g end end
 table.sort(gs,function(a,b) return a.load>b.load end)
 for i=1,math.min(16,#gs) do local g=gs[i]
  local at={};for st,n in pairs(g.makers) do at[#at+1]={(m.stations[st] or {}).name or st,n} end
  table.sort(at,function(a,b) return a[2]>b[2] end)
  local where=at[1] and (' top: %s %.0f'):format(at[1][1],at[1][2]) or ''
  Slab.Text(('  %-22s %4.0f%%  %7.1f / %7.1f per h  stock %s/%s%s'):format(g.name,g.load*100,g.required,g.capacity,
   g.stock and ('%.0f'):format(g.stock) or '?',g.buffer and ('%.0f'):format(g.buffer) or '?',where),{Color=g.load>1 and red or g.load>.85 and amber or nil})
 end
 Slab.Separator()
 Slab.Text('Busiest facilities',{Color={1,1,1}})
 local ps={};for _,p in ipairs(m.pools) do if p.used>0 then ps[#ps+1]=p end end
 table.sort(ps,function(a,b) return a.load>b.load end)
 for i=1,math.min(10,#ps) do local p=ps[i]
  Slab.Text(('  %4.0f%%  %s at %s (%s)'):format(p.load*100,p.id,(m.stations[p.station] or {}).name or p.station,p.policy),{Color=p.load>1 and red or p.load>.85 and amber or nil})
 end
 Slab.Separator()
 Slab.Text('Busiest lanes (hold kept out, round trip)',{Color={1,1,1}})
 for i=1,math.min(10,#m.flows) do local f=m.flows[i]
  local items={};for item,n in pairs(f.items) do items[#items+1]={m.goods[item].name,n} end
  table.sort(items,function(a,b) return a[2]>b[2] end)
  Slab.Text(('  %5.0f m3  %s -> %s, %.1f h: %s'):format(f.holdHours,(m.stations[f.source] or {}).name or f.source,(m.stations[f.target] or {}).name or f.target,f.hours,
   items[1] and ('%s %.0f/h'):format(items[1][1],items[1][2]) or ''))
 end
end

-- Play some fast hours and write what the model can't derive: service
-- demand by station (fuel, ammo, repair plates, modules sold, food),
-- ships sold by hull and goods the miners bring in, all per game hour.
function M.capture(game)
 local hoursN=tonumber(os.getenv('SOAK_HOURS') or '') or 2
 local u=game.universe
 local E=require('src.economy')
 local A=require('src.alife')
 local Tasks=require('src.tasks')
 game.autosaveOff=true;game:captureALife(true);require('src.supplies').universe=u
 local service,ships,mined={},{},{}
 local lastDeliver
 local consume,stat=E.consume,E.stat
 E.consume=function(uu,key,item,n,industrial)
  if uu==u and not industrial and n and n>0 then
   service[key]=service[key] or {};service[key][item]=(service[key][item] or 0)+n
  end
  return consume(uu,key,item,n,industrial)
 end
 local Mining=require('src.mining')
 E.stat=function(uu,kind,item,n)
  if uu==u and n and n>0 then
   if kind=='madeShips' then ships[item]=(ships[item] or 0)+n end
   -- the drills: src/mining.lua delivers, then counts it made
   local d=lastDeliver
   if kind=='made' and d and d[2]==item and d[3]==n then mined[d[1]]=mined[d[1]] or {};mined[d[1]][item]=(mined[d[1]][item] or 0)+n end
   lastDeliver=nil
  end
  return stat(uu,kind,item,n)
 end
 local Jobs=require('src.jobs');local deliver=Jobs.deliver
 Jobs.deliver=function(uu,node,item,n,...) if uu==u and n and n>0 then lastDeliver={require('src.locations').canonical(node),item,n} end return deliver(uu,node,item,n,...) end
 local start=u.clock
 for clock=start,start+hoursN*3600-1,5 do
  u.clock=clock;Mining.produce(game,clock)
  for _,r in pairs(u.npcs) do A.advance(r,clock,u,game) end
  if clock%60==0 then Tasks.clean(u,clock);E.update(u,clock);require('src.quests').update(u,clock);require('src.arbiter').update(u,clock);require('src.population').update(game,clock) end
 end
 E.consume,E.stat,Jobs.deliver=consume,stat,deliver
 do local used,denied=require('src.npc').searchStats(u);print(('board searches: %d made, %d turned away for want of allowance'):format(used,denied)) end
 local function per(t) local o={};for k,v in pairs(t) do o[k]=v/hoursN end return o end
 local lines={'-- Written by love . --econcapture (src/economy_model.lua). Per game hour.','return {'}
 local function ser(t,ind)
  local keys={};for k in pairs(t) do keys[#keys+1]=k end;table.sort(keys)
  local p={}
  for _,k in ipairs(keys) do local v=t[k]
   if type(v)=='table' then p[#p+1]=ind..('[%q]={\n'):format(k)..ser(v,ind..' ')..ind..'},'
   elseif type(v)=='string' then p[#p+1]=ind..('[%q]=%q,'):format(k,v)
   else p[#p+1]=ind..('[%q]=%.4g,'):format(k,v) end
  end
  return table.concat(p,'\n')..'\n'
 end
 local svc={};for st,items in pairs(service) do svc[st]=per(items) end
 lines[#lines+1]=ser({meta={hours=hoursN,note=('%g fast hours from a new game'):format(hoursN)}},' ')
 lines[#lines+1]=' service={\n'..ser(svc,'  ')..' },'
 lines[#lines+1]=' ships={\n'..ser(per(ships),'  ')..' },'
 local mn={};for st,items in pairs(mined) do mn[st]=per(items) end
 lines[#lines+1]=' minedAt={\n'..ser(mn,'  ')..' },'
 lines[#lines+1]='}'
 local path=os.getenv('ECON_BASELINE') or 'data/economy_baseline.lua'
 local f=assert(io.open(path,'w'));f:write(table.concat(lines,'\n')..'\n');f:close()
 print('wrote '..path)
end

return M
