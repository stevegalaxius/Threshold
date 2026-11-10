-- Read-only developer monitor. Route progress is schematic, never a world pose.
local Fields=require('src.fields')
local L=require('src.locations')
local data=require('src.data')
local HUD=require('src.hud')
local M={}
local function area(id) return id and L.byId[id] and L.byId[id].area end
local function name(id) return Fields[id] and Fields[id].name or tostring(id or '?') end
local function cargo(ship)
 local counts=ship.cargo or {}
 if ship.hold then
  counts=require('src.inventory.hold').totals(ship.hold)
 end
 local out={}
 for id,n in pairs(counts) do if n>0 then out[#out+1]=(data.items[id] and data.items[id].name or id)..' x'..n end end
 table.sort(out)
 return #out>0 and table.concat(out,', ') or '(empty)'
end
function M.snapshot(game,includeMoons)
 local clock=game.universe.clock
 local model={clock=clock,rows={},npcs={},total=0,waiting=0,transit=0,overdue=0,stranded=0,gone=0}
 local rows={}
 for id,r in pairs(game.universe.npcs or {}) do
  if r.state=='dead' or r.state=='escaped' then model.gone=model.gone+1 else model.total=model.total+1 end
  local e=game.alifeOnline and game.alifeOnline[id]
  local from,to,kind
  if r.state=='transit' and r.transit then
   from,to=r.transit.from,r.transit.to
   kind=r.transit.kind=='driver' and 'driver' or 'moon'
  elseif r.task and area(r.task.source) and area(r.task.target) then
   from,to=area(r.task.source),area(r.task.target);kind='driver'
  elseif r.onRoundTrip and r.tripDestination then
   from=r.area or r.home
   to=from==r.home and r.tripDestination or r.home
   kind='moon'
  end
  if r.taskWorker and not r.task and r.state=='docked' then model.waiting=model.waiting+1 end
  if from and to and from~=to and r.state~='dead' and r.state~='escaped' and (kind=='driver' or includeMoons) then
   local progress=0
   local phase=r.state
   local eta
   local stranded=r.fuelStatus=='stranded' and require('src.reactor_fuel').needsPropulsion(r)
   if stranded then model.stranded=model.stranded+1 end
   if r.state=='transit' then
    local legAt=require('src.alife').legClock(r,clock)
    progress=math.max(0,math.min(1,(legAt-r.depart)/math.max(.001,r.arrive-r.depart)))
    model.transit=model.transit+1
    if stranded then
     -- Frozen in place with no ETA; recovery is left to a future event.
     phase='stranded in transit'
    else
     eta=math.max(0,r.arrive-clock);phase=eta==0 and 'arrival pending' or 'in transit'
     if eta==0 then model.overdue=model.overdue+1 end
    end
   elseif r.area==to then progress=1;phase=r.state=='docked' and 'docked' or 'approaching port'
   elseif r.state=='docked' then phase='loading / docked'
   else phase='to departure' end
   local driver=e and (e.launch or e.driverTractor) or r.driverState
   if stranded and r.state~='transit' then phase='stranded'
   elseif driver and r.state~='transit' then phase=e and e.driverTractor and 'tractor capture' or driver.phase=='tractor' and 'tractor capture' or 'launching' end
   if r.state~='transit' and r.area then
    -- not physically in the lane: say which system's local space it's in
    local F=require('src.fields');local name=F[r.area] and F[r.area].name or r.area
    phase=phase..' at '..name..' (local space, not in lane)'
   end
   local ship=e or r.ship
   local n={id=id,role=r.label,state=r.state,phase=phase,stranded=stranded,from=from,to=to,kind=kind,
    progress=progress,eta=eta,depart=r.depart,arrive=r.arrive,online=e~=nil,
    hull=e and e.hull.name or (data.hulls[r.ship.hull] and data.hulls[r.ship.hull].name or r.ship.hull),cargo=cargo(ship),
    task=r.task and ((r.task.id and r.task.id..' / ' or '')..r.task.kind..(r.task.phase and ' / '..r.task.phase or ''))
      or '(itinerary)',
    homeStation=require("src.npc_home").get(r),status=(r.fuelStatus and r.fuelStatus~='normal' and require('src.reactor_fuel').label(r) or r.taskStatus),activity=require('src.reactor_fuel').activity(r),fuelStatus=r.fuelStatus,protected=e and e.driverProtected or false,localArea=r.area,
    launchTime=driver and driver.t,launchPhase=driver and (driver.ghost and 'barrel / coast' or phase)}
   model.npcs[id]=n
   local key=from..'>'..to
   if not rows[key] then rows[key]={key=key,from=from,to=to,kind=kind,npcs={}} end
   rows[key].npcs[#rows[key].npcs+1]=n
  end
 end
 for _,row in pairs(rows) do
  table.sort(row.npcs,function(a,b)return a.id<b.id end)
  model.rows[#model.rows+1]=row
 end
 table.sort(model.rows,function(a,b)return a.key<b.key end)
 return model
end
function M.isOpen(game) return game.npcTraffic~=nil end
function M.toggle(game)
 if M.isOpen(game) then game.npcTraffic=nil
 else game.npcTraffic={scroll=0,moons=false,frozen=false} end
end
local function layout()
 local w,h=love.graphics.getDimensions()
 return w,h,math.max(260,w-370),math.max(1,math.floor((h-135)/68))
end
local function current(game)
 local view=game.npcTraffic
 if not view.frozen or not view.model then view.model=M.snapshot(game,view.moons) end
 return view.model
end
function M.keypressed(game,key)
 if not M.isOpen(game) then return false end
 if key=='escape' or key=='f4' then M.toggle(game)
 elseif key=='space' then game.npcTraffic.frozen=not game.npcTraffic.frozen
 elseif key=='tab' then local v=game.npcTraffic;v.moons=not v.moons;v.model=nil;v.scroll=0 end
 return key~='f1'
end
function M.wheelmoved(game,y)
 if not M.isOpen(game) then return false end
 local v=game.npcTraffic;local _,h,right,visible=layout()
 if love.mouse.getX()>=right then
  v.detailScroll=math.max(0,math.min(math.max(0,(v.detailHeight or 0)-(h-155)),(v.detailScroll or 0)-y*24))
  return true
 end
 local step=y>0 and math.max(1,math.floor(y)) or y<0 and math.min(-1,math.ceil(y)) or 0
 v.scroll=math.max(0,math.min(math.max(0,#current(game).rows-visible),v.scroll-step))
 return true
end
function M.mousepressed(game,x,y,button)
 if not M.isOpen(game) then return false end
 if button~=1 then return true end
 local w,_,right,visible=layout()
 local v=game.npcTraffic
 if y>=16 and y<=45 then
  if x>w-90 then M.toggle(game)
  elseif x>=350 and x<510 then v.moons=not v.moons;v.model=nil;v.scroll=0
  elseif x>=520 and x<660 then v.frozen=not v.frozen end
  return true
 end
 local model=current(game)
 v.scroll=math.max(0,math.min(v.scroll,math.max(0,#model.rows-visible)))
 local rowIndex=math.floor((y-105)/68)+1+v.scroll
 local row=model.rows[rowIndex]
 if y>=105 and x<right and row then
  local start,finish=135,right-110
  local best,distance
  for i,n in ipairs(row.npcs) do
   local nx=start+(finish-start)*n.progress
   local ny=105+(rowIndex-v.scroll-1)*68+43+(i%3-1)*7
   local d=(nx-x)^2+(ny-y)^2
   if not distance or d<distance then best,distance=n,d end
  end
  if best then
   if best.id==v.selected and #row.npcs>1 then
    for i,n in ipairs(row.npcs) do if n.id==v.selected then best=row.npcs[i%#row.npcs+1];break end end
   end
   if v.selected~=best.id then v.detailScroll=0 end
   v.selected=best.id
  end
 end
 return true
end
function M.draw(game)
 if not M.isOpen(game) then return end
 local lg=love.graphics
 local v=game.npcTraffic;local model=current(game)
 local w,h,right,visible=layout()
 v.scroll=math.max(0,math.min(v.scroll,math.max(0,#model.rows-visible)))
 lg.push('all');lg.origin();lg.setScissor()
 lg.clear(.018,.027,.043,1)
 lg.setFont(HUD.font(18));lg.setColor(.7,.9,1)
 lg.print('NPC TRAFFIC / DEBUG',20,20)
 local function button(x,width,label,on)
  lg.setColor(on and .12 or .06,on and .25 or .12,.2,1);lg.rectangle('fill',x,16,width,30,4)
  lg.setFont(HUD.font(12));lg.setColor(.8,.9,1);lg.print(label,x+10,25)
 end
 button(350,160,v.moons and 'Planet + moon routes' or 'Interplanetary only',v.moons)
 button(520,140,v.frozen and 'Frozen view' or 'Live view',v.frozen)
 button(w-90,70,'Close',false)
 lg.setFont(HUD.font(12));lg.setColor(.55,.68,.78)
 lg.print(('Clock %.1fs   |   %d NPCs (+%d dead/escaped records)   |   %d shown in transit   |   %d stranded   |   %d workers waiting'):format(model.clock,model.total,model.gone,model.transit,model.stranded,model.waiting),20,60)
 lg.print('Schematic progress, not physical positions.  Click a ship to inspect.  Wheel: routes / inspector  /  Tab: moons  /  Space: freeze view  /  F4: close',20,h-25)
 local start,finish=135,right-110
 lg.setColor(.45,.62,.72);lg.setFont(HUD.font(10))
 lg.print('DEPARTURE',start-20,88);lg.printf('ARRIVAL',finish-65,88,80,'right')
 local paused=require('src.ui.pause').isOpen() or require('src.editor').isOpen()
 if paused then lg.setColor(1,.75,.35);lg.print('Simulation paused',680,26) end
 v.hits={}
 for index=v.scroll+1,math.min(#model.rows,v.scroll+visible) do
  local row=model.rows[index];local y=105+(index-v.scroll-1)*68
  lg.setColor(.04,.065,.09);lg.rectangle('fill',20,y,right-40,62,4)
  lg.setFont(HUD.font(13));lg.setColor(.65,.82,.95)
  lg.print(name(row.from)..'  >  '..name(row.to),32,y+7)
  lg.setFont(HUD.font(11));lg.setColor(.42,.57,.67)
  lg.printf((row.kind=='driver' and 'DRIVER' or 'MOON')..' / '..#row.npcs,right-155,y+8,115,'right')
  lg.setLineWidth(1);lg.setColor(.2,.36,.46);lg.line(start,y+43,finish,y+43)
  for _,p in ipairs({0,.25,.5,.75,1}) do
   local x=start+(finish-start)*p;lg.line(x,y+39,x,y+47)
  end
  for i,n in ipairs(row.npcs) do
   local x=start+(finish-start)*n.progress
   local yy=y+43+(i%3-1)*7
   local selected=v.selected==n.id
   if n.stranded then lg.setColor(1,.35,.3,1) else
   lg.setColor(n.progress==1 and .55 or .3,n.online and 1 or .7,n.kind=='driver' and 1 or .6,1) end
   lg.polygon('fill',x+6,yy,x-4,yy-4,x-4,yy+4)
   if selected then lg.setColor(1,.85,.35);lg.circle('line',x,yy,9) end
   v.hits[#v.hits+1]={id=n.id,x=x,y=yy}
  end
 end
 if #model.rows==0 then
  lg.setColor(.7,.8,.9);lg.print('No active journeys in this filter. Workers choose work when they finish docking.',32,125)
 end
 lg.setColor(.035,.055,.08);lg.rectangle('fill',right,90,w-right-16,h-135,5)
 local n=model.npcs[v.selected]
 local y=108-(v.detailScroll or 0)
 lg.setScissor(right+8,98,w-right-32,h-153)
 -- A wrapped inspector stays readable for long cargo manifests.
 local function detail(value)
  lg.setColor(.7,.82,.9)
  local _,lines=lg.getFont():getWrap(value,w-right-48)
  lg.printf(value,right+16,y,w-right-48,'left');y=y+#lines*16+10
 end
 lg.setFont(HUD.font(13))
 if n then
  detail(n.id..' / '..n.hull)
  detail(name(n.from)..' > '..name(n.to))
  detail(n.phase..' / '..(n.online and 'physical body' or 'offline record'))
  detail(('Progress: %.1f%%'):format(n.progress*100))
  if n.stranded then detail('ETA: none (stranded: no reactor fuel or power)')
  elseif n.eta then detail(('ETA: %.1fs%s'):format(n.eta,n.eta==0 and ' (awaiting simulation tick)' or '')) end
  if n.depart and n.arrive then detail(('Leg clock: %.1f > %.1f'):format(n.depart,n.arrive)) end
  if n.launchTime then detail(('Driver: %s / %.2fs'):format(n.launchPhase,n.launchTime)) end
  detail('Current area: '..name(n.localArea or (n.state=='transit' and 'transit')))
  detail('Identity: '..tostring(n.role))
  if n.homeStation then detail('Home: '..L.get(n.homeStation).name..' ('..n.homeStation..')') end
  detail('Task: '..n.task)
  detail('Cargo: '..n.cargo)
  if n.protected then detail('Mass-driver protection active') end
  if n.status then detail('Status: '..n.status) end
  if n.activity and n.activity~=n.status then detail('Activity: '..n.activity) end
 elseif v.selected then detail(v.selected..' is no longer on an active route. Select another ship.')
 else detail('Select an NPC marker.\n\nDeparture is the left end; arrival is the right end. Each row has its own direction.\n\nFreezing this view does not pause or advance the simulation.') end
 v.detailHeight=y+(v.detailScroll or 0)-108
 lg.setScissor()
 local mx,my=love.mouse.getPosition()
 for _,hit in ipairs(v.hits) do
  if (hit.x-mx)^2+(hit.y-my)^2<144 then
   local n=model.npcs[hit.id]
   local tx=math.min(right-240,math.max(20,mx+12))
   local ty=math.min(h-75,my+14)
   lg.setColor(.06,.1,.15,.98);lg.rectangle('fill',tx,ty,240,42,4)
   lg.setFont(HUD.font(11));lg.setColor(.8,.92,1)
   lg.print(n.id..' / '..n.phase,tx+8,ty+7)
   lg.print(('%.1f%% / %s'):format(n.progress*100,n.stranded and 'stranded' or n.eta and ('ETA %.1fs'):format(n.eta) or n.state),tx+8,ty+23)
   break
  end
 end
 lg.pop()
end
return M
