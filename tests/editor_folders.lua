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
 print(('EDITOR FOLDERS TEST PASSED (%d checks)'):format(checks))
end
