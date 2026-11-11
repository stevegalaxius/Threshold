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
 check(#g==2 and g[1]=='rounds_m' and has(g,'airburst_m'),'gun should default to solid rounds and accept airburst')
 check(#m==2 and m[1]=='shell_m' and has(m,'shot_m'),'artillery should default to explosive shells and accept scatter')
 check(r[1]=='missile_m' and has(r,'torp_m') and has(r,'torp_s') and not has(r,'torp_l'),'rack ammo options wrong')
 for id,mod in pairs(data.modules) do check(not (mod.weapon and mod.weapon.kind=='torpedo'),'torpedo weapon left: '..id) end
 -- a gun that lists more families chambers them, its own first
 local combo={ id='t', size='M', family='weapon', weapon={ kind='cannon', fireRate=3, chambers={ 'gun', 'artillery' } } }
 local c=data.ammoOptions(combo)
 check(c[1]=='rounds_m' and has(c,'shot_m') and has(c,'shell_m'),'chambers list ignored')
 check(data.fireRate==nil,'per-ammo fire rate still there')
 -- Scatter shells fire a fan through an ordinary artillery mount.
 check(not data.modules.shotgun_m_base and data.items.shot_m.family=='artillery','standalone shotgun category remains')
 do
  local en=Ship.new(game,{hull='brute_anvil',loadout={'artillery_m_base',false,false,false,'mule_engine','kiln_reactor',false},x=5000,y=5000})
  Ship.setLoad(en,en.weapons[1].index,'shot_m')
  en.cargo.shot_m=5
  en.intent=en.intent or {}
  en.intent.aimX,en.intent.aimY=6000,5000
  local before=#game.projectiles
  Weapons.fire(game,en,en.weapons[1],0.016)
  local n=#game.projectiles-before
  check(n==data.items.shot_m.shot.pellets,'scatter shell fired '..n..' pellets')
  check(game.projectiles[#game.projectiles].kind=='gun' and en.cargo.shot_m==4,'pellets should fly as rounds and take one shell')
 end
 -- Airbursts use a fixed fuse, one damage application and a compact effect.
 do
  local en=Ship.new(game,{hull='brute_anvil',loadout={'gun_m_base',false,false,false,'mule_engine','kiln_reactor',false},x=90000,y=90000})
  Ship.setLoad(en,en.weapons[1].index,'airburst_m');en.cargo.airburst_m=5
  en.intent.aimX,en.intent.aimY=100000,90000
  local oldProjectiles=game.projectiles;game.projectiles={}
  Weapons.fire(game,en,en.weapons[1],.016)
  local p=assert(game.projectiles[1])
  check(p.airburst and p.burst and not p.fuse and en.cargo.airburst_m==4,'airburst must use one round and no proximity fuse')
  local x,y=p.x+p.vx*p.life,p.y+p.vy*p.life
  local victim=Ship.new(game,{hull='brute_anvil',loadout=data.hulls.brute_anvil.loadout,x=x,y=y,team=2})
  local armor=victim.armor;local hits=0
  local raycast,damage=game.raycast,game.damage
  game.raycast=function()return nil end
  game.damage=function(self,target,...)if target==victim then hits=hits+1 end;return damage(self,target,...) end
  Weapons.updateProjectiles(game,p.life+.5)
  game.raycast,game.damage=raycast,damage
  check(#game.projectiles==0 and math.abs(p.x-x)<.001 and math.abs(p.y-y)<.001,'airburst overshot its fixed fuse on a long step')
  check(hits==1 and math.abs(armor-victim.armor-p.damage)<.001,'airburst double-hit a hull or changed direct damage')
  check(p.damage<data.items.rounds_m.shot.damage,'airburst direct hit outdamages solid rounds')
  check(game.effects[#game.effects].kind=='airburst','airburst used the generic heavy explosion effect')
  game.projectiles=oldProjectiles
 end
 for _,size in ipairs({'s','m','l'}) do
  check(data.items['shell_'..size].shot.speed>data.items.rounds_m.shot.speed,'artillery shell slower than gun rounds')
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
 -- lasers: pulse and beam kinds, several lines, own color
 do
  check(data.modules.pulse_s_base.weapon.kind=='laser' and not data.modules.pulse_s_base.weapon.beam and data.modules.beam_s_base.weapon.beam,'lasers should be one kind with a beam switch')
  local old=assert(data.defineModule({ id='t_oldbeam', name='t', family='weapon', size='S', mass=1, weapon={ kind='beam', damage=1, powerPerSecond=1, range=100 } }))
  check(old.weapon.kind=='laser' and old.weapon.beam==true,'a beam kind did not load as a beam laser')
  local en=Ship.new(game,{hull='brute_anvil',loadout={'pulse_m_base',false,false,false,'mule_engine','kiln_reactor',false},x=12000,y=12000})
  local sl=en.weapons[1]
  sl.w={}; for k,v in pairs(data.modules.pulse_m_base.weapon) do sl.w[k]=v end
  sl.w.beams, sl.w.beamSpread, sl.w.color = 5, 20, { 1, 0.2, 0.2 }
  en.power=1000; en.intent=en.intent or {}; en.intent.aimX,en.intent.aimY=13000,12000
  Weapons.fire(game,en,sl,0.016)
  check(sl.beams and #sl.beams.lines==5 and sl.beams.color[2]==0.2,'multi-beam laser should fire 5 colored lines')
  -- below the reserve floor lasers still fire, at reduced output
  local T=require('src.tuning')
  en.power=en.stats.powerCap; sl.cooldown=0; sl.beams=nil
  Weapons.fire(game,en,sl,0.016)
  check(sl.beams and sl.beams.alpha==1,'a full capacitor should fire at full output')
  en.power=en.stats.powerCap*T.boostRelight*0.5; en.burnerLocked=true; sl.cooldown=0; sl.beams=nil
  local before=en.power
  Weapons.fire(game,en,sl,0.016)
  check(sl.beams and sl.beams.alpha==T.laserReserve,'lasers on reserve should fire at reduced output, even after afterburning')
  check(en.power==before,'lasers on reserve should not drain the capacitor')
  en.burnerLocked=nil
 end
 check(not data.items.atomic_l,'atomic missile remains')
 -- a slot can face backwards (heading 180): fixed mounts fire that way
 do
  local hull={}; for k,v in pairs(data.hulls.brute_anvil) do hull[k]=v end
  hull.slots={}; for i,sl in ipairs(data.hulls.brute_anvil.slots) do local c={}; for k,v in pairs(sl) do c[k]=v end; hull.slots[i]=c end
  local en=Ship.new(game,{hull='brute_anvil',loadout=data.hulls.brute_anvil.loadout,x=30000,y=30000})
  local wi=en.weapons[1].index
  hull.slots[wi].heading, hull.slots[wi].mount = 180, 'fixed'
  en.hull=hull; Ship.refit(en)
  en.intent=en.intent or {}; en.intent.aimX,en.intent.aimY=31000,30000
  Weapons.update(game,en,0.016)
  local w1=en.weapons[1]
  check(math.abs(math.abs(w1.aim)-math.pi)<1e-6,'a slot facing 180 should aim out the back')
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
