# Wildcat sites

Wildcat sites are the instanced sites (`data/sites.lua`, `src/sites.lua`) as they
appear in normal play. They open on their own, raid the planet they orbit, and
close once their crew is gone. The code is in `src/wildcats.lua`.

## The cycle

1. **A site opens.** Every `T.siteSpawnEvery` (30 min, give or take 30%) `Sites.tick` may open a
   `wild` template near a planet that has a mass driver, police and a paying station
   (`Sites.homes`). The caps are `T.sitesPerPlanet` per planet and `T.sitesMax` in all. A new site
   is hidden: it isn't on the driver yet.
2. **Its crew is rolled once.** Each `enemies` piece gives `crew = { min, max }` wildcats. Each one
   is an A-Life record flying a hull rolled the way a pirate's is (`npc_ship_supply.seed`), with
   the raider combat profile. A crew never recruits from the NPC pool and never grows. Damage, ammo
   and cargo persist on each record.
3. **Wildcats raid.** A posted wildcat goes out every `T.wildcatSortieEvery` (15 min, give or
   take 40%). It comes off the planet's mass driver and runs the ordinary raider brain: raid legs
   round the planet, robbery demands and fights. It never leaves its site empty, never goes out
   hurt, and stays in while the site is under attack or you're in it.
4. **They come home.** A wildcat heads back to its site when it has loot, when it's hurt, or after
   `T.wildcatSortieTime`. What it stole goes on the site's hoard (`inst.hoard`). At its post it
   patches its hull (`T.wildcatPatchRate`) and rearms.
5. **The hoard is fenced.** Once the hoard reaches `T.hoardFenceAt`, one wildcat carries it to the
   a dark station (any one it can reach, picked at random) and sells it there through the usual fencing, so it turns up as shadow-market
   stock. Wildcats are raiders, so Milliways and the other dark raiders leave them alone. They are
   never Milliways and never move Milliways standing.
6. **Hulls are cycled.** At the fence a wildcat runs the same docked refit as every NPC
   (`src/npc_refit.lua`): if it can afford a better ship on that station's used lot, it trades its
   own in. Wildcats and hunters are scored by the role they buy ships as (pirate, patrol).
7. **A bounty is posted.** The system's paying station (the one that pays the wreck bounty) counts
   what a site's wildcats rob or kill. After `T.bountyLosses` it posts a bounty. The site is
   discovered for everyone, so it shows on the mass driver, and `T.bountySlots` `site_bounty`
   offers go on the board.
8. **Kills are paid.** Once a site has a bounty, each of its wildcats is worth `W.perHead` to
   whoever lands the last hit, wherever it dies. An NPC is paid into its credits. The player's pay
   goes on the same tab as the wreck bounty, collected on the Jobs tab at any station in that
   system. The Jobs tab lists the system's posted sites.
9. **Hunters go in.** Bounty hunters (template `hunter`, `T.huntersPerSystem` per owned system)
   take `site_bounty`, fly to the driver and enter the site (`r.assault`). Offline, `W.tick` rolls
   the fight pocket by pocket with the offline combat rule. A hunter that breaks pulls out and may
   not make it (`T.hunterBreakKill`). When you're in the pocket, both sides are live ships and fight
   there: you can warp in on them mid-fight and help, watch, or loot afterwards.
10. **The site closes.** When no crew is left at any post, the site is done and closes once you're
    out of it. If you killed the last of them, the hoard drops in containers in that pocket. If
    hunters did, what's left goes back to the station that posted the bounty. Wildcats still out
    raiding when their site closes scatter when they get back.

Killing a wildcat gives the usual +3 standing with the faction that owns its planet. The papers
covering that planet report bounties posted and sites cleared.

## Saves

Sites saved before wildcats (with garrisons topped up from the pool) close on load, and old
garrison records are removed.

## Checks

`love . --test` covers the crew roll, a raid and the trip home, the bounty, an offline hunter
fight, warping in mid-fight, save/load and a site opening on its own. `SOAK_FAST=1 love . --soak`
prints a `sites` line each hour.
