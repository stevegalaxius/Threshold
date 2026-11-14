-- Rank: spawn odds, policy scaling, earned rank, regular refits.
return function(game)
 local Rank,Refit,data=require('src.npc_rank'),require('src.npc_refit'),require('src.data')
 assert(Rank.roll(function() return 0 end)=='rookie' and Rank.roll(function() return .99 end)=='elite','spawn odds wrong')
 local base=require('src.npc_templates').purchase('trader')
 local p=Rank.policy(base,'rookie')
 assert(p.budget<base.budget and p.rank=='rookie' and p.sharpness and base.rank==nil,'rank policy did not scale a copy')
 local r={id='rank_test'}
 for _=1,9 do Rank.experience(r,1) end
 assert(r.rank=='rookie','ranked up too early')
 Rank.experience(r,1);assert(r.rank=='proficient','no rank up at threshold')
 Rank.experience(r,100);assert(r.rank=='veteran','veteran not earned')
 assert(Rank.get({}).name=='Rookie','unranked record is not a rookie')
 -- a refit is checked once per visit, and never breaks a role requirement
 local u=game.universe
 local preset=data.enemies.runner_trader
 local npc={id='refit_test',populationGroup='trader',rank='veteran',rankXp=60,credits=10^6,area='earth',
  dockedAt=1,ship={hull=preset.hull,loadout=require('src.persistence').copy(preset.loadout or data.hulls[preset.hull].loadout),armor=1}}
 local swap=Refit.dock(npc,'station:earth_1',u,u.clock,function() return 0 end)
 local again=Refit.dock(npc,'station:earth_1',u,u.clock,function() return 0 end)
 assert(not again,'refit ran twice in one visit')
 local caps=require('src.npc_access').capabilities({ship=npc.ship})
 assert(caps.cargo,'refit removed cargo capability')
 if swap then assert(npc.credits==10^6-swap.cost and swap.fit>swap.was,'refit did not pay or improve') end
 npc.dockedAt=2;npc.credits=0
 assert(not Refit.dock(npc,'station:earth_1',u,u.clock,function() return 0 end),'broke NPC refitted')
 print('NPC RANK: spawn odds, policy, rank up, refit gating and requirements passed')
end
