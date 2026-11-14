--[[
	NPC rank: rookie, proficient, elite, veteran.

	Rank shapes what a ship spawns with (budget, how carefully it picks a
	hull), how well it refits (src/npc_refit.lua) and how bravely it fights
	(src/personality.lua). Veteran is never rolled at spawn, only earned.

	R.roll(roll)        -> rank id for a new arrival
	R.get(r)            -> tier table for a record (rookie if unset)
	R.policy(p, rank)   -> purchase policy copy with rank budget/sharpness
	R.experience(r, n)  -> add experience; ranks up at thresholds
]]
local R={}
R.order={'rookie','proficient','elite','veteran'}
R.tiers={
 rookie    ={name='Rookie',    budget=.6, sharpness=1.5,refitChance=.3,refitMargin=.15,nerve=-.1, xp=0},
 proficient={name='Proficient',budget=1,  sharpness=4,  refitChance=.6,refitMargin=.08,nerve=0,   xp=10},
 elite     ={name='Elite',     budget=1.5,sharpness=6,  refitChance=.9,refitMargin=.04,nerve=.05, xp=30},
 veteran   ={name='Veteran',   budget=2,  sharpness=8,  refitChance=1, refitMargin=.02,nerve=.1,  xp=60},
}
-- Spawn odds (veteran is earned only).
R.spawn={{'rookie',.55},{'proficient',.35},{'elite',.10}}

function R.roll(roll)
 local x=(roll or love.math.random)()
 for _,e in ipairs(R.spawn) do x=x-e[2];if x<0 then return e[1] end end
 return R.spawn[#R.spawn][1]
end
function R.get(r) return R.tiers[r and r.rank or 'rookie'] or R.tiers.rookie end
function R.policy(policy,rank)
 local t=R.tiers[rank] or R.tiers.proficient;local p={}
 for k,v in pairs(policy) do p[k]=v end
 p.budget=math.floor(policy.budget*t.budget);p.sharpness=t.sharpness;p.rank=rank
 return p
end
-- Experience comes from surviving trips (one per completed dock visit).
function R.experience(r,n)
 r.rankXp=(r.rankXp or R.get(r).xp)+(n or 1)
 local before=r.rank or 'rookie'
 for _,id in ipairs(R.order) do if r.rankXp>=R.tiers[id].xp then r.rank=id end end
 return r.rank~=before
end
return R
