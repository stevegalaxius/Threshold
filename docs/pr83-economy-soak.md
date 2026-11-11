# PR #83 simulation soak

Tested revision: `86445a2`. No repository gameplay code or tuning changed during this review.

## Runs and scope

- A full 24-game-hour economy run using the existing five-second offline update step.
- A separate six-hour turnover run, retiring one trader, miner, salvager and patrol before each of hours 2–6: 20 retirements in total. Each retirement released its tasks before being marked escaped. This exercises population replenishment without claiming to simulate combat losses.
- World seed 34711, explicitly set before `Game.new`, plus explicit population scheduling. Temporary instrumentation recorded hourly commodity flows, fuel conditions, fleet/hull counts, factory blocking reasons, arrival sources, wholesale sales and Lua memory. Full final save states were retained.

Both runs passed the existing fuel-coverage assertion and completed without runtime exceptions. These are individual diagnostic worlds, not statistically paired experiments. The provisional **10,000 energy per fuel canister** remains in force. This does not validate the original 2,500-energy balance or live navigation, rendering performance, combat or weapon consumption.

## Coverage and circulation

| Game hour | Station fuel stock | Dry stations | Active NPCs | Ships assembled, cumulative | Wholesale sales, cumulative |
|---|---:|---:|---:|---:|---:|
| 1 | 2,013 | 0/40 | 205 | 0 | 0 |
| 6 | 4,841 | 0/40 | 205 | 8 | 8 |
| 12 | 4,214 | 0/40 | 205 | 20 | 20 |
| 18 | 4,020 | 0/40 | 205 | 34 | 32 |
| 24 | 4,377 | 0/40 | 205 | 41 | 43 |

Every hourly baseline sample had fuel at all 40 service stations and normal fuel status for every active NPC. This sampling does not rule out brief shortages between checks. After hour one the fleet stayed at 205: 93 traders, 40 miners, 18 patrols, 44 pirates and 10 salvagers. Baseline arrivals totalled 64 generated ships and 10 used purchases; population targets then held the fleet steady rather than continuously spawning ships.

Hourly Lua allocation samples ranged from 15.6 to 32.3 MiB without a sustained upward trend. The baseline retained 205 NPC records. These samples are not a formal memory-leak or FPS benchmark.

Full-run recorded flows:

| Good | Made | Used | Hauled | Final station stock |
|---|---:|---:|---:|---:|
| Iron ore | 29,115 | 24,551 | 26,404 | 4,600 |
| Empty canisters | 21,439 | 17,441 | 17,662 | 4,002 |
| Reactor fuel | 15,732 | 12,574 | 11,012 | 4,377 |
| Food | 42,041 | 35,417 | 28,520 | 14,919 |
| Steel plates | 1,556 | 1,489 | 919 | 755 |
| Hull frames | 123 | 76 | 95 | 49 |
| Electronics | 448 | 319 | 401 | 129 |

Fuel “used” means physical station withdrawals recorded by the economy, not direct measurement of reactor energy burn. Generated arrivals and incoming sale lots retain their abstract starting supplies. Stocks exclude cargo in transit, so this table is not a complete material-conservation ledger. Trade activity continues after the initial stocking period; food and raw-material totals are not evidence that every route or factory is equally well supplied.

The turnover run ended with 197 active NPCs and 217 total records, all active NPCs sampled in normal fuel condition. It recorded 73 generated arrivals, 13 used purchases and 8 wholesale sales, with no saved arrival deferral at its hourly snapshots. Active counts need not replace every retirement one-for-one: normal targets and arrival timers remain in force. Retired records remain stored; this deserves an archive/retention policy before substantially longer, high-attrition games, although this run did not demonstrate runaway memory growth.

## Confirmed assembly-selection bug

The economy is circulating, but production-derived fleet preferences currently inherit a scheduler bias. `Industry.finished` clears the completed job and records the last hull. The recipe loop can then select the next job, after which the legacy post-loop rotation advances it again. This repeatedly skips particular hulls rather than honouring the intended shortest-stock job policy.

An isolated 12-hour Brute probe supplied ample frames/food and removed parking limits:

| Code | Runts | Anvils | Nautiluses |
|---|---:|---:|---:|
| Tested PR revision | 5 | 0 | 4 |
| Temporary copy with the second post-loop advance removed | 4 | 3 | 3 |

The second row is a diagnosis in a temporary copy, **not a repository fix or a rerun of the full-world soak**. Real parking/stock conditions can force other selections, so the bug does not mean an Anvil can never be manufactured in the actual world.

Actual full-world completed hulls:

| Maker | Completed hulls |
|---|---|
| Brute | Runt 8, Anvil 1, Nautilus 1 |
| Ferrous | Runner 8, Mule 0, Bison 3 |
| MACK | Mustang 8, Burro 0, Longhorn 3 |
| Intaki | Wisp 7, Praetor 2, Archangel 0 |

The four factories ended with full sales lots and 2–4 frames each; Heaven-Ladder held its 36-frame storage cap. Late-run output was therefore constrained by showroom turnover and job selection, rather than a global lack of frames.

Fix this scheduler before interpreting the resulting NPC hull mix as an honest reflection of factory supply. It is a control-flow problem, not a reason to increase industrial rates.

## Showroom capacity and isolated content

Timed used deliveries compete with new factory stock for the same commercial parking. Wholesale removes only new ships, so incoming used stock can progressively reduce assembly/display capacity. A separate 32-hour factory probe, with frames/food supplied and real parking rules intact, left two used ships at Red Furnace; assembly continued, but intermittently. This demonstrated crowding, not a permanent deadlock. Reserve some factory commercial capacity for manufactured output or keep used intake from consuming that capacity; retain the existing guest reserve.

The one recurring food shortage was `station:station_1` (Hub Station), inside `Fields.station`, an isolated instance with no freight connection. It reached the 50% industry food floor. Connected-world food coverage held at the hourly samples. Give isolated instances an explicit local supply policy or exclude them from persistent economy demand; increasing global food production cannot connect a missing route.

## Recommended next work

1. Remove the duplicate assembly-job advance and verify that the existing dealer checks exercise consecutive real completions.
2. Protect factory output capacity from accumulation of timed used deliveries.
3. Define the isolated-instance food policy and keep it separate in soak coverage.

The current fuel band-aid supports continued development in this full-day offline run. The evidence does not call for another blanket fuel-rate increase. No fixes or new balance adjustments were applied by this review.

Raw logs, hourly audits, final saves, the audited harness and isolated probes are retained locally in `soak-results/pr83/`. Full final states are about 2 MiB each and are not committed.
