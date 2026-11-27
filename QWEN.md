# Threshold — QWEN.md

> Last updated: 2026-11-25

## Overview

**Threshold** is a 2D physics-based space shooter built in LÖVE 11.5 (Love2D) with plain Lua. It started as a "Flight Toy" milestone but has evolved into a full-scale space trading/simulation game with deep A-Life NPC simulation, a procedurally-driven economy, planetary travel, and extensive world systems.

The core loop: fly between planets and stations, trade cargo, take contracts, mine ore, fight enemies, upgrade your ship, and navigate a living universe where NPCs haul, mine, patrol, raid, and live their own lives whether you're watching or not.

## Tech stack

| Layer | Tech |
|---|---|
| Engine | LÖVE 11.5 (Love2D) |
| Language | Lua 5.2 (LuaJIT when available) |
| UI library | Slab (bundled in `lib/Slab/`) |
| Physics | Box2D (via LÖVE) |
| Content format | Plain Lua tables in `data/` |
| Mod support | Drop folders in `mods/` |
| Build/run | `love .` (no compilation) |

## Running

| Action | Command |
|---|---|
| Run | `love .` |
| Run (title intro) | `love .` (no arguments) |
| Autotest suite | `love . --test` |
| Soak test | `love . --soak` |
| Dock probe test | `love . --dockprobe` |
| Economy model | `love . --econmodel` |
| Economy capture | `love . --econcapture` |
| Industry catalogue | `love . --industrycatalogue` |
| Performance snap | F8 in-game |
| Frame profiler | F7 in-game |

The simulation runs on a fixed 120 Hz step (`src/game.lua` → `Game:step`); rendering happens per frame. LÖVE's run loop is overridden in `main.lua` to control VSync behavior at high refresh rates.

## Project structure

```
main.lua          — Entry point, LÖVE callbacks, fixed-step loop, run override
conf.lua          — Window settings, LÖVE 11.5 target, no audio module
data/             — All game content (hulls, modules, ammo, weapons, markets, sites)
  ships/          — Hull definitions (32 total)
  items.lua       — Module/ammo/weapon catalog
  markets.lua     — Station market catalog
  sites.lua       — Instanced site definitions
src/              — Game logic (the bulk of the codebase)
  game.lua        — Core Game object, level, collisions, explosions, pickups
  ship.lua        — Ship bodies, flight physics (player + AI share)
  weapons.lua     — Firing, ammo use, projectiles
  ai.lua          — Enemy AI behaviour
  world.lua       — Universe, save state, area persistence
  economy.lua     — Real stock/price/shortage simulation
  industry.lua    — Manufacturing chains with adaptive output
  alife.lua       — A-Life NPC simulation (online/offline)
  npc.lua         — Shared NPC controller (one loop for every job)
  npc_actions.lua — NPC job action definitions
  market.lua      — Player market (credits, shelves, trade grid)
  transport.lua   — Freight board, NPC hauling
  tasks.lua       — Shared task board (freight, mining, salvage, patrol, raid)
  economy_model.lua — Economy model runner / snapshot
  editor/         — In-game editor (canvas, export, panels)
  ui/             — Cargo screen, hangar, market tab, orrery, pause menu
  inventory/      — Grid hold: item shapes, grids, ship holds
  ui/*.lua        — Local map, NPC traffic, transit view, stall management
  *.lua           — A-Life records, encounters, reputation, mining, loot, etc.
lib/Slab/         — UI library (MIT license)
mods/             — Drop mod folders here (follow data/ structure)
docs/             — Design docs (economy, A-Life, ships, etc.)
tools/            — Ship generator, economy model viewer, soak log report
```

## Key design principles

These principles guide both the code and the simulation. Refer to them when adding new systems:

1. **Records are the truth, bodies are temporary.** NPC ship records save directly; bodies are built from records and folded back. See `src/alife.lua`.
2. **Online and offline are the same rules.** Any behaviour added for online NPCs needs a matching offline version, and vice versa. See `docs/alife-design.md`.
3. **Content is plain Lua tables.** All ships, weapons, modules, markets, and sites live as tables in `data/`. Errors are caught at load with file + field info. See `src/data.lua`.
4. **Mods use the same system.** Drop a folder in `mods/` with a `data/` subfolder — it follows the same conventions as base content.
5. **The job board is for everyone.** NPCs and the player compete for the same work (freight, mining, salvage, patrol, raid). See `src/tasks.lua`, `docs/player-contracts.md`.
6. **Local consequences.** Reputation, heat, and goodwill are tracked per faction and per node. Nothing travels as "rumour" across the universe. See `src/reputation.lua`.
7. **Emergent first, director second.** Pacing is driven by nudging offline simulation state, not scripted spawns. See `src/director.lua`.

## Core systems

### Flight & combat
- Box2D physics: thrust + torque + quadratic drag (no hard top speed).
- Light hulls strafe; heavy hulls only turn. Mass = hull + modules + cargo.
- Guns, artillery, lasers, missiles, torpedoes, drone launchers. Proximity fuses on missiles/artillery.
- Wreck drilling for salvage (hull alloy), part-shooting, ram damage.

### World & travel
- Planets, moons, mass driver lanes on an orbital clock (`src/fields.lua`, `src/transit.lua`).
- Dark grids: hidden areas (Milliways, the Shoals, Cordelia, Antichthon) discovered via gameplay.
- Instanced sites with acceleration gates (`src/sites.lua`).
- Satellites: player-built relays that earn credits.
- Close-surface gravity pull on all planets/moons.

### Economy
- Real station stock, prices, shortages driven by NPC activity (`src/economy.lua`).
- Industry chains: mining, manufacturing, fuel, ammo, electronics supply (`docs/` directory).
- Mining against finite resources.
- Merchant houses and fences for dark grid goods.
- Player freight board, buy orders, market stalls.

### A-Life NPCs
- One shared controller for every job, every NPC (`src/npc.lua`).
- Online (Box2D ships near player) and offline (timers on node graph) use same rules.
- Work profiles: freight, mining, salvage, patrol, raid/finance.
- Offline fights are rolled with dice; wrecks persist as salvage records.
- Population targets from demand (`src/arbiter.lua`).
- Home assignment, idle behaviour, fuel/repair cycles.

### Ship customization
- 32 hulls with slot layouts, 1 m³ grid cargo hold.
- Modules: reactor, engine, weapons, thrusters, shields, etc. Strict size matching.
- Refit docked only. Hangar bay with physical ship placement.
- Reputation per faction affects market prices and NPC attitudes.

## Debug & tools

| Key | Function |
|---|---|
| F1 | Debug panel (ship, modules, flight tuning, spawn, docked helpers) |
| F6 | A-Life inspector (NPC records, connections, simulation history) |
| F7 | Frame profiler |
| F8 | Performance snapshot |
| F2 | In-game editor |
| F4 | NPC traffic view |
| M | Local map |
| Tab | Cargo hold / station screen (docked) |
| Esc | Pause menu |
| R | Respawn after death |

Autotest suite (`love . --test`) runs scripted smoke tests for flight, combat, and handling. Prints numbers, saves screenshots, exits.

## Current status

### What's built
- Full flight model, combat, 32 hulls, modular ship system.
- Planetary travel with mass drivers, moon gates, dark grids.
- Deep economy simulation (stock, prices, shortages, industry chains, mining).
- A-Life NPC simulation with shared task board.
- Player contracts, freight board, market stalls, buy orders.
- Reputation system (standing, heat, goodwill).
- Ship hangars, berths, dealer parking.
- Saves: whole universe persisted (station state, wrecks, economy, player).

### What's next (planned / in progress)
- Armor repairers (nanite paste modules).
- Station grudges → node heat migration (offline twin).
- Cap on ships online (~12).
- Task generation layers (simulation/economy/director) + picker rotation.
- Director's "attention nudge" for player pacing.
- Fifth faction (shadow lever through instanced sites).
- Combat contracts, rewards/completion for other board work.

### Known issues
- Bison wedged under UAE-4 tunnel.
- Post-fight slowdown (no leak found; F8 dumps help diagnose).
- F-key overlaps between `main.lua` and local map.
- Drones and cargo pod have no `turnResponse`.
- No audio yet.

See `docs/status.md` for the latest status tracking.

## Conventions

- **No classes.** Modules are plain Lua tables with functions. `module {}` defines a module.
- **Data files are pure tables.** `data/*.lua` files only define content; no side effects. Sandboxed via `src/data.lua`.
- **One function per line in game loop.** `main.lua`'s `love.update` is dense but not obfuscated — each line is a separate system tick.
- **Simulation is decoupled from rendering.** Fixed 120 Hz physics step; drawing is per-frame and separate.
- **Extension points for NPCs.** Job/action/target/operation registries — register once at load, saved state is plain data. See `docs/npc-actions.md`.
- **IDs everywhere.** Locations, factions, ships — all use string IDs, not indices or references.

## File size notes

- `src/` has 180+ files (many are small: < 100 lines each for specific subsystems).
- `main.lua` is dense (~200 lines) but each `love.*` callback is clearly separated.
- `docs/` has ~20 design documents covering economy, A-Life, ships, manufacturing, etc.
