# Reactive Drug Consumption

## Problem

Drugs (`amphetamines`, `fentanyl`, `cannabinoid_moss`) are consumed at flat, invisible rates by a handful of stations via `use_*` facilities (`use_fentanyl={capacity=-6}`, etc.). They're just market demand sinks — negative-capacity consumers in the economy model. No visible effect, no quest hooks, no player agency. Contraband status is a label with no consequence.

## Goal

Replace flat consumption with **crisis-driven reactive demand** that:
- Spikes drug demand when stations are under real stress
- Reduces NPC trade activity when a station is in crisis
- Creates observable market signals the player can exploit or address
- Generates quest hooks through the existing quest system
- Has no dependency spirals, no irreversible feedback loops, no fence distribution networks

## The Three Drugs

Each drug is triggered by a different perpendicular axis of station state:

| Drug | Crisis Trigger | Direction | Logic |
|------|---------------|-----------|-------|
| **Amphetamines** | Production pressure | More bustle → more demand | Busy station, crews pushing extended shifts |
| **Fentanyl** | Food shortage | Hungry → more demand | Crews coping with hunger, appetite suppression |
| **Cannabinoid Moss** | Wildcat threat level | Safe → more demand | Stations under threat can't relax; safe stations unwind |

Moss is the only "leisure drug" — it goes up when things are going *well* (no wildcats nearby), not when something is wrong. The other two are crisis drugs.

## Crisis Triggers

### Amphetamines: production pressure

A station is under production pressure when it has sustained high NPC activity — lots of freight orders, many docked NPC ships, high throughput.

**Trigger**: `npc_activity > threshold` for `N` hours → `crisis.type = 'production_pressure'` → starts consuming amphetamines at a rate proportional to how far above the threshold the station is.

**Tangible signals**: Station appears busy on the freight board, lots of NPC ships docking/undocking, high market turnover.

### Fentanyl: food shortage

A station is short on food when its stockpile drops and stays low.

**Trigger**: `food_stockpile < threshold` for `N` hours → `crisis.type = 'food_shortage'` → starts consuming fentanyl at a rate proportional to shortage severity (how far below threshold, how long sustained).

**Tangible signals**: Station's food stock is low (visible in market/stockpile), food price at that station spikes.

### Moss: wildcat threat level

A station feels safe when there are few or no wildcat ships in its area. Wildcats are the unaffiliated pirate sites — not cartel pirates (who are the drug distributors).

**Trigger**: `wildcat_ship_count == 0` (or below threshold) for `N` hours → `crisis.type = 'low_threat'` → starts consuming moss at a rate proportional to how long the area has been clear.

**Tangible signals**: Player can clear wildcats (pirate sites). A cleared zone becomes a relaxation hub with rising moss demand. This is a lever the player directly controls.

## Consumption Mechanics

### Reactive rate, not flat

Instead of `use_fentanyl={capacity=-6}` being a constant, consumption becomes:

```
consumption_rate = base_rate × (1 + crisis_intensity × severity_multiplier)
```

Where:
- `base_rate` is a small baseline (0.1-0.5 units/tick)
- `crisis_intensity` is 0-1, driven by how far the trigger condition is from its threshold
- `severity_multiplier` scales the effect

When the crisis resolves (production normalizes, food restocked, wildcats return), consumption drops back to baseline.

### Station crisis state

Each station tracks a `crisis` record:

```lua
station.crisis = {
  type = nil,              -- 'production_pressure', 'food_shortage', 'low_threat'
  active = false,
  intensity = 0,           -- 0-1
  drug = nil,              -- which drug they're consuming
  consumptionRate = 0,     -- reactive rate
  triggeredAt = nil,
  resolvedAt = nil
}
```

This lives in the station's economy state (e.g., `u.stations[key].crisis`), same scope as stockpiles and accounts.

### NPC trade reduction

When a station enters crisis, it reduces its normal trade activity:
- Fewer freight orders posted (stations focused on crisis needs, not general goods)
- NPC haulers that normally trade there reduce frequency
- The station's market becomes quieter

This is a simple scaling factor on the station's trade behavior, proportional to `crisis.intensity`. Not a debuff — just reduced economic participation.

**No escalation, no dependency.** When the crisis resolves, trade returns to normal. The station recovers fully.

## Market Effects

### Price signal

Reactive consumption injects demand into the economy model just like `use_*` facilities do today — negative capacity creating demand. The difference is the rate is dynamic, not fixed.

Player sees this as:
- Price spikes on the drug at the crisis station
- Price drops elsewhere (supply diverted to high-demand station)
- A market opportunity: buy low elsewhere, sell at premium

### Cascading effects

Multiple stations in crisis competing for the same drug creates real market pressure:
- Antichthon produces ~8 units/tick of moss
- If two stations each demand 4 units during crisis, total demand = 16 > supply = 8
- Moss price at both stations rises, other consumers (like Neptune's Bounty's fence) get squeezed out

This is handled by the existing economy model — no new infrastructure needed. The only change is making the consumer capacity dynamic.

## Quest Hooks

### Crisis supply quests

The existing quest generator pattern (`keep`/`propose`/`resolve`, `q.news`/`q.onDone`/`q.onFailed`) supports this directly:

**Quest**: "Crisis supply" — station needs drugs to cope with its crisis.
- **keep**: station still in crisis, still consuming
- **propose**: generate offer based on current consumption rate and market price
- **resolve**: player delivers the required amount
- **reward**: scaled to urgency (higher intensity = higher reward)

**Quest lifecycle**:
1. Player observes a station in crisis (quiet freight board, drug price spike)
2. Quest appears: "Deliver X units of [drug] to [station] — they're running on fentanyl to get through the food shortage"
3. Player decides: supply the crisis (profit) or ignore it (station resolves on its own, quest expires)

### Wildcat clearance quest chain

Moss demand creates a natural quest hook around wildcat clearing:
1. Player notices moss demand rising at a station (news: "Safe skies mean crew relaxation at [station]")
2. Player realizes clearing nearby wildcats will sustain this demand
3. Player clears wildcats → demand stays high → ongoing supply opportunity
4. Wildcats return → demand drops → player must find new source or new station

### Enforcement opportunity

Heavy drug consumption at a regulated station attracts law enforcement attention (if enforcement exists as a mechanic in the relevant faction space). This creates a raid event:
- Station market restricted during raid
- Player risks contraband inspection if docked
- Opportunity: sell security goods at markup, or exploit lax inspections

## Implementation

### Phase 1: Reactive consumption rates

1. Remove flat `use_*` facilities from `world_layout.lua` for the four consumer stations (Elysium, Hakka Tulou, Valhalla Port, Neptune's Bounty)
2. Add `crisis` tracking to station economy state
3. Add crisis trigger logic (production pressure, food shortage, wildcat threat)
4. Make consumption rate a function of crisis state instead of a fixed facility capacity
5. Wire into existing economy model — negative capacity consumer, but rate is dynamic

### Phase 2: NPC trade reduction

1. When station crisis is active, scale down the station's trade output (freight orders, NPC haul frequency)
2. Proportional to `crisis.intensity`
3. No new systems — just read `station.crisis.intensity` in the trade behavior code

### Phase 3: Quest generation

1. Add `drug_crisis` quest generator to `quests.lua`
2. `keep`: station still in crisis with active consumption
3. `propose`: generate supply offer based on current rate and market price
4. `resolve`: player delivers required amount
5. `news`: publish story when crisis starts, when resolved, when player intervenes
6. `onDone`/`onFailed`: reputation effects with station's faction

### Phase 4: Wildcat integration

1. Track wildcat ship count per area (already exists — pirate site data)
2. Use wildcat count as moss trigger input
3. Publish news when moss demand rises due to cleared wildcats
4. Player can observe cause/effect: clear wildcats → safe zone → moss demand increases

## Data Changes

### world_layout.lua

Remove `use_*` facilities from consumer stations. Existing entries:
- `station:earth_2` (Elysium): remove `use_fentanyl`, `use_moss`
- `station:mars_5` (Hakka Tulou): remove `use_amphetamines`, `use_moss`
- `station:callisto_1` (Valhalla Port): remove `use_fentanyl`, `use_amphetamines`, `use_moss`
- `station:triton_1` (Neptune's Bounty): remove `use_moss`

### data/industry.lua

Keep `use_*` facility definitions (they're still valid facility types, just with dynamic capacity now):
```lua
{ id = 'use_amphetamines', market = false, item = 'amphetamines', cap = 96 }
{ id = 'use_fentanyl', market = false, item = 'fentanyl', cap = 96 }
{ id = 'use_moss', market = false, item = 'cannabinoid_moss', cap = 96 }
```

These become reactive consumers — capacity is set at runtime based on crisis state, not from world_layout.

### New: crisis trigger thresholds (tuning)

```lua
-- src/tuning.lua
T.crisisTriggers = {
  amphetamine_threshold = 0.7,     -- NPC activity above 70% → amphetamine demand
  fentanyl_threshold = 0.3,        -- Food stockpile below 30% → fentanyl demand
  moss_threat_threshold = 0,       -- Zero wildcats → moss demand
  moss_clear_hours = 24,           -- Hours of clear skies before moss demand turns on
  amphetamine_check_hours = 12,    -- Hours of sustained pressure before amphetamine demand
  fentanyl_check_hours = 8,        -- Hours of food shortage before fentanyl demand
  base_consumption_rate = 0.2,     -- Minimum consumption when crisis is active
  severity_multiplier = 2.0,       -- How much crisis intensity scales consumption
}
```

## What This Is NOT

- No station-wide debuffs or stat changes
- No dependency escalation or addiction mechanics
- No irreversible feedback loops
- No fence distribution networks
- No NPC crew AI behavior changes
- No new commodity types

## What This IS

- Crisis-driven demand that spikes when stations are under real stress
- Observable market signals (price spikes, trade withdrawal)
- Quest hooks through existing generator pattern
- Player lever (wildcat clearing → safe zone → moss demand)
- Cascading market effects handled by existing economy model
