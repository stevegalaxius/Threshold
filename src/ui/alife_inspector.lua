-- F6: the A-Life inspector. Pick an NPC, see who is driving it and why,
-- and poke it to reproduce a problem on the spot.
local Slab=require('lib.Slab')
local data=require('src.data')
local L=require('src.locations')
local Fuel=require('src.reactor_fuel')
local Trace=require('src.alife_trace')
local Overlay=require('src.ui.alife_overlay')
local I={filter='problems',search=''}

local FILTERS={
 {'problems','Problems (stranded, low fuel, no station)'},
 {'here','In this system'},{'online','Online now'},
 {'stranded','Stranded'},{'service','On a service visit'},
 {'fighting','In an encounter'},{'handover','Robbing / distress'},
 {'all','All living'},{'dead','Dead / escaped'},
}
local function problem(r)
 if r.fuelStatus=='stranded' or r.fuelStatus=='empty' then return true end
 local last=r.trace and r.trace[#r.trace]
 return last and (last.text:find('no station') or last.text:find('nobody') or last.text:find('fell through')) and true or false
end
local function matches(game,id,r)
 local f=I.filter;local e=game.alifeOnline and game.alifeOnline[id]
 local gone=r.state=='dead' or r.state=='escaped'
 if f=='dead' then return gone end
 if gone then return false end
 if I.search~='' and not (id:find(I.search,1,true) or (r.role or ''):find(I.search,1,true) or (r.area or ''):find(I.search,1,true)) then return false end
 if f=='all' then return true end
 if f=='here' then return r.area==game.fieldId end
 if f=='online' then return e~=nil end
 if f=='stranded' then return r.fuelStatus=='stranded' end
 if f=='service' then return r.service~=nil end
 if f=='fighting' then return r.encounter~=nil end
 if f=='handover' then return e and (e.asked or e.request) or r.distress~=nil end
 return problem(r)
end

local function fuelLine(r,e)
 local ship=e or r.ship
 return ('%s, %.0f fuel (%d %s aboard)'):format(r.fuelStatus or '?',Fuel.remaining(ship),
  (e and e.cargo or r.ship.cargo or {})[Fuel.item()] or 0,data.items[Fuel.item()].name)
end

local function list(game)
 local ids={}
 for id,r in pairs(game.universe.npcs) do if matches(game,id,r) then ids[#ids+1]=id end end
 table.sort(ids,function(a,b) return (tonumber(a:match('%d+')) or 0)<(tonumber(b:match('%d+')) or 0) end)
 Slab.Text(('%d match'):format(#ids))
 Slab.BeginListBox('alife_list',{H=180,W=520})
 for i,id in ipairs(ids) do
  local r=game.universe.npcs[id];local e=game.alifeOnline and game.alifeOnline[id]
  Slab.BeginListBoxItem('alife_item'..i,{Selected=Overlay.state.selected==id})
  Slab.Text(('%s%s  %s  %s  %s'):format(e and '* ' or '  ',id,r.role or '?',r.area or 'transit',Trace.controller(game,r,e)))
  if Slab.IsListBoxItemClicked() then Overlay.select(id,game) end
  Slab.EndListBoxItem()
 end
 Slab.EndListBox()
end

local function actions(game,r,e)
 local u=game.universe
 if e then
  if Slab.Button(game.debugFollow==e and 'Stop following' or 'Follow with camera') then game.debugFollow=game.debugFollow~=e and e or nil end
  Slab.SameLine()
  if Slab.Button('Teleport player here') and game.player and not game.player.dead then
   local x,y=e.body:getPosition();game.player.body:setPosition(x+e.halfLength+150,y);game.player.body:setLinearVelocity(e.body:getLinearVelocity())
  end
 else
  Slab.Text('Offline: travel to '..(r.area or 'its lane')..' to see it live.')
 end
 if Slab.Button('Drain fuel') then
  if e then e.fuelCharge=0;e.power=0;e.cargo[Fuel.item()]=nil;if e.hold then require('src.inventory.hold').sync(e.hold,e.cargo) end
  else r.ship.fuelCharge=0;r.power=0;Fuel.withRecord(r,function(s) s.cargo[Fuel.item()]=nil;if s.hold then require('src.inventory.hold').sync(s.hold,s.cargo) end end) end
  Trace.note(r,u.clock,'debug','fuel drained')
 end
 Slab.SameLine()
 if Slab.Button('Low fuel') then
  local f=function(s) s.fuelCharge=1;s.cargo[Fuel.item()]=nil;if s.hold then require('src.inventory.hold').sync(s.hold,s.cargo) end end
  if e then f(e) else Fuel.withRecord(r,f) end
  Trace.note(r,u.clock,'debug','fuel set low')
 end
 Slab.SameLine()
 if Slab.Button('Damage 50%') then
  if e then e.armor=e.armor*.5;r.ship.armor=e.armor else r.ship.armor=(r.ship.armor or 0)*.5 end
  Trace.note(r,u.clock,'debug','hull halved')
 end
 Slab.SameLine()
 if Slab.Button('Clear trace') then r.trace=nil end
end

local function details(game)
 local r=Overlay.state.selected and game.universe.npcs[Overlay.state.selected]
 if not r then Slab.Text('Select an NPC above.');return end
 local e=game.alifeOnline and game.alifeOnline[r.id]
 Slab.Separator()
 local hull=data.hulls[r.ship.hull]
 Slab.Text(('%s  %s  %s  (%s)'):format(r.id,r.role or '?',hull and hull.name or r.ship.hull,e and 'online' or 'offline'))
 Slab.Text('Driven by: '..Trace.controller(game,r,e))
 Slab.Text(('State: %s in %s   status: %s'):format(r.state,r.area or 'transit',tostring(r.taskStatus)))
 Slab.Text('Fuel: '..fuelLine(r,e))
 local maxArmor=require('src.npc_repair').maximum(r)
 Slab.Text(('Hull: %.0f / %.0f   needs: %s'):format(e and e.armor or r.ship.armor or 0,maxArmor,tostring(require('src.upkeep').need(r,e) or 'none')))
 if r.route then
  local parts={}
  for i,id in ipairs(r.route) do
   local name=L.byId[id] and L.byId[id].name or id
   parts[#parts+1]=(i==r.index and '['..name..']' or name)
  end
  Slab.Text('Route: '..table.concat(parts,' > '))
  if r.state=='travel' or r.state=='transit' then Slab.Text(('Leg: %.0fs to go'):format(math.max(0,(r.arrive or 0)-game.universe.clock))) end
 end
 if r.service then Slab.Text(('Service: %s at %s, then back to %s'):format(r.service.need,r.service.station,r.service.saved.route[r.service.saved.index] or '?')) end
 if r.distress then Slab.Text(('Distress: %s bringing %d fuel at %.0fs'):format(r.distress.helper,r.distress.amount,r.distress.at)) end
 local req=e and (e.asked or e.request)
 if req then Slab.Text(('Handover: %s, %d/%d, %.0fs left'):format(req.kind,req.paid,req.amount,math.max(0,req.deadline-game.time))) end
 actions(game,r,e)
 Slab.Separator()
 Slab.Text('Decision trace (newest first)')
 local t=r.trace or {}
 if #t==0 then Slab.Text('  (nothing yet)') end
 for i=#t,1,-1 do
  local x=t[i]
  Slab.Text(('  %7.0fs  %-9s %s%s'):format(x.clock,x.source,x.text,x.n and (' x'..x.n) or ''))
 end
end

function I.panel(game)
 if Slab.BeginComboBox('alife_filter',{Selected=(function() for _,f in ipairs(FILTERS) do if f[1]==I.filter then return f[2] end end end)(),W=320}) then
  for _,f in ipairs(FILTERS) do if Slab.TextSelectable(f[2]) then I.filter=f[1] end end
  Slab.EndComboBox()
 end
 Slab.SameLine()
 if Slab.Input('alife_search',{Text=I.search,W=180,ReturnOnText=true}) then I.search=Slab.GetInputText() end
 list(game)
 details(game)
end
return I
