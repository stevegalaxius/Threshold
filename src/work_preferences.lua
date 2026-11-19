-- Profiles describe usual work, independently of identity, faction and traits.
-- Choose a category once per accepted-job cycle; score opportunities normally
-- inside it. Offer counts cannot drown out a preference, and idle retries do
-- not reroll it. Missing preferred work leaves other eligible work available.
local W={profiles={
 freight_regular={transport=9,passenger=3,salvage=1,mine=1,patrol=1,satrefuel=1,satlaunch=1},
 scavenger={transport=1,passenger=1,salvage=9,mine=1,patrol=1,satrefuel=3,satlaunch=3},
 -- miners: the drills' ore is all of the system's iron and ice, so digging
 -- wins about 9 cycles in 10 (at mine=9 with sat jobs at 3 it was half)
 industrial={transport=1,salvage=1,mine=40,patrol=1,satrefuel=1,satlaunch=1},
 local_police={transport=0,salvage=0,mine=0,patrol=9}, -- police never take civilian work
 raider={transport=0,salvage=1,mine=1,raid=9}, -- too criminal to haul freight; dark-access haulers smuggle
 generalist={transport=1,passenger=2,salvage=1,mine=1,patrol=1,satrefuel=1,satlaunch=1},
 ship_hauler={ship_delivery=9,transport=1},
}}
function W.profile(r)
 r.workProfile=r.workProfile or 'generalist'
 return assert(W.profiles[r.workProfile],'unknown NPC work profile '..r.workProfile)
end
function W.weight(r,kind)
 local profile=W.profile(r)
 return r.workWeights and r.workWeights[kind] or profile[kind] or 0
end
function W.rank(r,kind)
 local weight=W.weight(r,kind)
 if not weight then return 0 end
 if weight<=0 then return -math.huge end
 local key=r.id..'/'..(r.jobsStarted or 0)..'/'..kind
 local seed=7193
 for i=1,#key do seed=(seed*31+key:byte(i))%2147483647 end
 for _=1,3 do seed=seed*48271%2147483647 end
 -- Exponential race: 9:1 weights give a 90:10 category split when both
 -- have suitable work, without counting each offer as another lottery ticket.
 return math.log(math.max(1,seed)/2147483647)/weight
end
return W
