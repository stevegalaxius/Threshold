return function(game)
 local M,T=require('src.mining'),require('src.tuning')
 local Save=require('src.save')
 local function world()
  return {clock=0,stations={},mining={resources={},sites={test={id='test',area='phobos',x=0,y=0,radius=100,angle=0,ore='rock',sequence=0,productionAt=0,productionCarry=0}}}}
 end
 local a,b=world(),world()
 for t=1,60 do a.clock=t;M.advanceProduction(a,t) end
 b.clock=60;M.advanceProduction(b,60)
 assert(Save.encode(a.mining.resources)==Save.encode(b.mining.resources),'resource production depends on update frequency')
 assert(math.abs(a.mining.sites.test.productionCarry-b.mining.sites.test.productionCarry)<1e-8,'fractional production differs')
 a.clock=3600;M.advanceProduction(a,3600)
 local n=0;local first;for id in pairs(a.mining.resources) do n=n+1;first=id end
 assert(n==T.drillCap,'site cap not respected')
 a.clock=7200;require('src.loose').remove(a,first)
 a.clock=7201;M.advanceProduction(a,7201)
 assert(not a.mining.resources['test/chunk/'..(T.drillCap+1)],'full site banked blocked production')
 local saved=assert(Save.decode(Save.encode(a)));saved.clock=7210;M.advanceProduction(saved,7210)
 local count=0;for _ in pairs(saved.mining.resources) do count=count+1 end
 assert(count==T.drillCap,'saved production did not resume')
 -- Scene identity and nearby ships cannot influence output records.
 local remote,online=world(),world();remote.clock=60;online.clock=60
 M.produce({universe=remote,fieldId='elsewhere'},60)
 M.produce({universe=online,fieldId='phobos',entities={{kind='ship'}}},60)
 assert(Save.encode(remote.mining.resources)==Save.encode(online.mining.resources),'visibility changes production')
 print('MINING CLOCK: cadence, saved progress, cap, blocked time and representation parity passed')
end
