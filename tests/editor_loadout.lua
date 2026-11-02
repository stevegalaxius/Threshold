return function(game)
 local data=require('src.data')
 local Export=require('src.editor.export')
 local E=require('src.editor').state
 local checks=0
 local function check(ok,msg) assert(ok,msg); checks=checks+1 end
 E.newDesign()
 E.openHull(data.list.hulls[1])
 local d=E.design
 local initial=Export.hullDef(d)
 for i in ipairs(d.slots) do check(initial.loadout[i]==data.hulls[d.base].loadout[i],'opening changed default') end
 local slot=1
 local item
 for _,id in ipairs(data.list.modules) do if data.fits(d.slots[slot],data.modules[id]) then item=id;break end end
 assert(item,'fixture has no compatible module')
 E.pushUndo(); E.ensureLoadout()[slot]=item
 check(Export.hullDef(d).loadout[slot]==item,'custom default lost')
 E.undoStep(); check(Export.hullDef(E.design).loadout[slot]==initial.loadout[slot],'undo lost original default')
 E.redoStep(); d=E.design
 check(Export.hullDef(d).loadout[slot]==item,'redo lost selection')
 Export.autosave(d)
 check(Export.loadAutosave().loadout[slot]==item,'autosave lost default')
 local source=Export.source(d)
 local def
 local chunk=assert(loadstring(source));setfenv(chunk,{hull=function(v) def=v end});chunk()
 check(def.loadout[slot]==item,'source export lost default')
 def.id='editor_loadout_probe'
 assert(data.defineHull(def))
 local ship=require('src.ship').new(game,{hull=def.id,x=50000,y=50000})
 check(ship.loadout[slot]==item,'new ship missing default equipment')
 ship.body:destroy()
 d.loadout[slot]=false
 check(Export.hullDef(d).loadout[slot]==false,'empty selection inherited base default')
 d.loadout[slot]=item
 d.slots[slot].family=data.modules[item].family=='reactor' and 'engine' or 'reactor'
 E.validateSlotDefault(slot)
 check(d.loadout[slot]==false,'incompatible default survived slot edit')
 d.loadout=nil
 check(E.ensureLoadout()~=nil,'legacy design did not initialize defaults')
 print(('EDITOR LOADOUT TEST PASSED (%d checks)'):format(checks))
end
