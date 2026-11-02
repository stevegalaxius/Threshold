return function(game)
 local Ship=require('src.ship')
 local copy=require('src.persistence').copy
 local data=require('src.data')
 local p=game.player
 p.hull=copy(p.hull)
 p.hull.slots={{family='primary',size='S'},{family='secondary',size='S'},{family='computer',size='any'}}
 p.loadout={'glint_laser','px2_autogun','fire_computer'}
 p.body:setPosition(0,0);p.body:setLinearVelocity(0,0);p.dockState=nil
 local target={kind='ship',team=2,halfLength=20,body=love.physics.newBody(game.world,200,0,'dynamic')}
 target.body:setLinearVelocity(0,100)
 p.team=1;p.intent.aimX=200;p.intent.aimY=0;p.navThreat=nil;p.lock=nil
 game.entities={p,target}
 local checks=0
 local function check(ok,msg) assert(ok,msg);checks=checks+1 end
 local function capture()
  local lg=love.graphics
  local circle,line,color,width=lg.circle,lg.line,lg.setColor,lg.setLineWidth
  local circles,styles,lines,widths={},{},{},{}
  lg.circle=function(mode,x,y,r) circles[#circles+1]={mode=mode,x=x,y=y,r=r} end
  lg.line=function(...) lines[#lines+1]={...} end
  lg.setColor=function(r,g,b,a) styles[#styles+1]={r,g,b,a} end
  lg.setLineWidth=function(w) widths[#widths+1]=w end
  local ok,err=pcall(function() game:drawComputers(1) end)
  lg.circle,lg.line,lg.setColor,lg.setLineWidth=circle,line,color,width
  assert(ok,err)
  return circles,styles,lines,widths
 end
 local function marker()
  local circles=capture()
  for _,c in ipairs(circles) do if c.mode=='line' and c.r==9 then return c end end
 end
 Ship.refit(p)
 local pip=marker()
 check(pip and pip.y>0,'laser-first mixed loadout suppressed projectile lead')
 p.loadout[1]='px2_autogun';p.loadout[2]='glint_laser';Ship.refit(p)
 local reversed=marker()
 check(reversed and math.abs(reversed.y-pip.y)<.001,'weapon ordering changed projectile lead')
 p.loadout[1]='glint_laser';p.loadout[2]=false;Ship.refit(p)
 pip=marker()
 check(pip and pip.x==200 and pip.y==0,'laser-only loadout did not use instantaneous target marker')
 p.loadout[1]=false;p.loadout[2]='px2_autogun';Ship.refit(p)
 check(marker().y>0,'secondary gun did not get a lead solution')
 p.loadout[2]=false;Ship.refit(p)
 check(not marker(),'unarmed ship showed a false lead marker')
 p.loadout[1]='glint_laser';Ship.refit(p)
 local _,styles=capture()
 local markerAlpha
 for _,s in ipairs(styles) do if s[1]==1 and s[2]==.85 and s[4]>.2 then markerAlpha=s[4] end end
 check(markerAlpha and markerAlpha<.7,'ordnance marker remains too opaque')
 -- Find the catalog guidance module rather than depending on its ID.
 for id,m in pairs(data.modules) do if m.computer=='guidance' then p.loadout[3]=id end end
 p.lock=target
 local _,colors,lines,widths=capture()
 local bright=false;local shadow=false
 for _,s in ipairs(colors) do
  if s[1]==1 and s[2]==.45 and s[4]>=.85 then bright=true end
  if s[1]<.1 and s[4]>.5 then shadow=true end
 end
 check(bright and shadow and #lines==16,'missile guidance lock is missing bright outlined brackets')
 p.lock=nil;p.navWarn=1;p.navThreat={ship=p,time=2,vx=100,vy=0,hitX=200,hitY=0}
 _,colors=capture()
 check(colors[1][4]<.5,'navigation course remains too opaque')
 p.navThreat.time=.2
 _,colors=capture()
 check(colors[1][4]>.35 and colors[1][4]<.8,'urgent navigation warning lost contrast or stays opaque')
 -- Render the combined overlay for visual inspection after behavior checks.
 p.hull.slots[4]={family='computer',size='any'}
 p.loadout[4]=p.loadout[3];p.loadout[3]='fire_computer'
 p.loadout[1]='glint_laser';p.loadout[2]='px2_autogun';Ship.refit(p);p.lock=target
 local lg=love.graphics;local canvas=lg.newCanvas(640,360)
 lg.push('all');lg.setCanvas(canvas);lg.clear(.02,.035,.06,1);lg.origin()
 lg.translate(120,170)
 lg.setColor(.5,.65,.75,.4);lg.circle('line',200,0,20)
 game:drawComputers(1)
 lg.setCanvas();lg.pop()
 canvas:newImageData():encode('png','computer-overlays.png')
 print(('ORDNANCE COMPUTER TEST PASSED (%d checks)'):format(checks))
end
