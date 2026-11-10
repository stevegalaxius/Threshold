-- World events: comings and goings, fights and rescues all land in the one
-- saved log, per record and per node, and quests can query them.
return function(game)
 local H=require('src.simulation_history')
 local Rep=require('src.reputation')
 local u=game.universe
 u.clock=u.clock or 0
 u.npcs=u.npcs or {}
 local node='station:saturn_1'
 local t={id='t_evt',role='trader',state='docked',area='saturn',node=node}
 local p={id='p_evt',task={kind='raid'},state='travel',area='saturn',node=node}
 u.npcs.t_evt,u.npcs.p_evt=t,p
 H.observe(u,u.clock)              -- first look: nothing to report
 assert(#H.recent(u,{participant='t_evt'})==0,'first sighting is silent')
 t.state='travel';u.clock=u.clock+1;H.observe(u,u.clock)
 assert(H.recent(u,{participant='t_evt'})[1].kind=='undocked','undocking is noticed')
 t.area=nil;t.state='transit';u.clock=u.clock+1;H.observe(u,u.clock)
 assert(H.recent(u,{participant='t_evt',kind='left_area'})[1],'leaving an area is noticed')
 t.area='saturn';t.state='docked';u.clock=u.clock+1;H.observe(u,u.clock)
 assert(H.recent(u,{participant='t_evt',kind='arrived'})[1],'arriving is noticed')
 assert(H.recent(u,{node=node,kind='docked'})[1],'and it is logged at the node')
 assert(#t.log>0 and #t.log<=5,'records keep a short log')
 -- a pirate on a trader, and the player kills the pirate: a rescue
 local before=Rep.goodwill(u,t)
 H.begin(u,'t_evt','p_evt',u.clock,'saturn','p_evt')
 H.begin(u,'p_evt','player',u.clock,'saturn','player')
 p.state='dead';require('src.tasks').release(u,p,'dead',u.clock);H.death(u,p,u.clock,'saturn','player')
 H.finish(u,'p_evt','player',u.clock,'death')
 local rescue=H.recent(u,{kind='rescued'})[1]
 assert(rescue and rescue.participants[1]=='t_evt' and rescue.result.rescuer=='player','killing its attacker rescues the trader')
 Rep.onOutcome(u,rescue)
 assert(Rep.goodwill(u,t)>before and Rep.standing(u,'diwan')>0,'the trader and the Diwan remember it')
 local f=H.recent(u,{kind='combat_started',participant='t_evt'})[1]
 assert(f.result.aggressor=='p_evt' and f.node==node,'fights know who started them and where')
 print('world events ok')
end
