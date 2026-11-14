-- Role fit: jobs prefer the stats they use, danger hardens choices, buyers
-- take the best ship for the job rather than the cheapest.
return function(game)
 local F,D,data=require('src.ship_fit'),require('src.dealers'),require('src.data')
 local L=require('src.locations')
 local ref={hold=100,armor=100,firepower=4,drill=4,agility=10}
 local hauler={hold=100,armor=20,firepower=0,drill=0,agility=5}
 local gunship={hold=10,armor=80,firepower=4,drill=0,agility=8}
 local digger={hold=60,armor=20,firepower=0,drill=4,agility=4}
 assert(F.score('trader',hauler,ref,0)>F.score('trader',gunship,ref,0),'trader did not prefer the hauler')
 assert(F.score('pirate',gunship,ref,0)>F.score('pirate',hauler,ref,0),'pirate did not prefer the gunship')
 assert(F.score('miner',digger,ref,0)>F.score('miner',hauler,ref,0),'miner did not prefer the drill ship')
 -- danger narrows the gap toward armour and guns
 local calm=F.score('trader',hauler,ref,0)-F.score('trader',gunship,ref,0)
 local hot=F.score('trader',hauler,ref,1)-F.score('trader',gunship,ref,1)
 assert(hot<calm,'danger did not push traders toward tougher ships')
 local u={clock=100*3600,stations={},npcs={}}
 assert(F.danger(u,'earth')==0,'empty history reads as dangerous')
 for i=1,F.dangerDeaths do require('src.simulation_history').note(u,'npc_died',u.clock,'earth',{},{}) end
 assert(F.danger(u,'earth')==1,'recent deaths did not raise danger')
 assert(F.danger(u,'mars')==0,'danger leaked between regions')
 u.clock=u.clock+(F.dangerHours+1)*3600
 assert(F.danger(u,'earth')==0,'old deaths still count as danger')
 -- hull bonuses count: metrics go through the stat pipeline
 for id,hull in pairs(data.hulls) do
  local m=F.metrics(hull,hull.loadout or {})
  assert(m.hold>=0 and m.armor>=0 and m.agility>=0,'bad metrics for '..id)
 end
 -- a trader buyer takes the armed stock fit over a cheaper stripped one
 local q={clock=0,stations={},npcs={}}
 for _,id in ipairs(L.stations('earth')) do local s=D.state(q,id);if s then s.lots={} end end
 local key='station:earth_1';local preset=data.enemies.runner_trader
 local function lot(trim,price)
  local l=D.roll({hulls={preset.hull},trims={trim}},D.state(q,key),preset.hull)
  l.used=true;l.condition=.8;l.price=price;l.cargo={[require('src.reactor_fuel').item()]=2}
  return l
 end
 local stripped,stock=lot('stripped',5000),lot('stock',9000)
 D.state(q,key).lots={stripped,stock}
 local hasGun=false
 for i,id in ipairs(stock.loadout) do if id and data.modules[id].weapon and not stripped.loadout[i] then hasGun=true end end
 if hasGun then
  local pick=D.purchaseCandidate(q,'earth',require('src.npc_templates').purchase('trader'),true)
  assert(pick and pick.lot==stock,'trader bought the cheapest lot instead of the best fit')
  local cheap=D.purchaseCandidate(q,'earth',{budget=10^6,requires={cargo=true}},true)
  assert(cheap and cheap.lot==stripped,'roleless buyer no longer takes the cheapest')
 end
 print('SHIP FIT: role preference, danger, metrics and best-fit purchase passed')
end
