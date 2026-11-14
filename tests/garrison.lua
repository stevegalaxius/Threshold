-- Site garrisons: site enemies are A-Life NPCs, and the ones that get away live on.
return function(game)
 local Sites,G=require('src.sites'),require('src.garrison')
 local checks=0
 local function check(ok,msg) assert(ok,msg);checks=checks+1 end
 local u=game.universe
 game:loadField('saturn')
 local inst=Sites.spawn(u,'iron_vault',{home='saturn'})
 check(game:enterSite(inst.id),'into the site')
 local field=game.fieldId
 local crew=G.members(u,field)
 check(#crew==5,'pocket 1 musters its groups: '..#crew)
 game:updateALife(true)
 local online=0
 for _,r in ipairs(crew) do if game.alifeOnline[r.id] then online=online+1 end end
 check(online==5,'the garrison wakes as ships: '..online)
 local e=game.alifeOnline[crew[1].id]
 check(e.siteEnemy and e.team==2 and not e.route,'a garrison ship fights as a site enemy')
 -- one runs: it leaves the pocket and joins the world as a pirate
 local runner=crew[1]
 e.fleeing=true;e.body:setPosition(game.arenaRadius+2000,0)
 game:reap()
 check(not runner.garrison and runner.area=='saturn' and runner.state~='dead' and runner.state~='escaped','a runner lives on at the site home: '..tostring(runner.area)..' '..tostring(runner.state))
 check(runner.veteranOf and runner.veteranOf.site==inst.id,'and remembers where it came from')
 check(#G.members(u,field)==4,'the pocket has four left')
 -- leave with the rest alive: they keep their post; coming back tops up
 local e2=game.alifeOnline[crew[2].id];e2.armor=e2.stats.armor*0.6
 local hurtArmor=e2.armor
 game:loadField('saturn',{player=require('src.ship').record(game.player)})
 check(#G.members(u,field)==4,'survivors keep guarding while you are away')
 check(crew[2].ship.armor<=hurtArmor+1,'with their damage')
 game:loadField(field,{player=require('src.ship').record(game.player)})
 check(#G.members(u,field)==5,'a revisit recruits back up to strength')
 check(crew[2].garrison,'and the old crew is still there')
 -- the site closing sets the rest free
 game:loadField('saturn',{player=require('src.ship').record(game.player)})
 Sites.close(u,inst,game)
 check(#G.members(u,field)==0,'closing the site disbands the garrison')
 local free=0
 for _,r in pairs(u.npcs) do if r.veteranOf and r.veteranOf.site==inst.id and r.state~='dead' then free=free+1 end end
 check(free==6,'and they all live on, runner included: '..free)
 for _=1,3 do game:updateALife(true) end
 print(('garrison: %d checks passed'):format(checks))
end
