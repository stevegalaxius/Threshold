-- Population templates seed identity and equipment preferences, never controllers.
-- $owner and $area are resolved from the spawn location, without faction cases.
local Templates={
 trader={label='Trader',profile='freight_regular',homePurpose='trade',mobile=true},
 salvager={label='Salvager',profile='scavenger',homePurpose='trade'},
 miner={label='Miner',profile='industrial',homePurpose='mining'},
 patrol={label='Faction Police',profile='local_police',homePurpose='trade',archetype='patrol_wisp',affiliation='$owner',
  authorizations={{kind='police',issuer='$owner',jurisdiction='$area'}}},
 pirate={label='Raider',profile='raider',homePurpose='pirateBase',archetype='pirate_wisp',roamingHome=true},
}
function Templates.apply(r,name,area)
 local t=assert(Templates[name],'unknown NPC template '..name)
 r.populationGroup=name;r.label=t.label;r.workProfile=t.profile
 r.homePurpose=t.homePurpose;r.mobile=t.mobile;r.roamingHome=t.roamingHome
 local owner=require('src.npc_access').owner(area)
 local function resolve(v) if v=='$owner' then return owner elseif v=='$area' then return area else return v end end
 r.affiliation=resolve(t.affiliation);r.authorizations={}
 for _,grant in ipairs(t.authorizations or {}) do
  local g={};for k,v in pairs(grant) do g[k]=resolve(v) end
  if g.issuer then r.authorizations[#r.authorizations+1]=g end
 end
 return r
end
return Templates
