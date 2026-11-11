# Electronics and guided ammunition

The new goods are silicon, industrial acids, and electronics. They use ordinary finite stock, quoted freight, local prices and reservation-aware production.

| Producer | Facility | Rated hourly output |
|---|---|---:|
| Terminator Station, Mercury | Silicon refinery | 12 silicon |
| Apollo Heritage Foundation, Luna | Silicon refinery | 12 silicon |
| Hub Station, Venus | Acid works | 8 industrial acids |
| Pele Works, Io | Acid works | 8 industrial acids |
| Jita Orbital Logistics, Earth | Electronics factory | 4 batches / 32 electronics |
| Thule Prime, Luna | Electronics factory | 4 batches / 32 electronics |

Silicon and acids are abstract station extraction/refining, without additional mineable ores or intermediates. Each electronics batch consumes two silicon and one industrial acid to make eight electronics. Electronics plants allocate by profit/customer demand; their maximum rate is not unconditional output. Raw suppliers have fixed capacity. Existing food shortage penalties apply to these facilities.

Zhongke shares its existing 24 processing units/hour among ballistic and guided ammunition. Every missile/torpedo batch consumes steel plates, explosives and electronics:

| Ammunition | Batch output | Steel | Explosives | Electronics | Processing time |
|---|---:|---:|---:|---:|---:|
| Missile S | 40 | 1 | 1 | 1 | 1 |
| Missile M | 20 | 2 | 2 | 1 | 1 |
| Missile L | 12 | 4 | 4 | 2 | 2 |
| Torpedo S | 4 | 4 | 8 | 2 | 2 |
| Torpedo M | 2 | 6 | 12 | 3 | 3 |
| Torpedo L | 1 | 8 | 16 | 4 | 4 |

All six types use the same service reserve policy as the other manufactured ammunition: two stacks at supported customer stations, none as a minimum at the producer, plus observed usage demand. NPC rearming consumes actual inventory and can be partial; shop timers cannot replenish these types. Freight and player purchases use the existing stock/usage paths. Drones and flares retain their previous supply behavior. Weapon behavior is unchanged.

There is no automatic electronics or raw-material opening stock. Facilities must receive their inputs through existing freight. Rates and batch sizes are initial gameplay tuning values; no new population or arbiter rules are introduced.

`love . --electronicstest` checks source geography/rates, both electronics inputs, electronics freight to Zhongke, missing-electronics blocking for all guided types, and finite missile/torpedo rearming. The existing ammunition check now exercises all sixteen recipes and their shared processing budget.
