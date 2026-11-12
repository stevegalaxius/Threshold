# Player contracts

Dock at any station and open **Contracts**. The global freight list reads the same offers as NPC task selection; it does not generate separate player jobs. Available pickups at the current station sort first. Scroll for the rest.

Each row shows source, destination, cargo, delivery payment and quoted route distance in AU. The accepted quantity is limited to available source stock and space in the current ship’s actual grid hold. For a partial load, the row shows the load versus the full order quantity. The remainder stays on the shared board for other workers. Acceptance takes just the selected order, without NPC-style automatic bundling of other goods on the route.

Only one player contract may be active at a time:

1. **Accept freight** reserves the offer and its source stock. If already at the source, cargo loads immediately. Otherwise travel there and use **Load cargo**.
2. Fly to the destination with the goods aboard the current ship, then use **Deliver & collect**. This transfers actual cargo into station stock and pays the existing freight quote into the player’s credits. The shared settlement records the delivery in simulation history and freight statistics.
3. Before pickup, **Cancel contract** releases the reservation. After pickup, return the required cargo to the source and use **Return & cancel**. Missing cargo must be replaced before delivery or return. Goods in station storage or a different ship must first be moved into the current ship.

In flight, open the inventory with Tab and select **Contracts** to read the active assignment. Acceptance and cargo handling require completed station docking. Jobs are rechecked on acceptance, so a stale screen cannot steal an offer already reserved by an NPC.

The owner/task lives in `universe.tasks.player`, alongside the normal offers. Cargo remains in the actual player ship rather than a second saved inventory. Existing task saving includes the contract; cleanup recognizes player ownership, and the normal economy preserves accepted orders. Completion uses the same transport loading, stock and payment code as NPC freight.

This first board exposes real, sourced freight orders. Mining, salvage, patrol and raid entries currently describe ongoing NPC duties without equivalent player contract rewards/completion conditions; those are not advertised as player contracts.

Validation: `love . --contracttest` exercises a partial remote acceptance, NPC competition, reservation cleanup/economy updates, pickup, real save/load, missing cargo, exact and single payment, both cancellation paths, authorization and the rendered station/in-flight UI. `love . --freighttest` checks the existing NPC freight behavior. The contract suite is included in `--smoketest`.
