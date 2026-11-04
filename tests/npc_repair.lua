return function(game)
 local pirateBase=require('src.locations').station(nil,'pirateBase')
 local R,A,M,T=require('src.npc_repair'),require('src.alife'),require('src.mining'),require('src.tuning')
 local Save,copy=require('src.save'),require('src.persistence').copy
 local u=copy(game.universe);local fixture={universe=u};local checks=0
 local function check(ok,msg)assert(ok,msg);checks=checks+1 end
 local function near(a,b)return math.abs(a-b)<.001 end
 local station='station:007'
 local template,miner,pirate
 for _,r in pairs(u.npcs) do
  if r.role=='trader' then template=r end
  if r.role=='miner' and R.supports(r.base) then miner=r end
  if r.role=='pirate' and r.home=='earth' then pirate=r end
 end
 assert(template and miner and pirate,'repair fixtures missing')
 check(R.supports(station) and R.supports(pirateBase),'service station layout lookup failed')
 check(not R.supports(require('src.fields').earth.buoyIds[1]),'buoy offers repairs')
 -- The same completed-docking gate applies to every persistent role.
 local physical={universe=u,stationServices=function(st)return st.services end}
 local st={services={repair=true}}
 for i,role in ipairs({'trader','courier','miner','patrol','pirate'}) do
  local r=copy(template);r.id='repair/'..i;r.role=role;u.npcs[r.id]=r
  local max=R.maximum(r);r.ship.armor=max*.5
  local e={alifeId=r.id,armor=r.ship.armor,stats={armor=max},dockState={station=st,done=false},fleeing=true}
  R.online(physical,e,2)
  check(e.armor==max*.5,role..' healed during docking approach')
  e.dockState.done=true;R.online(physical,e,2)
  check(near(e.armor,max*.5+2*T.npcRepairPerSecond) and e.armor==r.ship.armor,role..' dock repair did not update saved armor')
  st.services={};local hp=e.armor;R.online(physical,e,2)
  check(e.armor==hp,role..' repaired without station service');st.services={repair=true}
  R.online(physical,e,10000)
  check(e.armor==max and not e.fleeing,role..' failed to finish repairs/clear retreat')
 end
 -- Ordinary trader/courier schedules repair without losing their travel duties.
 for _,role in ipairs({'trader','courier'}) do
  local r=copy(template);r.role=role;r.taskWorker=nil;r.onRoundTrip=nil;r.home='earth'
  r.area='earth';r.route={require('src.fields').earth.buoyIds[1],station};r.index=2
  r.state='travel';r.arrive=u.clock;r.encounter=nil;r.ship.armor=R.maximum(r)*.2
  local hp=r.ship.armor;A.advance(r,u.clock,u,fixture)
  check(r.state=='docked' and r.untilTime-u.clock>= (R.maximum(r)-hp)/T.npcRepairPerSecond,role..' stay too short for repair')
  A.advance(r,u.clock+2,u,fixture)
  check(near(r.ship.armor,hp+2*T.npcRepairPerSecond),role..' offline repair rate differs')
  local restored=assert(Save.decode(Save.encode({npcs={[r.id]=r}}))).npcs[r.id]
  A.advance(restored,u.clock+2,u,fixture)
  check(restored.ship.armor==r.ship.armor,'reload repeated elapsed repair')
  A.advance(restored,r.untilTime,u,fixture)
  check(restored.ship.armor==R.maximum(r) and restored.state=='travel',role..' failed to resume route')
 end
 -- Empty repair trips keep the miner's reserved job; loaded trips still deliver.
 for _,load in ipairs({0,3}) do
  local r=copy(miner);u.npcs[r.id]=r;r.ship.armor=R.maximum(r)*.2
  r.ship.hold=nil;r.ship.cargo={};r.ship.cargo[r.task.item]=load
  r.task.phase='mining';r.state='idle';r.encounter=nil;r.savedOnline=nil
  local offer=r.task.offer;local target=r.task.target;local item=r.task.item
  M.advance(fixture,r,u.clock)
  check(r.repairReturn and r.task.phase=='delivery','damaged miner did not return for repair')
  u.clock=r.arrive;M.advance(fixture,r,u.clock)
  check(r.state=='docked','repairing miner did not dock')
  u.clock=r.untilTime;M.advance(fixture,r,u.clock)
  check(r.ship.armor==R.maximum(r) and r.task and r.task.phase=='mining','miner failed to repair and resume mining')
  if load==0 then check(r.task.target==target and r.task.offer==offer,'empty repair trip lost mining reservation')
  else check((M.state(u).stock[r.base][item] or 0)>=load,'repair trip lost mined cargo delivery') end
 end
 -- Empty-handed damaged pirates use the existing saved return/redeploy loop.
 local r=pirate;r.ship.armor=R.maximum(r)*.2;r.ship.cargo={};r.ship.hold=nil;r.stolenCargo={}
 r.encounter=nil;r.piracy=nil;r.state='idle';r.node='station:007';r.route={r.node,r.node};r.index=1
 A.advance(r,u.clock,u,fixture)
 check(r.piracy and r.route[#r.route]==pirateBase,'empty damaged pirate did not seek repair')
 for _=1,80 do if r.state=='docked' then break end;u.clock=r.arrive;A.advance(r,u.clock,u,fixture) end
 check(r.state=='docked' and r.node==pirateBase,'repairing pirate never reached base')
 u.clock=r.untilTime;A.advance(r,u.clock,u,fixture)
 check(r.ship.armor==R.maximum(r) and r.piracy.phase=='redeploy','pirate failed to repair before redeploy')
 check(not next(u.piracy.stashes[pirateBase]),'empty repair trip manufactured stolen cargo')
 print(('ALL-ROLE NPC REPAIR TEST PASSED (%d checks)'):format(checks))
end
