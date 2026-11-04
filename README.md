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
| Buy a ship (shipyard list, with your own ship selected) / sell a parked ship | Hangar tab buttons | |
| Save / load newest (docking and quitting autosave; launching continues) | F5 / F9 | |
| New ship after death (at the last station you docked at) | R | Start |
| Hide help | H | |
| Pause menu (resume, save, load, quit) | Esc | Start |

## What's in it

- Box2D flight: thrust and torque only, with quadratic drag giving a natural top speed instead of a hard cap.
- Thrust is relative to the nose, and the main engine only pushes forward. Reverse and sideways movement come from built-in maneuvering thrusters (the hull's `sideThrust`). Light hulls have plenty, so they can strafe with their guns on target. Heavy hulls (Bastion, Hauler) can't strafe: A/D turn them, and built-in maneuvering thrust helps them turn faster. Maneuvering thrust is configured per hull with `sideThrust`.
- Mass is hull + modules + whatever's in the hold. Firing ammo makes you lighter; picking up loot makes you heavier.
- Your hold is a grid of 1 m3 cells (Wisp 6 x 4, Bastion 12 x 10, Hauler 20 x 20), and each Cargo Pod adds a small grid of its own. Items take shapes on it (rounds 1 x 1 in stacks of 50, missiles 2 or 3 cells long, crates 2 x 2), so a hold can fill up before its raw volume does. Press Tab to open it: drag stacks around, R rotates while dragging, Shift-drag splits a stack, and right-clicking a stack (or dragging it out of the window) ejects it behind the ship. Docked at a station, the same screen opens next to that station's storage: Ctrl-click or right-click moves a stack to the other panel, and double-clicking an ammo crate unboxes it into loose rounds.
- Docked, the left side of the cargo screen shows your ship's equipment on the hull outline. Drag a module from the hold or storage onto a slot (or double-click it) to fit it; the old one goes back where the new one came from. The panel shows top speed, acceleration, turn, spare power and mass before and after. Refitting only works docked, and a Cargo Pod with cargo in it can't be pulled. You can't launch without a reactor and an engine or thrusters (side jets push you forward when there's no engine). Modules never wear out, and each one fitted to a wreck has a 50% chance to survive as loot.
- Looting: tap E with the cursor on a wreck or a cargo container in tractor range to open it next to your hold, then drag, Ctrl-click or right-click to take things, or press Take All. While it's open your tractor beam holds it, matching your speed and pulling it back in when it drifts past about half the beam's range; the pull has a limit, so burn away hard and it slips out of reach and the window closes. Cargo containers (8 x 4 inside) drift in every field, and a Hauler carries its cargo packed in them, so its wreck holds loaded containers: double-click one to open it, or move the whole thing if your hold has room. Shooting a container apart spills its contents. Hold E on a floating container to tow it (slowly); if your hold has room for its 8 x 5 shape it's reeled in and stowed, cargo and all (a Wisp's hold doesn't, an Anvil's just does).
- Three hulls (Wisp, Anvil, Bastion) with slot layouts and hull bonuses, plus 20 catalog modules with strict size matching.
- Fast projectiles: guns reach about 1,000 px and artillery 2,000 to 3,000 px. Lasers run on power instead of ammo, and missiles are guided. Artillery shells and missiles have a proximity fuse, so they burst near an enemy, on contact, or at the end of their range. Every round is an item in the hold.
- Hulls can be built from several polygons (`parts` in data/hulls.lua), each shaded or tinted apart from the ship's colour. Its wreck stays whole, but each part besides the biggest can be shot off, breaking away as its own small wreck with its share of the loot. The Hauler is the first.
- Knockback, recoil and ram damage. Ram damage scales with impact force, so heavy ships hit harder. Each hull also has its own impact speed below which a bump does it no harm (`ramSpeed`): a Wisp takes damage from about 100 px/s, an Anvil 170, a Hauler 200 and a Bastion 250.
- Five enemy types built from the same parts and flight code as you. The basic Scrap Drone has no side thrusters, so it flies straight at you and is easy to hit. The Dart harasser is the twitchy, hard-to-hit one. Each level has its own enemies scattered around it; they leave you alone until you come within about 2,600 px or shoot them.
- An Enemy damage slider (default 0.7) in the debug panel is the quick difficulty knob.
- Wrecks drop part of their ammo plus salvage, and a full hold leaves loot behind.
- Planets: you start at Earth (the big planet map). Venus and Mars are planet maps too, and Mars has the Heaven-Ladder, an orbital ring with gaps to fly through, held up by four space elevators. Jupiter is a first, barebones gas giant: a map three times Earth's size with no surface, where the deeper you sink below the cloud tops the harder it crushes your hull. The asteroid field, giant asteroid and lone station maps are kept as instance maps for missions later (debug panel). Scenery and combat NPCs regenerate on arrival; traders persist across regions and saves; station state, wrecks, containers and loose cargo persist in named areas.
- Mass drivers: every planet has one mass driver at the very edge of its map. Fly up its runway lights toward the breech and its tractor beam takes you like a station's, easing you in and holding you at the breech (come in too fast and it can't stop you: you overshoot out the barrel). It opens an orrery of the planets where they are right now; pick one (100 cr plus 60 per AU) and it fires you into the transit lane: a long highway arc laid out in full when you enter (rocks on the road, rocks off-road and the odd derelict, nothing popping in), longer the further apart the planets are right now (they circle the Sun with their real year lengths relative to each other; Earth's year is 30 minutes of game clock). There's no current in it: your thrusters just hit far harder while you're on it (the afterburner gets nothing extra). At the far end you come in from the edge of the other planet's map, still flying the way you were and lined up on the planet; turn round and fly back out the near end and you come home instead. The debug panel can switch drivers to the other way of travelling instead: a warp trip and a catch through braking rings at the other end.
- Hangar: docked, press Tab (or click the Hangar tab on top of the window). Each station's hangar bay is a 30 x 14 grid, and every ship takes a footprint the size of its hull (Wisp 4 x 2, Anvil 8 x 3, Bastion 14 x 5, Hauler 14 x 6), including the one you're docked in, so a bay only holds so many. Click a ship to select it, drag to move it (R rotates), and double-click or press Fly to swap into it; the ship you came in stays parked where it was. Cargo opens the Cargo tab with three panels: your hold, then station storage, then the parked ship's hold. Ships on the storage panel opens the first parked ship, Next cycles through them and x closes it. With a parked ship open, each panel has a Target button: right-click (or Ctrl-click) sends a stack to the target panel (the parked ship to start with), and from the target panel back to your hold (or from your hold to storage). The equipment panel hides while three panels are open, so close the parked panel to refit. For now new ships come from the debug panel's "Park a new ..." buttons; buying ships in the hangar comes next.
- Market: docked, the Market tab shows your hold (or station storage: the Your hold / Storage tabs on the left panel switch), a shared trade grid in the middle and the station's shelf on the right. You start with 5,000 cr. Put your goods and the station's on the trade grid (drag, or Ctrl-click / right-click to move a stack across); green frames are yours, amber the station's, and hovering a stack shows its price in green. The totals show what you get, what you pay and your balance after, and Complete trade settles it all at once. Bought goods go into your hold first, then storage. Leave the tab (or launch) and everything on the grid goes home. Buying costs the list price and selling pays 50% of it (a loaded container sells with everything in it). Each station sells its own catalogue (data/markets.lua), restocking each item a stack at a time on its own timer, and anything you sell stays on its shelf, where you can buy it back, for 10 minutes before it's sold on. The filters on the shelf (Ammo, Weapons, Modules, Misc) dim the rest.
- Death ends the ship. Press R for a starter Wisp docked at the last station you docked at (in whatever level it is), or at the start if you never docked. Your wreck stays where you died with everything you had.
- Saving: the game picks up from your latest save when it starts. Docking and quitting autosave, F5 saves, and F9 loads whichever save is newest. The debug panel has New game. Saves hold the universe (every station's storage, hangar and market shelf, named-area wrecks and cargo, your home station, your credits and the game clock), your ship with its hold, and where it is. They're plain Lua tables in LÖVE's save folder, versioned so later builds can upgrade them.

## Stable locations

Authored stations, trade buoys, mass drivers and moon departure points have
explicit IDs such as `earth/orbital_one` and `mars/to_deimos`. These identify
places independently of their display names, construction order and physics
bodies. `src/locations.lua` provides `get(id)`, `list(area)`, `position(id, clock)`,
`heading(id, clock)` and `velocity(id, clock)` without loading an area.

Loaded bodies follow those same clock-based motion rules, including station
orbits and cloud-city drift. Retained highway views also stay synchronized.
`game:locationEntity(id)` finds the physical representation if that area is
loaded. F1's **Location IDs and positions** section lists the local catalogue.

Station storage, hangars and home/save references now use location IDs. Markets
can declare a `location` ID, independently of their display label. Runtime/debug
stations remain temporary and are not catalogue entries. Start a new game when
switching to this build: old numbered station references are not migrated.

This catalogue does not yet assign NPCs, offer smart-terrain jobs or plan routes.
`love . --locationtest` checks all existing regions, live/unloaded position
agreement, stable save references, display renames and construction reordering.

## Area-object persistence

Wrecks (including detached parts and placed derelicts), cargo containers, and
loose dropped items survive travel between named areas and save/load. Their
position, motion, damage, part damage, remaining loot and nested cargo are
stored as plain records under `universe.areas`. Collected and destroyed objects
stay gone; an emptied area does not regenerate its cargo containers.

Around planets and moons, unloaded objects advance along the orbital current
using elapsed game time, at constant altitude. Other areas retain their saved
positions. This is a lightweight motion approximation, not offline physics. NPCs, projectiles, effects,
and background asteroid populations are not persistent in this first step.
Highways are temporary per-trip areas and are excluded. There is no offline NPC
simulation, expiration policy, or permanent NPC registry yet.

Save version 2 adds optional area snapshots. Older object snapshots can load,
but old numbered station references are not migrated by the location catalogue. `love . --persisttest` runs the focused round-trip, loot, wreck damage,
moon-travel and save-compatibility checks.

## Close-surface flight

Every planet and moon gently pulls ships inward near its surface, even when
stationary. The pull builds smoothly with proximity and follows rocky outlines.
Its reach is capped at 2,200 pixels on large worlds and half the radius on small
moons. Gas giants pull 4 times harder around and below the cloud tops, so a
cloud-city approach needs altitude control. Once fully docked, the station holds
the ship. Existing atmospheric heating and gas pressure hazards still apply.

F1 exposes **Surface inward pull**, **Surface pull reach**, and **Cloud-top pull
multiplier**. Defaults are 35 px/s² at the surface, 2,200 pixels maximum reach,
and 4 times strength for gas giants.

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

## Expanded destinations

Io and Callisto use Jupiter's existing moon highways; Enceladus uses Saturn's,
Titania uses Uranus's, and Deimos joins Phobos at Mars. Fly through the marked departure arc at the
parent map's edge to reach a moon, and use the moon's return arc to come back.
Pluto is a mass-driver destination (the `-` shortcut in the target window).

Phobos and Deimos retain their irregular rocky moon bodies (radii 1,400 and
800 pixels). Mars keeps the Heaven-Ladder and its existing stations, with nine
local traders and much less rock debris.

`love . --worldtest` runs targeted checks for the expanded destinations: highway
arrival and return, rocky moon bodies and sizes, docked save/load, and
Pluto's targeting shortcut. It exits with a failing status on an assertion and
writes `phobos-rocky-moon.png` to the game's save directory for visual inspection.
It also runs highway handoff regressions: immediate turnarounds preserve the
original scene, and arrivals reuse the visible approach scene without moving
the camera or changing ship motion. Comparison screenshots are saved as
`turnaround-before.png`, `turnaround-highway.png`, and `turnaround-after.png`.
The existing `love . --autotest` also exercises all moon round trips.

## Known gaps (on purpose for this milestone)

- Combat NPCs and background asteroids still regenerate; highway debris is transient. Station traders persist.
- The art is placeholder outlines, and there's no audio.
- Field repair items aren't in yet, pending their design.

## Local map

Press **M** to see the current region: planet, stations, trade buoys, mass driver,
moon departure gates, and your ship. Numbered markers match the location list;
click a marker or list entry to select it and see its distance. Loaded ships,
wrecks, cargo, and nearby offline traders appear as smaller contacts. Transit lanes show both exits.

Drag to pan, scroll to zoom, **Home** to fit the whole region, and **P** to center
on your ship. **M** or **Esc** closes the map. The map has its own camera and
blocks flight controls while open; the simulation continues running.

`love . --maptest` checks fitting and coordinate transforms across every region,
selection, zoom, pan, camera isolation, closing, and transit, and saves example
map screenshots in the game's save directory.

## Persistent traders

All 54 existing station traders have persistent identities, ship state, and
itineraries from the start of a universe. Loading an area never refills its
population. Cargo, loadout, armor, paint, journey, and docking waits survive
area changes and save/load. Dead traders stay dead and use normal wreck creation.
The shared replenishment timer introduces new traders to replace losses.
Mars retains its nine traders; other populated regions retain their three.

Highway previews draw the same circular map edge and departure arcs as local
space. Region labels are attached to fixed points on that edge, with no
camera-following badges or separate straight imitation of the boundary.

One in three traders takes a repeating planet/moon round trip where both ends
have stations (10 itineraries in the current world). Others keep their existing
station/buoy loops. Travellers fly directly between their station and moon gate,
bypassing mass drivers, then cross the highway, dock, wait, and return home. Phobos/Deimos have
no docking stations yet, and Neptune has no port, so these are not docking-trip
destinations. Moon corridor bearings stay fixed over time, so ships can reach an exit without
chasing its orbit. No station structures or artificial navigation points are added.

NPC gate approaches turn toward the exit early and straighten into an outward
radial approach before crossing the boundary. Powered traders follow the same
curved approach used by offline travel and the graph overlay, and compensate
for orbital current when aiming at a stationary exit. This applies to both
planet departures and moon return gates, including Earth and Deimos.

The graph names real locations and declared journeys in `fields.lua`. Earth has
six places and nine connections. The system-level connection for a moon is its
existing pair of departure gates and highway length. NPC movement never adds
nodes or edges.

- Online within 18,000 world units: real ship, existing flight/docking AI.
- Offline beyond 22,000: one journey record with progress; no physics body.
- Remote region/highway: arrival and activity timers, without map positions.
- Same highway as the player: matching persistent travellers can become physical
  ships, including oncoming traffic. These are the actual NPC records, not
  independently generated freighters. Departing ships remain visible in local
  space under powered AI and still react to attackers. Following them into a moon highway preserves relative position and
  departure velocity rather than assigning a fixed highway speed. Damage/cargo
  carry into their destination.

Each trader has a persistent cross-track offset up to 1,500 world units that
fades toward local endpoints. Offline station stops last 60 seconds; online
stops retain the existing 30–90-second behavior. Economic transactions remain deferred. Persistent transport duties use mass
drivers; patrols and pirates also participate in offline encounters. Highway derelict generation is unchanged.

Open **F1 → A-Life records and connections**, enable **Show simulation connections
and NPCs**, then open **M**. Blue lines are declared connections. Labels show
actual trader identity, state, and destination; the debug panel also lists
travellers in connecting highways. The map shows contacts sharing your highway.

`love . --tradertest` checks populations across every region and an Earth–Luna–Earth
round trip, including encountering the same trader in the matching highway,
route/direction filtering, damage/cargo retention, docking, return, save/load,
repairing saved driver detours, and exact spacing/speed when following a departure.
`love . --alifetest` checks local body/record transitions, hysteresis, spread,
docking waits, death salvage, scene adoption, and duplicate prevention.
`love . --graphtest` checks declared topology, projection, routing, serialization,
and graph construction without physics bodies.

`love . --navtest` runs a real physical departure from a station to a fixed moon
exit, checks that the ship does not first head to the perimeter, and follows and
attacks it during powered departure.

`love . --idletest` simulates ten minutes idling in a highway with physics and
preview rendering, returns to retained Earth, resumes physics, and saves. It
also checks that preview drawing follows the location clock without moving the
paused Box2D bodies. Preview poses are render-only; repeated physics transforms
on an unstepped world previously caused a native broad-phase crash on return.

The navigation computer shows the current relative collision course only when
contact between the actual collision fixtures is predicted within its lookahead
(default two seconds). Bounding circles alone do not trigger a warning. It fades in
briefly and clears immediately when the course is safe; reversing does not
leave a stale warning. Moving hazards are evaluated relative to the ship, and
the line follows the earliest predicted contact rather than an arbitrary object.
During the final half second before impact, the line becomes thicker and red,
and a larger X with a ring marks the obstacle surface. The warning clears
immediately when danger passes.
`love . --navcomputertest` checks warning lifetime, direction, near misses,
stationary motion, incoming hazards, docking/catching, and removing the module.

### Mars mining slice

Phobos and Deimos have permanent surface mining stations, retaining their rocky moon bodies. Mars traders reserve ore-hauling jobs at station departure instead of continuing fixed trading loops. Each mine produces one unit of Martian ore per 12 seconds, stores up to 80 units, and permits two reserved pickups. Haulers carry up to 10 units, constrained by cargo space, and deliver them to their Mars station. Unassigned traders wait docked; dead or escaped traders release reservations. Mine stocks, assignments, cargo, and delivery totals persist through saves and offline travel. Combat NPCs are unchanged.

The travel-graph debug overlay shows pickup/delivery assignments and waiting traders. Existing saved Mars traders adopt jobs at their next Mars docking departure. Run `love . --marsjobtest` for the production/reservation/delivery and physical mine-docking checks. Delivered ore is recorded as station supply; industrial consumption and player job contracts are not implemented yet.

Debug travel is available in **F1 → Teleport and destinations**: filter areas by name and jump to the selected planet or moon. On the **M map**, the dropdown beneath the planet name teleports to a selected area; scroll the list to reach all planets and moons. Right-click a map point to teleport within the current area. Right-click a planet on the mass-driver map to teleport directly to that area. The current ship, equipment, cargo and damage are preserved, and no travel fare is charged. Run `love . --debugtraveltest` for the integration checks.

## NPC tasks and interplanetary dispatch

A role-neutral task board in `src/tasks.lua` owns available work and exclusive
reservations. Task definitions specify eligible roles, requirements, selection
scores, preparation, route planning and completion. NPC records retain their
fixed role, current task and last outcome; the board and tasks survive save/load.
Death releases a reservation, and idle workers retry after ten seconds.

`src/transport.lua` supplies the first task type. One existing local trader per
eligible planet (apart from Mars's mining workers) becomes a dispatch worker
at its next docking stop. It chooses available transport work from that station,
loads five scrap, flies to the mass driver, crosses to the destination planet,
docks, delivers and chooses again. Tasks favor destinations other than the last
pickup port, avoiding immediate return trips. Busy manifests remain reserved; completed or abandoned ones become
available again after 120 seconds.

These are authored, recurring transport manifests with placeholder cargo.
They do not buy from markets, charge fares or calculate profits. A future economy
can supply requests through `Tasks.post`. Existing local traffic, moon trips and
Mars mining jobs remain supported. Other roles can register task types with the
same lifecycle; patrol and raid duties now use it alongside transport. Mars
mine hauling keeps its existing reservations.

Run `love . --tasktest` for role eligibility, reservation ownership, cargo,
offline completion and reassignment, save/load, death cleanup, and a powered
mass-driver departure followed by online destination docking and delivery.

## Engine exhaust

Player and NPC ships use the same warm engine exhaust. Each fitted engine
emits from its slot's `x, y` hardpoint, so placing two engines in the shipyard
creates two plumes. Exhaust points aft (local negative X), scales with engine
module-defined dimensions and throttle, and extends under afterburner.
Engine modules define an `exhaust` table in `data/modules.lua`: `width`, `length`,
`color`, `coreColor`, `glowColor`, `afterburnScale`, and `flicker`.
Changing an engine changes its effect for both player and NPC ships. Empty slots produce no flame.
Legacy unplaced engines use a tail fallback. Maneuvering jets use the same warm
palette.

`love . --enginetest` renders twin-engine player and NPC fixtures and checks
hardpoint positions, matching colors, refits, idle engines, afterburner extension,
and legacy coordinates.

Exhaust also burns intersecting ships, rocks, wrecks and cargo containers.
Each engine's `exhaust.damage` sets damage per second at full throttle (30/50/80
for Flit/Mule/Cinder); zero or an omitted value disables damage. Throttle scales
damage, afterburner extends its reach, and overlapping engine plumes add damage.
The entire visible plume, including its outer glow, shares collision geometry
with rendering. Asteroids briefly glow orange while being burned. It cannot damage its own ship or burn while docked. Damage uses the
normal attribution, immunity and retaliation rules and can hit friendly ships.

`love . --exhausttest` checks real polygon/circle overlaps, multiple fixtures,
two-engine damage, empty/idle/docked engines, rotation, throttle/time scaling,
afterburner reach, attribution and per-module disabling.


Ordnance computers also support laser-only ships (direct target marker) and
secondary guns. Mixed laser/projectile loadouts retain projectile lead regardless
of weapon ordering. Navigation and ordnance marks use translucent strokes; missile
guidance uses bright brackets with a dark under-stroke for contrast.
Run `love . --ordnancetest` for loadout and overlay regressions.


Computer variants are authored in `data/modules.lua` with two settings each:

| Computer | Range (world pixels) | Second setting |
| --- | --- | --- |
| Navigation | `radarRange = 12000` | `lookahead = 2` seconds |
| Ordnance | `radarRange = 6000` | `predictionTime = 4` seconds |
| Missile guidance | `radarRange = 4000` | `lockCone = 25` degrees, half-angle |
| Drone uplink | `uplinkRange = 4000` | `controlLimit = 4` |

Ordnance range applies even when another computer supplies a missile lock.
Its prediction horizon limits projectile flight time; lasers have zero flight
time. Drone controlLimit is the largest drone control cost eligible for direct
piloting (S=1, M=2, L=4); launch bays keep their own capacity. Leaving uplink range
or fitting a smaller controller hands control back to the ship. Existing mod
computers without these fields retain defaults. The global navigation/cone
sliders now serve as fallbacks for those older definitions.

`love . --computervarianttest` checks both settings on all four computers,
lock and pilot retention after limits change, and legacy definitions.

Side Jets are no longer a module or equipment slot. Hull `sideThrust` provides maneuvering thrust directly and is editable in the shipyard. Baseline hull values retain the previous scaled Side Jets thrust; ships no longer carry the module mass or continuous power draw. Existing saves/designs with the old slot layout may need to be recreated.


Moon transit uses the local-map slowdown-and-drift response beyond
`laneWidth + laneRamp + 2500` pixels from the route. It retains ordinary moon
flight (no highway thrust buff or near-end wall). A denser rock belt spans the
edge and extends `laneHazardDepth` pixels beyond it by default (24,000;
Transit lane debug setting), expanded for the widest camera view and limited
to valid lane geometry. Density is retained in bands across the wider field.
Those rocks are laid out at entry, stay clear of
the handoff mouths, and are not pushed back inside by the moon boundary.
`laneOffroad` controls their population; zero disables the off-road rocks.
Run `love . --moonboundarytest` for force, placement and no-pop-in checks.


Mass-driver users share one tractor/alignment/barrel/coast controller.
NPC dispatch workers reserve the driver, are reeled into its breech, aim at
their task destination and fire with the same choreography as the player.
NPC launches do not take over the player's camera, menus or travel state.
Both get the blue transit glow and immunity to damage and weapon knockback
while captured, held or being fired off. Losing the beam or cancelling the
targeting menu releases that protection. NPC launch phases survive save/load.
Run `love . --drivertest` and `love . --tasktest` for these launch regressions.


## NPC traffic debugging

Press **F4**, or use **F1 > A-Life records and connections > NPC traffic monitor**.
The live route board groups directed journeys and shows each NPC progressing
from departure to arrival. Click a marker for identity, role, task, cargo,
online/offline state, launch phase, departure/arrival clock and ETA. Hover for
quick details; click again to cycle stacked markers.

**Tab** toggles moon routes, the wheel scrolls routes or the inspector, and
**Space** freezes/resumes the displayed snapshot. Freezing the view does not
pause or advance the game. The header identifies an already-paused simulation.
**Escape/F4** closes it. The monitor is a debug schematic, not a gameplay map or
a claim about physical solar-system positions. It reads existing records without
advancing remote NPCs, spawning bodies or teleporting the player. Arrival timers
that have expired but await a simulation tick are marked as pending.
Run `love . --traffictest` for diagnostic data and UI regression checks.


## Custom station docks

In the station editor, select a docking part and disable **Auto direction from
station center** to set its heading independently of the station shape.
Enable **Custom entrance position** to place the door in station-local X/Y
coordinates. Opening width, interior depth, runway length, tractor half-width,
door-frame thickness, and a second tunnel opening are configurable per dock.
Headings use local +X = 0 degrees and +Y = 90 degrees. Other station parts retain
their authored collision shapes; the preview helps keep the approach clear.

The canvas previews the actual runtime geometry: amber door/centerline, green
tractor footprint. Custom entrance points follow whole-part drags and duplicate
offsets; mirrors reflect both heading and entrance position. All settings survive
export, reopen and autosave. Automatic geometry remains available for ring
stations. Data fields: `dockHeading`, `dockX`, `dockY`, `dockWidth`,
`dockDepth`, `dockRunway`, `dockCapture` (tractor half-width), `dockWall`,
and `dockBoth`. Run `love . --dockeditortest` for editor/runtime regressions.

Circular map edges and transit side boundaries share one response: brake outward
velocity, then apply the same small inward drift regardless of distance outside.
They do not apply a distance-proportional spring force. The outer rock belt
remains in place.


Moon exits hand off directly when the player crosses the map edge outward
through a marked exit. There is no scripted alignment, velocity override,
input lock, ghosting, flash or cinematic zoom. The retained origin scenery,
ship motion/spin, cursor aim, zoom, capacitor, engine spool and weapon cadence
carry across the coordinate change. The player can steer, reverse, boost or fire
immediately. Mass-driver launches retain their separate scripted sequence.
Run `love . --moonentrytest` for entry and immediate-control regressions.

Jupiter has two orbital trade buoys on its station track. Moon exits and the
mass driver connect to this corridor, with Olympus reached through a buoy rather
than used as a through-traffic junction. City-bound pilots finish circling above
the gravity band before descending to the runway. The city's tractor supports
NPCs against gravity just as it supports the player. Existing saved routes adopt
the buoy approach without teleporting their ships.
`love . --olympustest` checks orbital positions, routes at different phases,
saved-route repair, and a physical visitor docking at Olympus and climbing back
out to its buoy.

Berths accept ships up to three times their authored pad half-length; the
editor marker keeps its existing dimensions. `T.berthShipScale` controls this
capacity multiplier. Docking uses the nearest unoccupied berth that fits. Switching
ships while berthed preserves that placement and docking entrance. If the new
ship does not fit, it uses the nearest suitable free berth. Ships that fit the
corridor and hangar grid can use the station interior; oversized ships use a
suitable free authored berth. If none is available, docking is refused without
moving the ship to a generated overflow position. Berths provide normal station
access and survive saves and ship switching; undocking launches from that position.
Saves retain the player's berth or mooring, entrance and docking side.
`love . --berthtest` checks berth selection, taxi placement, ship switching,
save/load, and refusal when no suitable berth is available.

Enceladus, Pluto, Titania, Io, Europa, Ganymede, Callisto, Mercury and Triton
use the Moon's round rocky surface treatment: cratered terrain in each world's
own colors, without atmospheric haze or cloud bands. Surface appearance is
independent of landing rules: only Phobos, Deimos and Ceres permit soft terrain
contacts for mining. Other planetary impacts remain lethal, including Luna.
Titan retains its atmosphere; Phobos and Deimos retain their irregular outlines.


## Patrols and pirates

The main planets with orbital trade corridors seed two independent patrols and
one pirate as persistent A-Life records. They replace disposable field enemies
on those planets. Legacy authored pilots are restricted to the Asteroid field,
Giant asteroid and Space station instance maps. Roles remain fixed; patrols are
seeded once and lost ships are replenished through the saved arrival schedules below.

Patrols choose inspection duties through the shared task board and visit existing
stations and buoys. Pirates choose buoy raids and relocation duties, preferring
passing traders as targets. Patrols engage pirates and defend themselves when
attacked; peaceful ships are not automatic targets. Nearby combat uses the same
flight controller, fitted weapons, ammunition, damage and wrecks as other ships.
After losing contact, ships resume their selected duty. F1's A-Life list and the
map graph overlay show role, duty, destination and current target.

Remote encounters only compare records sharing a graph segment or endpoint.
Periodic seeded exchanges spend actual ammunition and carry hull damage across
online/offline transitions and saves. In offline encounters, low-health ships
withdraw; lengthy fights
also disengage. A fight involving a physical ship never receives abstract damage.
When the player approaches, both participants become physical where practical and
ordinary AI takes over. Offline deaths leave salvage records for 30 minutes;
approaching materializes each wreck once, after which normal area persistence
handles its cargo, looting and destruction. Pricing, reputation, node heat and an
event director remain future work.

Run `love . --securitytest` for role-specific autonomous duties, population
identity, target selection, physical combat and navigation, save/load, offline
ammunition/damage, repeatable rolls, mixed-state immunity and wreck persistence.

## Station services prototype

Docking opens three services: **Storage**, **Market**, and **Hangar**, beneath
a persistent station header. Panels size around their actual inventory contents,
using the player inventory frames, colors, typography, small-cell renderer,
and item controls. Storage keeps equipment beside the ship hold and station storage, including parked cargo
and opened containers. Equipment remains part of the inventory service. The
in-space inventory is unchanged.

Market uses three panels: player inventory (hold/storage selector), a pending
offer with separate **You give** and **You receive** grids, and station stock.
Right-click/Ctrl-click offers a stack; dragging, splitting and rotation still
work. Completing a trade uses the existing pricing and atomic settlement.
The **Ships** inventory selector shows owned stored vessels; the **Shipyard** stock
control opens both sides of ship trading and shows this station's catalogue.
Stations without a ship catalogue explain that they have no ships for sale;
they still buy stored ships. Hull footprints can be dragged or
right-clicked into the same offer as goods. Ship sales include installed modules,
cargo and containers; the active ship must be stored by switching ships before
it can be sold. Ownership changes only when the trade completes. Parking is
checked for the entire offer, including space released by sold ships.
Leaving Market returns the staged goods. No prices or economic simulation
rules were replaced.

The Hangar service shows a small interior packing grid, exterior mooring
positions, and shared ship details/actions. Ship shopping is in Market. Owned ships have one location:
`bay` for interior grid coordinates or `mooring` for a reserved exterior slot.
Purchases require a suitable free location. Switching ships leaves the old ship
in its own location and selects the new ship at its existing location. Both
types retain equipment, damage and their real cargo/container grids. The move
action transfers a ship between interior and exterior storage when space fits.
Drag an owned ship onto a specific free berth, or from its berth back into the
interior grid; occupied and unsuitable berths reject the drop. Use the exterior
list's arrows or mouse wheel to reach additional positions.

Layouts are station-specific, not hull-class limits. Defaults are a 12×10
interior grid with 20-unit cells and authored exterior berths. No overflow
positions are generated. Station definitions can set `hangar = { w = 12, h = 10 }`.
Berths may set `maxLength` and `maxWidth` independently of
their existing editor marker `size`. These settings survive F2 export and
autosaves; dedicated capacity-editing controls are not part of this prototype.
Larger ships and larger station layouts use the same system. Mooring fit checks
validate the parked hull against station geometry. A straight departure corridor
is not required to accept an otherwise usable berth.

Parking locations, owned ships and exterior coordinates persist through travel
and saves. Stored exterior ships are drawn at their moorings using the existing
hull renderer; they remain stored records rather than additional simulated NPCs.
`love . --stationtest` exercises service layouts, grid transfers, purchase/cancel
settlement, ship storage, switching, capacity limits, and save restoration. It
also writes real screenshots for the three services to the LÖVE save folder.

## Shipyard comparison

In F2, click **Compare ships** to open a movable, resizable comparison window.
The left column follows the current unsaved design; the right column selects a
ship from the hull list. Both use their fitted default modules and cargo, with
an option to empty both holds. Invalid or unfinished designs show an explanation
while the reference ship remains available. Preview ships live in a separate
physics world and do not replace the live ship or registered hull definitions.

The window includes the F1 handling numbers, power, armor, hold capacity and
maximum afterburner speed. The same afterburner maximum now appears in F1; it is
the full-power speed relative to the local current before capacitor reserve mode.
F1 can toggle the debug panel while the editor or its text inputs have focus.
Run `love . --comparetest` for handling parity, live edits, empty holds,
incomplete designs, preview cleanup, and the actual F1 key handler.

`love . --npclifetest` checks drawing immediately after NPC removal, fleeing,
death and stale-body cleanup, plus distance culling/rematerialization. Online
ownership ends before a body is destroyed; ordinary culling preserves the record
and its duty instead of marking the ship gone.

Afterburner reserve protects the configured capacitor floor (30% by default).
Holding boost stays at reduced output once that floor is reached, without
cycling to empty and back. Release boost to recharge and rearm full output.
Weapons and passive power deficits can still use charge below the reserve.
Engine plumes interpolate between normal, reserve and full boost; their damage
bounds use the same geometry. `love . --afterburntest` checks reserve stability,
rearming, energy accounting, actual thrust and corresponding flame sizes.


## NPC replenishment and warp-ins

Pirates, traders, patrols and miners share `src/population.lua`. Each role checks
for replacements every 3–5 minutes of game time, with a separate saved timer per
home region. Pirates retain their target of two; other roles use the region's
existing trader, patrol or miner population. Living ships still count toward
their home population while visiting another region or travelling between planets.

Dead or escaped ships are replaced with new identities, fitted ships and their
role's existing routes or jobs. Each overdue role gets at most one arrival per
check, without catch-up swarms. Remote arrivals remain records without physics
bodies. Local arrivals use the same clear-space checks and blue warp flash as
pirates. Instance maps do not receive persistent A-Life reinforcements.

In **F1 > Spawn and arena**, select a role and use **Warp in … (A-Life)** for an
immediate arrival near the player. This debug action bypasses the automatic
population target. The panel shows each supported role's count, target and next
check. Role intervals and warp duration are in `src/tuning.lua`; additional
roles register their target, navigation nodes and ship/job creation with the
population module. Existing pirate saves retain their scheduled arrival time.

Run `love . --populationtest` for all-role replacements, travel-aware caps,
remote records, saved timers, local warp effects and failed placement. The
existing `--piratespawntest` also exercises pirates through the shared scheduler.


## NPC local navigation

NPCs sweep their hull clearance against nearby collision fixtures and moving
traffic before choosing a local heading. They prefer clear detours, keep a
consistent passing side, and can turn back out of concave obstacles. Waiting
patrols and pirates use separate holding positions around a shared buoy. The
authored travel graph and planetary routes still determine their destinations.

Traders, security ships and highway traffic use their fitted afterburners when
aligned with a clear route and sufficiently far from their stopping point.
Obstacle avoidance, final approaches and braking disable boost; ordinary engine
power and capacitor reserve rules apply. Low-altitude departures climb out of
the gravity band before resuming their orbital route. Cloud-city NPCs receive
the existing runway support until clear of the structure, including across an
immediate save/load.

Steering decisions are cached for 0.2 seconds while the route remains stable,
and geometry queries use the physics broad phase. Clearance, refresh interval,
boost cruise multiplier and stopping margin live in `src/tuning.lua`.
Run `love . --localnavtest` for physical hauler tests around a wall, inside a
concave pocket, in head-on and crossing traffic, and for safe boost activation.
`love . --olympustest` checks city arrival, supported departure and restoration.

Terrain chains have multiple broad-phase proxies, so navigation processes each
fixture once per query before expanding its edges. `love . --navprofile` runs
60 simulated seconds each on Phobos, Deimos and Earth and reports simulation
step timings plus steering, detour and mining-position costs. Rendering and
display FPS are excluded from these measurements.

Cloud-city inspection visits use a point above the gravity band, following the
city's bearing. Non-docking patrols approach and hold there instead of trying to
reach the docking runway below their avoidance boundary. Remote materialization
and saved inspection offsets use the same point. Run `love . --patrolnavtest`
for Olympus patrol arrival, holding, restoration and the next autonomous duty.


F3 region cycling uses the shared debug teleport cleanup, closing cargo/trade
UI and cancelling old travel state. Unloading a field disposes of its complete
physics world instead of reusing its native allocations. Distant generated
debris is put to sleep before NPCs start navigating, avoiding an initial scan
of the complete belt. Only highway origin
and arrival scenes that are still needed remain alive; adopting a retained
scene preserves that scene's world. `love . --teleporttest` checks two complete
F3 cycles, leftover unmanaged bodies, abandoned highway previews and warp-flight
cancellation.

## Drill sites and A-Life miners

Surface drill props on Phobos, Deimos and Ceres, plus the large asteroid props at
Ring Station, periodically blast out batches of mineable rock. The Giant
asteroid instance has a drill site as well, without adding A-Life pilots there.
Each drill emits three chunks every 18 game seconds and stops at twelve
outstanding chunks or ore stacks. Timers survive revisits and saves; overdue
sites emit one batch rather than a catch-up swarm. Chunk damping keeps the work
close to its source. Timing, population, batch and capacity settings live in
`src/tuning.lua`.

Two independent miners per populated mining region choose work through the
shared task board. They approach a chunk, use their fitted **Bore Drills** at
contact range, tractor the actual dropped ore, and return to dock with a load.
They unload into saved station raw-material stock and choose their next duty.
Stock is shown in F1's A-Life section; pricing and market settlement remain
separate work. NPCs and the player use the same drill damage, ore drop table,
power rules and pickup transport. Ordinary drilled debris keeps its existing
fragmentation behavior; industrial chunks are consumed once into their ore.

Miner identities, cargo, drill timers, chunk health, loose ore and delivered
stock all persist. Miners retain pickup destinations outside tractor range and
seek saved resources that drift beyond the local physics band, rather than
returning to an empty waiting node. Distant workers use the same finite chunk/loot records and
fitted drill power budget, without remote physics bodies. A resource represented
by a live body or pickup is excluded from abstract mining. Physical resources
stay awake around the player or an online miner, within the per-site cap.

Run `love . --miningtest` for a complete physical drill/loot/delivery cycle,
autonomous next duties, save restoration, shared online/offline resource
accounting and production caps. Set `THRESHOLD_MINING_AREA=phobos` or `belt` to
run the same physical cycle against those surfaces. The test writes a mining
screenshot into LÖVE's save directory.
