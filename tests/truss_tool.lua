-- Drives the Primitive tool's truss shape: drags a box on a ship, checks it
-- adds one part per member (two rails plus struts) in a single undo step,
-- and that a tall box makes a vertical truss.
return function(game)
 local Editor=require('src.editor')
 local E=Editor.state
 local Canvas=require('src.editor.canvas')
 local checks=0
 local function check(ok,msg) assert(ok,msg);checks=checks+1 end
 Editor.open(game)
 E.view.x,E.view.y,E.view.zoom=0,0,3
 E.tool='rect'; E.primitive='truss'; E.trussPattern='warren'; E.trussBay=16; E.trussThick=2; E.snap=false; E.mirrorNew=false
 local before,undo=#E.design.parts,#E.undo
 local ax,ay=Canvas.toScreen(E,-100,200)
 local bx,by=Canvas.toScreen(E,100,224)
 Editor.mousepressed(ax,ay,1); Canvas.mousemoved(E,bx,by); Editor.mousereleased(bx,by,1)
 local added=#E.design.parts-before
 check(added==2+2+13,'warren truss made '..added..' parts')
 check(#E.undo==undo+1,'truss took more than one undo step')
 E.undoStep()
 check(#E.design.parts==before,'undo left truss parts behind')
 for _,pat in ipairs({'x','ladder'}) do
  E.trussPattern=pat
  check(#Canvas.truss(E,0,0,200,24)>2,pat..' made no struts')
 end
 -- tall box: rails run vertically
 E.trussPattern='ladder'
 local s=Canvas.truss(E,0,0,20,90)[1]
 local w,h=0,0
 for k=1,#s,2 do w=math.max(w,s[k]);h=math.max(h,s[k+1]) end
 check(h==90 and w==2,'tall truss rail is not vertical')
 print(('truss tool: %d checks passed'):format(checks))
end
