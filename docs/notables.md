# Notables and the world-state ledger

Code: `src/notables.lua`, `src/worldstate.lua`. Data: `data/notables.lua`. Generated list of every consequence: `docs/world-state.md` (`luajit tools/worldstate_doc.lua`). Test: `tests/notables.lua` (in `tests/fast.lua`).

## The idea

A fixed cast of unique named people, three for each of the four powers and the cartel: a journalist (the editor of the faction's paper), a leader, and a magnate who owns real production lines. They are not pilots and they never respawn. When the player kills one (or hands one over to another faction), the world changes for good, Kenshi-style.

## Presence

- **Seat.** Each notable lives at a station. The Jobs tab lists the notables staying where you're docked.
- **Circuits.** Journalists and magnates ride to the stations on their circuit and back, about every two hours, as **VIP passenger contracts**: a `passenger` offer with item `vip`, one seat, 8 times a single fare, a seat of comfort 0.5 or better, and a standing floor (their staff won't book a captain their faction is wary of). NPC transports take most of them. Nobody takes one in 30 minutes and they go with their own staff, off the board.
- **Summits.** Every 3 hours 2 or 3 leaders go to Ring Station (neutral ground). Every 5th summit is a grand one with every living leader. The news announces it 30 minutes ahead, when their VIP runs go up. After the session they ride home.

## Endings

- **Airlock.** With a VIP aboard, eject them from the hold in space. They die, the contract ends unpaid, and what floats away is "Remains in a pressure suit". If their faction saw it (their own space, or one of their ships or stations within 2,500 units), it's a witnessed killing. Otherwise it goes out as a deed with you as the obvious suspect: the papers are 40% likelier to name you.
- **Destroy the transport.** If the player kills an NPC carrying a VIP, the VIP dies.
- **Hand over.** Cancel a VIP contract at another faction's station and they're captured. Same consequences as a death, and the captor faction warms to you.
- Anything else (pirates kill the transport, your own ship is wrecked) and they escape in a pod and go back. Only the player changes the world.

## Consequences (role rules, `D.consequences`)

All of them go through the ledger as sourced effects, and never revert:

| Role | Lasting | One-off |
|---|---|---|
| all | passenger demand at their seat x0.6 (residential seats) | obituaries in every paper (own paper mourns, hostile ones gloat); player deed: journalist -30, leader -50, magnate -40 standing, heat at the seat; factions hostile to them warm to you |
| journalist | their paper keeps 35% of its runs and price influence; a rival paper takes over their beat | |
| leader | faction markets 5% dearer; authored stance changes (`stances`) | their goods +40% across the faction, fading over 6h |
| magnate | their facilities keep 40% of output | their goods +60% at their works, fading over 6h |

Extra hand-authored effects go in a notable's `extra` list, in the same shape.

## The ledger (`src/worldstate.lua`)

The rule: nothing changes the world directly. An event sets a flag (`notable.<id> = dead`), writes to an append-only log, and applies effects. Lasting effects are modifiers tagged with their source, and systems ask for them:

- `WS.mul(u,'output',station,facility)` in `I.scale`
- `WS.mul(u,'price',station,item)` in `Markets.price`
- `WS.mul(u,'passengers',station)` in `P.cap`
- `WS.mul(u,'outlet_reach',outlet)` and `WS.beats(u)` in the news
- stance effects call `Rep.setStance`, which is saved with reputation

`where` can be a station, an outlet, or `faction:<id>` (every station the faction owns). `WS.validate` checks every id an effect names. The test runs it over the whole cast, so a renamed station, item or facility fails the build. F1 debug panel, "Notables and world state": where everyone is, the next summit, a button to call one now, every flag, every lasting effect by source, and the log.

## Open questions for review

1. The cartel's notables use the `milliways` faction id. If "the Brand" is meant to be its new name, the faction display name should change in `src/reputation.lua`.
2. Notables escape in a pod when anyone other than the player kills their transport. That keeps the world from changing at random. Should NPC-caused deaths ever count?
3. VIP runs nobody takes happen off the board (6 of 52 in a 6-hour probe). There are no escorts yet; the faction's patrols could fly an escort or the notable's own staff ship.
4. Capture counts the same as a death. Ransom, rescue or a return would be quest-layer work.
5. The leader stance changes are my picks: Zhuhai and Jove crack down on the cartel, the Diwan softens toward it, the cartel's death turns Zhuhai hostile, and the Estates leader's death cuts every Estates facility to 85%.
6. Passenger demand only drops at residential seats (4 of the 15).
7. Patrol and inspection density don't change yet: no clean hook in `src/security.lua`/`src/population.lua`.
8. The rival-beat takeover is read through a module pointer to the current universe, because `News.covers` has no universe argument.
9. Ceres Concern and Bowman have no notables, and the Beltway has no editor.
10. The economic ripple was checked for stability only (2 hours with the whole cast dead, no errors). It wasn't measured with the economy check.
