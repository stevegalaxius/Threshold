# Freight capacity

## Contracts and manifests

Economy orders are capped at 30 cargo volume rather than 120 item units. The actual ship's grid hold remains authoritative when fitting cargo. A trader builds a manifest from available contracts sharing its pickup and destination; different goods and price quotes remain separate lines. Every line keeps its original unit prices, AU quote, payment and history outcome. Completion pays once per line and removes the companion contracts.

Reserved contracts remain on the board while the trader flies to pickup. Their source quantities are unavailable to other freight assignments. The economy subtracts both open and reserved outgoing commitments before promising more stock. Pickup marks the lines loaded, so they are no longer subtracted from source inventory; destination inbound accounting includes every line throughout the trip. Cancellation before pickup releases reservations; cargo lost after pickup does not put fictitious goods back on the board. The shared stock API protects reserved quantities from station consumers, including factory inputs, food consumption, NPC supplies, repairs and player purchases. Physical stock remains distinct from available stock. The owning contract ID authorizes withdrawal at pickup; a player trade staged before a reservation is revalidated at settlement.

## Dispatch

Urgency combines remaining reserve coverage with shortage consequences: food and reactor fuel, then production inputs, then ordinary inventory. Destination/commodity shortage clocks survive contract replacement and save/load; they clear only when physical stock recovers to its reorder threshold. Incoming cargo does not clear the clock. Orders retain placement age as a fallback; age can eventually outweigh urgency so less critical freight still moves. Within these priorities, NPCs compare payment for the amount their hold can carry against estimated delivery and empty pickup time. Ambition increases the reward preference and reduces reluctance to fly empty. Freight pays 200 credits handling plus delivered m³ × (10 + 6 × route AU). Partial loads retain a proportional share of their original order’s handling allowance; a mixed manifest caps total handling at 200 credits. New economy listings have a 30-second player browsing window before NPC selection or manifest bundling. This waiting period does not remove their workload or suitable idle haulers from the arbiter’s capacity estimates.

Travel estimates are deliberately inexpensive: 120 seconds locally or 300 across regions, plus 120 seconds per quoted AU and 180 seconds for a remote pickup. They are planning estimates, not reservations or enforced arrival times.

## Population arbiter

Once a minute, open freight is grouped by source/destination. Cargo volume divided by a nominal 30-volume load estimates trips, with a quarter-trip minimum per route. Multiply by estimated route duration and an age factor (up to twice normal) to estimate waiting ship-seconds. Missing production alone creates no freight population pressure.

Idle capacity is credited only for reachable, eligible freight that fits the current hold, with fuel, access, work preferences and blocking actions checked. Busy capacity receives at most one quarter credit, further discounted by estimated remaining phase time and any later action arrival deadline. Suspended, servicing or fuel-disabled haulers receive no busy capacity credit. These capacities offset workload over a ten-minute clearance window. Busy ships count toward the source region they service; idle ships count where they are. Pending population targets are accounted for before requesting additional ships. Targets rise by at most one extra ship per minute per region and fall slowly. Existing regional extra caps, global budget calculation and miner population rules remain in place; ships are not deleted when demand falls.

F6's Freight capacity panel shows waiting ship-minutes, idle/busy traders, additional population targets, goods without surplus production, reserved units awaiting pickup and units in transit. These are tuning estimates; gameplay observation should guide the clearance window and nominal load size.

`love . --freighttest` checks reservations, cleanup/cancellation, mixed pickup/delivery, per-contract settlement, urgency/aging and workload sensitivity. It is also included in the smoke suite.
