# Setting and lore

Curated from a brainstorm (an outside AI's lore export) and checked against
what the game already has: `src/reputation.lua` (factions), `data/outlets.lua`
(news), `src/world_layout.lua` (stations), `data/markets.lua` (yards and
shops). This is a writing reference only. Nothing here changes game data.

Anything marked **[CONFLICT]** disagrees with something already in the game;
the game wins until you decide otherwise. **[NEW]** is not in the game yet.

## The premise (kept)

Non-relativistic travel; mass drivers fire ships between planets (matches the
driver/orrery system). Four major powers (Estates, Zhuhai, Diwan, Jove) in a
200-year equilibrium that is mutual dependency, not peace. Each power
runs on a belief that cannot be disproved, and its outlet repeats it. The
outer system is independents, company towns and drifters (the secondary
factions: Ceres Concern, Milliways, Bowman Atmospherics).

## The powers

**The Estates (Earth, Venus, Mercury).** Hereditary houses plus the remnant UN.
Venus's Garden is habitable only through constant machine maintenance; the
maintenance contracts are the economy, handed out by rank. Status over power.
Mercury is the ugly automated foundry that makes the Garden possible and goes
unmentioned; its few technicians are free and redundant. Fits the game's
Terminator Station, Cloudline Station, Elysium and Ashgrove Drone Foundry.
Their house style is elegant, fragile, maintenance-hungry (fits the Estates
hulls). Outlet: Inner Worlds Gazette (in game).
- Kept as flavour: the Court, the Season (rank is set in public), the Chancery
  (awards contracts). Use as station/quest vocabulary.
- [CONFLICT] The export's yards (Maison Vaugirard, Ateliers Delacroix, Chantier
  du Soleil) don't exist; the game has Estates Naval Yards, Ferrous Collective
  and Brute Industries (Mercury). Don't add them unless you want new yards.
- [CONFLICT] Export outlet "Le Courrier des Deux Mondes" / Hélène de Vaugirard.
  The game's outlet is Inner Worlds Gazette. Dropped.

**Zhuhai (Mars).** Industrial state ruled by a deadlocking rotating council
(the Mandate) of conglomerates; the Heaven-Ladder ring is its showpiece. Poor
live in the spokes, the rich on the sunlit tier; workers are bound but
essential. Mirror image of Mercury: bound-but-essential vs free-but-redundant.
Keep that pairing; it's the best idea in the export. Heavy, overbuilt ships
(fits Red Furnace hulls). Outlet: Red Signal (in game).
- Kept: the creed ("cast the mountains into sea"), Contract-Bearers /
  Dust-Workers / Ring-Rats as class names, Hakka Tulou and the Home-Gazing
  Terrace as places to describe.
- [CONFLICT] Phobos/Deimos: the export says Phobos = Moon-Swallowing Yards and
  Deimos = Star-Breaking Mine. The game has them the other way round
  (`phobos_1` The Star-Breaking Mine, `deimos_1` The Moon-Swallowing Yard).
  Game wins.
- [CONFLICT] "3,000 km habitat ring" vs the game's Heaven-Ladder, an orbital
  ring on four elevators with gaps to fly through. Keep the game's version;
  the seven-seat Mandate fits either.
- [CONFLICT] Angelmaschinenwerft is a Zhuhai shipyard in the export; in the
  game it is the Venus (Estates-side) atelier. Game wins.
- [CONFLICT] Export outlet "The Cast-Sea Daily" / Wei Jian. Game: Red Signal.
  Dropped.

**Jove / the Olympian Accord (Jupiter system).** A federation of station-states
with no capital, a council that deadlocks, a navy that employs more than it
protects, and docking law everyone cites and nobody understands. Holds
together because a paying customer is cheaper than a war. The game already
has Olympus and Kyrakos at Jupiter, so "Olympian Accord" is a natural formal
name for Jove; use it in text, keep `jove` as the faction id.
- Kept as flavour: Kyrakos as customs house and dispute court; each Galilean
  moon's role (Io sulfur, Europa water, Ganymede nitrogen/fertilizer,
  Callisto logistics and records). Matches the game's Io/Europa/Ganymede/
  Callisto stations and customs depots.
- [CONFLICT] The export's Agora as the central exchange, plus names Brimstone,
  the Cinder, Bowman's Folly, the Brine, the Table, the Archive. Not in the
  game (the game has "Cinder Works" in the Shoals, a different place).
  Treat as optional district names only; don't reuse "Cinder" or "Bowman" as
  they already mean other things.
- [CONFLICT] Yards: Standard Yards, Amalthea Marine Works, Kessler & Vane are
  not in the game. Outlet: game has Jovian Ledger; export had Jovian Register
  / Marta Kessler. Dropped.

**The Diwan of Ephraim (Saturn).** A closed dynasty on Titan; a petrostate that
sells just enough to keep everyone dependent. The ruling tribe (Ephraim, Titan)
and working tribe (Manasseh, Enceladus). Fits the game's Shiloh, Zebulun's
Bounty, Ephraim's Bounty, Abaddon, Sinai Deep, Rephidim, Gilgal Arsenal and
the Diwan hull names (Cherubim, Seraph). Keep the Trust (hydrocarbons held as
sacred stewardship), the Qibla Fund (speculative arm), and a Hebrew domestic
press that argues with the government and is never translated (nice detail;
could be a flavour line in the Courier).
- [CONFLICT] "Manasseh's Bounty" (Enceladus): the game has no such station;
  its third Bounty is Neptune's Bounty at Triton. Don't add without deciding.
- [CONFLICT] Export ship names (Solomon, Absalom...) are unused; fine as NPC
  ship names if wanted. Outlet "The Ephraim Review" / Joseph Bernstein vs the
  game's Diwan Courier. Dropped.

## Secondary factions and places

- **Ceres Concern**: the Belt's nitrate/explosives works, named for Ceres and
  for worry about what it makes. Fits the game (Ceres Dock/Logistics/Quarry
  Depot, outlet Beltway with a hidden Ceres owner). Keep the joke in the name.
- **Ring Station**: joint Estates-Zhuhai habitat in the Belt, run by a
  commission that agrees on nothing, now the Belt's biggest port. Fits the game's
  Ring Station and Lumen Fabrication. Keep. Good hook: the only place both
  powers' reputation matters at once.
- **Bowman Atmospherics**: Uranus cloud platform, chartered company town of
  shareholder families, suspicious of outsiders. Fits UAE-4/7/9. Keep;
  "contract crews on fixed rotations" is a good way to flavour its jobs.
- **Triton**: last stop before the lanes run out, bonded warehouses, people who
  don't want to be found. Fits Triton Logistics and Neptune's Bounty. Keep.
- **The Freeport (neutral ground, "leave your guns at the door")**: the game's
  equivalents are Milliways (Pluto), Shoals, Cordelia and Antichthon freeports.
  Fold the "guns at the door" rule and the grey market role into those instead
  of adding a new station. Not added as a separate "Clearing".
- **Thule Prime (Moon)**: exists in the game as a Luna station. The
  "descendants of an old ideology, isolated and not taken seriously" backstory
  is a fine one-line description. Keep, keep it light.
- **The Hollow** (abandoned Belt stations, nothing can be owned): [NEW].
  Good fit for the hidden-site system (`data/sites.lua`); a discoverable
  derelict-station site. Kept as an idea.

## Economy and mobility (adapted)

The export puts the central exchange at Jupiter, a secondary market at Ring
Station and a grey market at the Freeport, and says only the Belt and the Accord
let newcomers buy into the trade. That's consistent with the game's hub-to-hub
logistics (each system has a logistics hub) but not a mechanic. Keep as
background text: independents thrive in the Belt and Jovian space, are stuck
as contractors or contract-bearers elsewhere.

## Timeline (adapted, loosely)

Venus terraformed -> Martian independence and a war over the Ladder -> the
Jovian wars and the Accord -> the Diwan breaks from Jove (tariff war into cold
peace) -> the Long Equilibrium. [CONFLICT] The export's year counts ("1,800
years ago" and so on) are inconsistent with a roughly 200-year equilibrium
and with each other. Keep the order of events, drop the numbers until you pick
a calendar.

## The Fifth Faction (idea, unresolved)

The export's "Standing / the Quiet / Bloom Cult" is one thing under three names:
a movement organised around an unfalsifiable claim about something in the outer
system, whose power is that it never stops claiming. Good concept, but the
export gives it no name, place, or goal, and it's the only plot hook in the
whole document. [NEW] If wanted, it would be a hidden site or a minor faction.
Needs a decision on name, location and what the claim is before any of it is
usable.

## Dropped

- Reactor tiers (chemical / fission / fusion with helium-3): the game's items
  and power model are its own; adding tiers is a design change, not lore.
- Ship manufacturer table (Great Hearth, Trust Yards, House Salim & Sons, the
  Closed Yard, Slag Forge, Station Customs, etc.): mostly absent from the
  game; the real yard list is in `data/markets.lua`. Only the philosophy
  one-liners (Zhuhai heavy, Estates elegant, Accord modular, Diwan sealed,
  Belt repurposed) are kept.
- The export's whole news-outlet table: all six names and editors conflict
  with `data/outlets.lua`. The only keepers are each outlet's "fiction"
  (what it insists is true), which matches how the game already writes them.
- The "Caliphate"-style, invented-faction, and "Not Yet Developed" lists
  (Kuiper Belt, Oort Cloud, the Sun, Earth as a place): no content, nothing to
  keep.
