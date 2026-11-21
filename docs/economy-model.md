# Economy model

`love . --econmodel` works out, from the data files and in about a second,
what the economy has to make, where, and what has to be hauled where. Run it
before changing recipes, facilities or station layouts, instead of finding out
from a soak. `src/economy_model.lua` has the details.

```
love . --econmodel                        # print the report
ECON_OUT=model.json love . --econmodel    # also write the model as JSON
SOAK_HOURS=3 love . --econcapture         # re-measure data/economy_baseline.lua
```

Open `tools/econmodel/viewer.html` and load one or two model JSON files to
browse it: goods, facility load, freight lanes, a system map, and a comparison
of two models (for example main against a branch). Issues new in the second
model are marked.

In the game, the A-Life debug suite (F6) has an **Economy model** section.
*Model live demand* runs the model on the running game, with the service
demand its stations are measuring now; *Model baseline demand* uses the
captured baseline instead. It lists the issues, the tightest goods with their
stock against buffer, the busiest facilities and the busiest lanes. *Save
JSON* writes `econ_model.json` to the LÖVE save directory for the viewer.

## What it computes

1. **Final demand**: what stations use up for their own sake. That's the
   `use_*` facilities, water and food, plus the service demand measured in
   `data/economy_baseline.lua` (fuel, ammunition, repair plates, modules,
   ships sold) and what the miners bring in.
2. **Required production**: final demand pushed back up every recipe. Each
   taker draws first on its own system's makers, then the nearest spare
   capacity anywhere. Fixed plants (wells, farms, shipworks) run at their
   rated pace whatever anyone wants, so their inputs count at full rate.
3. **Load**: required production against rated capacity, per good and per
   facility pool (recipes that share an installation share its units).
4. **Lanes**: every maker-to-taker link routed the way `src/economy.lua`
   routes it. Inside a system it goes straight there. Between systems it goes
   maker, hub, hub, taker. Hold kept on a lane is volume an hour times the
   round trip, which is compared with the haulers' total hold.
5. **Buffers**: the stock stations want on hand (`E.target`) against what
   they hold, and how long spare capacity takes to close the gap.
6. **Order lots**: on each lane, the order a buyer places when it runs low
   (its target, or `E.orderLot`: `T.orderLotHours` of its own use) and what
   that order pays per hour of flying, against the median lane.

## Issues it flags

| kind | meaning |
|---|---|
| `source` | used, but nothing makes or mines it |
| `pool` | a facility needs more than its rated capacity |
| `buffer` | spare capacity takes over 6 hours to fill the stock stations want |
| `fleet` | lanes need more than 60% of all hauler hold out at once |
| `freight` | hauling a unit pays more than the unit is worth |
| `slow` | a single trip takes over 2 hours |
| `lot` | a lane's orders pay under a quarter of the typical lane per hour flown: lots of tiny orders that crowd the freight board |

It's a capacity model, not a simulation: no prices or timing, and order sizes
only as an estimate.
Anything it calls short is short however the game plays. Anything it calls
fine can still go wrong in the timing, so keep soaking the changes that pass.

The fleet's limit is trips, not hold. The freight board ranks orders by how
long their shortage has gone unserved, so a board full of small orders keeps
the whole fleet busy carrying a few units at a time while the orders behind
them wait for hours. That is what the `lot` check catches.

The baseline comes from the first hours of a new game. Re-capture it when
service demand changes a lot (new fuel use, a bigger fleet).
