# Industry circulation changes

Factories previously combined long historical usage reserves with large full-capacity ingredient reserves. That continued requesting inputs after output bins filled. Fuel recipes also had four times the input allocation weight of competing recipes. Separately, steel and shared chemical capacity lacked comfortable headroom for downstream consumers.

## Rules

- Fuel and other recipes receive equal default input allocation weights.
- Factories plan half an hour of allocated work, bounded by output room, with a starter batch for idle profitable alternatives. Ordinary import orders can refill up to twice this target.
- Factory usage and service usage have separate accounting. Full output bins release unclaimed excess freight; accepted shipments remain intact.
- Assembly requests frames for its next selected ship rather than every potential empty sales slot.
- Fuel energy remains 2,500 per canister. Fuel production capacities and service reserves are unchanged.

## Rated production budget

| Chain | Capacity change | Budget basis |
|---|---|---|
| Heaven-Ladder steel | 120 → 480 plates/hour | Downstream frames and ammunition share the supply |
| Heaven-Ladder frames | 6 → 10/hour | Headroom above installed assembly processing capacity |
| Callisto and Titan chemicals | 80 → 160 processing units/hour each | 320 combined versus 128 fertilizer + 144 peak explosives/hour |
| Ganymede nitrates | 80 → 240/hour | Chemical input headroom |
| Titan and Enceladus nitrates | 40 → 120/hour each | 560 total including Ceres, versus 416/hour chemical input need |
| Silicon, acids, electronics | Rates unchanged; output storage doubled | Existing rated supply exceeds installed manufacturing input needs |

Rated capacity is a budget, not guaranteed throughput: food, prices, inputs, storage and transport still affect actual production. Chemical recipes share processing time; the explosives peak includes the large artillery recipe. The feedback test checks these budgets directly against definitions.

## Surface-mining correction

Ceres emitted accessible ice rocks, but both mining selection and action execution applied the broad sinking-salvage exclusion band. All of that drill’s rocks were rejected. The resource provider now uses the solid body boundary for assigned surface-drill material. Material inside the body is still rejected; ordinary salvage keeps its existing exclusion band.

## Validation scope

Existing focused feedback, commodity, dealer and NPC-action checks cover allocation, material conservation, input buffers, blocked-output release, committed freight and surface mining.

A six-hour fresh-world run used the new demand rules and steel/frame rates, with an earlier smaller chemical budget. Fuel remained stocked at all 42 surveyed stations, and intermediate goods were produced and shipped. That run exposed the Ceres collection defect. It is not a six-hour test of the final configuration.

A separate one-hour continuation loads that six-hour saved world with the final definitions and mining correction, without replacing its inventory with opening stock. At the end of that interval:

- Fuel: 13,635 canisters across all 42 surveyed stations; zero dry stations.
- Surface ice: 498 collected, 483 consumed, 15 remaining. Miner delivery is not counted in the trader freight column.
- Steel: 164 produced and 30 hauled; hull frames: 10 produced and 9 hauled.
- Fertilizer: 113 produced and 73 hauled; explosives: 26 produced and 17 hauled; nitrates: 393 produced and 144 hauled.
- Electronics: 16 produced and 21 hauled (freight also draws existing stock).
- One recipe waiting for an input at the final snapshot: Titan’s farm needed fertilizer. Five recipes were paused by output capacity.
- 202 living NPCs; one surveyed station remained food-short/slow.

Figures come from `soak-results/industry-circulation-verified/1h.log` and its saved final snapshot in the development workspace. The run uses five-second offline simulation steps; the NPC-action suite separately exercises shared action behavior.

These checks demonstrate circulation and recovery over the measured interval. They do not establish indefinite equilibrium. Short input waits and demand-driven idle recipes remain expected; the isolated Hub Station food shortage remains outside this change.
