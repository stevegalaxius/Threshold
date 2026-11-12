return function(game)
 local S,E,I=require('src.stockpile'),require('src.economy'),require('src.industry')
 local function world()return {clock=0,stations={},npcs={}} end
 local function set(u,key,item,n)S.stock(u,key,S.shopFor(key,item))[item]=n end
 local key='station:mars_3'
 local function scarce(first)
  local u=world();set(u,key,'iron_ore',10);set(u,key,'steel_plate',0);set(u,key,'empty_canister',0)
  u.clock=3600;S.count(u,key,first)
  return S.count(u,key,'steel_plate'),S.count(u,key,'empty_canister'),S.count(u,key,'iron_ore')
 end
 local a,b,c=scarce('steel_plate');local d,e,f=scarce('empty_canister')
 assert(a==d and b==e and c==f,'stock query order changed resource allocation')
 assert(a>0 and b>0 and a*2+math.ceil(b*.5-1e-9)+c==10,'scarce ore was lost or entirely monopolized')
 local u=world();local ceres='station:belt_1'
 set(u,ceres,'empty_canister',0);set(u,key,'empty_canister',1000)
 E.update(u,0)
 local imported=false
 for _,offer in pairs(require('src.tasks').state(u).offers) do
  if offer.item=='empty_canister' and offer.target==ceres then imported=true end
 end
 assert(imported,'producer could not import its own scarce input')
 local r={id='dry-customer',ship={hull='intaki_wisp',loadout=require('src.data').hulls.intaki_wisp.loadout,cargo={},fuelCharge=0,fuelInitialized=true}}
 set(u,ceres,'deuterium_canister',0)
 require('src.supplies').refill(r,ceres,u)
 assert((r.ship.cargo.deuterium_canister or 0)==0,'refill created emergency fuel')
 local worker={id='work-power',power=100,ship={hull='intaki_wisp',loadout=require('src.data').hulls.intaki_wisp.loadout,cargo={deuterium_canister=2},fuelInitialized=true,fuelCharge=0}}
 assert(require('src.npc_actions').power({r=worker},5,30)==30 and worker.power==70,'work did not spend capacitor')
 assert(worker.ship.cargo.deuterium_canister==2 and worker.ship.fuelCharge==0,'work ran a second reactor step')
 -- Operating buffers follow output room, not historical input consumption.
 local factory='station:earth_1';local v=world()
 set(v,factory,'electronics',0);set(v,factory,'silicon',0);set(v,factory,'industrial_acids',0)
 assert(E.target(v,factory,'silicon')==8 and E.target(v,factory,'industrial_acids')==4,'factory requested more than its half-hour input buffer')
 E.consume(v,factory,'silicon',100,true)
 set(v,factory,'electronics',require('src.commodities').byId.make_electronics.cap)
 assert(E.target(v,factory,'silicon')==0 and E.target(v,factory,'industrial_acids')==0,'full output kept ordering historical inputs')
 local Tasks=require('src.tasks')
 local open=Tasks.post(v,{kind='transport',source='station:mercury_1',target=factory,item='silicon',amount=10,order=true,layoutScope=E.scope,placed=0})
 local committed=Tasks.post(v,{kind='transport',source='station:mercury_1',target=factory,item='silicon',amount=5,order=true,layoutScope=E.scope,placed=0})
 committed.state='reserved';committed.owner='already-accepted'
 E.update(v,0)
 assert(not Tasks.state(v).offers[open.id] and Tasks.state(v).offers[committed.id],'blocked factory kept excess open orders or cancelled accepted freight')
 set(v,factory,'electronics',0)
 assert(E.target(v,factory,'silicon')>0,'freeing output space did not restart input orders')
 -- Authoring budgets compare shared facility capacity, not the sum of
 -- mutually exclusive recipes, and leave supply headroom for their users.
 local C=require('src.commodities')
 local function outputRate(item)
  local n=0
  for _,recipe in ipairs(C.list) do for _,out in ipairs(C.outputs(recipe)) do if out.item==item then
   for _,rate in pairs(recipe.make) do n=n+rate*out.n/(recipe.time or 1) end
  end end end
  return n
 end
 local function inputPeak(item)
  local n=0
  for _,place in pairs(require('src.locations').byId) do for id,installation in pairs(place.facilities or {}) do
   local peak=0
   for _,recipe in ipairs(I.definition(id,installation).recipes) do
    local c=C.byId[recipe]
    for _,input in ipairs(C.inputs(c)) do if input.item==item then peak=math.max(peak,input.n/(c.time or 1)) end end
   end
   n=n+installation.capacity*peak
  end end
  return n
 end
 for _,item in ipairs({'silicon','industrial_acids','electronics','hull_frame','steel_plate'}) do
  assert(outputRate(item)>=inputPeak(item)*1.25,'nominal supply lacks consumer headroom for '..item)
 end
 local fertilizers,explosives=inputPeak('fertilizer'),inputPeak('explosives')
 local chemicalCapacity=I.installations('station:callisto_2').chemicals.capacity+I.installations('station:titan_2').chemicals.capacity
 assert(chemicalCapacity>=fertilizers+explosives,'shared chemical plants cannot cover both consumer chains')
 assert(outputRate('nitrates')>=(fertilizers+explosives*2)*1.25,'raw nitrates lack headroom for fertilizer and warheads')
 -- A surface mine is allowed to work its own ejecta inside the broad
 -- salvage exclusion band, but never material inside the planet itself.
 local Mining=require('src.mining');local Fields=require('src.fields');local iceSite=Fields.belt.drillIds[1]
 local iceWorld=world();local state=Mining.state(iceWorld)
 state.sites[iceSite]={id=iceSite,planet=true,x=0,y=0,radius=Fields.belt.planetR}
 local rock={id='test-ice',site=iceSite,area='belt',kind='rock',item='water_ice',yield=2,
  x=Fields.belt.planetR+500,y=0,vx=0,vy=0,clock=0,readyAt=0,radius=40,hp=1}
 state.resources[rock.id]=rock
 local miner={id='ice-selector',area='belt',state='idle',node=iceSite,route={iceSite,iceSite},index=1,
  task={kind='mine',phase='mining',target=iceSite,item='water_ice'},speed=600,ship={hull='ferrous_mule',loadout=require('src.persistence').copy(require('src.data').enemies.miner_packhorse.loadout),cargo={}}}
 local context={u=iceWorld,r=miner,clock=0,game={miningLive={},pickups={}}}
 assert(require('src.npc_actions').sinking(miner,rock.x,rock.y),'fixture is not inside the salvage exclusion band')
 local action=Mining.nextAction(context)
 assert(action and action.kind=='work' and action.operation=='drill','surface mining rejected its own accessible ice')
 local Actions=require('src.npc_actions');context.dt=1
 Actions.request(context,action);Actions.step(context)
 assert(miner.action and (not miner.lastAction or miner.lastAction.status~='failed'),'action executor rejected accessible surface-mining output')
 Actions.cancel(context,'fixture complete')
 rock.x=Fields.belt.planetR-100;miner.resourceScanAt=nil
 assert(Mining.nextAction(context).kind=='hold','miner pursued material inside the planet')
 print('ECONOMY FEEDBACK: producer imports, fair inputs, bounded buffers, blocked-output release, committed freight and physical fuel passed')
end
