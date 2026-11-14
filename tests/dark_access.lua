-- Dark access: raiders and a fixed share of white haulers/miners may work
-- the dark grids; everyone else is kept off dark offers and dark homes.
return function(game)
 local Templates,Access,Dark=require('src.npc_templates'),require('src.npc_access'),require('src.dark')
 local T=require('src.tuning')
 local checks=0
 local function check(ok,msg)assert(ok,msg);checks=checks+1 end
 local n,with=0,0
 for i=1,400 do
  local r=Templates.apply({id='npc/h'..i},'trader','earth');n=n+1
  if r.darkAccess then with=with+1 end
  check(Templates.apply({id='npc/h'..i},'trader','earth').darkAccess==r.darkAccess,'dark access pick is not stable')
 end
 local share=with/n
 check(math.abs(share-T.darkAccessShare)<.07,('dark access share %.2f, want about %.2f'):format(share,T.darkAccessShare))
 check(Templates.apply({id='npc/p'},'pirate','earth').darkAccess,'raider without dark access')
 for i=1,50 do check(not Templates.apply({id='npc/g'..i},'patrol','earth').darkAccess,'guard with dark access') end
 check(Templates.apply({id='npc/x1'},'trader','shoals').darkAccess,'hauler born on a dark grid without dark access')
 -- find a white hauler with and one without
 local yes,no
 for i=1,400 do local r=Templates.apply({id='npc/h'..i},'trader','earth');if r.darkAccess then yes=yes or r else no=no or r end end
 local offer={kind='transport',source='station:shoals_1',target='station:mars_1'}
 check(Access.darkOffer(offer),'Shoals offer not seen as dark')
 check(not Access.darkOffer({kind='transport',source='station:mars_1',target='station:earth_1'}),'white offer seen as dark')
 check(Access.eligible(yes,offer,{cargo=true}) and not Access.eligible(no,offer,{cargo=true}),'dark offer gate wrong')
 check(Access.eligible({player=true},offer,{cargo=true}),'player kept off a dark offer')
 -- every good floats in price on a dark grid, only market goods elsewhere
 local M=require('src.markets')
 check(M.floats('station:shoals_1','food_crate') and not M.floats('station:mars_1','food_crate'),'food price floats in the wrong places')
 -- old saves: someone already homed on a dark grid keeps access
 local old=Templates.migrate({id=no.id,populationGroup='trader',homeStation='station:shoals_1'})
 check(old.darkAccess,'dark-homed old record lost its access')
 -- seeded population: no one without access lives on a dark grid
 local dark,total=0,0
 for _,r in pairs(game.universe.npcs) do
  if r.state~='dead' and r.state~='escaped' then
   total=total+1;if r.darkAccess then dark=dark+1 end
   local home=r.homeStation and require('src.locations').byId[r.homeStation]
   if home and Dark.isDarkArea(home.area) then
    check(Access.darkAccess(r),r.id..' lives on '..home.area..' without dark access')
   end
  end
 end
 print(('DARK ACCESS TEST PASSED (%d checks, haulers %.0f%%, population %d/%d)'):format(checks,share*100,dark,total))
end
