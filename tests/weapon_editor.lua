return function(game)
 local data=require('src.data')
 local Export=require('src.editor.export')
 local Editor=require('src.editor')
 local E=Editor.state
 local V=require('src.weapon_visual')
 local checks=0
 local function check(ok,msg) assert(ok,msg); checks=checks+1 end
 Editor.game=game
 E.switchCategory('weapon')
 check(E.category()=='weapon' and E.design.kind=='weapon','weapon tab')
 E.openHull('gun_m_base')
 local d=E.design
 check(d.kind=='weapon' and d.module.weapon.kind=='cannon' and #d.slots==0,'opened a built-in weapon')
 d.id='wtest_gun'; d.name='Test Gun'; d.module.weapon.fireRate=7
 d.parts={ { name='base', shape={-4,-4,4,-4,4,4,-4,4} }, { name='barrel', shape={0,-1,14,-1,14,1,0,1}, barrel=true } }
 d.muzzles={ {14,-2}, {14,2} }
 local def,err=E.define()
 check(def,'defines: '..tostring(err))
 check(data.modules.wtest_gun.art and #data.modules.wtest_gun.art.parts==2,'art registered')
 check(data.items.wtest_gun and data.items.wtest_gun.kind=='module','module item added')
 -- the saved file loads back as the same module
 local src=Export.source(d)
 check(src:match('^%-%- Made in the Shipyard') and src:find('module {',1,true),'module source')
 check(Export.write(d),'saved')
 data.load()
 local m=data.modules.wtest_gun
 check(m and m.weapon.fireRate==7 and m.size=='M' and #m.art.muzzles==2 and m.art.parts[2].barrel==true,'reloads from save')
 local back=Export.fromModule('wtest_gun')
 check(#back.parts==2 and back.module.weapon.fireRate==7,'round trip into the editor')
 -- muzzles take turns
 local slot={}
 local x1,y1=V.muzzle(m,slot); local x2,y2=V.muzzle(m,slot); local x3,y3=V.muzzle(m,slot)
 check(y1==-2 and y2==2 and y3==-2 and x1==14,'muzzles cycle')
 check(V.muzzle(data.modules.rockbiter,{})==nil,'no art: no muzzle')
 -- kick right after a shot, none at rest
 check(V.kick({w=m.weapon,cooldown=1/7})>0 and V.kick({w=m.weapon,cooldown=0})==0,'barrel kick')
 -- test fire fits it to the ship
 game.playerHull='brute_anvil'
 local hull=data.hulls.brute_anvil
 local fits=0
 for _,s in ipairs(hull.slots) do if data.fits(s,m) then fits=fits+1 end end
 E.testFly()
 if fits>0 then
  local n=0
  for _,id in ipairs(game.player.loadout) do if id=='wtest_gun' then n=n+1 end end
  check(n==fits,'fitted to every matching slot')
  local wn=0
  for _,w in ipairs(game.player.weapons) do if w.module.id=='wtest_gun' then wn=wn+1 end end
  check(wn==fits,'weapons built')
 end
 E.deleteSaved('wtest_gun.lua')
 check(not love.filesystem.getInfo(Export.FOLDER..'/wtest_gun.lua'),'cleaned up')
 print(('WEAPON EDITOR TEST PASSED (%d checks)'):format(checks))
end
