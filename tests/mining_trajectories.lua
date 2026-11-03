-- Launch actual Box2D rocks and compare their curved paths with remote motion.
return function()
 local Game,M,Fields=require('src.game'),require('src.mining'),require('src.fields')
 local copy=require('src.persistence').copy
 local checks,paths=0,{}
 local function check(ok,msg)assert(ok,msg);checks=checks+1 end
 for _,area in ipairs({'deimos','phobos','belt'}) do
  local R=Fields[area].planetR
  for sequence=1,4 do
   local site={id=area..'/drill/1',area=area,x=0,y=0,radius=R,planet=true,
    angle=0,nextAt=0,sequence=sequence-1}
   local g=setmetatable({world=love.physics.newWorld(0,0,true),entities={},pickups={},
    idCounter=0,fieldId=area,field=Fields[area],
    well={x=0,y=0,radius=R,flow=290,swirl=.1},
    universe={clock=0,mining={sites={[site.id]=site},resources={}}}},Game)
   M.produce(g,0)
   local resource=copy(select(2,next(g.universe.mining.resources)))
   local x,y,vx,vy=M.position(resource,0)
   local r0=math.sqrt(x*x+y*y)
   local outward=(x*vx+y*vy)/r0
   local tangent=(x*vy-y*vx)/r0
   check(tangent>outward*4 and outward>0,area..': ejecta sprays outward instead of joining the orbital flow')
   local rock=g:spawnAsteroid(x,y,resource.radius,'rock')
   rock.body:setLinearVelocity(vx,vy);rock.body:setLinearDamping(M.chunkDamping(area))
   local path={area=area,R=R,points={x,y}}
   for i=1,12*120 do
    g:applyCurrent(1/120);g.world:update(1/120)
    if i%30==0 then local px,py=rock.body:getPosition();path.points[#path.points+1]=px;path.points[#path.points+1]=py end
   end
   local px,py=rock.body:getPosition();local r=math.sqrt(px*px+py*py)
   local pvx,pvy=rock.body:getLinearVelocity()
   local vr=(px*pvx+py*pvy)/r;local vt=(px*pvy-py*pvx)/r
   local turn=(math.atan2(py,px)-math.atan2(y,x))%(2*math.pi)
   check(turn>.25 and vt>math.abs(vr),area..': physical ejecta did not curve around the body (turn '..turn..', tangent '..vt..', radial '..vr..')')
   check(r>r0 and r<r0+outward*12*1.15,area..': ejecta leaves its orbital arc along a straight tangent')
   local ox,oy=M.position(resource,12)
   local error=math.sqrt((ox-px)^2+(oy-py)^2)
   check(error<r*.12,area..': remote trajectory diverged from the physical orbital arc: '..error)
   paths[#paths+1]=path
   g.world:destroy()
  end
 end
 -- Diagnostic artifact only; no additional art or overlays in the game.
 local lg=love.graphics;local canvas=lg.newCanvas(900,900)
 lg.push('all');lg.setCanvas(canvas);lg.clear(.02,.03,.04)
 lg.translate(450,450);lg.scale(.09)
 lg.setLineWidth(12)
 lg.setColor(.4,.4,.4);lg.circle('line',0,0,Fields.deimos.planetR,100)
 for _,path in ipairs(paths) do
  if path.area=='deimos' then lg.setColor(.7,.6,.3);lg.line(path.points) end
 end
 lg.setCanvas();lg.pop()
 canvas:newImageData():encode('png','mining-orbital-trajectories.png');canvas:release()
 print(('MINING TRAJECTORY TEST PASSED (%d checks)'):format(checks))
end
