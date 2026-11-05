# A-Life: design intent

Revised draft, 2026-11-04. Merges the original design doc and the expanded "layers and arbiter" draft, and is checked against `main` (after PR #37/#38). Sections marked **Open** need your call.

## The idea

Every NPC ship exists all the time as a saved **record**. Near the player it is **online**: a real Box2D ship flown by `src/ai.lua`. Everywhere else it is **offline**: timers and progress along a node graph. Both states must behave the same way. An NPC should do the same things, fight the same targets and end up in the same place whether or not the player is watching. Online is only a more detailed view of the same thing.

The world should make interesting situations on its own. Every event the player meets should be explainable from simulation state (a stranded trader is stranded because its hp and fuel say so), not spawned from a script.

## Principles

1. **Records are the truth, bodies are temporary.** Records save directly. A body is built from a record and folded back into it.
2. **Online and offline are the same rules.** Any behaviour added online (who pirates target, who docks, who holds grudges) needs a matching offline version, and the other way round.
3. **Fixed archetypes.** An NPC is one role for life. Nobody switches jobs (for example a trader who turns pirate when broke), because it's too hard to balance.
4. **Loners are the default population.** Most NPCs belong to no faction. Sovereign powers are mostly backdrop: owned space, guards and local rules. Faction-flagged NPCs are rare set pieces.
5. **The job board is for contract work.** Hauling, mining and bounties go on one shared `Tasks` board that NPCs and the player can both take, so the player competes with the world for work. Each archetype's own loop drives everything else (patrolling, lurking, wandering), with no posting needed. There are no special cases per planet.
   To keep it from making behaviour samey:
   - **Boards are local, not global.** Each station posts its own jobs, shaped by its owner and type. A mining outpost offers different work from a court. An NPC only sees the boards where it docks.
   - **NPCs pick by temperament.** Each record has a few preference weights (risk, distance, pay, cargo type), so two haulers looking at the same board choose differently, and some walk away.
   - **Jobs are contested and finite.** Whoever takes a job first gets it, NPC or player. A job can expire or fail.
6. **Local consequences.** Reputation and crime stay where they happened. Nothing travels as rumour.
7. **Node ownership is static lore.** Who owns a station sets local rules and guards; it is not a contested world variable. Contested ground, if any, lives inside instances.
8. **Emergent first, director second.** Pacing works by nudging the offline simulation, not by spawning scripted scenes.

## The world graph

- **System level:** planets and moons, linked by mass driver lanes and moon gates. Lane cost changes with the orbital clock (`Fields.distance`).
- **Local level:** a navigation graph built for each area (`src/travelgraph.lua`): stations, drivers, gates and waypoints, with node positions as a function of the clock.
- Records in transit between areas have a timer and no position.

## Record states

| State | Where | What runs |
|---|---|---|
| Online | Same area as the player, inside the near band | Real ship, Box2D, `ai.lua` |
| Local offline | Same area, outside the far band | Edge plus progress, shown on radar/map |
| Remote offline | Other area or in a lane | Node plus timer only |

The band has a gap (near/far) so ships don't flicker. A ship coming online mid-edge appears at its interpolated pose with cruise velocity.

## Roles

| Role | Loop | Board task |
|---|---|---|
| Trader | Haul between stations | `transport` (placeholder cargo for now) |
| Miner | Belt/site to home station | `mine` |
| Salvager | Sweep loose cargo around a planet and its moons, sell locally | `salvage` |
| Patrol | Loop and dock at owned stations, hunt pirates | none (own loop; may take bounties) |
| Pirate | Lurk on busy edges, raid, return to base to fence | none (own loop) |

`src/population.lua` keeps each area topped up per role, using saved spawn timers.

## Economy

The economy is **deliberately placeholder** for now: transport jobs move `scrap x5` that is created at pickup and deleted at delivery. The goal is still for NPC hauling and mining to move real station stock and prices. The parts already exist (mining stock for each node, markets for each station), but they aren't connected yet.

## Fights and wrecks

When hostile records share a graph segment, the fight is rolled with dice instead of simulated (`src/encounters.lua`). The loser leaves a wreck record that decays (`T.alifeWreckLifetime`, 30 min) and becomes real salvage if the player gets there in time. If the player arrives during a fight, both sides go online with the hp they have at that moment.

## Reputation

- **Disposition:** one number per NPC from -100 to 100 that drifts back to 0. Archetypes map it to behaviour: wary means flee, hostile means attack, friendly means discounts, warnings or backup.
- **Heat:** one number per node, raised by witnessed attacks and cooling slowly. Guards read heat plus their own disposition.
- Today's station grudges (online-only, unsaved) should become node heat. The system is undeveloped and needs its own design pass.
- Only witnesses are affected. Helping (supplies, returned cargo, cleared hazards, sparing a fleeing ship) raises disposition, and each kind of help starts from a state the simulation already produces.

## The fifth faction (not built)

The fifth faction is the simulation's **shadow lever**: the hidden hand the system uses to push the world when emergent state alone isn't enough. It has no home node and no records on the normal graph. It only acts through the director, and its effects look like ordinary simulation outcomes:

- It removes stock from circulation (ore, relics, ships), so prices drift with no visible cause.
- It plants false signals, such as a wreck that looks like a pirate kill or a hauler that "vanished".
- It pays in things other than credits, such as access, information or relics.

The player meets it only through instanced sites reached from the belts (`Fields[area].instance`, where a record may have no `area`). Any contest over ground happens there, never in the main world state.

## Task generation

Player tasks are generated from the live simulation, in the style of Call of the Zone. Nobody authors them. Every task points at real records that keep living their own lives: the escort target can be killed before you arrive, the bounty can dock somewhere else, the stranded miner can be rescued by a patrol. The task resolves against what actually happened. Quest targets get no protection, so a task fails or picks a new target when its subject is gone.

**Layers.** Each layer reads its own slice of world state and proposes tasks:

1. **Simulation:** individual records and nodes in a bad state, such as a damaged trader with a full hold, a pirate on the same edge as a hauler, a miner out of fuel, or a fresh wreck.
2. **Economy:** flows that are wrong, such as stock piling up at a site, a price gap nobody is closing, or a station short of something. This waits on the economy being real.
3. **Director:** player attention. If nothing has reached the player for a while (`last_interaction_clock`), it nudges the offline simulation toward them, for example by routing a pirate at a nearby trader. It never spawns anything from nothing.

**Arbiter.** It picks which layer speaks each cycle, so the player gets variety instead of five of the same task in a row. Each layer has its own cooldown, director events come first when they fire, and the same layer doesn't speak twice in a row unless nothing else is eligible. The cooldowns are tuning numbers in `src/tuning.lua`.

**What the simulation must provide.** These also keep later world-changing quests possible:

- **Readable state:** records, node stock, heat, disposition and wrecks can all be queried by id.
- **Writable levers:** tasks and quests change the world only through the inputs the simulation already uses (post a board task, set a goal, adjust stock or heat, spawn through `population.lua`), so their effects work offline too.
- **Events out:** arrivals, deaths, fights and dockings are emitted on `src/events.lua` for online and offline records alike.
- **Fight outcomes:** a `fight_log` on records says who fled, who died and what dropped, so a task can tell whether its subject survived.

Build this after fights and wrecks exist (build step 3), because before that there is nothing interesting to generate from.

---

## Where the docs and the code disagree

| Topic | Docs say | Code does | Note |
|---|---|---|---|
| Online band | 7,000 / 8,000 px, same as debris | `T.alifeNear/Far = 18000/22000`, separate from debris (7,000/6,000) | Code looks deliberate, so the doc should follow the code |
| Courier role | Couriers use mass drivers between planets | No courier role. Traders cross planets via drivers and moon gates | Resolved: folded into trader |
| Factions on records | `faction` field, patrols loop their faction's nodes | No faction field on records | Fits "loners default", but patrols still need an owner |
| Disposition / heat | Specced | Not built. The only grudges are weak-keyed, online-only station grudges (`game.lua:958`, `:1845`) | Station grudges break principle 2 (no offline twin) |
| Task generation (layers / arbiter) | Specced | Not built. `src/events.lua` is only an event bus, and the board only carries NPC work | Planned |
| Instances | Fifth-faction sites as sub-graphs | `Fields[area].instance` flag exists, and population skips instances | Fifth faction not built yet |
| Online cap | About 12 ships | No cap found | Worth adding |
| Online vs offline pirate prey | Same rules | Online `security.lua` picks prey by `ai.style=="trader"`, offline `encounters.lua` also targets miners and patrols | Audit item. Check whether PR #37 fully closed it |
| Fight log | `fight_log` on records | Not built | Needed for task generation |

| Job board scope | Contract work shared by NPCs and player | Board holds `patrol` and `raid` too, and the player can't take board jobs | Move patrol/raid to role loops, open the board to the player |

## Open questions

- Design pass on heat and disposition, starting from the current station grudges.
