# NPC jobs and actions

NPC execution has four extension points. Register code once when its module is
loaded; requests and saved state contain only plain data.

| Extension | Responsibility | Registration |
|---|---|---|
| Job | Eligibility, preferences, goals, phases and final outcome | `Tasks.register(kind, definition)` |
| Action | Execute a goal, including movement and lifecycle | `Actions.register(kind, definition)` |
| Target provider | Resolve a stable descriptor to the current authoritative object | `Actions.registerTarget(name, definition)` |
| Equipment operation | Apply an effect while positioned at that object | `Actions.registerOperation(name, definition)` |

The modules are `src/tasks.lua`, `src/npc_actions.lua`, and
`src/npc_operations.lua`. Mining registers the shared loose-resource target
provider; recovery registers saved/live loot targets in `src/offline_loot.lua`.
The latter retains its historical filename but contains resource selection and
transfer effects, not its former movement/timing loop.

## Jobs

Keep existing board hooks (`eligible`, `score`, `prepare`, `plan`, `complete`).
`requires` declares capabilities or issuer/jurisdiction authorization. Add the
kind's weight to the appropriate shared work profiles; zero disables a kind.
Population templates never gate access or choose an execution controller.

`plan(task, node, clock)` supplies the initial graph itinerary. During execution,
`nextAction(ctx)` chooses the next action when there is no unfinished action:

```lua
return {
    kind = "work",
    operation = "drill",
    target = { provider = "resource", id = resourceId, expected = "rock" },
}
```

An unfinished action continues without asking the job to select it every frame.
`before(ctx)` can make a high-level decision such as returning with a full load.
Use `NPC.travel(game, record, destination, clock)` for such a destination change;
it cancels work, preserves position, and uses the shared route kernel.

`actionEnded(ctx, action, status, reason)` can update the job's phase or release
a failed job. Supply its next request from `nextAction`. `pickedUp(ctx, item, n,
stack)` tracks job-specific manifests; shared transfer operations call it for
both physical and remote pickups. Equipment operations do not know professions.
`complete` remains responsible for authoritative delivery, sale and payment.

## Actions

Built-in actions are `travel`, `dock`, `hold`, `approach` and `work`.
Travel/dock requests use a `location` target and initialize the shared graph and
berthing kernel. Hold accepts `untilTime`. Work approaches and remains within
an operation's working distance before applying its effects. Approach does the
positioning only. A job can also request any registered action:

```lua
Actions.register("wait_until", {
    update = function(ctx, action, elapsed)
        return ctx.clock >= action.untilTime and "done" or "running"
    end,
})
```

Action definitions require `update(ctx, action, elapsed)`. Optional `start` runs
once; `finish(ctx, action, status, reason)` performs cleanup. Update returns
`running`, `done` or `failed` (with an optional reason). Built-in route actions
use `delegate` to advance through the shared NPC graph/berthing lifecycle.

Context contains `u`, `game`, `r`, and the universe `clock`. Physical updates
also supply `e`, `AI` and `dt`. Live objects and functions belong in registries
or transient context, never in saved action requests. Action requests may carry
additional plain fields for custom behavior. Use a distinct `key` when requests
with the same kind/operation/target represent different steps.

## Targets and operations

A target provider implements `resolve(ctx, descriptor)`, returning `x`, `y`,
optional `vx`, `vy`, `radius`, an authoritative `record`, and an optional live
`entity`. Return nil when the target is unavailable; `done=true` indicates an
observed completed transformation. Providers must respect area and live-scene
ownership. The resource provider refuses remote mutations while a physical
view owns that resource. Counted resource providers also implement `remove`.

The shared runner reserves `record.actionOwner` / `actionKey`. Claims are
released on completion, failure, interruption, replacement and task release.
Players can still interact with claimed objects; missing or changed resources
make the action finish or fail so the job can select again.

Operations require `online(ctx, target, dt, action)` and
`offline(ctx, target, dt, action)` effects, returning the same statuses as an
action. Optional fields:

- `distance(ctx, target)` gives a center-to-center working distance.
- `keepDistance` (boolean or function) maintains a standoff for drilling/shooting;
  collection coasts once in range, allowing the tractor to close the gap.
- `maxStep` bounds a remote work slice (default 12 seconds).
- `allowDocked` explicitly permits stationary equipment work while docked.
- `missing(ctx, action)` distinguishes a completed physical pickup from a lost target.

Effects change resources, inventory and equipment intent. They must not steer,
replace NPC routes or advance task clocks. `Actions.power` spends remote work
energy in addition to the common fuel update. `Actions.recordOperation` syncs
an online actor around an authoritative remote-record effect outside the
physics band. `Actions.pickedUp` reports transfers through the active job hook.
Engine-side transformations can use `Actions.targetResult` to finish or fail a
claim before its next update (for example, a drilled body becomes loose ore).

## Interruptions and observation

Combat, fuel loss, service, controlled transit and layout recovery pause or
cancel actions through the same runner. Paused time is not charged as work.
A resume rechecks ownership and approach distance; docking can discard a paused
resource approach so the job replans its return route. Representation changes
preserve position and reacquire targets, rather than retaining stale bodies.

F6 shows action kind/operation, target, phase and interruption reason. Each NPC
retains `lastAction` and a bounded decision trace. Global simulation history
continues recording meaningful job outcomes rather than every action tick.

Live planning runs through `src/npc_scheduler.lua`. Routine job/target/upkeep
decisions and clear-route cruise plans run once per second, close approaches
and active equipment work at 5 Hz, and combat at 10 Hz. Deadlines are staggered
per NPC. Route changes, new aggression, fuel changes, driver occupancy changes
and action completion request an immediate plan. Flight actuation, aiming,
weapon firing, docking beams and physics continue each simulation step. Equipment
effects must use the elapsed `dt` supplied by the runner, rather than assuming
one call per physics step.

Wreck recovery prefers a fitted drill, otherwise a laser or a cannon with ammo.
The shared recovery operation selects its firing group and a suitable standoff;
ships with neither tool skip wreck targets but can still collect loose cargo.
Shooting preserves each cargo unit with probability `T.wreckShotRecovery` (0.5);
drilling preserves every unit and remains the source of hull alloy. Packed
containers survive or are lost whole. Remote recovery saves its cargo-loss roll
with the source, so retries and materialization do not reroll its contents.
