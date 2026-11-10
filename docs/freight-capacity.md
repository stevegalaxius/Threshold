# Freight capacity

## Contracts and manifests

Economy orders are capped at 30 cargo volume rather than 120 item units. The actual ship's grid hold remains authoritative when fitting cargo. A trader builds a manifest from available contracts sharing its pickup and destination; different goods and price quotes remain separate lines. Every line keeps its original unit prices, AU quote, payment and history outcome. Completion pays once per line and removes the companion contracts.

Reserved contracts remain on the board while the trader flies to pickup. Their source quantities are unavailable to other freight assignments. The economy subtracts both open and reserved outgoing commitments before promising more stock. Pickup marks the lines loaded, so they are no longer subtracted from source inventory; destination inbound accounting includes every line throughout the trip. Cancellation before pickup releases reservations; cargo lost after pickup does not put fictitious goods back on the board. Local consumption can still reduce physical stock before pickup, in which case the trip releases its reservation and retries through ordinary job selection.

## Dispatch

Urgency combines remaining reserve coverage with shortage consequences: food and reactor fuel, then production inputs, then ordinary inventory. Orders retain placement age; age can eventually outweigh urgency so less critical freight still moves. Within these priorities, NPCs compare payment for the amount their hold can carry against estimated delivery and empty pickup time. Ambition increases the reward preference and reduces reluctance to fly empty. Player-visible freight rates remain based on route AU.

Travel estimates are deliberately inexpensive: 120 seconds locally or 300 across regions, plus 120 seconds per quoted AU and 180 seconds for a remote pickup. They are planning estimates, not reservations or enforced arrival times.

## Population arbiter

Once a minute, open freight is grouped by source/destination. Cargo volume divided by a nominal 30-volume load estimates trips, with a quarter-trip minimum per route. Multiply by estimated route duration and an age factor (up to twice normal) to estimate waiting ship-seconds. Missing production alone creates no freight population pressure.

Idle trader hull capacity and half of busy hauling capacity offset the workload over a ten-minute clearance window. Busy ships count toward the source region they service; idle ships count where they are. Pending population targets are accounted for before requesting additional ships. Targets rise by at most one extra ship per minute per region and fall slowly. Existing regional extra caps, global budget calculation and miner population rules remain in place; ships are not deleted when demand falls.

F6's Freight capacity panel shows waiting ship-minutes, idle/busy traders, additional population targets, goods without surplus production, reserved units awaiting pickup and units in transit. These are tuning estimates; gameplay observation should guide the clearance window and nominal load size.

`love . --freighttest` checks reservations, cleanup/cancellation, mixed pickup/delivery, per-contract settlement, urgency/aging and workload sensitivity. It is also included in the smoke suite.
