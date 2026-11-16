# Status: built and to build

The one page for "where are we". Other docs in `docs/` describe how a built
system works. This page only says what exists and what's next. Keep it short:
when something ships, move its line from **To build** to **Built** and link
the doc or source file that explains it.

Last checked against `main`: 2026-11-15.

## Built

### Flight, combat and ships
- Box2D flight with drag, side thrusters and turn response (`src/ship.lua`).
- Guns, artillery, lasers, missiles, torpedoes and drone launchers (`data/items.lua`, `src/weapons.lua`).
- 32 hulls (`data/ships/`), including drones and the cargo pod. Slot-matched modules (`data/modules.lua`).
- Wrecks you can loot or drill for steel, and parts you can shoot off.
- Patch kits as field repair (`src/item_use.lua`), with Q as the hotkey.

### World
- Planets, moons, moon gates and mass driver lanes on an orbital clock (`src/fields.lua`, `src/transit.lua`).
- Dark grids: Milliways, the Shoals, Cordelia and Antichthon (`src/dark.lua`).
- Instanced sites with acceleration gates (`data/sites.lua`, `src/sites.lua`).
- Satellites burn fuel over time; NPC haulers (or the player) take refuel and launch jobs, and a dry satellite drops to low power (`src/satellites.lua`, `src/sat_jobs.lua`).
- Persistence for named areas: wrecks, containers and loose cargo (`src/persistence.lua`, `src/loose.lua`).
- Saves of the whole universe (`src/world.lua` `Game:saveState`).

### Stations and the player economy
- Markets and Quartermaster storefronts (`data/markets.lua`, `src/market.lua`).
- Hangars, berths and ship hauling (`src/berths.lua`).
- Dealers, used lots and new-ship deliveries ([used-ships.md](used-ships.md)).
- Freight contracts on the shared board ([player-contracts.md](player-contracts.md)).
- Shortage delivery quests (`src/quests.lua`).
- Reputation: standing per faction, heat per node and goodwill per NPC (`src/reputation.lua`).

### Simulated economy
- Real station stock, prices and shortages (`src/economy.lua`, `src/stockpile.lua`).
- Industry chains with adaptive output ([industry.md](industry.md), [manufacturing-outputs.md](manufacturing-outputs.md)).
- Mining against finite resources ([mining-production.md](mining-production.md)).
- Ammunition, electronics and fuel supply ([ammunition-economy.md](ammunition-economy.md), [electronics-economy.md](electronics-economy.md), [fuel-supply-balance.md](fuel-supply-balance.md)).
- Merchant houses and fences that sell what raiders bring in (`src/merchants.lua`, `src/dark.lua`).

### A-Life (NPCs)
- One shared NPC loop for every job: travel, arrive, stay, decide (`src/npc.lua`).
- Work comes from the shared `Tasks` board, chosen by preference profile: freight, mining, salvage, patrol and raid ([npc-actions.md](npc-actions.md), [alife-design.md](alife-design.md)).
- Fights between offline ships are rolled, they leave wreck records, and records keep a `fight_log` (`src/encounters.lua`, `src/simulation_history.lua`).
- Population targets come from demand (`src/arbiter.lua`, [freight-capacity.md](freight-capacity.md)).
- The director keeps station stock caught up to the clock (`src/director.lua`).

### Tools
- Debug panel (F1), A-Life inspector, item spawner, F8 performance dump.
- In-game editor, including the icon editor (`src/editor/`).
- Autotest suite, run with `--test` (`src/autotest.lua`).

## To build

### Approved or obviously next
- **Armor repairers.** Modules that use up nanite paste. Nanite paste exists but nothing makes or uses it yet.
- **Station grudges.** Make them offline too, or fold them into node heat. They're still online-only and unsaved, and they ignore damage from trader-styled ships (`src/game.lua`). That breaks the rule that online and offline behave the same.
- **A cap on ships online.** The design calls for about 12. There's no cap in the code.

### Designed, not built
- **Task generation layers** (simulation, economy, director) and a picker that rotates between them. Only the shortage quests exist ([alife-design.md](alife-design.md#task-generation)).
- **The director's attention nudge.** Steering offline events toward the player when things have been quiet.
- **The fifth faction.** The hidden hand that reaches the player through instanced sites.
- **Rewards and completion for other board work.** The player can only take freight off the board so far.

### Waiting on a decision
- Capital ships as stations (plan not approved).
- Rescaling ship size classes (not approved). Ship `class` values are still mixed free text.
- Combat contracts (plan not approved).
- Ship carrier (shelved).
- A redesign of the ammo and weapon box icons.
- A wider pass on the editor.

### Known bugs and loose ends
- A Bison gets wedged under the UAE-4 tunnel.
- Slowdown that persists after fights. No leak found yet; F8 dumps data for it.
- F-key bindings overlap between `main.lua` and the local map.
- Drones and the cargo pod have no `turnResponse`.
- Audio: there isn't any.
