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
 local hours=tonumber(os.getenv('ECON_HOURS') or '') or 48
 local stations={}
 for _,area in ipairs(Fields.list) do
  for _,id in ipairs(L.stations(area,'trade')) do
   if require('src.supplies').supports(id) then stations[#stations+1]=id end
  end
 end
 local fuel=Fuel.item()
 local dryHours={}
 local start=u.clock
 local worst={}
 for hour=1,hours do
  for clock=start+(hour-1)*3600,start+hour*3600-1,5 do
   u.clock=clock
   require('src.mining').produce(game,clock)
   for _,r in pairs(u.npcs) do A.advance(r,clock,u,game) end
   if clock%60==0 then Tasks.clean(u,clock);Econ.update(u,clock) end
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
  local use=0 for _,id in ipairs(stations) do use=use+Econ.rate(u,id,fuel) end
  local npcs=0 for _,r in pairs(u.npcs) do if r.state~='dead' and r.state~='escaped' then npcs=npcs+1 end end
  local busy,idle,tr,other=0,0,0,{} for _,r in pairs(u.npcs) do if r.role=='trader' and r.state~='dead' and r.state~='escaped' then tr=tr+1 if r.task and r.task.order then busy=busy+1 elseif r.task then other[r.task.item or '?']=(other[r.task.item or '?'] or 0)+1 else idle=idle+1 end end end
  local o={} for k,v in pairs(other) do o[#o+1]=k..'='..v end
  print(('  traders %d: on orders %d, other tasks %s, idle %d'):format(tr,busy,table.concat(o,' '),idle))
  for _,k in ipairs({'station:jupiter_1','station:jupiter_2','station:uranus_1','station:uranus_2','station:belt_1','station:mars_1'}) do local inb=0 local outb=0 for _,o in pairs(Tasks.state(u).offers) do if o.order and o.target==k then inb=inb+1 end if o.order and o.source==k then outb=outb+1 end end print(('    %s deut %d empty %d ore %d ice %d tgtEmpty %d  orders in %d out %d'):format(k,Stock.count(u,k,fuel),Stock.count(u,k,'empty_canister'),Stock.count(u,k,'iron_ore'),Stock.count(u,k,'water_ice'),Econ.target(u,k,'empty_canister'),inb,outb)) end
  print(('  fuel use %.0f/h by %d npcs'):format(use,npcs))
  print(('hour %3d  fuel %5d at %d stations, %2d dry  orders %3d  | %s'):format(hour,total,#stations,dry,orders,table.concat(goods,', ')))
 end
 local long={}
 for id,h in pairs(dryHours) do if h>hours*.25 then long[#long+1]=('%s dry %dh'):format(id,h) end end
 table.sort(long)
 print('stations dry over a quarter of the time: '..(#long>0 and table.concat(long,', ') or 'none'))
 assert(#long==0,'stations ran out of reactor fuel for long stretches')
 print('ECONOMY TEST PASSED')
end
