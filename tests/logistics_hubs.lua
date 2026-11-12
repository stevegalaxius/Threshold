-- Logistics hubs: love . --hubtest
-- Runs the seeded world offline and reports trunk runs and hub depots.
return function(game)
 local A=require('src.alife');local Econ=require('src.economy');local Tasks=require('src.tasks')
 local Stock=require('src.stockpile');local L=require('src.locations')
 local u=game.universe
 game.autosaveOff=true;game:captureALife(true);require('src.supplies').universe=u
 local hours=tonumber(os.getenv('HUB_HOURS') or '') or 2
 local start=u.clock
 local seen,trunks,claimed={},0,0
 local bulk=0
 for _,r in pairs(u.npcs) do if r.ship and require('src.npc_access').capabilities(r).bulk and r.populationGroup=='trader' then bulk=bulk+1 end end
 print('bulk traders',bulk)
 for clock=start,start+hours*3600,5 do
  u.clock=clock
  require('src.mining').produce(game,clock)
  for _,r in pairs(u.npcs) do A.advance(r,clock,u,game) end
  if clock%60==0 then
   Tasks.clean(u,clock);Econ.update(u,clock)
   require('src.arbiter').update(u,clock);require('src.population').update(game,clock)
   for id,o in pairs(Tasks.state(u).offers) do if o.trunk then
    if not seen[id] then seen[id]='available';trunks=trunks+1 end
    if o.state~='available' and seen[id]=='available' then seen[id]='taken';claimed=claimed+1 end
   end end
  end
  if (clock-start)%3600==0 then
   local lines={}
   for _,area in ipairs(require('src.fields').list) do for _,id in ipairs(L.stations(area,'trade')) do if L.byId[id].hub then
    local held={};for _,item in ipairs(Econ.goods()) do local n=Stock.count(u,id,item);if n>0 then held[#held+1]=item..'='..n end end
    lines[#lines+1]=id..' '..table.concat(held,' ')
   end end end
   for _,id in ipairs({'station:titan_3','station:mars_2'}) do
    local t={};for _,item in ipairs({'steel_plate','explosives','electronics'}) do t[#t+1]=item..'='..Stock.count(u,id,item) end
    lines[#lines+1]=id..' '..table.concat(t,' ')
   end
   print(('t=%dmin trunk orders %d claimed %d'):format((clock-start)/60,trunks,claimed));print(table.concat(lines,'\n'))
  end
 end
 assert(trunks>0,'no trunk runs were posted')
 assert(claimed>0,'no trunk run was claimed')
 print('HUB TEST PASSED')
end
