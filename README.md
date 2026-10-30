# Space Shooter Prototype: Flight Toy

Milestones 0 and 1 from the design doc: the project skeleton and a flight
toy you can fly, fight and tune. It's built in LÖVE 11.5 with plain Lua.

## Running it

1. Install LÖVE 11.5 from https://love2d.org.
2. Either double-click `spacegame.love`, or from this folder run `love .`

On Windows, if double-clicking doesn't work, drag the folder (or the .love
file) onto `love.exe`.

## Controls

| Action | Keyboard / mouse | Gamepad |
| --- | --- | --- |
| Main engine / retro thrusters | W / S | Left stick up / down |
| Side thrusters | A / D | Left stick left / right |
| Aim (the ship turns to face it) | Mouse | Right stick |
| Primary weapons | Left button | Right trigger |
| Missiles | Right button | Left trigger or right bumper |
| Afterburner | Shift | A |
| Zoom | Mouse wheel | |
| Debug panel | F1 | Back |
| New ship after death | R | Start |
| Hide help / quit | H / Esc | |

## What's in it

- Box2D flight: thrust and torque only, with quadratic drag giving a natural top speed instead of a hard cap.
- Thrust is relative to the nose, and the main engine only pushes forward. Reverse and sideways movement come from maneuvering thrusters (the hull's `sideThrust`). Light hulls have plenty, so they can strafe with their guns on target. Heavy hulls barely have any, so they turn and burn. The Side Jets utility modules add more.
- Mass is hull + modules + whatever's in the hold. Firing ammo makes you lighter; picking up loot makes you heavier.
- Your hold is a grid of 1 m3 cells (Wisp 6 x 4, Bastion 12 x 10, Hauler 20 x 20), and each Cargo Pod adds a small grid of its own. Items take shapes on it (rounds 1 x 1 in stacks of 50, missiles 2 or 3 cells long, crates 2 x 2), so a hold can fill up before its raw volume does. Turn on "Show hold grid" in the debug panel to see the packing.
- Three hulls (Wisp, Anvil, Bastion) with slot layouts and hull bonuses, plus 20 catalog modules with strict size matching.
- Fast projectiles: guns reach about 1,000 px and artillery 2,000 to 3,000 px. Lasers run on power instead of ammo, and missiles are guided. Artillery shells and missiles have a proximity fuse, so they burst near an enemy, on contact, or at the end of their range. Every round is an item in the hold.
- Knockback, recoil and ram damage. Ram damage scales with impact force, so heavy ships hit harder.
- Five enemy types built from the same parts and flight code as you. The basic Scrap Drone has no side thrusters, so it flies straight at you and is easy to hit. The Dart harasser (from wave 3) is the twitchy, hard-to-hit one. Waves start at two drones and grow.
- An Enemy damage slider (default 0.7) in the debug panel is the quick difficulty knob.
- Wrecks drop part of their ammo plus salvage, and a full hold leaves loot behind.
- Death ends the ship. Press R to launch a new one; the economy that makes this permanent comes later.

## The debug panel (F1)

- Ship, modules and hold: swap hulls, refit any slot, add ammo, repair, show the hold grid.
- Handling readout: acceleration, top speed, turn rate, mass, and the hardest impact so far.
- Flight tuning: every handling knob as a live slider. When something feels right, copy the number into `src/tuning.lua`.
- Spawn and arena: spawn any enemy, start a wave, clear the field.
- Also: god mode, infinite ammo, and toggling waves.

## Where things live

```
main.lua          LÖVE callbacks, fixed 120 Hz simulation step
conf.lua          window settings
data/             ALL content: hulls, modules, ammo/salvage, enemies
src/data.lua      sandboxed loader for data/ and mods/
src/stats.lua     hull + modules -> final stats
src/ship.lua      ship bodies and flight (player and AI share it)
src/weapons.lua   firing, ammo use, projectiles
src/ai.lua        enemy behaviour (fills the same intent the player's controls do)
src/game.lua      the arena: world, collisions, explosions, pickups, waves
src/render.lua    placeholder drawing
src/hud.lua       HUD
src/debugui.lua   debug panel (Slab)
src/input.lua     keyboard, mouse and gamepad
src/tuning.lua    flight-feel knobs
src/inventory/    grid hold: item shapes, grids, holds
src/events.lua    event bus (fire, hit, kill, pickup, death, ram): the future modding API
src/autotest.lua  scripted smoke test
lib/Slab          Slab UI library (MIT)
mods/             drop mod folders here
```

## Adding content

Content is plain Lua tables. To add a gun, put this in any file in `data/`:

```lua
module {
	id = "scatter_s", name = "Scatterbox", maker = "Brute Industries",
	family = "primary", size = "S", mass = 5, powerDraw = 1, price = 2600,
	weapon = { kind = "gun", fireRate = 4, damage = 2, speed = 2200, range = 600,
	           spread = 12, gimbal = 10, knockback = 150, recoil = 60 },
}
```

The comments at the top of each data file list every field. If something's
wrong (a missing field, a module in a slot it doesn't fit), the game stops
with an error naming the file and the problem.

Mods work the same way, from `mods/<modname>/data/*.lua`. A mod can add new
things or replace base ones by reusing their id. Data files run in a sandbox,
so they can only define content.

## Smoke test

`love . --autotest` flies a scripted run. It prints handling numbers and a
damage breakdown, saves screenshots to the save folder, then quits. Run it
after changing data or flight code.

## Known gaps (on purpose for this milestone)

- No stations, docking, economy, saving or sector map yet. Those are M4 and M5.
- The art is placeholder outlines, and there's no audio.
- Field repair items aren't in yet, pending their design.
