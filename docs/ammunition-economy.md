# Ammunition manufacturing

Zhongke Intelligent Manufacturing shares 24 batches per game hour across their ballistic ammunition recipes. Local input prices and reachable customer bids, less freight, determine profit per batch and gradually shift factory allocations. Industry shortages reduce production through the existing food system. Production requires actual steel plates and explosives.

| Product | Output per batch | Steel plates | Explosives |
|---|---:|---:|---:|
| Solid Rounds S / M | 200 / 100 | 1 | 1 |
| Airburst Rounds S / M | 200 / 100 | 1 | 3 |
| Explosive Shells S | 24 | 1 | 2 |
| Explosive Shells M | 12 | 2 | 3 |
| Explosive Shells L | 12 | 4 | 6 |
| Scatter Shells S | 64 | 1 | 1 |
| Scatter Shells M | 32 | 2 | 1 |
| Scatter Shells L | 24 | 4 | 2 |

Each recipe stores up to eight batches. Full storage or missing ingredients does not bank unused factory time. Factories start without finished ammunition; supported customer stations start with two inventory stacks per ammo type and retain that reserve target. Usage also informs the existing demand calculation. Ordinary freight replenishes shortages.

NPC rearming respects each weapon's selected ammunition and takes only what the station has. Shortages leave ships partially supplied. Player purchases consume the same finite stock; sales replenish it. These products bypass automatic shop restocking. Debug supplies remain unlimited. Missiles, torpedoes, drones and flares retain their existing supply behavior.

F6's factory production and prices panel shows allocations, stock, prices, margins and customer demand. The focused check is `love . --ammunitiontest`; it also runs in the smoke suite. Freight handling and population planning are described in [freight-capacity.md](freight-capacity.md).
