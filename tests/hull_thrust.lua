return function(game)
 local data,Ship=require('src.data'),require('src.ship')
 local checks=0
 local function check(ok,msg) assert(ok,msg);checks=checks+1 end
 check(not data.modules.aux_thrusters and not data.items.aux_thrusters,'Side Jets still in catalog')
 for _,h in pairs(data.hulls) do
  for _,slot in ipairs(h.slots) do check(slot.family~='thruster','retired thruster slot remains') end
 end
 local e=Ship.new(game,{hull='halcyon_wisp',x=100000,y=100000})
 check(e.stats.sideThrust==e.hull.sideThrust and e.stats.sideThrust>0,'hull does not supply maneuvering thrust')
 for i,slot in ipairs(e.hull.slots) do if slot.family=='engine' then e.loadout[i]=false end end
 Ship.refit(e)
 check(not Ship.launchProblem(e),'built-in maneuvering thrust cannot launch without main engine')
 e.body:setLinearVelocity(0,0);e.intent.strafe=1;e.intent.aimX=101000;e.intent.aimY=100000
 for _=1,30 do Ship.fly(e,1/120);game.world:update(1/120) end
 local _,vy=e.body:getLinearVelocity()
 check(vy>0,'built-in maneuvering thrust did not physically strafe')
 e.body:destroy()
 local heavy=Ship.new(game,{hull='ferrous_bastion',x=102000,y=100000})
 heavy.intent.strafe=1
 for _=1,30 do Ship.fly(heavy,1/120);game.world:update(1/120) end
 check(math.abs(heavy.body:getAngularVelocity())>0,'heavy hull lost maneuvering turn assistance')
 heavy.body:destroy()
 print(('HULL THRUST TEST PASSED (%d checks)'):format(checks))
end
