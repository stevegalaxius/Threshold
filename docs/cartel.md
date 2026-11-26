# The Milliways cartel

Milliways (the Shoals, Cordelia, Antichthon and the Milliways grid off Pluto)
is a drug cartel. Its grids are on the public charts (`cartel = true` in
`src/fields.lua`, no longer `dark`) and trade like any other station, except
with the two powers that embargo it. Pirates still call them home: raiders
don't raid there, wildcats sell their hoards there, and fences still buy
pirate loot from them (`Dark.isHaven`).

## Relations

`Rep.STANCE` in `src/reputation.lua` contains the starting relationships.
NPC port access, patrol targeting, and trip preferences read the current
relationship through `Rep.stance(a, b, universe)`. `Rep.setStance` changes a
pair for that save.

| Power | Stance | Why |
|---|---|---|
| Estates | hostile | the labs run on medicine bought out from under the Garden |
| Diwan | hostile | a devout House, and the cartel's brine and chemistry are smuggled off its moons |
| Jove | ambivalent | a customer is a customer |
| Zhuhai | ambivalent | the Mandate can't agree on a crackdown, and the spokes run on stims |

A hostile power:

- embargoes the cartel (`Rep.embargoed`): its stations neither buy from nor
  sell to cartel stations, and buy no contraband (`Rep.CONTRABAND`) except
  at a fence. Contraband goes to a fence directly, never through a hostile
  power's hub.
- has its patrols shoot crews of hostile factions on sight in its own space.
  Crews check both the port owner and the local power before booking a routine
  stop. They prefer jobs that avoid hostile grids and can still pass through
  those grids. A dedicated fence run can call at its designated fence.

## The chain

| Where | Makes | From |
|---|---|---|
| Conamara Station (Europa), South Pole Port (Enceladus) | alkalines | ocean brine |
| Cinder Works (cartel lab) | amphetamines | nitrates, alkalines, medical supplies |
| Cinder Works (cartel lab) | fentanyl analogues | industrial acids, heavy metals, medical supplies |
| Antichthon Gardens (moss beds, profit-run) | cannabinoid moss | fertilizer, water |

Buyers:

- Hakka Tulou Habitat (Mars): amphetamines, moss
- Valhalla Port (Callisto): fentanyl, some amphetamines, moss
- Elysium (Earth, a fence): fentanyl and moss, smuggled
- Neptune's Bounty (Triton, a fence): moss

## Not built yet

Fast or stealthy cartel hulls, contraband heat for the player carrying
product through hostile space, dependency levels that drive demand, and
crackdown events.
