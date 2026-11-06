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
 check(c[1]=='rounds_m' and has(c,'shot_m') and not has(c,'shell_m'),'chambers list ignored')
 check(data.fireRate==nil,'per-ammo fire rate still there')
 -- a shotgun fires a fan of pellets that fly as rounds
 local sg=data.modules.shotgun_m_base
 check(sg and data.ammoOptions(sg)[1]=='shot_m','shotgun does not load shot')
 do
  local en=Ship.new(game,{hull='brute_anvil',loadout={'shotgun_m_base',false,false,false,'mule_engine','kiln_reactor',false},x=5000,y=5000})
  en.cargo.shot_m=5
  en.intent=en.intent or {}
  en.intent.aimX,en.intent.aimY=6000,5000
  local before=#game.projectiles
  Weapons.fire(game,en,en.weapons[1],0.016)
  local n=#game.projectiles-before
  check(n==data.items.shot_m.shot.pellets,'shotgun fired '..n..' pellets')
  check(game.projectiles[#game.projectiles].kind=='gun' and en.cargo.shot_m==4,'pellets should fly as rounds and take one shell')
 end
 -- missile racks: tubes hold capacity in S units, re-arm per round
 do
  local en=Ship.new(game,{hull='estates_bastion',loadout=data.hulls.estates_bastion.loadout,x=8000,y=8000})
  local rk
  for _,w in ipairs(en.weapons) do if w.module.id=='missile_l_base' then rk=w end end
  en.cargo.missile_l=5; en.cargo.missile_s=20; en.cargo.torp_l=3
  en.intent=en.intent or {}; en.intent.aimX,en.intent.aimY=9000,8000
  Weapons.arm(en,rk,0)
  check(Weapons.tubes(rk)==2 and rk.armed==2,'fresh L rack should start with 2 L missiles armed')
  for _=1,3 do rk.cooldown=0; Weapons.fire(game,en,rk,0.016) end
  check(rk.armed==0 and en.cargo.missile_l==3,'rack fired more than its tubes held')
  Weapons.arm(en,rk,data.items.missile_l.shot.armTime-0.01)
  check(rk.armed==0,'armed too early')
  Weapons.arm(en,rk,0.02)
  check(rk.armed==1,'did not arm after its arm time')
  Ship.setLoad(en,rk.index,'missile_s')
  for _,w in ipairs(en.weapons) do if w.index==rk.index then rk=w end end
  Weapons.arm(en,rk,0)
  check(Weapons.tubes(rk)==8 and rk.armed==0,'S missiles should pack 8 into an L rack, and swapping ammo should empty the tubes')
  check(data.items.torp_l.shot.armTime>data.items.missile_l.shot.armTime,'torpedoes should arm slower than missiles')
 end
 -- lasers: one kind; pulsed ones light for `pulse` per shot, others while held
 do
  local pl,bm=data.modules.pulse_m_base.weapon,data.modules.beam_s_base.weapon
  check(pl.kind=='laser' and bm.kind=='laser' and pl.pulse and not bm.pulse,'lasers should be one kind, pulse set or not')
  local old=assert(data.defineModule({ id='t_oldpulse', name='t', family='weapon', size='S', mass=1, weapon={ kind='laser', damage=30, powerPerShot=20, pulse=0.1, fireRate=1, range=100 } }))
  check(math.abs(old.weapon.damage-300)<1e-6 and math.abs(old.weapon.powerPerSecond-200)<1e-6 and old.weapon.powerPerShot==nil,'old per-shot pulse not converted to per second')
  local en=Ship.new(game,{hull='brute_anvil',loadout={'pulse_m_base',false,false,false,'mule_engine','kiln_reactor',false},x=12000,y=12000})
  local sl=en.weapons[1]
  sl.w={}; for k,v in pairs(pl) do sl.w[k]=v end
  sl.w.beams, sl.w.beamSpread, sl.w.color = 5, 20, { 1, 0.2, 0.2 }
  en.power=1000; en.intent=en.intent or {}; en.intent.aimX,en.intent.aimY=13000,12000
  Weapons.fire(game,en,sl,0.016)
  check(sl.litLeft==sl.w.pulse,'pulse did not light')
  local p0=en.power
  Weapons.burn(game,en,sl,0.05)
  check(sl.beams and #sl.beams.lines==5 and sl.beams.color[2]==0.2,'shotgun laser should fire 5 colored lines')
  check(math.abs((p0-en.power)-sl.w.powerPerSecond*0.05)<1e-6,'laser power not per second while lit')
  Weapons.burn(game,en,sl,1); Weapons.burn(game,en,sl,0.01)
  check(sl.litLeft<=0,'pulse should go dark after its length')
 end
 -- atomic warheads: a missile that vaporizes what it kills (no wreck)
 do
  check(data.items.atomic_l.family=='missile' and has(data.ammoOptions(data.modules.missile_l_base),'atomic_l'),'atomic should be L missile ammo')
  local victim=Ship.new(game,{hull='brute_anvil',loadout=data.hulls.brute_anvil.loadout,x=20000,y=20000,team=2})
  local listed=false; for _,e in ipairs(game.entities) do if e==victim then listed=true end end
  if not listed then table.insert(game.entities,victim) end
  local husks=0; for _,e in ipairs(game.entities) do if e.kind=='husk' then husks=husks+1 end end
  game:explode(20000,20000,3000,25000,0,nil,victim,'atomic')
  check(victim.dead and victim.vaporized,'atomic blast should vaporize')
  game:reap()
  local after=0; for _,e in ipairs(game.entities) do if e.kind=='husk' then after=after+1 end end
  check(after==husks,'a vaporized ship left a husk')
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
