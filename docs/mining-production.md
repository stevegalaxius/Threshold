# Mining production clock

Sites accumulate elapsed production at a steady interval equal to the old emission interval's mean: (2.5 + 8) / 2 = 5.25 seconds per chunk before the existing crew modifier. Chunk appearance, trajectory and potential yield still use the deterministic per-site sequence. Emission timing no longer depends on that random sequence or the number of update calls.

Saved site state contains `productionAt` and fractional `productionCarry`. Production creates ordinary persistent resource records, with historical birth/settle times, up to the existing cap of 18 outstanding resources per site. Station ore stock caps still stop production. Full sites discard blocked time. Collection/removal settles the affected site's production before freeing its capacity. Existing asteroid drilling, collection and delivery remain unchanged.

A site's active scene, physical outline and ships crossing the muzzle no longer change its production schedule or spawn records. Bodies materialize from those records at their current simulated positions, waiting if the position is obstructed. Effects use the existing emission timestamps rather than replaying a burst of physical ejections after visiting an area. Old saves without a production timestamp begin accounting at their first update; no historical production is invented.

`love . --miningclocktest` compares frequent/coarse calls and visible/remote contexts, and checks saved fractional progress, resource caps, collection-time advancement and blocked production. It is in the smoke suite. Existing live-mining action checks and the bounded smoke/action suites pass.

## Before/after comparison

Four three-game-hour offline-dominant economy runs used the same starting RNG seed (34711), before/after code, and the existing economy harness with hourly audits. Temporary instrumentation counted free emergency fuel grants. No fuel/ore rates or fleet settings were tuned.

| Step | Measure | Before | After |
|---|---|---:|---:|
| 5 seconds | Water ice delivered by miners | 630 | 1,048 |
| 5 seconds | Iron ore delivered by miners | 4,361 | 4,250 |
| 5 seconds | Fuel produced | 2,937 | 2,951 |
| 5 seconds | Fuel hauled | 644 | 531 |
| 5 seconds | Final dry fuel-service stations | 33/40 | 34/40 |
| 5 seconds | Free emergency fuel grants | 1,648 | 1,668 |
| 60 seconds | Water ice delivered by miners | 89 | 12 |
| 60 seconds | Iron ore delivered by miners | 461 | 164 |
| 60 seconds | Fuel produced | 250 | 66 |
| 60 seconds | Final dry fuel-service stations | 27/40 | 28/40 |
| 60 seconds | Free emergency fuel grants | 1,080 | 918 |

All four runs completed their requested three hours and failed the existing fuel-coverage assertion. The five-second comparison improves ice delivery by about 66%, but fuel production is effectively unchanged and coverage is not better. Increased raw resource generation alone is not a demonstrated fix for fuel shortages.

The site-level tests establish update-independent emission records under the same cap/collection events. They do not establish update-independent NPC collection, navigation, service or delivery. The coarse full-world runs remain severely cadence-sensitive and are unsuitable for tuning normal-game throughput. They also omit full live physics and combat. A shared initial seed does not keep random streams identical after different decisions consume RNG; these are individual diagnostic runs, not statistical balance guarantees.

Next investigation: mining work/collection timing at coarse steps, ore allocation between canisters and plates, fuel producer input coverage/export reserves, and actual fuel burn versus emergency grants. Logs are retained locally in `soak-results/mining-clock/`. No additional production tuning was applied from these results.
