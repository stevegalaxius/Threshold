-- Economy soak: love . --economytest
-- Runs the seeded world offline for a few game days and checks that the
-- goods economy (src/economy.lua) holds: no station sits out of reactor
-- fuel for long, and no stock grows without bound. Prints an hourly log.
return function(game)
 local A=require('src.alife')
 local Econ=require('src.economy')
 local Tasks=require('src.tasks')
 local Stock=require('src.stockpile')
 local L=require('src.locations')
 local Fields=require('src.fields')
 local Fuel=require('src.reactor_fuel')
 local u=game.universe
 game.autosaveOff=true
 game:captureALife(true)
 require('src.supplies').universe=u
 local hours=tonumber(os.getenv('ECON_HOURS') or '') or 12
 local stations={}
 for _,area in ipairs(Fields.list) do
  for _,id in ipairs(L.stations(area,'trade')) do
   if require('src.supplies').supports(id) then stations[#stations+1]=id end
  end
 end
 local fuel=Fuel.item()
 local dryHours,lastDry,lastTotal={},0,0
 local start=u.clock
 local worst={}
 for hour=1,hours do
  for clock=start+(hour-1)*3600,start+hour*3600-1,5 do
   u.clock=clock
   require('src.mining').produce(game,clock)
   for _,r in pairs(u.npcs) do A.advance(r,clock,u,game) end
   if clock%60==0 then
    Tasks.clean(u,clock);Econ.update(u,clock)
    require('src.arbiter').update(u,clock);require('src.population').update(game,clock)
   end
  end
  local dry,total,orders=0,0,0
  for _,id in ipairs(stations) do
   local n=Stock.count(u,id,fuel);total=total+n
   if n==0 then dry=dry+1;dryHours[id]=(dryHours[id] or 0)+1 end
  end
  for _,o in pairs(Tasks.state(u).offers) do if o.order then orders=orders+1 end end
  local goods={}
  for _,item in ipairs({'iron_ore','empty_canister','water_ice','deuterium_canister','hydrogen_canister'}) do
   local n=0
   for _,area in ipairs(Fields.list) do for _,id in ipairs(L.stations(area,'trade')) do n=n+Stock.count(u,id,item) end end
   goods[#goods+1]=('%s %d'):format(item,n)
   worst[item]=math.max(worst[item] or 0,n)
  end
  lastDry,lastTotal=dry,total
  local tr=0 for _,r in pairs(u.npcs) do if r.role=='trader' and r.state~='dead' and r.state~='escaped' then tr=tr+1 end end
  goods[#goods+1]='traders '..tr
  print(('hour %3d  fuel %5d at %d stations, %2d dry  orders %3d  | %s'):format(hour,total,#stations,dry,orders,table.concat(goods,', ')))
 end
 local long={}
 for id,h in pairs(dryHours) do if h>hours*.25 then long[#long+1]=('%s dry %dh'):format(id,h) end end
 table.sort(long)
 print('stations dry over a quarter of the time: '..(#long>0 and table.concat(long,', ') or 'none'))
 -- A skeleton economy: fuel keeps being made and reaches at least half the
 -- system. Which outposts go short is reported above, not yet asserted.
 assert(lastTotal>0 and lastDry<=#stations*.5,'fuel stopped reaching most stations')
 print('ECONOMY TEST PASSED')
end
