"""New stats, slots and loadout for a generated ship, worked out from its
own geometry and a design brief, not copied from an existing hull.

  plan(rng, role)      before the geometry: a brief (what the ship is for
                       and what it trades away) and how many engines,
                       weapons, bays and utility slots it carries
  finish(ship, m, ...) after: slot sizes, mounts and triggers; a loadout
                       from the module catalogue; mass, armour, hold, drag,
                       thrusters, turning, spool and price from the hull's
                       area, cargo space, length and shape, bent by the brief

The game's existing hulls are only used as the yardstick: balance() checks
a ship's flight numbers (acceleration, top speed, turn rate, power, armour
per tonne, price per tonne) land inside the range that existing ships of a
similar mass already cover, so a new design can be unusual without being
broken.
"""

import math

# What each role is generated as. L: length range (px) the hull is drawn at,
# aspect: width / length, and slot counts (min, max).
ROLE_SPEC = {
    "fighter": dict(L=(64, 120), aspect=(0.22, 0.55), eng=(1, 2), hard=(1, 3), bay=(0, 1), util=(2, 3),
                    tw=(3.6, 7.0), weapons=["gun", "gun", "pulse", "beam", "artillery"]),
    "gunship": dict(L=(130, 230), aspect=(0.2, 0.48), eng=(1, 2), hard=(2, 4), bay=(0, 2), util=(2, 3),
                    tw=(2.6, 4.2), weapons=["gun", "artillery", "pulse", "beam"]),
    "hauler": dict(L=(110, 330), aspect=(0.26, 0.55), eng=(1, 2), hard=(0, 2), bay=(0, 1), util=(3, 4),
                   tw=(1.7, 3.0), weapons=["gun", "gun", "drill"]),
    "heavy": dict(L=(230, 300), aspect=(0.28, 0.45), eng=(1, 3), hard=(3, 6), bay=(0, 2), util=(2, 4),
                  tw=(2.0, 4.0), weapons=["gun", "artillery", "pulse", "beam"]),
    "yacht": dict(L=(100, 160), aspect=(0.25, 0.45), eng=(1, 2), hard=(0, 1), bay=(0, 1), util=(3, 4),
                  tw=(3.0, 5.0), weapons=["pulse", "gun"]),
    "carrier": dict(L=(240, 300), aspect=(0.45, 0.62), eng=(1, 2), hard=(1, 3), bay=(0, 1), util=(2, 3),
                    tw=(1.8, 2.6), weapons=["gun", "pulse"]),
}

# Briefs: what a design leans into and what it pays for it. Multipliers on
# the role's baseline; each one that gives also takes.
BRIEFS = {
    "balanced":   dict(armor=1.0, mass=1.0, thrust=1.0, turn=1.0, drag=1.0, hold=1.0),
    "armoured":   dict(armor=1.45, mass=1.2, thrust=0.9, turn=0.8, drag=1.05, hold=0.9),
    "racer":      dict(armor=0.7, mass=0.85, thrust=1.25, turn=1.25, drag=0.8, hold=0.8),
    "long-haul":  dict(armor=0.9, mass=1.05, thrust=0.9, turn=0.9, drag=0.9, hold=1.4),
    "brawler":    dict(armor=1.25, mass=1.1, thrust=1.0, turn=1.1, drag=1.1, hold=0.7),
    "skirmisher": dict(armor=0.85, mass=0.95, thrust=1.1, turn=1.15, drag=0.95, hold=0.9),
}
ROLE_BRIEFS = {
    "fighter": ["balanced", "racer", "skirmisher", "brawler", "armoured"],
    "gunship": ["balanced", "brawler", "armoured", "skirmisher"],
    "hauler": ["balanced", "long-haul", "long-haul", "armoured", "racer"],
    "heavy": ["balanced", "armoured", "brawler"],
    "yacht": ["balanced", "racer", "long-haul"],
    "carrier": ["balanced", "armoured", "long-haul"],
}

CLASS_NAMES = {
    "fighter": ["Interceptor", "Fighter", "Light fighter", "Strike craft"],
    "gunship": ["Gunship", "Heavy fighter", "Escort", "Corvette"],
    "hauler": ["Courier-class", "Freighter-class", "Errand-class", "Hauler"],
    "heavy": ["Battlecruiser", "Frigate", "Destroyer", "Heavy cruiser"],
    "yacht": ["Yacht", "Tourer", "Shuttle"],
    "carrier": ["Carrier", "Tender", "Ship hauler"],
}

PAINT_SETS = [
    ["Terracotta", "Olive Drab", "Champagne", "Signal"], ["Gunmetal", "Charcoal", "Hazard"],
    ["Khaki", "Sage", "Old Gold"], ["Bone", "Ash", "Cobalt"], ["Tanker", "Cargo Blue", "Bone"],
    ["Primer", "Umber", "Taupe"], ["Forest", "Moss", "Pine", "Khaki"], ["Plum", "Orchid", "Champagne"],
]

WEAPON_IDS = {"gun": "gun_%s_base", "artillery": "artillery_%s_base", "pulse": "pulse_%s_base",
              "beam": "beam_%s_base", "drill": "drill_%s_base"}
ENGINES = {"S": "flit_engine", "M": "mule_engine", "L": "cinder_drive"}
REACTORS = {"S": "ember_reactor", "M": "kiln_reactor", "L": "forge_reactor"}
SIZE_RANK = {"S": 1, "M": 2, "L": 3}


def interp(points, x):
    """Piecewise linear through (x, y) points, flat past the ends."""
    if x <= points[0][0]:
        return points[0][1]
    for (x0, y0), (x1, y1) in zip(points, points[1:]):
        if x <= x1:
            return y0 + (y1 - y0) * (x - x0) / (x1 - x0)
    return points[-1][1]


def plan(rng, role):
    spec = ROLE_SPEC[role]
    brief = rng.choice(ROLE_BRIEFS[role])
    r = lambda k: rng.randint(*spec[k])
    p = {"brief": brief, "n_eng": r("eng"), "n_hard": r("hard"), "n_bay": r("bay"), "n_util": r("util")}
    if brief in ("brawler", "armoured") and p["n_hard"] < spec["hard"][1]:
        p["n_hard"] += 1
    if brief == "long-haul":
        p["n_util"] = min(5, p["n_util"] + 1)
        p["n_hard"] = max(spec["hard"][0], p["n_hard"] - 1)
    p["class"] = rng.choice(CLASS_NAMES[role])
    p["paints"] = rng.choice(PAINT_SETS)
    p["weapon"] = rng.choice(spec["weapons"])
    p["mixed"] = rng.random() < 0.35   # a second weapon type on the smaller mounts
    p["weapon2"] = rng.choice(spec["weapons"])
    return p


def size_letter(mass):
    return "S" if mass < 160 else "M" if mass < 520 else "L"


def finish(ship, m, modules, rng):
    """Fills ship["hull"] with the generated hull fields. m: validate metrics."""
    role, p = ship["role"], ship["plan"]
    bf = BRIEFS[p["brief"]]
    L, W, area = m["L"], m["W"], m["area"]
    cargo_area = m.get("cargo_area", 0)

    # --- body: mass from area, armour from mass, hold from volume ------------
    mass = 0.25 * area ** 0.8 * bf["mass"] * rng.uniform(0.92, 1.08)
    if role == "carrier":
        mass *= 0.85   # open decks are light
    armor = (60 + 1.05 * mass) * bf["armor"] * rng.uniform(0.92, 1.08)
    hold = (12 + 0.006 * area + 0.022 * cargo_area) * bf["hold"]
    if role == "carrier":
        hold *= 0.35

    # --- slots: sizes follow the body's weight --------------------------------
    cls = size_letter(mass)
    down = {"L": "M", "M": "S", "S": "S"}
    hard = [s for s in ship["slots"] if s["family"] == "hardpoint"]
    # the outermost / foremost pair gets the main size, the rest one smaller
    # on bigger ships
    for i, s in enumerate(sorted(hard, key=lambda s: -s["x"])):
        s["size"] = cls if (i < 2 or cls == "S") else down[cls]
    for s in ship["slots"]:
        f = s["family"]
        if f == "bay":
            s["size"] = cls if role in ("heavy", "carrier") else down[cls] if cls != "S" else "S"
        elif f == "reactor":
            s["size"] = cls
        elif f == "utility":
            s["size"] = "any"
    mount = {"S": "fixed", "M": "gimbal", "L": "turret"}[cls]
    if rng.random() < 0.25:
        mount = {"fixed": "gimbal", "gimbal": rng.choice(["fixed", "turret"]), "turret": "gimbal"}[mount]
    if hard and ship["slots"] and any(s["family"] == "bay" for s in ship["slots"]):
        for s in ship["slots"]:
            if s["family"] == "bay":
                s["trigger"] = "secondary"

    # --- engines: size so thrust / weight lands in the role's band ------------
    engines = [s for s in ship["slots"] if s["family"] == "engine"]
    tw_lo, tw_hi = ROLE_SPEC[role]["tw"]
    want_tw = rng.uniform(tw_lo, tw_hi) * bf["thrust"]
    total_guess = mass * 1.15
    best = None
    for letter, eid in ENGINES.items():
        thr = modules[eid]["thrust"] * len(engines)
        err = abs(math.log(thr / total_guess / want_tw))
        if best is None or err < best[0]:
            best = (err, letter)
    for s in engines:
        s["size"] = best[1]

    # --- loadout ----------------------------------------------------------------
    loadout = []
    weapon_first = True
    util_pool = {
        "fighter": ["fire_computer", "flare_pod", "guidance_computer", "tug_beam"],
        "gunship": ["fire_computer", "guidance_computer", "flare_pod", "scanner"],
        "hauler": ["hold_pod_s", "hold_pod_s", "climate_pod_s", "tug_beam", "scanner"],
        "heavy": ["fire_computer", "guidance_computer", "scanner", "flare_pod"],
        "yacht": ["climate_pod_s", "hold_pod_s", "scanner", "tug_beam"],
        "carrier": ["drone_uplink", "tug_beam", "hold_pod_s", "scanner"],
    }[role]
    utils_left = ["nav_computer"] + [rng.choice(util_pool) for _ in range(6)]
    for s in ship["slots"]:
        f = s["family"]
        if f == "hardpoint":
            kind = p["weapon"]
            if p["mixed"] and s["size"] != cls:
                kind = p["weapon2"]
            mid = WEAPON_IDS[kind] % s["size"].lower()
            loadout.append(mid if mid in modules else "gun_%s_base" % s["size"].lower())
        elif f == "bay":
            loadout.append(("drone_%s_base" if role == "carrier" else "missile_%s_base") % s["size"].lower())
        elif f == "engine":
            loadout.append(ENGINES[s["size"]])
        elif f == "reactor":
            loadout.append(REACTORS[s["size"]])
        else:
            u = utils_left.pop(0)
            loadout.append(u if rng.random() < 0.85 or u == "nav_computer" else False)

    mod_mass = sum(modules[x]["mass"] for x in loadout if x)
    total = mass + mod_mass
    thrust = sum(modules[x].get("thrust", 0) for x in loadout if x)

    # --- handling: from length and weight, bent by the brief -----------------
    side = (300 + 1.25 * mass) * bf["thrust"] * rng.uniform(0.88, 1.12)
    retro = side * rng.uniform(0.7, 1.1)
    turn_speed = interp([(70, 280), (110, 250), (150, 175), (220, 125), (280, 60), (340, 42)], L)
    turn_speed *= bf["turn"] * rng.uniform(0.88, 1.12)
    turn_resp = interp([(70, 0.11), (110, 0.2), (150, 0.55), (220, 0.85), (280, 1.6), (340, 1.9)], L)
    turn_resp /= bf["turn"]
    turn_resp *= rng.uniform(0.9, 1.1)
    spool = interp([(70, 0.07), (150, 0.2), (280, 0.45), (340, 0.6)], L) * rng.uniform(0.85, 1.15)
    turn = interp([(70, 400), (150, 3000), (340, 3300)], L)
    bluntness = W / L
    drag = (0.08 + 0.0015 * mass) * (0.75 + 0.6 * bluntness) * bf["drag"] * rng.uniform(0.9, 1.1)

    mod_price = sum(modules[x].get("price", 0) for x in loadout if x)
    price = (8000 + 55 * mass + 0.12 * armor * 10 + 0.4 * mod_price) * (1.15 if p["brief"] == "racer" else 1.0)

    h = {
        "class": p["class"], "mass": round(mass), "armor": round(armor / 5) * 5, "hold": max(4, round(hold)),
        "drag": round(drag, 2), "sideThrust": round(side), "retroThrust": round(retro),
        "turn": round(turn / 50) * 50, "turnSpeed": round(turn_speed / 5) * 5, "turnResponse": round(turn_resp, 2),
        "spoolTime": round(spool, 2), "price": round(price / 500) * 500, "mount": mount,
        "bonuses": {}, "paints": p["paints"], "loadout": loadout,
    }
    if role == "yacht" or (role == "hauler" and rng.random() < 0.3):
        w = 4 if L > 140 else 3
        h["compartments"] = [{1: w, 2: 2, "kind": "climate", "name": "Climate hold"}]
    perf = {
        "accel": thrust / total, "top": math.sqrt(thrust / max(0.01, drag)), "turn": h["turnSpeed"],
        "side": side / total, "armor_t": armor / total, "price_t": price / total, "total": total,
    }
    power_out = sum(modules[x].get("powerOut", 0) for x in loadout if x)
    power_draw = sum(modules[x].get("powerDraw", 0) for x in loadout if x)
    perf["power"] = power_out - power_draw
    ship["hull"], ship["perf"] = h, perf
    return h


def perf_of(hull, modules):
    lo = [x for x in hull.get("loadout", []) if x and x in modules]
    total = hull["mass"] + sum(modules[x].get("mass", 0) for x in lo)
    thrust = sum(modules[x].get("thrust", 0) for x in lo)
    return {
        "accel": thrust / total, "top": math.sqrt(thrust / max(0.01, hull["drag"])),
        "turn": hull.get("turnSpeed") or 200, "side": hull.get("sideThrust", 0) / total,
        "armor_t": hull["armor"] / total, "price_t": hull.get("price", 0) / total, "total": total,
    }


def balance(perf, yardstick):
    """Problems if a flight number sits outside what existing ships of a
    similar total mass (half to double) already do, with 20% slack."""
    near = [y for y in yardstick if 0.5 <= y["total"] / perf["total"] <= 2.0] or yardstick
    out = []
    names = {"accel": "acceleration", "top": "top speed", "turn": "turn rate", "side": "strafe",
             "armor_t": "armour per tonne", "price_t": "price per tonne"}
    for k, label in names.items():
        lo = min(y[k] for y in near) * 0.8
        hi = max(y[k] for y in near) * 1.2
        if not lo <= perf[k] <= hi:
            out.append("stats: %s %.2f outside %.2f..%.2f of ships its weight" % (label, perf[k], lo, hi))
    if perf.get("power", 1) <= 0:
        out.append("stats: reactor can't cover the steady power draw")
    return out
