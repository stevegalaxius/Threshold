-- Profiles describe usual work, independently of identity, faction and traits.
-- Choose a category once per accepted-job cycle; score opportunities normally
-- inside it. Offer counts cannot drown out a preference, and idle retries do
-- not reroll it. Missing preferred work leaves other eligible work available.
local W={profiles={
 freight_regular={transport=9,salvage=1},
 scavenger={transport=1,salvage=9},
}}
local defaults={trader='freight_regular',courier='freight_regular',salvager='scavenger'}
function W.profile(r)
 r.workProfile=r.workProfile or defaults[r.role]
 return r.workProfile and W.profiles[r.workProfile]
end
function W.weight(r,kind)
 local profile=W.profile(r)
 if not profile then return nil end -- other controllers are not opted in yet
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
