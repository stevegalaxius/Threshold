return function(game)
 local C=require('src.editor.comparison')
 local Editor,Debug=require('src.editor'),require('src.debugui')
 local E=Editor.state
 local Ship,data,T=require('src.ship'),require('src.data'),require('src.tuning')
 local Export=require('src.editor.export')
 local checks=0
 local function check(ok,msg)assert(ok,msg);checks=checks+1 end
 local function near(a,b)return math.abs(a-b)<.001 end
 game.autosaveOff=true
 E.openHull('halcyon_wisp');Editor.open(game)
 local live=game.player;local bodies=game.world:getBodyCount()
 local hull=data.hulls.halcyon_wisp;local catalogCount=#data.list.hulls
 -- Use the real top-level key handler, even while editor inputs have focus.
 local Slab=require('lib.Slab');local focus=Slab.IsAnyInputFocused
 Slab.IsAnyInputFocused=function()return true end
 Debug.visible=true;love.keypressed('f1')
 check(not Debug.visible and Editor.isOpen(),'F1 could not hide debug inside the editor')
 love.keypressed('f1')
 check(Debug.visible and Editor.isOpen(),'F1 could not reopen debug inside the editor')
 Slab.IsAnyInputFocused=focus;Debug.visible=false
 local result=assert(C.compare(E.design,'halcyon_wisp',false))
 check(result.current and result.reference,'valid design failed comparison')
 local fresh=Ship.new(game,{hull=assert(data.prepareHull(Export.hullDef(E.design))),grid=true})
 local catalogShip=Ship.new(game,{hull='halcyon_wisp',grid=true})
 local expected=Ship.performance(fresh)
 local referenceExpected=Ship.performance(catalogShip)
 for _,key in ipairs({'mass','accel','topSpeed','afterburnTopSpeed','sideAccel','turnAccel','turnSpeed'}) do
  check(near(Ship.performance(result.current)[key],expected[key]),'design does not match live F1 '..key)
  check(near(Ship.performance(result.reference)[key],referenceExpected[key]),'reference does not match live F1 '..key)
 end
 fresh.body:destroy();catalogShip.body:destroy()
 check(game.player==live and game.world:getBodyCount()==bodies,'comparison altered the live ship/world')
 check(data.hulls.halcyon_wisp==hull and #data.list.hulls==catalogCount,'comparison overwrote the ship catalogue')
 local same=assert(C.compare(E.design,'halcyon_wisp',false))
 check(same.current==result.current and same.reference==result.reference,'unchanged preview rebuilt its bodies')
 E.design.stats.mass=hull.mass*2;E.design.stats.drag=hull.drag*.5
 local changed=assert(C.compare(E.design,'halcyon_wisp',false))
 local perf=Ship.performance(changed.current)
 check(perf.mass>expected.mass and perf.accel<expected.accel,'hull mass edit did not update handling')
 check(perf.topSpeed>expected.topSpeed,'drag edit did not update top speed')
 check(near(Ship.performance(changed.reference).mass,expected.mass),'design edits changed reference stats')
 check(C.world:getBodyCount()==2,'editing leaked preview bodies')
 local before=perf.afterburnTopSpeed
 local boost=T.boostThrust;T.boostThrust=boost*2
 check(Ship.performance(changed.current).afterburnTopSpeed>before,'afterburner readout ignores live tuning')
 T.boostThrust=boost
 local rows=C.rows(changed.current);local afterburnRow
 for _,row in ipairs(rows) do if row[1]=='Max afterburner speed' then afterburnRow=row end end
 check(afterburnRow and near(afterburnRow[2],before),'comparison omitted maximum afterburner speed')
 -- Main-engine-only boost must not multiply a stronger hull thruster fallback.
 local fallback=Export.copy(E.design)
 for i,slot in ipairs(fallback.slots) do if slot.family=='engine' then fallback.loadout[i]=false end end
 fallback.stats.sideThrust=1000
 local jets=assert(C.compare(fallback,'halcyon_wisp',true)).current
 local jetsPerf=Ship.performance(jets)
 check(near(jetsPerf.topSpeed,jetsPerf.afterburnTopSpeed),'hull-only thrust was incorrectly boosted')
 local empty=assert(C.compare(E.design,'brute_anvil',true))
 check(empty.current.cargoMass==0 and empty.reference.cargoMass==0,'empty-hold setting left cargo mass')
 check(empty.reference.hull.id=='brute_anvil','reference selector compared the wrong ship')
 local invalid=Export.copy(E.design);invalid.parts={}
 local broken=assert(C.compare(invalid,'brute_anvil',true))
 check(not broken.current and broken.currentError and broken.reference,'incomplete hull hid the valid reference or crashed')
 check(data.hulls.halcyon_wisp==hull and #data.list.hulls==catalogCount,'invalid preview polluted the catalogue')
 -- Render a real comparison window and the editor together.
 C.open=true;C.selected='brute_anvil';C.emptyHolds=false
 local canvas=love.graphics.newCanvas(love.graphics.getDimensions())
 for _=1,3 do
  Debug.update(1/60,game);Editor.update(1/60)
  love.graphics.setCanvas(canvas);love.graphics.clear();Editor.draw();Debug.draw();love.graphics.setCanvas()
 end
 canvas:newImageData():encode('png','ship-comparison.png')
 check(C.open,'comparison window failed to remain open')
 Editor.close()
 check(not C.world and not next(C.previews),'closing editor retained preview physics')
 check(game.world:getBodyCount()==bodies and game.player==live,'comparison changed gameplay after closing')
 print(('SHIP COMPARISON TEST PASSED (%d checks)'):format(checks))
end
