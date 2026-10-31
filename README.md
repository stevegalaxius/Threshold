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
| Cargo hold (drag items, R rotate, right-click eject) | Tab | |
| Tractor beam: hold on a pickup to reel it in, tap on a wreck or container to open it, hold on a container to tow it | E | X |
| Afterburner | Shift | A |
| Zoom | Mouse wheel | |
| Debug panel | F1 | Back |
| Station screen: cycle Cargo / Hangar / Market tabs | Tab (docked) | |
| Save / load newest (docking and quitting autosave; launching continues) | F5 / F9 | |
| New ship after death (at the last station you docked at) | R | Start |
| Hide help | H | |
| Pause menu (resume, save, load, quit) | Esc | Start |

## What's in it

- Box2D flight: thrust and torque only, with quadratic drag giving a natural top speed instead of a hard cap.
- Thrust is relative to the nose, and the main engine only pushes forward. Reverse and sideways movement come from maneuvering thrusters (the hull's `sideThrust`). Light hulls have plenty, so they can strafe with their guns on target. Heavy hulls (Bastion, Hauler) can't strafe: A/D turn them, and Side Jets in their thruster slot help them turn faster. Side Jets fit every hull.
- Mass is hull + modules + whatever's in the hold. Firing ammo makes you lighter; picking up loot makes you heavier.
- Your hold is a grid of 1 m3 cells (Wisp 6 x 4, Bastion 12 x 10, Hauler 20 x 20), and each Cargo Pod adds a small grid of its own. Items take shapes on it (rounds 1 x 1 in stacks of 50, missiles 2 or 3 cells long, crates 2 x 2), so a hold can fill up before its raw volume does. Press Tab to open it: drag stacks around, R rotates while dragging, Shift-drag splits a stack, and right-clicking a stack (or dragging it out of the window) ejects it behind the ship. Docked at a station, the same screen opens next to that station's storage: Ctrl-click or right-click moves a stack to the other panel, and double-clicking an ammo crate unboxes it into loose rounds.
- Docked, the left side of the cargo screen shows your ship's equipment on the hull outline. Drag a module from the hold or storage onto a slot (or double-click it) to fit it; the old one goes back where the new one came from. The panel shows top speed, acceleration, turn, spare power and mass before and after. Refitting only works docked, and a Cargo Pod with cargo in it can't be pulled. You can't launch without a reactor and an engine or thrusters (side jets push you forward when there's no engine). Modules never wear out, and each one fitted to a wreck has a 50% chance to survive as loot.
- Looting: tap E with the cursor on a wreck or a cargo container in tractor range to open it next to your hold, then drag, Ctrl-click or right-click to take things, or press Take All. While it's open your tractor beam holds it, matching your speed and pulling it back in when it drifts past about half the beam's range; the pull has a limit, so burn away hard and it slips out of reach and the window closes. Cargo containers (8 x 4 inside) drift in every field, and a Hauler carries its cargo packed in them, so its wreck holds loaded containers: double-click one to open it, or move the whole thing if your hold has room. Shooting a container apart spills its contents. Hold E on a floating container to tow it (slowly); if your hold has room for its 8 x 5 shape it's reeled in and stowed, cargo and all (a Wisp's hold doesn't, an Anvil's just does).
- Three hulls (Wisp, Anvil, Bastion) with slot layouts and hull bonuses, plus 20 catalog modules with strict size matching.
- Fast projectiles: guns reach about 1,000 px and artillery 2,000 to 3,000 px. Lasers run on power instead of ammo, and missiles are guided. Artillery shells and missiles have a proximity fuse, so they burst near an enemy, on contact, or at the end of their range. Every round is an item in the hold.
- Knockback, recoil and ram damage. Ram damage scales with impact force, so heavy ships hit harder. Each hull also has its own impact speed below which a bump does it no harm (`ramSpeed`): a Wisp takes damage from about 100 px/s, an Anvil 170, a Hauler 200 and a Bastion 250.
- Five enemy types built from the same parts and flight code as you. The basic Scrap Drone has no side thrusters, so it flies straight at you and is easy to hit. The Dart harasser is the twitchy, hard-to-hit one. Each level has its own enemies scattered around it; they leave you alone until you come within about 2,600 px or shoot them.
- An Enemy damage slider (default 0.7) in the debug panel is the quick difficulty knob.
- Wrecks drop part of their ammo plus salvage, and a full hold leaves loot behind.
- Planets: you start at Earth (the big planet map). Venus and Mars are planet maps too, and Mars has the Heaven-Ladder, an orbital ring with gaps to fly through, held up by four space elevators. Jupiter is a first, barebones gas giant: a map three times Earth's size with no surface, where the deeper you sink below the cloud tops the harder it crushes your hull. The asteroid field, giant asteroid and lone station maps are kept as instance maps for missions later (debug panel). Each map is rebuilt fresh on arrival, but station storage and hangars last.
- Mass drivers: every planet has one mass driver at the very edge of its map. Fly up its runway lights toward the breech and its tractor beam takes you like a station's, easing you in and holding you at the breech (come in too fast and it can't stop you: you overshoot out the barrel). It opens an orrery of the planets where they are right now; pick one (100 cr plus 60 per AU) and it fires you into the transit lane: a long highway arc laid out in full when you enter (rocks on the road, rocks off-road and the odd derelict, nothing popping in), longer the further apart the planets are right now (they circle the Sun with their real year lengths relative to each other; Earth's year is 30 minutes of game clock). There's no current in it: your thrusters just hit far harder while you're on it (the afterburner gets nothing extra). At the far end you're spat out of the other planet's driver at speed; turn round and fly back out the near end and you come home instead. The debug panel can switch drivers to the other way of travelling instead: a warp trip and a catch through braking rings at the other end.
- Hangar: docked, press Tab (or click the Hangar tab on top of the window). Each station's hangar bay is a 30 x 14 grid, and every ship takes a footprint the size of its hull (Wisp 4 x 2, Anvil 8 x 3, Bastion 14 x 5, Hauler 14 x 6), including the one you're docked in, so a bay only holds so many. Click a ship to select it, drag to move it (R rotates), and double-click or press Fly to swap into it; the ship you came in stays parked where it was. Cargo opens the Cargo tab with three panels: your hold, then station storage, then the parked ship's hold. Ships on the storage panel opens the first parked ship, Next cycles through them and x closes it. With a parked ship open, each panel has a Target button: right-click (or Ctrl-click) sends a stack to the target panel (the parked ship to start with), and from the target panel back to your hold (or from your hold to storage). The equipment panel hides while three panels are open, so close the parked panel to refit. For now new ships come from the debug panel's "Park a new ..." buttons; buying ships in the hangar comes next.
- Market: docked, the Market tab shows your hold (or station storage: the Your hold / Storage tabs on the left panel switch), a shared trade grid in the middle and the station's shelf on the right. You start with 5,000 cr. Put your goods and the station's on the trade grid (drag, or Ctrl-click / right-click to move a stack across); green frames are yours, amber the station's, and hovering a stack shows its price in green. The totals show what you get, what you pay and your balance after, and Complete trade settles it all at once. Bought goods go into your hold first, then storage. Leave the tab (or launch) and everything on the grid goes home. Buying costs the list price and selling pays 50% of it (a loaded container sells with everything in it). Each station sells its own catalogue (data/markets.lua), restocking each item a stack at a time on its own timer, and anything you sell stays on its shelf, where you can buy it back, for 10 minutes before it's sold on. The filters on the shelf (Ammo, Weapons, Modules, Misc) dim the rest.
- Death ends the ship. Press R for a starter Wisp docked at the last station you docked at (in whatever level it is), or at the start if you never docked. Your wreck stays where you died with everything you had.
- Saving: the game picks up from your latest save when it starts. Docking and quitting autosave, F5 saves, and F9 loads whichever save is newest. The debug panel has New game. Saves hold the universe (every station's storage, hangar and market shelf, your home station, your credits and the game clock), your ship with its hold, and where it is. They're plain Lua tables in LÖVE's save folder, versioned so later builds can upgrade them.

## The debug panel (F1)

- Ship, modules and hold: swap hulls, refit any slot, add ammo, repair, show the hold grid.
- Handling readout: acceleration, top speed, turn rate, mass, and the hardest impact so far.
- Flight tuning: every handling knob as a live slider. When something feels right, copy the number into `src/tuning.lua`.
- Spawn and arena: spawn any enemy (these come straight for you), clear enemies, jump to any level.
- Docked: park a new ship of any hull in this station's hangar. +10,000 credits. Save, load and load the autosave.
- Also: god mode and infinite ammo.

## Where things live

```
main.lua          LÖVE callbacks, fixed 120 Hz simulation step
conf.lua          window settings
data/             ALL content: hulls, modules, ammo/salvage, enemies, station markets
src/data.lua      sandboxed loader for data/ and mods/
src/stats.lua     hull + modules -> final stats
src/ship.lua      ship bodies and flight (player and AI share it)
src/weapons.lua   firing, ammo use, projectiles
src/ai.lua        enemy behaviour (fills the same intent the player's controls do)
src/game.lua      the level: world, collisions, explosions, pickups, docking
src/world.lua     the universe: station storage, hangars, travel, respawn, save state
src/market.lua    credits, station shelves and their timers, settling a trade
src/fields.lua    the planet maps and the planets' orbits
src/transit.lua   mass drivers, the flight and catch, the old lane, gas giants, the Heaven-Ladder
src/save.lua      save files (plain Lua tables, sandboxed on load)
src/ui/           cargo screen (with the market tab), hangar tab, mass driver orrery, in-flight view, pause menu
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

- No economy or market yet, and levels don't remember what's floating in them (wrecks, containers) when you leave.
- The art is placeholder outlines, and there's no audio.
- Field repair items aren't in yet, pending their design.
