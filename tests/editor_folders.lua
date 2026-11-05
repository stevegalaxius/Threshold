return function(game)
 local data=require('src.data')
 local Export=require('src.editor.export')
 local E=require('src.editor').state
 local checks=0
 local function check(ok,msg) assert(ok,msg); checks=checks+1 end
 check(Export.cleanFolder('a/../b c//d\\e')=='a/b_c/d/e' and Export.cleanFolder('x.lua')=='x.lua','cleanFolder')
 E.newDesign('hull'); E.openHull(data.list.hulls[1])
 local d=E.design; d.id='foldertest_ship'
 check(E.makeFolder('tests/fighters')=='tests/fighters','makeFolder'); d.folder='tests/fighters'
 check(Export.write(d),'export into folder')
 check(love.filesystem.getInfo(Export.FOLDER..'/tests/fighters/foldertest_ship.lua'),'file in folder')
 check(Export.folderOf('foldertest_ship')=='tests/fighters','folderOf')
 d.folder='tests'; Export.write(d)
 check(not love.filesystem.getInfo(Export.FOLDER..'/tests/fighters/foldertest_ship.lua'),'move left old copy')
 check(love.filesystem.getInfo(Export.FOLDER..'/tests/foldertest_ship.lua'),'moved')
 -- reloads from subfolders
 data.load(); check(data.hulls.foldertest_ship,'subfolder design loads')
 E.deleteSaved('tests')
 check(love.filesystem.getInfo(Export.FOLDER..'/tests','directory'),'non-empty folder kept')
 E.deleteSaved('tests/foldertest_ship.lua')
 check(not love.filesystem.getInfo(Export.FOLDER..'/tests/foldertest_ship.lua'),'file deleted')
 E.deleteSaved('tests/fighters')
 E.deleteSaved('tests')
 check(not love.filesystem.getInfo(Export.FOLDER..'/tests'),'folders deleted')
 -- files copied in by hand show up without any editor action
 local src=Export.source(E.design)
 Export.list(); love.filesystem.createDirectory(Export.FOLDER..'/handcopy')
 love.filesystem.write(Export.FOLDER..'/handcopy/foldertest_ship.lua',src)
 love.timer.sleep(1.1)
 local seen=false
 for _,e in ipairs(Export.list()) do if e.rel=='handcopy/foldertest_ship.lua' then seen=true end end
 check(seen,'hand-copied file listed')
 -- another mod's data folder is browsable
 love.filesystem.createDirectory('mods/zz_handmod/data/ships')
 love.filesystem.write('mods/zz_handmod/data/ships/foldertest_ship.lua',src)
 Export.refresh(); local modDir,modFile=false,false
 for _,e in ipairs(Export.list()) do
  if e.rel=='@zz_handmod' and e.dir then modDir=true end
  if e.rel=='@zz_handmod/ships/foldertest_ship.lua' and e.path=='mods/zz_handmod/data/ships/foldertest_ship.lua' then modFile=true end
 end
 check(modDir and modFile,'other mod listed')
 check(Export.isFolder('@zz_handmod/ships'),'mod subfolder resolves')
 check(not Export.remove('@zz_handmod'),'mod root protected')
 love.filesystem.remove('mods/zz_handmod/data/ships/foldertest_ship.lua'); love.filesystem.remove('mods/zz_handmod/data/ships'); love.filesystem.remove('mods/zz_handmod/data'); love.filesystem.remove('mods/zz_handmod')
 love.filesystem.remove(Export.FOLDER..'/handcopy/foldertest_ship.lua'); love.filesystem.remove(Export.FOLDER..'/handcopy')
 print(('EDITOR FOLDERS TEST PASSED (%d checks)'):format(checks))
end
