return function(game)
 local Dock=require('src.dock_geometry')
 local Export=require('src.editor.export')
 local data,Ship=require('src.data'),require('src.ship')
 local copy=require('src.persistence').copy
 local checks=0
 local function check(ok,msg) assert(ok,msg);checks=checks+1 end
 local function near(a,b)return math.abs(a-b)<.001 end
 local part={dock=true,shape={400,-100,600,-100,600,100,400,100},
  dockHeading=90,dockX=500,dockY=130,dockWidth=100,dockDepth=80,
  dockRunway=900,dockCapture=200,dockWall=12}
 local d=Dock.build(part)
 local x,y=Dock.point(d,d.x2,0)
 check(near(d.a,math.pi/2) and near(x,500) and near(y,130),'off-axis dock entrance ignored custom heading/position')
 check(d.hw==50 and near(d.x2-d.x1,80) and d.capture==200 and d.wall==12,'custom dock dimensions lost')
 local design={id='test_nonradial_station',name='Side-facing rectangular station',kind='station',parts={copy(part)}}
 local def=assert(data.defineStation(Export.stationDef(design)))
 check(near(def.dock.a,math.pi/2),'runtime forced dock to point away from station center')
 local source=Export.source(design);local exported
 local chunk=assert(loadstring(source));setfenv(chunk,{station=function(v)exported=v end});chunk()
 for _,field in ipairs(Dock.fields) do check(exported.parts[1][field]==part[field],'export lost '..field) end
 Export.autosave(design)
 local restored=Export.loadAutosave()
 check(restored.parts[1].dockX==500 and restored.parts[1].dockHeading==90,'autosave lost custom dock')
 local opened=Export.fromStation(def.id)
 check(opened.parts[1].dockCapture==200,'opening station lost tractor customization')
 local automatic=copy(part)
 for _,field in ipairs(Dock.fields) do automatic[field]=nil end
 local old=Dock.build(automatic)
 check(near(old.a,0) and near(old.x2,600) and old.hw==100 and old.capture==130,'automatic classic ring geometry changed')
 local tunnel=copy(part);tunnel.dockBoth=true
 local td=Dock.build(tunnel)
 x,y=Dock.point(td,td.x2,0,-1)
 check(near(x,500) and near(y,50),'tunnel second door did not follow custom depth/heading')
 local mirrored=copy(part);mirrored.mirror=true
 local twins=assert(data.defineStation({id='test_mirror_dock',parts={mirrored}}))
 check(#twins.docks==2 and near(twins.docks[2].a,-math.pi/2),'mirrored heading not reflected')
 x,y=Dock.point(twins.docks[2],twins.docks[2].x2,0)
 check(near(x,500) and near(y,-130),'mirrored door not reflected')
 local st=game:spawnStation(def.id,100000,100000,0)
 st.body:setAngle(.7)
 local wx,wy=game.dockWorld(st,1,st.dock.x2+300,150)
 check(game:inTractorZone(st,wx,wy),'custom capture width not used by real tractor')
 wx,wy=game.dockWorld(st,1,st.dock.x2+300,201)
 check(not game:inTractorZone(st,wx,wy),'tractor ignored configured width')
 wx,wy=game.dockWorld(st,1,st.dock.x2+400,0)
 local e=Ship.new(game,{hull='intaki_wisp',x=wx,y=wy,angle=game.dockAngle(st,1)+math.pi})
 e.def={ai={style='trader'}};e.route={st};e.routeIndex=1
 game.entities={st,e}
 game:updateDocking(1/120)
 check(e.dockState and e.dockState.phase=='tractor','nonradial dock did not capture ship')
 for _=1,12000 do
  game:updateDockedShip(e,1/120);game.world:update(1/120)
  if e.dockState.done then break end
 end
 check(e.dockState.done,'physical docking failed with custom heading and entrance')
 game:undockShip(e)
 local lx,ly=game.dockLocal(st,1,e.body:getPosition())
 check(lx>st.dock.x2 and math.abs(ly)<.01,'undocking used radial geometry')
 local bad=copy(part);bad.dockWidth=-1
 check(not pcall(Dock.build,bad),'invalid dock dimensions accepted')
 -- Render the editor preview using the same geometry.
 local E=require('src.editor').state
 E.newDesign('station');E.design=design;E.sel=1;E.view={x=600,y=300,zoom=.4}
 E.duplicateSelected()
 check(E.design.parts[2].dockX==500+E.grid*2 and E.design.parts[2].dockY==130+E.grid*2,
  'duplicating a dock left its entrance behind')
 E.undoStep();E.sel=1;E.grid=1;E.snap=false
 E.drag={kind='part',moving=true,lx=0,ly=0}
 local sx,sy=require('src.editor.canvas').toScreen(E,10,20)
 require('src.editor.canvas').mousemoved(E,sx,sy)
 check(E.design.parts[1].dockX==510 and E.design.parts[1].dockY==150,
  'dragging docking part did not move custom entrance')
 E.drag=nil
 local canvas=love.graphics.newCanvas(love.graphics.getDimensions())
 love.graphics.setCanvas(canvas);require('src.editor.canvas').draw(E);love.graphics.setCanvas()
 canvas:newImageData():encode('png','nonradial-dock-editor.png')
 print(('DOCK EDITOR TEST PASSED (%d checks)'):format(checks))
end
