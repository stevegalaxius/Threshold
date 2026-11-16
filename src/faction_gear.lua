--[[
	What each faction's pilots prefer to fly and fit.

	Every major faction makes one kind of weapon (data/industry.lua
	D.moduleLines) and favors it; factions with shipyards favor their own
	makers' hulls. Preference shades choices, it never forces one: a better
	fit from elsewhere still wins.

	G.faction(r)              -> a record's faction, or nil for loners
	G.prefersModule(f, id)    -> true when faction f makes that module
	G.prefersHull(f, hullId)  -> true when one of f's makers builds that hull
]]
local G={}
-- Faction -> the module line it makes (data/industry.lua D.moduleLines).
G.lines={diwan='launchers',zhuhai='guns',estates='bays',jove='lasers',ceres='drills'}
-- Faction -> the shipbuilders it buys from (data/industry.lua D.lineups).
G.makers={estates={'ferrous','amw','brute'},zhuhai={'redfu','intaki'},ceres={'mack'}}
G.refitBonus=.06   -- added to a refit trial's fit per preferred module it brings in
G.hullWeight=2     -- arrival weight multiplier for a preferred maker's hull

local moduleSets,hullSets
local function build()
 local D=require('data.industry')
 moduleSets,hullSets={},{}
 for faction,line in pairs(G.lines) do
  local set={};moduleSets[faction]=set
  for _,m in ipairs((D.moduleLines[line] or {}).modules or {}) do set[m[1]]=true end
 end
 for faction,makers in pairs(G.makers) do
  local set={};hullSets[faction]=set
  for _,maker in ipairs(makers) do for _,hull in ipairs(D.lineups[maker] or {}) do set[hull]=true end end
 end
end
function G.faction(r) return r and r.affiliation or nil end
function G.prefersModule(faction,id)
 if not (faction and id) then return false end
 if not moduleSets then build() end
 return (moduleSets[faction] or {})[id]==true
end
function G.prefersHull(faction,hull)
 if not (faction and hull) then return false end
 if not hullSets then build() end
 return (hullSets[faction] or {})[hull]==true
end
return G
