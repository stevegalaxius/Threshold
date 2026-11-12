-- Shortage deliveries and the player's first look at local freight.
-- love . --questtest
return function()
 local game=require('src.game').new({field='mars'});game.autosaveOff=true
 local Q,Tasks,Stock,T=require('src.quests'),require('src.tasks'),require('src.stockpile'),require('src.tuning')
 local Hold,Ship=require('src.inventory.hold'),require('src.ship')
 local u=game.universe;local st='station:mars_2';local item='nitrates'
 local function dock(id)
  local s=assert(game:findStation(id));game.state='docked'
  game.player.dockState={station=s,done=true,phase='done',dock=s.dock,side=1}
 end
 -- a shortage older than the threshold posts one delivery, once
 Stock.stock(u,st,Stock.shopFor(st,item))[item]=0
 local src='station:mars_1';Stock.stock(u,src,Stock.shopFor(src,item))[item]=1000
 local rec=Stock.record(u,st);rec.shortages=rec.shortages or {};rec.shortages[item]=u.clock-T.questShortageAge-1
 local real=require('src.economy').target;require('src.economy').target=function() return 40 end
 Q.state(u).next=0;Q.update(u,u.clock)
 local offers=Q.offersAt(u,st);local q
 for _,o in ipairs(offers) do if o.item==item then q=o end end
 assert(q and q.amount==40,'old shortage did not post a delivery')
 assert(q.unit>=require('src.markets').price(u,st,item)*T.questPremium-1,'delivery pays below premium')
 Q.state(u).next=0;Q.update(u,u.clock)
 local n=0;for _,o in ipairs(Q.offersAt(u,st)) do if o.item==item then n=n+1 end end
 assert(n==1,'shortage posted twice')
 -- accept, deliver part, then the rest
 assert(Q.accept(u,q.id,u.clock))
 dock(st);local p=game.player;p.cargo={};p.hold=Hold.new(Ship.holdLayout(p))
 Hold.add(p.hold,item,25);p.cargo=Hold.totals(p.hold);Ship.updateMass(p)
 require('src.ui.contracts').draw(game)
 local credits=u.credits
 assert(Q.deliver(game,q.id,st))
 assert(Stock.count(u,st,item)==25 and u.credits==credits+25*q.unit and not p.cargo[item],'partial delivery wrong')
 assert(Q.state(u).active[q.id] and Q.state(u).active[q.id].delivered==25,'partial delivery closed the quest')
 Hold.add(p.hold,item,20);p.cargo=Hold.totals(p.hold)
 assert(Q.deliver(game,q.id,st))
 assert(not Q.state(u).active[q.id] and p.cargo[item]==5,'completion took too much or stayed open')
 -- deliveries survive a save
 u.clock=u.clock+T.questCooldown.shortage_delivery+1
 Stock.stock(u,st,Stock.shopFor(st,item))[item]=0;rec.shortages[item]=u.clock-T.questShortageAge-1;Q.state(u).next=0;Q.update(u,u.clock)
 local q2=Q.offersAt(u,st)[1];assert(Q.accept(u,q2.id,u.clock))
 local state=game:saveState();game:loadState(state)
 assert(Q.state(game.universe).active[q2.id],'active delivery lost on save/load')
 u=game.universe
 -- overdue deliveries fail
 Q.state(u).next=0;Q.update(u,Q.state(u).active[q2.id].deadline+1)
 assert(not Q.state(u).active[q2.id],'overdue delivery did not fail')
 require('src.economy').target=real
 -- first look: an order at the docked station is held from NPCs
 local o={order=true,source=st,placed=u.clock,npcClaimAt=0}
 u.playerDocked=st
 assert(not Tasks.npcMayClaim(u,o,u.clock+10),'NPC took freight during the player first look')
 assert(Tasks.npcMayClaim(u,o,u.clock+T.playerFirstLookSeconds+1),'first look never ended')
 u.playerDocked='station:mars_1'
 assert(Tasks.npcMayClaim(u,o,u.clock+10),'first look applied away from the docked station')
 -- rescue: a real stranded record gets a rescue posted at its nearest station
 local Rep=require('src.reputation')
 local function strand()
  for id,r in pairs(u.npcs) do if r.area=='mars' and r.state~='dead' and r.fuelStatus~='stranded' then r.fuelStatus='stranded';return r end end
 end
 local r=assert(strand(),'no NPC on Mars to strand')
 local function tick(c) Q.state(u).next=0;u.clock=c;Q.update(u,c,game) end
 tick(u.clock);tick(u.clock+T.rescueMinAge+1)
 local rescue
 for _,o in pairs(Q.state(u).offers) do if o.kind=='rescue' and o.subject==r.id then rescue=o end end
 assert(rescue,'stranded ship got no rescue posted')
 local n=0;for _,o in pairs(Q.state(u).offers) do if o.subject==r.id then n=n+1 end end
 assert(n==1,'rescue posted twice')
 assert(Q.accept(u,rescue.id,u.clock))
 local credits,standing=u.credits,Rep.standing(u,Rep.ofNode(rescue.giver))
 local live=Q.state(u).active[rescue.id];live.near=u.clock
 r.fuelStatus='empty';tick(u.clock+5)
 assert(not Q.state(u).active[rescue.id],'rescue did not settle')
 assert(u.credits==credits+rescue.unit*rescue.amount,'rescue did not pay')
 assert(Rep.standing(u,Rep.ofNode(rescue.giver))>standing,'rescue gave no standing')
 -- someone else gets there first: fails
 local r2=assert(strand());tick(u.clock);tick(u.clock+math.max(T.rescueMinAge,T.questCooldown.rescue)+1)
 local other;for _,o in pairs(Q.state(u).offers) do if o.subject==r2.id then other=o end end
 assert(other and Q.accept(u,other.id,u.clock))
 r2.fuelStatus='empty';credits=u.credits;tick(u.clock+5)
 assert(not Q.state(u).active[other.id] and u.credits==credits,'rescue paid without the player there')
 -- arbiter: a station never holds more of one kind than the cap, and hostile stations offer nothing
 local per={};for _,o in pairs(Q.state(u).offers) do local k=o.giver..o.kind;per[k]=(per[k] or 0)+1;assert(per[k]<=T.questKindMax,'kind cap broken') end
 Rep.addStanding(u,Rep.ofNode(st),-200);Rep.addHeat(u,st,100)
 assert(#Q.offersAt(u,st)==0,'hostile station still offered work')
 print('quests: ok')
end
