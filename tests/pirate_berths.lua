-- Pirates come from the dark economy: a base with a shipyard launches as many
-- raiders as its fuel stock covers, fits and fuels them from its own region,
-- and sends them out to hunt. Fenced loot lands back on its shelves.
return function(game)
 local Pop,S,L=require('src.population'),require('src.security'),require('src.locations')
 local St,Fuel,P=require('src.stockpile'),require('src.reactor_fuel'),require('src.piracy')
 local Dark=require('src.dark')
 local checks=0
 local function check(ok,msg) assert(ok,msg);checks=checks+1 end
 local u=game.universe
 local base='station:pluto_1'
 check(L.byId[base].hub and require('src.economy').hubFor(base)==base,'Milliways is not the dark hub')
 check(require('src.economy').hubFor('station:shoals_1')==base,'other dark grids do not route through Milliways')
 check(Pop.target('earth','pirate',u)==0 and Pop.target('belt','pirate',u)==0,'white regions still have a flat pirate quota')
 local fuel=Fuel.item()
 St.add(u,base,fuel,500)
 local berths=S.berths(u,base)
 check(berths>0 and Pop.target('milliways','pirate',u)==berths,'a fuelled dark shipyard offers no berths')
 local before=St.count(u,base,fuel)
 local r,why=Pop.spawn(game,'milliways','pirate',false)
 check(r,'no pirate launched from Milliways: '..tostring(why))
 check(r.homeStation==base and r.spawnOrigin=='launch' and Pop.where(r)=='milliways','pirate was not homed at and counted against its base')
 check(St.count(u,base,fuel)<before and (r.ship.cargo[fuel] or 0)>0,'pirate fuel did not come off the base shelf')
 check(r.task and r.task.kind=='deploy' and not Dark.isDarkNode(r.task.target),'new pirate did not head out to a white hunting ground')
 -- it flies out and joins the raid network there
 for _=1,400 do u.clock=u.clock+30;require('src.npc').advance(r,u.clock,u,game);if not r.piracy then break end end
 check(not r.piracy and not Dark.isDarkArea(r.area),'deployed pirate never reached its hunting ground ('..tostring(r.area)..')')
 -- a base with no fuel launches nobody
 St.take(u,base,fuel,St.available(u,base,fuel))
 check(S.berths(u,base)==0 and not Pop.spawn(game,'milliways','pirate',false),'a base with no fuel still launched a pirate')
 -- fenced goods become stock the base can launch on
 r.ship.cargo[fuel]=(r.ship.cargo[fuel] or 0)+200;r.stolenCargo={[fuel]=200};r.ship.hold=nil
 local credits=r.credits or 0
 r.piracy={phase='escape',base=base}
 P.unload(u,r)
 check(St.count(u,base,fuel)>=200 and (r.credits or 0)>credits,'fenced fuel did not become paid-for base stock')
 check(S.berths(u,base)>0,'fenced fuel did not open berths again')
 print(('PIRATE BERTHS TEST PASSED (%d checks)'):format(checks))
end
