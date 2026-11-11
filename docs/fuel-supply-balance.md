# Fuel supply at the original energy value

Fuel remains **2,500 energy per canister**. No emergency fuel grants, fuel-consumption reductions or NPC controller changes were added by this balance pass. It changes the authored supply chain and finite opening inventory.

## Throughput budget

The restored-fuel run failed to bootstrap: workers entered refueling visits, station shelves emptied, mining and freight stopped, and adding traders only added more refueling demand. Raising refinery capacity without feeding it is insufficient. The first capacity-only pilot also consumed ore faster than mining supplied it; it was not accepted as a fix.

The final settings account for both fuel and the hydrogen industry:

| Facility | Nominal output/hour |
|---|---:|
| Heaven-Ladder canister press | 12,000 empty canisters |
| Ceres canister press | 1,200 empty canisters |
| Ceres fuel cracking | 1,200 fuel canisters |
| Each of four Jupiter/Uranus fuel refineries | 2,400 fuel canisters |

One ore now presses two empty canisters. The existing fractional input-credit mechanism keeps inventory withdrawals whole. Empty-canister storage is 6,000 per producer and fuel storage is 4,000 per producer.

At the existing minimum adaptive scale of 25%, supplied, fully fed plants provide **3,300 empty canisters/hour** and **2,700 fuel canisters/hour**. Hydrogen skimming can use up to 208 canisters/hour at maximum scale. Thus the pressing budget covers the fuel baseline plus hydrogen, rather than allocating all canisters to fuel on paper. Baseline pressing uses 1,650 ore/hour, leaving room for steel within the mining throughput measured in the pilots. Food shortages and missing inputs can still lower actual output; these are capacity budgets, not guaranteed deliveries.

Fuel service stations keep a minimum target of 120 canisters and open with 240. Presses/refineries receive half an hour of their authored input requirements on creation. These buffers initialize once through the existing inventory system; they are not periodic grants or a way to refill an empty station. Existing saved inventories are preserved.

## Validation and limits

All world runs use seed 34711 and the existing five-second offline economy step, with population scheduling and hourly audits. These are individual diagnostic worlds; code changes can change RNG consumption, so they are not isolated statistical A/B experiments.

| Run | Duration | Fuel result |
|---|---:|---|
| Original 2,500-energy value, old supply rates; assembly/delivery fixes present | 24 hours | Failed: 36/40 stations dry at the end; only 600 fuel made over the whole day |
| Higher supply, two canisters per ore, lower pressing capacity | 12 hours | Fuel coverage passed, but pressing made 34,206 against 34,934 consumed; not accepted as the final input balance |
| Final pressing headroom and supply settings above | 6 hours | Passed; all 40 service stations stocked at every hourly check; production covers each tested stage's consumption |

The capacity-only pilot was stopped after four hourly samples because its ore buffer was draining. It is not a completed soak or a passing result. The six-hour final configuration is distinct from the twelve-hour, lower-pressing variant; the final rates have not had a full-day run.

Final six-hour totals:

| Stage | Newly produced/mined | Consumed/withdrawn | Hauled | Final station stock |
|---|---:|---:|---:|---:|
| Iron ore | 14,415 | 11,486 | 13,396 | 6,259 |
| Empty canisters | 21,931 | 18,411 | 19,347 | 8,920 |
| Reactor fuel | 17,646 | 14,577 | 9,269 | 12,209 |

New production exceeds consumption at all three stages across the final run. The last three hours also maintain that margin: 8,100 fuel made versus 6,928 withdrawn, 9,900 empty canisters made versus 8,332 consumed, and 7,431 ore mined versus 5,228 consumed. Opening stocks are not making up a net material deficit. Fuel withdrawals also exceed the world's opening station fuel inventory. Station totals omit cargo in transit, so the table is not a complete conservation ledger. Hourly samples do not rule out brief shortages between checks.

The final world had 199 active NPCs, all sampled in normal fuel condition at the end. Freight and manufacturing continued. The twelve-hour recovery run completed all twelve factory hull types, exercising the assembly-selection fix beyond its focused regression check. The remaining food shortage in both recovery runs was isolated Hub Station, which has no freight connection; connected stations remained fed at the samples.

Existing dealership, industry, reactor/NPC fuel lifecycle and focused economy-feedback checks passed during the change. The generated manufacturing catalogue and Mars industry notes reflect the new settings. This supports the observed scenario at the original energy value; it does not establish live combat demand, navigation performance or indefinite equilibrium. No AI refueling thresholds or two-canister dealership arrival allowances were changed to obtain these results.

Raw logs, hourly audits and final saves are retained locally in `soak-results/pr83-original-fuel/`, `soak-results/pr83-fuel-capacity-pilot/`, `soak-results/pr83-fuel-supply/` and `soak-results/pr83-fuel-headroom/`.
