-- Selectable ammo: cannons load rounds or shells, missile racks missiles or
-- torpedoes, the pick is per slot and saved, and old ids still load.
return function(game)
 local data,Ship,Weapons=require('src.data'),require('src.ship'),require('src.weapons')
 local checks=0
 local function check(ok,msg) assert(ok,msg);checks=checks+1 end
 local function has(t,v) for _,x in ipairs(t) do if x==v then return true end end end
 local gun,mortar,rack=data.modules.gun_m_base,data.modules.artillery_m_base,data.modules.missile_m_base
 check(gun and mortar and rack,'lower-case _base ids missing')
 check(data.modules.gun_m_base==gun and data.modules.maul_tube==data.modules.missile_s_base,'old ids do not resolve')
 check(gun.weapon.kind=='cannon' and mortar.weapon.kind=='cannon' and mortar.weapon.chambers[1]=='artillery','guns and artillery should be cannons that chamber their ammo')
 local g,m,r=data.ammoOptions(gun),data.ammoOptions(mortar),data.ammoOptions(rack)
 check(#g==1 and g[1]=='rounds_m','a plain gun should chamber only its rounds')
 check(#m==1 and m[1]=='shell_m','a plain mortar should chamber only its shells')
 check(r[1]=='missile_m' and has(r,'torp_m') and has(r,'torp_s') and not has(r,'torp_l'),'rack ammo options wrong')
 for id,mod in pairs(data.modules) do check(not (mod.weapon and mod.weapon.kind=='torpedo'),'torpedo weapon left: '..id) end
 -- a gun that lists more families chambers them, its own first
 local combo={ id='t', size='M', family='weapon', weapon={ kind='cannon', fireRate=3, chambers={ 'gun', 'shotgun' } } }
 local c=data.ammoOptions(combo)
 check(c[1]=='rounds_m' and has(c,'buckshot_m') and not has(c,'shell_m'),'chambers list ignored')
 check(data.fireRate==nil,'per-ammo fire rate still there')
 -- a shotgun fires a fan of pellets that fly as rounds
 local sg=data.modules.shotgun_m_base
 check(sg and data.ammoOptions(sg)[1]=='buckshot_m','shotgun does not load buckshot')
 do
  local en=Ship.new(game,{hull='brute_anvil',loadout={'shotgun_m_base',false,false,false,'mule_engine','kiln_reactor',false},x=5000,y=5000})
  en.cargo.buckshot_m=5
  en.intent=en.intent or {}
  en.intent.aimX,en.intent.aimY=6000,5000
  local before=#game.projectiles
  Weapons.fire(game,en,en.weapons[1],0.016)
  local n=#game.projectiles-before
  check(n==data.items.buckshot_m.shot.pellets,'shotgun fired '..n..' pellets')
  check(game.projectiles[#game.projectiles].kind=='gun' and en.cargo.buckshot_m==4,'pellets should fly as rounds and take one shell')
 end
 -- per-slot pick
 local e=Ship.new(game,{hull='estates_bastion',loadout=data.hulls.estates_bastion.loadout,x=0,y=0})
 local slot,bay
 for _,w in ipairs(e.weapons) do if w.module.id=='missile_l_base' then bay=w.index end end
 check(bay,'test hull has no missile rack')
 local function at() for _,w in ipairs(e.weapons) do if w.index==bay then return w end end end
 slot=at()
 check(slot.ammo=='missile_l','rack did not default to missiles')
 Ship.setLoad(e,bay,'torp_m')
 slot=at()
 check(slot.ammo=='torp_m','picked ammo not loaded')
 local rec=Ship.record(e)
 check(rec.loads[bay]=='torp_m','pick not in the ship record')
 Ship.setLoad(e,bay,'rounds_m')
 slot=at()
 check(slot.ammo=='missile_l','an ammo the weapon cannot take was loaded')
 check(Weapons.cycleAmmo==nil,'global launcher cycling still there')
 print(('weapon ammo test: %d checks passed'):format(checks))
end
