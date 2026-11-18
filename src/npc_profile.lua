--[[
	An NPC's flight and combat profile (data/npc_profiles.lua), from its job:
	hauler and miner fly civilian, guards as police, raiders as raiders.

	  r.aiProfile   the profile id, set at spawn and on load
	  r.archetype   only on garrison ships, which still fight as the enemy
	                they were placed as (src/garrison.lua); older saves'
	                archetypes are turned into a profile on load
]]
local data=require('src.data')
local P={}
P.byJob={hauler='hauler',miner='miner',guard='police',raider='raider'}
function P.forJob(job) return P.byJob[job or ''] or 'hauler' end
-- The definition a record (or a wreck of one) flies with.
function P.of(r)
 if not r then return end
 return data.npcProfiles[r.aiProfile or ''] or data.enemies[r.archetype or ''] or data.npcProfiles.hauler
end
-- Older saves: an A-Life record that borrowed an enemy preset takes its
-- job's profile instead. Garrison ships keep theirs.
function P.migrate(r)
 if r.garrison then return r end
 if not r.aiProfile then r.aiProfile=P.forJob(require('src.npc_templates').job(r)) end
 r.archetype=nil
 return r
end
return P
