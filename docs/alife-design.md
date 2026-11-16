# A-Life: design intent

Design intent for the NPC simulation. Last checked against `main` on 2026-11-15. For what is built and what's still to build across the whole game, see [status.md](status.md).

## The idea

Every NPC ship exists all the time as a saved **record**. Near the player it is **online**: a real Box2D ship flown by `src/ai.lua`. Everywhere else it is **offline**: timers and progress along a node graph. Both states must behave the same way. An NPC should do the same things, fight the same targets and end up in the same place whether or not the player is watching. Online is only a more detailed view of the same thing.

The world should make interesting situations on its own. Every event the player meets should be explainable from simulation state (a stranded trader is stranded because its hp and fuel say so), not spawned from a script.

## Principles

1. **Records are the truth, bodies are temporary.** Records save directly. A body is built from a record and folded back into it.
2. **Online and offline are the same rules.** Any behaviour added online (who pirates target, who docks, who holds grudges) needs a matching offline version, and the other way round.
3. **Persistent preferences.** Every NPC uses one controller. Shared preference profiles make individuals favor particular kinds of work, while allowing occasional alternatives. Equipment, circumstances and authorizations determine eligibility; the active task determines execution. Ambition and aggression vary individual decisions.
4. **Loners are the default population.** Most NPCs belong to no faction. Sovereign powers are mostly backdrop: owned space, guards and local rules. Affiliated NPCs provide flavor. Local faction police have explicit, scoped authorization; affiliation alone grants no police powers. There is no faction-to-faction diplomacy.
5. **The job board is for contract work.** Hauling, mining and bounties go on one shared `Tasks` board that NPCs and the player can both take, so the player competes with the world for work. Patrol and raid duties use task handlers on the same board. Issuer and jurisdiction requirements distinguish faction police duties from freelance patrol work. There are no special cases per planet.
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

## Work and identity

NPCs have no behavioral role. Population templates choose starting equipment,
residence, affiliation, scoped authorizations and a preference profile. The
shared controller selects eligible work, commits to it, handles upkeep and
movement, and executes registered actions requested by the active task. Actions own
steering, positioning, claims, timing and interruption; equipment operations
own resource effects. See [NPC action extensions](npc-actions.md).

| Work | Execution | Requirements |
|---|---|---|
| Freight | Collect and deliver station stock | Cargo capacity |
| Mining | Work finite resources and return the collected ore | Drill and free hold space |
| Salvage | Collect loose items and sell the recovery manifest | Free hold space |
| Patrol | Visit the offered nodes and respond to local aggression | Armed; police duties also require matching issuer/jurisdiction authorization |
| Raid / fence | Hunt, acquire cargo, return it to storage | Armed for raiding; return is a continuation task |

Permanent police authority stays active within its jurisdiction even during
other assignments. Freelance patrol contracts do not grant that authority.
Population replenishment counts birth templates, independently of current work.

## Economy

Built. NPC hauling and mining move real station stock, and prices and shortages
come from that stock (`src/economy.lua`, `src/stockpile.lua`). See
[industry.md](industry.md) and [mining-production.md](mining-production.md).

## Fights and wrecks

When hostile records share a graph segment, the fight is rolled with dice instead of simulated (`src/encounters.lua`). The loser leaves a wreck record that decays (`T.alifeWreckLifetime`, 30 min) and becomes real salvage if the player gets there in time. If the player arrives during a fight, both sides go online with the hp they have at that moment.

## Reputation

Built in `src/reputation.lua`, as three saved numbers (-100 to 100) that drift
back to rest on the universe clock, so they work offline too:

- **Standing** per faction.
- **Heat** per node, raised by attacks and kept local.
- **Goodwill** per NPC.

An NPC's attitude to the player is goodwill + its faction's standing - local heat.

Still open: the station grudges (`src/game.lua`) are online-only, unsaved, and
ignore damage from trader-styled ships. They should become node heat, or get an
offline twin (principle 2).

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

**Picker.** It picks which layer speaks each cycle, so the player gets variety instead of five of the same task in a row. Each layer has its own cooldown, director events come first when they fire, and the same layer doesn't speak twice in a row unless nothing else is eligible. The cooldowns are tuning numbers in `src/tuning.lua`.

**What the simulation must provide.** These also keep later world-changing quests possible:

- **Readable state:** records, node stock, heat, disposition and wrecks can all be queried by id.
- **Writable levers:** tasks and quests change the world only through the inputs the simulation already uses (post a board task, set a goal, adjust stock or heat, spawn through `population.lua`), so their effects work offline too.
- **Events out:** arrivals, deaths, fights and dockings are emitted on `src/events.lua` for online and offline records alike.
- **Fight outcomes:** a `fight_log` on records says who fled, who died and what dropped, so a task can tell whether its subject survived.

Status: fights, wrecks, the fight log and the event bus exist. One generator is built (shortage deliveries, `src/quests.lua`). The layers and the picker are not. (`src/arbiter.lua` is a different thing: it sets population targets.)

---

## Built vs. not built

| Part | State | Where |
|---|---|---|
| Records, online/offline bands | Built. `T.alifeNear/Far = 18000/22000`, separate from debris | `src/alife.lua`, `src/tuning.lua` |
| One shared controller for every job | Built | `src/npc.lua`, [npc-actions.md](npc-actions.md) |
| Shared Tasks board (freight, mining, salvage, patrol, raid) | Built. Police duties need authorization | `src/tasks.lua` |
| Affiliation and scoped authorizations on records | Built | `src/npc_access.lua` |
| Real economy | Built | `src/economy.lua` |
| Rolled offline fights, wreck records, `fight_log` | Built | `src/encounters.lua`, `src/simulation_history.lua` |
| Same pirate prey online and offline | Built | `src/security.lua`, `src/encounters.lua` |
| Standing, heat, goodwill | Built | `src/reputation.lua` |
| Player access to the board | Freight only | [player-contracts.md](player-contracts.md) |
| Station grudges as heat (offline twin) | Not built | `src/game.lua` |
| Cap on ships online (about 12) | Not built | |
| Task generation layers and picker | One generator (shortage quests) | `src/quests.lua` |
| Director attention nudge | Not built. The director only keeps stock up to date | `src/director.lua` |
| Fifth faction | Not built. The dark grids are a separate thing | |

## Open questions

- Station grudges: turn them into node heat, or keep them as their own thing with an offline twin?
- Which task generation layer to build after shortage quests.
