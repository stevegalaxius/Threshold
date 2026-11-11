# Manufacturing integration smoke review

Ship assembly now uses declared recipes, the shared input/time executor, typed dealer outputs, and the economy's station-independent schedule. Dealer reads initialize/read inventory but do not replenish it.

Checks performed:

- Focused dealership integration: remote assembly via economy update, explicit frame use, processing time, saved partial progress, repeated-time idempotence, reserved frames, full sales lots, no banked replacement on purchase, physical parking, and actual game save/load of dealer stock.
- Existing bounded smoke suite: lifecycle/fuel, stockpile, food, chemicals, steel, all sixteen ammunition recipes, electronics, generic multi-output industry, freight, NPC jobs/actions, driver service, reputation, events and scavenging.
- Existing bounded action suite: activation, docking and driver queues, avoidance, scheduler, wreck salvage and representation handoffs.

All passed. Long persistence/movement suites and economy soaks were omitted. These checks validate behavior, not long-term economic balance or scene frame times.

Remaining follow-up decisions:

Physical parking is now enforced: production and timed restocking require actual suitable space, reserving the bottom quarter of hangar rows and the two largest berths for guests. A focused loaded/remote geometry check passes, including full-space blocking without input use, resuming after a sale, no instant banked replacement, and saved occupancy. Existing unallocated or invalid parked records block further production until resolved.

1. **Outfitting material costs.** A ship output includes its selected trim's modules. Frames account for the hull, but assembly does not consume separately manufactured engines, reactors, weapons or electronics for the installed fit. This is the boundary for the future module-manufacturing chain at Zhongke, not a failure of frame consumption.
2. **Gameplay tuning.** Red Furnace's two processing units/hour allow an Anvil or Runt in one hour and a Nautilus in two, before penalties. Guided and ballistic ammunition compete for Zhongke's capacity. The smoke checks do not establish whether those rates create the desired player-facing availability.
