-- Drives the shipyard's Lights tool for real: opens a station, selects a
-- part, places lights by click and by dragged row, fills a part, and
-- checks the lights carry the tool's kind, size and colour settings.
-- With THRESHOLD_SHOTS set, saves screenshots there.
return function(game)
 local Editor=require('src.editor')
 local E=Editor.state
 local Canvas=require('src.editor.canvas')
 local Panels=require('src.editor.panels')
 local checks=0
 local function check(ok,msg) assert(ok,msg);checks=checks+1 end
 Editor.open(game)
 E.switchCategory('station')
 E.openHull('jovian_stack')
 local d=E.design
 check(d and d.kind=='station','no station open')
 -- a part with room for windows
 local best,area=nil,0
 for i,p in ipairs(d.parts) do local a=Canvas.area(p.shape) if a>area and not p.dock then best,area=i,a end end
 E.sel=best
 local p=d.parts[best]
 local x0,x1,y0,y1=math.huge,-math.huge,math.huge,-math.huge
 for k=1,#p.shape,2 do x0,x1=math.min(x0,p.shape[k]),math.max(x1,p.shape[k]);y0,y1=math.min(y0,p.shape[k+1]),math.max(y1,p.shape[k+1]) end
 local cx,cy=(x0+x1)/2,(y0+y1)/2
 E.view.x,E.view.y=cx,cy
 E.view.zoom=math.min(600/(x1-x0),400/(y1-y0))
 E.tool='light'; E.lightKind='window'; E.paneW=40;E.paneH=24; E.windowPalette='cool'; E.snap=false
 p.lights=nil
 -- one click inside the part
 local sx,sy=Canvas.toScreen(E,cx,cy)
 Editor.mousepressed(sx,sy,1); Editor.mousereleased(sx,sy,1)
 check(p.lights and #p.lights==1,'click did not place a light')
 local l=p.lights[1]
 check(l.kind=='window' and l.w==40 and l.h==24,'placed window ignored pane size')
 check(l.color and l.color[2]>=0.9,'placed light ignored the colour palette')
 -- a dragged row
 local ax,ay=Canvas.toScreen(E,x0+(x1-x0)*0.2,cy+(y1-y0)*0.2)
 local bx,by=Canvas.toScreen(E,x0+(x1-x0)*0.8,cy+(y1-y0)*0.2)
 E.lightSpacing=30
 Editor.mousepressed(ax,ay,1); Canvas.mousemoved(E,bx,by); Editor.mousereleased(bx,by,1)
 check(#p.lights>3,'dragged row placed '..#p.lights-1)
 for _,q in ipairs(p.lights) do check(q.w==40 and q.h==24,'row pane size') end
 local shots=os.getenv('THRESHOLD_SHOTS')
 local function shot(name)
  if not shots then return end
  love.graphics.origin(); love.graphics.clear(0,0,0)
  Editor.draw(); love.graphics.present()
  love.graphics.captureScreenshot(function(img) local fd=img:encode('png'); local f=io.open(shots..'/'..name..'.png','wb'); f:write(fd:getString()); f:close() end)
  love.graphics.present()
 end
 shot('placed')
 -- the real panels, a few frames through Slab, to see the Lights tool UI
 if shots then
  local Slab=require('lib.Slab')
  E.lightKind='window'
  for _=1,4 do
   Slab.Update(1/60); Editor.update(1/60)
   love.graphics.origin(); love.graphics.clear(0,0,0); Editor.draw(); Slab.Draw(); love.graphics.present()
  end
  Slab.Update(1/60); Editor.update(1/60)
  love.graphics.origin(); love.graphics.clear(0,0,0); Editor.draw(); Slab.Draw()
  love.graphics.captureScreenshot(function(img) local f=io.open(shots..'/ui.png','wb'); f:write(img:encode('png'):getString()); f:close() end)
  love.graphics.present()
 end
 -- fill, every pattern
 for _,pat in ipairs({'rooms','scattered','rows','checker','grid'}) do
  E.windowPattern=pat; E.windowSpacing=60; E.windowRowSpacing=40; E.windowPalette='mixed'
  Panels.fillWindows(E,p)
  check(p.lights and #p.lights>0,pat..' placed nothing')
  for _,q in ipairs(p.lights) do check(q.w==40 and q.h==24,pat..' pane size') end
  shot('fill_'..pat)
 end
 E.lightKind='nav'; E.lightSize=5
 local n0=#p.lights
 Editor.mousepressed(sx,sy,1); Editor.mousereleased(sx,sy,1)
 check(#p.lights==n0+1 and p.lights[#p.lights].size==5 and not p.lights[#p.lights].w,'nav light ignored size')
 -- the station still loads with panes
 local Export=require('src.editor.export')
 local def=require('src.data').defineStation(Export.stationDef(d))
 check(def,'station with panes did not validate')
 -- multi-select: box lights, move them as a group, edit together, delete together
 E.tool='select'; E.boxMode='lights'; E.lsel=nil; E.lmulti={}
 local total=#p.lights
 local bx0,by0=Canvas.toScreen(E,x0-50,y0-50)
 local bx1,by1=Canvas.toScreen(E,x1+50,y1+50)
 -- start the box outside every part
 local ox,oy=Canvas.toScreen(E,x1+5000,y1+5000)
 E.view.zoom=E.view.zoom*0.5
 bx0,by0=Canvas.toScreen(E,x0-50,y0-50); bx1,by1=Canvas.toScreen(E,x1+50,y1+50)
 Editor.mousepressed(bx0-200,by0-200,1); Canvas.mousemoved(E,bx1+5,by1+5); Editor.mousereleased(bx1+5,by1+5,1)
 local grp=Canvas.lightSelection(E)
 check(#grp>=total,'box selected '..#grp..' of '..total..' lights')
 local fx,fy=grp[1].x,grp[1].y; local lx,ly=grp[2].x,grp[2].y
 local gx,gy=Canvas.toScreen(E,fx,fy)
 Editor.mousepressed(gx,gy,1); Canvas.mousemoved(E,gx+20,gy); Editor.mousereleased(gx+20,gy,1)
 check(math.abs((grp[1].x-fx)-(grp[2].x-lx))<1e-6 and grp[1].x~=fx,'group light move')
 E.deleteSelected()
 check(not p.lights or #p.lights==0,'group light delete left '..(p.lights and #p.lights or 0))
 -- points: box a part's corners and delete them, keeping a valid polygon
 E.sel=best; E.boxMode='points'; E.vsel=nil; E.vmulti={}
 local npts=#p.shape/2
 Editor.mousepressed(bx0-200,by0-200,1); Canvas.mousemoved(E,bx1+5,by1+5); Editor.mousereleased(bx1+5,by1+5,1)
 E.sel=E.sel or best
 check(#Canvas.vertexSelection(E)==npts,'box selected '..#Canvas.vertexSelection(E)..' of '..npts..' points')
 E.deleteSelected()
 check(#p.shape/2==3,'point delete left '..(#p.shape/2))
 print(('light tool: %d checks passed'):format(checks))
end
