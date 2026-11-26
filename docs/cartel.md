# The Milliways cartel

Milliways (the Shoals, Cordelia, Antichthon and the Milliways grid off Pluto)
is a drug cartel. It still raids and fences loot; its industry now makes
narcotics and counterfeit medicine and sells them into the white network
through fences.

## Relations

`Rep.STANCE` in `src/reputation.lua` is the one standing feud between
factions; read it with `Rep.stance(a, b)`.

| Power | Stance | Why |
|---|---|---|
| Estates | hostile | the counterfeits undercut their medicine trade |
| Diwan | hostile | the precursors are Diwan chemistry leaked by its own people |
| Jove | ambivalent | a customer is a customer; Callisto looks the other way |
| Zhuhai | ambivalent | the Mandate can't agree on a crackdown, and the spokes run on stims |

In a hostile power's space its patrols shoot cartel crews on sight
(`Rep.cartelCrew`: runners, raiders, dark-born crews; `src/security.lua`).
Hostile powers keep no fences.

## The chain

| Station | Makes | From |
|---|---|---|
| Antichthon Gardens | poppy latex | fertilizer, water |
| Slag Harbor | precursor chemicals | nitrates, water |
| Cinder Works (cartel lab) | synthetic opioids | poppy latex, precursors |
| Cinder Works (cartel lab) | amphetamines | precursors |
| Cinder Works (pill press) | counterfeit medicine | precursors, water |

Milliways Freeport is the hub the product is shipped out from. The fences
that buy and use it up:

- Hakka Tulou Habitat (Mars): mostly amphetamines
- Valhalla Port (Callisto): mostly opioids
- Neptune's Bounty (Triton): opioids and counterfeits

Elysium is no longer a fence, since the Estates are hostile.

## Not built yet

Fast or stealthy cartel hulls, contraband heat for the player carrying
product through hostile space, dependency levels that drive demand, and
crackdown events.
