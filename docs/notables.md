# Notables and the world-state ledger

Code: `src/notables.lua`, `src/worldstate.lua`. Data: `data/notables.lua`. Generated list of every consequence: `docs/world-state.md` (`luajit tools/worldstate_doc.lua`). Test: `tests/notables.lua` (in `tests/fast.lua`).

## The idea

A fixed cast of unique named people, three for each of the four powers and the cartel: a journalist (the editor of the faction's paper), a leader, and a magnate who owns real production lines. The corporations are smaller: Ceres Concern and Bowman Atmospherics each have a CEO, and the Beltway (Ceres's paper) has an editor. They are not pilots and they never respawn. When the player kills one (or hands one over to another faction), the world changes for good, Kenshi-style.

## Presence

- **Seat.** Each notable lives at a station. The Jobs tab lists the notables staying where you're docked.
- **Circuits.** Journalists, magnates and CEOs ride to the stations on their circuit and back, about every two hours, as **VIP passenger contracts**: a `passenger` offer with item `vip`, one seat, 8 times a single fare, a seat of comfort 0.5 or better, and a standing floor (their staff won't book a captain their faction is wary of). NPC transports take most of them. If nobody takes one in 30 minutes, they miss the trip and stay put. A booked run is due 2 hours after booking: an NPC carrier that runs over gives them up where it is; a player who runs over loses 10 standing with their faction, and the next station they dock at takes the VIP off the ship (`C.expire`, `C.collectLapsed`: any contract with a `timeLimit` works the same way).
- **Summits.** Every 3 hours 2 or 3 leaders go to Providence (neutral ground). Every 5th summit is a grand one with every living leader. The news announces it 30 minutes ahead, when their VIP runs go up. After the session they ride home. A leader whose run nobody takes misses the summit: they're dropped from the attendees, listed in `summit.missed`, and the `notable_missed_summit` event fires for the quest layer.

## Endings

- **Airlock.** With a VIP aboard, eject them from the hold in space. They die, the contract ends unpaid, and what floats away is "Remains in a pressure suit". Their faction booked them onto your ship, so it always knows: it counts as a witnessed killing wherever it happens.
- **Destroy the transport.** If the player kills an NPC carrying a VIP, the VIP dies.
- **Hand over.** The powers aren't at odds enough to hold each other's people. The cartel will take anyone's: cancel a VIP contract at a cartel station and they're captured. A power hostile to the cartel (the Estates, the Diwan) will arrest a cartel notable the same way. Same consequences as a death, their faction knows it was you, and the captor warms to you. Cancelling anywhere else just leaves them there.
- Anything else (pirates kill the transport, your own ship is wrecked) and they escape in a pod and go back. Only the player changes the world.

## Consequences (role rules, `D.consequences`)

All of them go through the ledger as sourced effects, and never revert:

| Role | Lasting | One-off |
|---|---|---|
| all | | obituaries in every paper (own paper mourns, hostile ones gloat); player deed: journalist -30, leader -50, magnate -40 standing, heat at the seat; factions hostile to them warm to you |
| journalist | their paper keeps 35% of its runs and price influence; a rival paper takes over their beat | |
| leader | faction markets 5% dearer; police wanted in its systems x0.7; squads hold at each stop half as long; authored stance changes (`stances`) | their goods +40% across the faction, fading over 6h |
| magnate | their facilities keep 40% of output | their goods +60% at their works, fading over 6h |
| CEO | the company's police x0.7 and holds halved, like a leader; their facilities keep 40% of output | their goods +60% at their works |

Extra hand-authored effects go in a notable's `extra` list, in the same shape.

## The ledger (`src/worldstate.lua`)

The rule: nothing changes the world directly. An event sets a flag (`notable.<id> = dead`), writes to an append-only log, and applies effects. Lasting effects are modifiers tagged with their source, and systems ask for them:

- `WS.mul(u,'output',station,facility)` in `I.scale`
- `WS.mul(u,'price',station,item)` in `Markets.price`
- `WS.mul(u,'outlet_reach',outlet)` in the news; `WS.beats(u)` behind `News.beat(u,o)` and `News.covers(u,o,area)`, the only way any code asks what a paper covers (both take the universe, so nothing reads a stale or global copy)
- `WS.mul(u,'patrols','faction:<id>')` in `S.policeWanted` (fewer police arrive; the ships already serving stay until lost)
- `WS.mul(u,'inspections','faction:<id>')` in the squad sweep hold time

The lookup index is rebuilt only when an effect is added: per target and place it holds the product of everything that applies, with faction-wide effects already copied onto each of the faction's stations. A lookup is one or two table reads. The log keeps only its newest 200 lines (`WS.T.logMax`), since nothing in the game reads it; flags and effects hold everything that matters.
- stance effects call `Rep.setStance`, which is saved with reputation

`where` can be a station, an outlet, or `faction:<id>` (every station the faction owns). `WS.validate` checks every id an effect names. The test runs it over the whole cast, so a renamed station, item or facility fails the build. F1 debug panel, "Notables and world state": where everyone is, the next summit, a button to call one now, every flag, every lasting effect by source, and the log.

## Open questions for review

1. The cartel's notables use the `milliways` faction id. If "the Brand" is meant to be its new name, the faction display name should change in `src/reputation.lua`.
2. Notables escape in a pod when anyone other than the player kills their transport. That keeps the world from changing at random. Should NPC-caused deaths ever count?
3. VIP runs nobody takes happen off the board (6 of 52 in a 6-hour probe). There are no escorts yet; the faction's patrols could fly an escort or the notable's own staff ship.
4. Capture counts the same as a death. Ransom, rescue or a return would be quest-layer work, as would anything hanging off a missed summit.
5. The leader stance changes are my picks: Zhuhai and Jove crack down on the cartel, the Diwan softens toward it, the cartel's death turns Zhuhai hostile, and the Estates leader's death cuts every Estates facility to 85%.
6. Fewer police only shows as losses go unreplaced; serving ships aren't stood down. "Inspection" is the time squads hold at each stop, since there is no player inspection or contraband scan yet.
7. CEOs don't attend summits.
8. The economic ripple was checked for stability only (2 hours with the whole cast dead, no errors). It wasn't measured with the economy check.
