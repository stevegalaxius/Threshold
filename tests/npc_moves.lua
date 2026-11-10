-- One NPC AI: every job keeps moving, at the shared cruise speed.
-- Runs the whole seeded world offline for two hours and checks that no
-- pirate, patrol or salvager sits at one place for the whole run.
return function(game)
 local A,T,N=require('src.alife'),require('src.tuning'),require('src.npc')
 local u=game.universe
 game:captureALife(true)
 local low,high=T.npcCruise*(1-T.npcCruiseSpread)-1e-6,T.npcCruise*(1+T.npcCruiseSpread)+1e-6
 local moved,count={},{}
 local checks=0
 for id,r in pairs(u.npcs) do
  if r.state~='dead' and r.state~='escaped' then
   assert(r.speed>=low and r.speed<=high,('%s (%s) cruises at %s, outside the shared speed'):format(id,r.populationGroup,tostring(r.speed)))
   checks=checks+1
   assert(not r.task or N.work(r),id..' has unknown work')
  end
 end
 local start=u.clock
 for clock=start,start+7200,2 do
  u.clock=clock
  for id,r in pairs(u.npcs) do
   A.advance(r,clock,u,game)
   if r.state=='travel' or r.state=='transit' then moved[id]=true end
  end
 end
 local stuck={};local lonely
 for id,r in pairs(u.npcs) do
  local role=r.piracy and 'pirate' or r.populationGroup
  if r.state~='dead' and r.state~='escaped' and (role=='pirate' or role=='patrol' or role=='salvager') then
   count[role]=(count[role] or 0)+1
   -- a ship whose job has nowhere else to go here can't be expected to move
   local j=N.controller;local here=r.node or r.route[r.index];local elsewhere=false
   for _,other in ipairs(j.roam and j.roam(r,here) or {}) do if other~=here then elsewhere=true end end
   if not moved[id] and not elsewhere then lonely=(lonely or 0)+1
   elseif not moved[id] then stuck[#stuck+1]=('%s %s at %s (%s, %s)'):format(role,id,tostring(r.node or r.route[r.index]),r.state,tostring(r.taskStatus)) end
   checks=checks+1
  end
 end
 assert(#stuck==0,'NPCs that never moved in two hours:\n'..table.concat(stuck,'\n'))
 assert((count.pirate or 0)>0 and (count.patrol or 0)>0,'world has pirates and patrols to check')
-- A patrol passing a pirate's fight joins on the victim's side.
 local E=require('src.encounters');local copy=require('src.persistence').copy
 local pirate,patrol,victim
 for _,r in pairs(u.npcs) do
  if r.populationGroup=='pirate' and not pirate and r.state~='dead' then pirate=r end
  if r.populationGroup=='patrol' and not patrol and r.state~='dead' then patrol=r end
  if r.populationGroup=='trader' and not victim and r.state~='dead' then victim=r end
 end
 local function park(r,id,node)
  r=copy(r);r.id=id;r.area=pirate.area;r.state='idle';r.node=node;r.route={node,node};r.index=1
  r.untilTime=u.clock+1e6;r.encounter=nil;r.piracy=nil;r.service=nil;r.retreatUntil=nil;r.worldRecovery=nil
  r.ship.armor=require('src.npc_repair').maximum(r);u.npcs[id]=r;return r
 end
 local node=pirate.node or pirate.route[pirate.index]
 local P=park(pirate,'npc/970001',node);local V=park(victim,'npc/970002',node);local S=park(patrol,'npc/970003',node)
 P.task={kind='raid',source=node,target=node};V.task={kind='transport'}
 S.authorizations={{kind='police',issuer='test_authority',jurisdiction=P.area}}
 E.begin(P,V,u.clock)
 u.encounterNext=0;E.update(game,u.clock)
 assert(S.encounter and S.encounter.support and S.encounter.target==P.id,'patrol did not join the fight')
 local hp=P.ship.armor
 for i=1,3 do u.encounterNext=0;u.clock=u.clock+T.offlineCombatTick;E.update(game,u.clock) end
 assert(P.ship.armor<hp or P.state=='dead','pirate took no fire with a patrol defending')
 checks=checks+2
 print(('NPC MOVEMENT TEST PASSED (%d checks, %d with nowhere to go)'):format(checks,lonely or 0))
end
