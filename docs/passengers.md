# Residential stations and passengers

Code: `src/passengers.lua`. Config: `residential = { population, storage, routes }` on a station in `src/world_layout.lua`. Housing is its own capability: it grants no industry, market or ship sales.

Authored set: Elysium (Earth: commutes to Jita, Ferrous Shipyard and Ashgrove; visits to Apollo Heritage on the Moon and to Cloudline on Venus), Cloudline (Venus: Hub Station and the AMW Atelier; visits to Elysium) and The Apollo Heritage Foundation (Luna: Thule Prime and Jita; visits to Elysium).

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

## Resident storage

- An idle NPC whose home is a residential station with free storage waits inside the station instead of in a berth (`r.resident`). This only happens offline; a ship on screen keeps its berth. Stored ships do not count toward `src/dock_room.lua` and are never woken into the scene.
- The existing 60 s idle grace period before going home is unchanged, and NPCs never need to visit home between jobs.
- Stored ships check for work every ~30 s, staggered by id. A job is reserved before the ship departs. If no berth frees up within 180 s, the job is released ("waiting to depart" in F6).
- Storage is counted from the records themselves, so it survives save/load and frees automatically on departure or death.
- When a home is chosen, residential stations with spare storage are preferred. Homes that already exist are never redistributed.

F6 shows the passenger status (stored at home, waiting to depart, travelling to pickup, carrying N passengers), the locked fare, and why an NPC can't take the nearest passenger contract.

Short check: `/mnt/project-files/notes/passenger_probe.lua` (run it in place of tests/fast.lua).
