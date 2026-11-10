-- Shared fixture geometry must follow rotation and velocity changes immediately.
return function()
 local Nav=require('src.local_navigation')
 local world=love.physics.newWorld(0,0,true)
 local scene={world=world,time=0}
 local wall=love.physics.newBody(world,200,150,'kinematic')
 local fixture=love.physics.newFixture(wall,love.physics.newRectangleShape(100,500))
 fixture:setUserData({kind='structure'})
 local function actor(id,x)
  return {id=id,body=love.physics.newBody(world,x,0,'dynamic'),hull={radius=10},halfLength=10,spine={0,0}}
 end
 local first,second=actor(1,0),actor(2,-50)
 local function steer(e)
  e.navigation=nil
  return Nav.steer(scene,e,1,0,150,0,0,{brake=100,distance=1000})
 end
 local x,y,scale=steer(first)
 assert(x<.99 or math.abs(y)>.01 or scale<1,'wall did not obstruct the requested course')
 steer(second) -- another NPC shares this fixture's cached geometry
 wall:setAngle(math.pi/2)
 x,y,scale=steer(first)
 assert(x>.99 and math.abs(y)<.01 and scale==1,'rotated wall retained stale blocking geometry')
 wall:setAngle(0);wall:setPosition(-500,150)
 x,y,scale=steer(first)
 assert(x>.99 and math.abs(y)<.01 and scale==1,'wall behind the ship blocked forward travel')
 wall:setLinearVelocity(1000,0)
 x,y,scale=steer(first)
 assert(x<.99 or math.abs(y)>.01 or scale<1,'cached obstacle velocity missed approaching traffic')
 wall:setPosition(10000,10000)
 steer(first);steer(second)
 assert(first.navigation.untilTime~=second.navigation.untilTime,'NPC avoidance refreshes remained synchronized')
 assert(first.navigation.untilTime>scene.time and first.navigation.untilTime<=scene.time+require('src.tuning').aiSteerEvery,'staggering exceeded the refresh interval')
 world:destroy()
 print('AVOIDANCE: moved/rotated geometry, relative velocity and staggered refresh passed')
end
