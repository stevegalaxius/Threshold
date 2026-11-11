# Industry definitions

`data/industry.lua` owns recipes, facility types, service reserve policies and food's consumption/shortage parameters. `src/world_layout.lua` installs facilities at stations. `src/industry.lua` executes recipes and allocates shared facility time; `src/markets.lua` supplies local quotes and customer bids. `src/commodities.lua` compiles the station/recipe indexes used by freight and demand queries.

## Add a production chain

Define the items in `data/items.lua`, then add a recipe to `D.recipes` before the definition-finalization loop:

```lua
{id='make_components', item='components', time=1,
 inputs={{item='steel_plate',n=2},{item='explosives',n=1}},
 outputs={{item='components',n=8,cap=160},{item='water_ice',n=1,cap=40}}}
```

`item` names the primary output and its stock-flow owner. Every output has an integer quantity and storage cap. The shorthand `item`, `batch` (default 1) and `cap` defines a single output. `time` defaults to one processing unit per batch. No inputs means direct extraction; it doesn't require a separate producer implementation.

Add a facility type:

```lua
component_works={policy='profit',recipes={'make_components','make_other_components'}}
```

Install it in a station definition:

```lua
facilities={assembly={type='component_works',capacity=24}}
```

The installation ID is independent of the type. Omitting `type` uses the installation ID as the type. Capacity is processing units per game hour, shared across the supported recipes. A recipe may be installed only once per station; use the installation's capacity to represent several identical production lines. Separate installations supporting different recipes have independent capacity pools.

Policies:

- `fixed`: equal shares across supported recipes.
- `profit`: allocations gradually follow reachable customer revenue minus freight and local input costs, per processing unit. Near-equal positive margins preserve the existing mix. No profitable demand eventually idles the facility.
- `adaptive`: the existing single-product industry response, slowing with stock accumulation and accelerating with unmet demand when inputs are present. Authored capacity is multiplied by the existing 0.25–4 adjustment. Multiple recipes divide that capacity equally before their adjustments.

New recipe outputs participate in local pricing by default; set `market=false` to retain catalogue prices. Legacy fuel and food definitions retain their original pricing behavior. All recipe inputs and outputs automatically participate in the goods list and receive a stocked storefront if the station's shops don't already list them. Freight generation and saving need no item-specific additions.

## Inventory and demand

The executor uses unreserved inputs and physical output storage. Outputs are produced atomically in whole batches: a full co-product store stops the entire batch. Reading a secondary output also catches up the primary recipe. Fractional processing progress persists; time blocked by missing inputs or storage cannot accumulate into a production burst.

Fractional input quantities use saved material credits. Farming, for example, consumes one fertilizer cargo unit for twenty food batches without creating fractional inventory. All outputs still have whole cargo quantities.

Station `reserves={item=quantity}` sets explicit local reserve floors. `D.reserves` and recipe `reserve` entries specify minimum service stock, either `minimum` units or `stacks`, an optional service requirement, producer exclusion, and an `openingMultiplier`. Ammunition uses two stacks at supplied customer stations; repair services retain their steel floor. Fuel retains its existing service floor.

Factory input demand follows allocated capacity. Profit facilities can additionally retain enough inputs for the most demanding alternative recipe using `inputReserveScale`; alternative recipes are not added as if each owned the whole factory. Independent facilities' input reserves add together. The migrated chemical and ammunition facilities explicitly preserve their preceding reserve policies.

`openingInputs={item=hours}` on a facility type seeds input stock according to its most input-intensive recipe. Recipe `opening` supplies a default initial primary-output quantity. These are opening world stock, not periodic restocking.

## Food and event-driven consumers

Food consumption and its gradual output penalty remain a consumption policy, rather than pretending to be manufacturing. Farms execute `grow_food` through the same recipe controller as the other facilities. Food production remains exempt from its own shortage penalty. Farm output and station food-use rates are unchanged.

Repairs, rearming and fuel sales remain event-driven consumers of the shared available-stock API. They do not need a manufacturing loop. Manufacturing cannot consume their freight reservations, and service consumers cannot consume manufacturing shipments reserved for pickup.

## State and inspection

Facility mixes and margins are saved in `universe.facilities`, keyed by station/installation. Recipe processing carries and input credits are saved with the shop's recipe state. Market prices and bids are saved separately in `universe.markets`. This refactor does not migrate the previous save schema.

F6 lists each installed facility, capacity, policy, recipe allocation/margin, output stock/prices, and available versus physical inputs.

Validation: `love . --industrytest` exercises a definition-only facility with multiple outputs, independent consumption, processing time, reserved inputs, both output caps and saved progress. Existing food, chemicals, steel, ammunition and freight scenarios cover the migrated chains. Long simulation soaks are not required for this refactor.
