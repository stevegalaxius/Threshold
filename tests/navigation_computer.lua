return function(game)
 local T=require('src.tuning')
 local checks=0
 local function check(ok,msg) assert(ok,msg); checks=checks+1 end
 game.autosaveOff=true
 local p=game.player
 local slot
 for i,s in ipairs(p.hull.slots) do if s.family=='computer' then slot=i; break end end
 assert(slot,'test ship needs a computer slot')
 p.loadout[slot]='nav_computer'
 p.body:setPosition(0,0); p.body:setLinearVelocity(100,0)
 game.entities={p}
 local hazard=game:spawnAsteroid(180,0,20,'rock')
 hazard.body:setLinearVelocity(0,0)
 game:updateComputers(.2)
 check(p.navThreat and p.navThreat.target==hazard and p.navWarn>.9,'imminent danger did not show')
 p.body:setLinearVelocity(-5,0)
 game:updateComputers(1/120)
 check(not p.navThreat and p.navWarn==0,'warning lingered after reversing away')
 p.body:setLinearVelocity(100,0)
 local reach=hazard.radius+p.halfLength*.8
 hazard.body:setPosition(reach+100*(T.navLookahead+.1),0)
 game:updateComputers(.2)
 check(not p.navThreat,'warning shown outside immediate lookahead')
 hazard.body:setPosition(180,200)
 game:updateComputers(.2)
 check(not p.navThreat,'near miss reported as danger')
 hazard.body:setPosition(180,0)
 p.body:setLinearVelocity(0,0)
 game:updateComputers(.2)
 check(not p.navThreat,'stationary relative motion kept the warning alive')
 -- An incoming object is still dangerous while you are stopped or backing away.
 p.body:setLinearVelocity(-5,0); hazard.body:setLinearVelocity(-200,0)
 game:updateComputers(.2)
 check(p.navThreat and p.navThreat.vx>0,'incoming hazard used backwards absolute ship velocity')
 local line=love.graphics.line; local lines={}
 love.graphics.line=function(x,y,xx,yy) lines[#lines+1]={x,y,xx,yy} end
 game:drawComputers(1)
 love.graphics.line=line
 check(#lines>0 and lines[1][3]>=lines[1][1],'warning line points away from incoming hazard')
 hazard.body:setLinearVelocity(200,0)
 game:updateComputers(1/120)
 check(not p.navThreat and p.navWarn==0,'departing hazard retained its warning')
 hazard.body:setLinearVelocity(-200,0)
 game:updateComputers(.2)
 p.loadout[slot]=false
 game:updateComputers(1/120)
 check(not p.navThreat and p.navWarn==0,'removed computer left a stale warning')
 p.loadout[slot]='nav_computer'
 p.dockState={}
 game:updateComputers(.2)
 check(not p.navThreat,'docking kept a collision warning')
 p.dockState=nil
 p.catching=true
 game:updateComputers(.2)
 check(not p.navThreat,'catching kept a collision warning')
 p.catching=nil
 p.body:setLinearVelocity(300,0); hazard.body:setPosition(400,0); hazard.body:setLinearVelocity(0,0)
 local nearer=game:spawnAsteroid(180,0,20,'rock'); nearer.body:setLinearVelocity(0,0)
 game:updateComputers(.2)
 check(p.navThreat.target==nearer,'warning picked an arbitrary hazard over the earliest collision')
 -- The impact X is only shown in the final half second, on a real fixture.
 game:remove(hazard)
 nearer.body:setPosition(300,0)
 p.body:setLinearVelocity(300,0)
 game:updateComputers(.2)
 check(p.navThreat and p.navThreat.time>.5 and not p.navThreat.hitX,'impact X appeared too early')
 nearer.body:setPosition(130,0)
 game:updateComputers(.2)
 check(p.navThreat.time<=.5 and p.navThreat.hitX~=nil,'imminent impact did not get an X')
 local hitX,hitY=p.navThreat.hitX,p.navThreat.hitY
 check(hitX>100 and hitX<150 and math.abs(hitY)<.01,'impact marker missed the actual obstacle surface')
 local drawn={}
 love.graphics.line=function(x,y,xx,yy) drawn[#drawn+1]={x,y,xx,yy} end
 game:drawComputers(1)
 love.graphics.line=line
 check(#drawn==12,'impact marker was not drawn as an X after the ten path dashes')
 local a,b=drawn[11],drawn[12]
 check(math.abs((a[1]+a[3])/2-hitX)<.01 and math.abs((b[2]+b[4])/2-hitY)<.01,'X was not centered at impact')
 p.body:setLinearVelocity(-300,0)
 game:updateComputers(1/120)
 check(not p.navThreat and p.navWarn==0,'impact X survived steering clear')
 print(('NAV COMPUTER TEST PASSED (%d checks)'):format(checks))
end
