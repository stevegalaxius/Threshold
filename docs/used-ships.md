# Used ships and NPC acquisition

Station sales inventory is shared by the player and replenishment arrivals. Stations without a named dealer have a four-space used-ship exchange; its Shipyard tab is exposed to the player. Named dealerships keep their configured lot capacity. The four factory dealerships also manufacture new ships.

Factory dealerships have dedicated stations:

| Maker | Location | Layout |
|---|---|---|
| Intaki | Red Furnace Shipyard, Mars (`station:mars_1`) | `shipyard_1` |
| Brute | Brute Industries Shipyard, Mercury (`station:mercury_3`) | `shipyard_1` |
| Ferrous | Ferrous Collective Shipyard, Earth (`station:earth_3`) | `shipyard_1` |
| MACK | MACK Industrial Works, Ceres (`station:belt_2`) | supplied `shipyard_2` |

Mercury and Earth each have three stations. Mars keeps its three existing stations including Heaven-Ladder. Haephestus Logistics retains its hydrogen industry and equipment store; Elysium retains its farm and general market. Their assembly facilities and factory dealer definitions moved to the dedicated shipyards, which receive frames through ordinary freight. Assembly capacities, maker lineups, pricing and sales-lot limits are unchanged.

The economy's existing schedule occasionally delivers used ships only to fallback exchanges at stations without a configured dealership or ship-production facility. Named resellers replenish new ships from their configured lineups; factories receive no timed ship deliveries and replenish through assembly. Existing owned lots and player transactions are preserved. `D.usedShips` in `data/industry.lua` defines the incoming fit pool, default eight-hour interval, discount, and 70–95% armor condition. Ordinary named dealers keep their configured interval. Fits are drawn from declared ship presets, without tying a sale to the identity of its eventual buyer. Price reflects actual fit, discount and condition. Ships include two fuel canisters. Hulls, fits, paint, condition, price and parking persist with each lot.

All arrivals and opening stock require commercial parking; guest reserves remain protected. Time spent without space does not bank a later flood of deliveries. Opening fallback exchange inventory is used stock; named dealership inventory is new stock from its configured lineup. Manufactured outputs remain new. Player purchases preserve actual armor condition and fuel rather than replacing a used ship with a pristine instance.

Population targets and arrival intervals are unchanged. Replenishment arrivals now use an abstract wider ship market: 80% generate a ship, and 20% attempt to buy a local used ship. A missing suitable used lot falls back to generation, so empty hangars cannot block population recovery. The cheapest eligible used lot is selected; factory-new showroom ships remain available to the player. `D.npcShips` in `data/industry.lua` controls these proportions.

Generated ships come from the four factory lineups. Each hull starts with weight one, plus its recent completed production across all factories. Each completion adds one to that hull's weight; production influence halves every 12 game hours. These saved tallies are independent of stock queries, opening inventory, used deliveries and generated arrivals, so spawning a ship cannot inflate its own production weight. The baseline preserves variety and allows recovery when factories stall. Production affects future arrivals, not existing NPC ships or population targets.

Declarative acquisition policies in `npc_templates.lua` still supply budget, cargo and capability requirements. Generated ships retain their stock fit, adding a compatible gun or drill when required; unsuitable hulls are excluded before weighted selection. Fit-adjusted price must fit the budget, and propulsion and reactor power are required. Generated ships receive starting fuel and ammunition within hold space from the abstract arrival market; they do not withdraw local station supplies or consume hull frames. This intentionally abstracts the wider fleet supply rather than modelling every hull's construction.

Factory assembly still consumes real frames and needs commercial parking. Every two game hours a factory may sell one new showroom ship at least two hours old to the wider market. Used lots are preserved, and missed wholesale intervals never accumulate a catch-up purge. These sales free showroom space so production can continue even without local buyers. Only completed assembly affects fleet weights; a wholesale sale does not count the same hull twice.

The acquired record is installed before the NPC controller selects work. Its identity, preferences, faction affiliation and authority still come from the population template. A used purchase removes that specific lot from the player's list and releases its commercial parking, preserving its equipment and armor condition. Acquisition provenance distinguishes used purchases from generated ships; simulation history records both, as well as wholesale sales. The acquisition budget is separate from player funds; its unspent balance becomes the arriving NPC's operating credits. This abstracts the NPC's pre-arrival financing rather than adding debt or off-screen income simulation.

Starting-world population seeding remains pre-existing ownership; subsequent arrivals through `Population.spawn` use the mixed supply policy. Initial scene construction does not retroactively buy the existing population from the opening sales lots. Player trade-ins and direct ship sales retain their existing sale behavior; this change does not add a buyback market for those records.

`love . --usedshiptest` checks shared inventory, affordability, an actual population arrival purchase, empty-market generated fallback, production weighting and decay, compatible fits for each population template, saved weights/provenance, wholesale turnover, player access to the exchange, and a missing-electronics production explanation. The scenario is included in the smoke suite.

Heaven-Ladder remains one economy with shared markets, industry and cargo storage. Its four anchors have independent owned-ship hangars, exterior berth occupancy and docking queues, identified by their physical access locations. Stored ships remain at their anchor across save/load, and the Hangar tab shows only the anchor where the player is docked. Shared dealer inventory is physically displayed at the primary anchor rather than repeated at all four entrances. Existing unassigned shared hangar ships remain at the primary anchor.
