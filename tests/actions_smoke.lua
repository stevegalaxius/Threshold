-- Bounded real-engine action checks: love . --actiontest
return function(game)
 local Game=require('src.game')
 for i,suite in ipairs({'tests.npc_actions','tests.npc_work','tests.salvager','tests.npc_actions_live','tests.npc_activation','tests.dock_queue','tests.driver_queue','tests.avoidance','tests.npc_scheduler','tests.wreck_salvage','tests.npc_handoff','tests.npc_home'}) do
  if i>1 then game=Game.new() end
  game.autosaveOff=true
  require(suite)(game)
 end
 print('NPC ACTION SMOKE PASSED')
end
