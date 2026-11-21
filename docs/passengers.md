# Residential stations and passengers

Code: `src/passengers.lua`. Config: `residential = { population, storage, routes }` on a station in `src/world_layout.lua`. Housing is its own capability: it grants no industry, market or ship sales.

Authored set: two new housing-only stations and Ring Station.
- Tranquility Commons (Luna, `estates_quadrangle`): commutes to Thule Prime, Apollo Heritage and Jita; visits to Hakka Tulou.
- Hakka Tulou Habitat (Mars, `zhuhai_tulou`): commutes to Heaven-Ladder, Mars's shipyards and Zhuhai Logistics; visits to Ring Station and Tranquility Commons. Heaven-Ladder is the most heavily weighted workplace. The visits are the interplanetary runs.
- Ring Station (the Ring): keeps its market and yard, and adds commutes to Lumen Fabrication and visits to Hakka Tulou.

Tranquility Commons and Hakka Tulou have their own passenger-service market profiles, with climate pods and navigation computers but no dealership. Unspecified station markets use a general supply catalogue without a named dealer; Hub Station Motors belongs only to Venus's Hub Station, where the Shipyard tab exposes it.

## Contracts

- Each residential station may post one contract every `T.passengerInterval` (300 s). Stations are staggered by id.
- Demand cap per home: `clamp(round(population / 1000), 1, 6)` open contracts. Accepted contracts and parties already aboard count toward it.
- A contract that nobody accepts is withdrawn after `T.passengerExpiry` (30 min). Industry never depends on passengers.
- Party size is 1 to 8 and skews small. Each passenger takes one climate cell. Work routes run in both directions: 40% of trips are commuters going home.
- Contracts are `kind='passenger'` offers on the shared board (`src/tasks.lua`). NPCs choose them through work preferences (`passenger` weight: freight_regular 3, generalist 2, scavenger 1, others 0). Players take them on the Jobs tab.

## Fare

`party × (60 + 40 × route AU) × (1 + comfort premium + speed incentive)`

- Comfort premium: up to +40%. It uses the average comfort of the seats the party fills, best seats first. Built-in climate holds carry `comfort` (Wayfarer 1, Pony 0.5). A Climate Pod gives 0.3.
- Speed incentive: up to +25%. It is computed from the ship's NPC cruise speed, which is already capped at ±15% of the reference hull, and only counts the flown share of the journey. Mass-driver legs take everyone the same time, so raw top speed earns nothing extra.
- The fare is locked on acceptance (`t.fare`, `t.fareDetail`), so a refit afterwards does not change it.

## Residential homes

Ships living at a residential station park in its berths, like at any other home. `homes` caps how many new ships choose it: when a home is picked, residential stations with homes to spare come first. Established homes are never redistributed. The idle grace period, home return and work search are all unchanged.

F6 shows the passenger status (parked at residential home, waiting for a home berth, travelling to pickup, carrying N passengers), the locked fare, and why an NPC can't take the nearest passenger contract.

Short check: `/mnt/project-files/notes/passenger_probe.lua` (run it in place of tests/fast.lua).
