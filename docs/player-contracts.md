# Player contracts

Dock at any station and open **Contracts**. The global freight list reads the same offers as NPC task selection; it does not generate separate player jobs. Available pickups at the current station sort first. Scroll for the rest. Newly generated freight is visible to players immediately; NPCs can reserve it after a 30-second game-time listing window, including when bundling other orders. This provides a chance to accept work without guaranteeing a permanent backlog.

Each row shows source, destination, cargo quantity/volume, delivery payment and quoted route distance in AU. The accepted quantity is limited to available source stock and space in the current ship’s actual grid hold. For a partial load, the row shows the load versus the full order quantity. The remainder stays on the shared board for other workers. Acceptance takes just the selected order, without NPC-style automatic bundling of other goods on the route.

## Payment

New quotes use **200 credits handling + volume × (10 + 6 × route AU)**. Volume is cargo quantity multiplied by the item’s volume in m³. A full 30 m³ order pays 500 credits locally, 680 at 1 AU, or 1,400 at 5 AU. NPCs and players use the same invoice and rates.

The original order’s handling allowance is divided across its quantity. Accepting half of an order earns half its handling allowance; the remainder retains the other half. Combining several orders on one trip caps total handling at 200 credits. Splitting an existing order never creates another allowance. Rounding down to whole credits can lose a fraction of a credit per line. The active contract displays its handling share within the total reward.

Quotes freeze when created. Accepted contracts retain their price across saves and orbital changes; unclaimed older economy listings are refreshed to the new rates. Manufacturing and freight source selection use volume-based freight costs as well.

## Taking a contract

Only one player contract may be active at a time:

1. **Accept freight** reserves the offer and its source stock. If already at the source, cargo loads immediately. Otherwise travel there and use **Load cargo**.
2. Fly to the destination with the goods aboard the current ship, then use **Deliver & collect**. This transfers actual cargo into station stock and pays the existing freight quote into the player’s credits. The shared settlement records the delivery in simulation history and freight statistics.
3. Before pickup, **Cancel contract** releases the reservation. After pickup, return the required cargo to the source and use **Return & cancel**. Missing cargo must be replaced before delivery or return. Goods in station storage or a different ship must first be moved into the current ship.

In flight, open the inventory with Tab and select **Contracts** to read the active assignment. Acceptance and cargo handling require completed station docking. Jobs are rechecked on acceptance, so a stale screen cannot steal an offer already reserved by an NPC.

The owner/task lives in `universe.tasks.player`, alongside the normal offers. Cargo remains in the actual player ship rather than a second saved inventory. Existing task saving includes the contract; cleanup recognizes player ownership, and the normal economy preserves accepted orders. Completion uses the same transport loading, stock and payment code as NPC freight.

This first board exposes real, sourced freight orders. Mining, salvage, patrol and raid entries currently describe ongoing NPC duties without equivalent player contract rewards/completion conditions; those are not advertised as player contracts.

Validation: `love . --contracttest` exercises a partial remote acceptance, NPC competition, reservation cleanup/economy updates, pickup, real save/load, missing cargo, exact and single payment, both cancellation paths, authorization and the rendered station/in-flight UI. `love . --freighttest` checks the existing NPC freight behavior. The contract suite is included in `--smoketest`.
