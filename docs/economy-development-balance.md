# Economy development balance

This is a temporary stabilization pass to keep traffic moving ahead of the next dealership expansion. It does not establish long-term economic equilibrium.

One deuterium canister now provides 10,000 energy instead of 2,500, for both players and NPCs. This deliberately lowers fuel demand while ship supply and replacement fleets are developed. Revisit this tuning once that work is in place. Stations no longer hand out free emergency canisters: refueling withdraws real inventory.

The underlying corrections are separate from that balance adjustment:

- Producers can import goods they also manufacture, allowing Ceres to receive empty canisters.
- Unmet output demand can increase a factory's requested capacity even when inputs are missing, propagating demand upstream within the existing scale limits. Discretionary industry consumption backs off when its stock is scarce.
- A station settles its shops together. Competing recipes share scarce inputs with stable weighted allocation rather than whichever shelf was queried first taking everything. Canister pressing and fuel refining have input weight four; other recipes default to one. Recipes cannot reserve inputs for batches blocked by another missing ingredient.
- Offline work spends the capacitor already charged by the common reactor update; it no longer runs a second reactor timestep.
- Fuel service waits for actual refueling before departure. Resuming a delayed visit uses the current clock rather than retroactively travelling from the old departure deadline.

## Validation

The focused economy-feedback checks, bounded smoke suite, and action smoke suite pass. The bounded smoke run excluded the long persistence and NPC movement suites.

A diagnostic offline-dominant soak used seed 34711, five-second updates, and three simulated hours with these settings. At the end, all 40 fuel-service stations had stock (2,851 canisters total); no station spent more than a quarter of the run dry. The existing economy harness's fuel-coverage assertion passed. The detailed log is retained locally as `/tmp/feedback-development.log`.

This single short run demonstrates useful development circulation, not a fully balanced economy. Coarse-step NPC behavior, replacement ship availability, and longer-term material shortages remain outside this stabilization pass. Dealership acquisition logic was not expanded here.
