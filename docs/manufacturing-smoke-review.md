# Manufacturing integration smoke review

Ship assembly now uses declared recipes, the shared input/time executor, typed dealer outputs, and the economy's station-independent schedule. Dealer reads initialize/read inventory but do not replenish it.

Checks performed:

- Focused dealership integration: remote assembly via economy update, explicit frame use, processing time, saved partial progress, repeated-time idempotence, reserved frames, full sales lots, no banked replacement on purchase, physical parking, and actual game save/load of dealer stock.
- Existing bounded smoke suite: lifecycle/fuel, stockpile, food, chemicals, steel, all sixteen ammunition recipes, electronics, generic multi-output industry, freight, NPC jobs/actions, driver service, reputation, events and scavenging.
- Existing bounded action suite: activation, docking and driver queues, avoidance, scheduler, wreck salvage and representation handoffs.

All passed. Long persistence/movement suites and economy soaks were omitted. These checks validate behavior, not long-term economic balance or scene frame times.

Remaining follow-up decisions:

1. **Sales capacity versus physical parking.** Manufacturing stops at the dealer's lot limit. It may still produce a ship without a free physical bay or berth; that ship awaits allocation. Decide whether those ships represent off-site storage or whether production should require a space. Online-only parking checks would introduce a representation mismatch, so a stricter rule needs a saved station parking model usable remotely.
2. **Outfitting material costs.** A ship output includes its selected trim's modules. Frames account for the hull, but assembly does not consume separately manufactured engines, reactors, weapons or electronics for the installed fit. This is the boundary for the future module-manufacturing chain at Zhongke, not a failure of frame consumption.
3. **Gameplay tuning.** Red Furnace's two processing units/hour allow an Anvil or Runt in one hour and a Nautilus in two, before penalties. Guided and ballistic ammunition compete for Zhongke's capacity. The smoke checks do not establish whether those rates create the desired player-facing availability.
