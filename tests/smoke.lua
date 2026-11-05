-- A-Life smoke test: love . --smoketest
-- A quick check that the persistent simulation still works end to end:
-- NPC lifecycles, reactor fuel and stranding, loose-object records and area
-- persistence, and salvagers/pirates working loot offline. Not a spec of
-- exact numbers; rewrite freely as the design moves.
return function(game)
 local Game=require('src.game')
 for i,suite in ipairs({'tests.npc_lifecycle','tests.reactor_fuel','tests.persistence','tests.salvager'}) do
  -- Each part gets a fresh universe so one can't leave fixtures for the next.
  if i>1 then game=Game.new() end
  game.autosaveOff=true
  require(suite)(game)
 end
 print('A-LIFE SMOKE TEST PASSED')
end
