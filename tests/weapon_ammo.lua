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
 check(gun.weapon.kind=='cannon' and mortar.weapon.kind=='cannon','guns and artillery are not cannons')
 local g,m,r=data.ammoOptions(gun),data.ammoOptions(mortar),data.ammoOptions(rack)
 check(g[1]=='rounds_m' and has(g,'shell_m') and not has(g,'shell_s'),'cannon ammo options wrong')
 check(m[1]=='shell_m' and has(m,'rounds_m'),'mortar does not load shells first, or rounds at all')
 check(r[1]=='missile_m' and has(r,'torp_m') and has(r,'torp_s') and not has(r,'torp_l'),'rack ammo options wrong')
 for id,mod in pairs(data.modules) do check(not (mod.weapon and mod.weapon.kind=='torpedo'),'torpedo weapon left: '..id) end
 -- fire rate: own ammo at full rate, heavier slower, lighter no faster
 check(data.fireRate(gun.weapon,'rounds_m')==gun.weapon.fireRate,'cannon rate with rounds changed')
 check(math.abs(data.fireRate(gun.weapon,'shell_m')-gun.weapon.fireRate/4)<1e-9,'shells not slower in an autocannon')
 check(data.fireRate(mortar.weapon,'rounds_m')==mortar.weapon.fireRate,'rounds fired faster than a mortar cycles')
 check(math.abs(data.fireRate(rack.weapon,'torp_m')-rack.weapon.fireRate/6)<1e-9,'torpedo rate wrong')
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
