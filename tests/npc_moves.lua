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
   assert(r.speed>=low and r.speed<=high,('%s (%s) cruises at %s, outside the shared speed'):format(id,r.role,tostring(r.speed)))
   checks=checks+1
   assert(N.jobOf(r),id..' has no job')
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
  local role=r.piracy and 'pirate' or r.role
  if r.state~='dead' and r.state~='escaped' and (role=='pirate' or role=='patrol' or role=='salvager') then
   count[role]=(count[role] or 0)+1
   -- a ship whose job has nowhere else to go here can't be expected to move
   local j=N.jobOf(r);local here=r.node or r.route[r.index];local elsewhere=false
   for _,other in ipairs(j.roam and j.roam(r,here) or {}) do if other~=here then elsewhere=true end end
   if not moved[id] and not elsewhere then lonely=(lonely or 0)+1
   elseif not moved[id] then stuck[#stuck+1]=('%s %s at %s (%s, %s)'):format(role,id,tostring(r.node or r.route[r.index]),r.state,tostring(r.taskStatus)) end
   checks=checks+1
  end
 end
 assert(#stuck==0,'NPCs that never moved in two hours:\n'..table.concat(stuck,'\n'))
 assert((count.pirate or 0)>0 and (count.patrol or 0)>0,'world has pirates and patrols to check')
 print(('NPC MOVEMENT TEST PASSED (%d checks, %d with nowhere to go)'):format(checks,lonely or 0))
end
