"""Builds one ship from a seed.

A ship is kitbashed from a few kinds of block, the way the hand-made hulls
are: a spine of sections from engines to nose, things hung off its sides
(wings, pods, cargo racks, sponsons, fins, decks), then engines, a cockpit,
paint, lights and detail panels. design.py plans the slots first (how many
engines, weapons, bays) and works out the stats and loadout afterwards from
the finished geometry.
"""

import math
import random

import geom

from design import ROLE_SPEC, plan as plan_ship

ROLES = ROLE_SPEC

SYLL_A = ["Ar", "Bel", "Cor", "Dra", "Ev", "Fal", "Gar", "Hel", "Ir", "Jav", "Kes", "Lor", "Mar",
          "Nyx", "Or", "Pel", "Quil", "Ros", "Sab", "Tor", "Ul", "Var", "Wex", "Yar", "Zen"]
SYL_B = ["a", "e", "i", "o", "u", "ae", "io"]
SYL_C = ["n", "x", "th", "ris", "dor", "lan", "rek", "vin", "mos", "tal", "ssa", "rin", "ven"]

GLASS = [0.16, 0.24, 0.32]
WINDOW = [1, 0.95, 0.85]


def ship_name(rng):
    return rng.choice(SYLL_A) + rng.choice(SYL_B) + rng.choice(SYL_C)


class Builder:
    def __init__(self, rng):
        self.rng = rng
        self.parts = []

    def add(self, poly, **tags):
        part = dict(tags)
        part["poly"] = poly
        self.parts.append(part)
        return part


def pick_profile(rng, role):
    """Half-width (0..1 of the spine's widest) at t along the spine, tail 0 to nose 1."""
    kinds = {
        "fighter": ["wedge", "cigar", "hammer", "box"],
        "gunship": ["wedge", "box", "dumbbell", "cigar", "hammer"],
        "hauler": ["box", "box", "dumbbell", "cigar"],
        "heavy": ["box", "wedge", "dumbbell", "hammer"],
        "yacht": ["cigar", "wedge", "cigar"],
        "carrier": ["box", "dumbbell"],
    }[role]
    k = rng.choice(kinds)
    f = {
        "wedge": lambda t: 1 - 0.45 * t,
        "cigar": lambda t: 0.62 + 0.38 * math.sin(math.pi * min(1, t * 1.15)),
        "hammer": lambda t: 0.7 + 0.3 * t,
        "dumbbell": lambda t: 1 - 0.4 * math.sin(math.pi * t),
        "box": lambda t: 1.0,
    }[k]
    return k, f


def build(seed, role, templates):
    """One ship as a dict of hull fields plus 'parts' with raw polygons
    (validate.py and write_hull turn it into a data file)."""
    rng = random.Random("%s:%d" % (role, seed))
    spec = ROLE_SPEC[role]
    brief = plan_ship(rng, role)
    L = rng.uniform(*spec["L"])
    W = max(L * rng.uniform(*spec["aspect"]), 14)
    n_eng, n_hard, n_bay = brief["n_eng"], brief["n_hard"], brief["n_bay"]
    slots = ([{"family": "hardpoint"} for _ in range(n_hard)] + [{"family": "bay"} for _ in range(n_bay)] +
             [{"family": "engine"} for _ in range(n_eng)] + [{"family": "reactor"}] +
             [{"family": "utility"} for _ in range(brief["n_util"])])

    style = {
        "chamfer": rng.choice([0.0, 0.15, 0.3, 0.5]),     # share of a section's half-width cut off its corners
        "step": rng.random() < 0.6,                        # stepped (kitbash) or smoothly tapered spine
        "accent": rng.choice(["nose", "alternate", "engines", "pods"]),
    }
    sym = rng.random() < 0.5
    asym_kind = None if sym else rng.choice(["uneven", "side_module", "offset_bridge", "uneven"])
    b = Builder(rng)
    cham = lambda w: w * style["chamfer"]

    tail = -L / 2
    nose = L / 2
    eng_len = L * rng.uniform(0.07, 0.12)
    nose_len = L * rng.uniform(0.12, 0.22)
    has_side = role in ("hauler", "carrier", "heavy") or rng.random() < 0.7
    spine_frac = rng.uniform(0.35, 0.6) if has_side else rng.uniform(0.9, 1.05)
    S = W / 2 * spine_frac
    S = max(S, 6 if L < 130 else 10)
    prof_kind, prof = pick_profile(rng, role)

    # --- spine -----------------------------------------------------------
    body0, body1 = tail + eng_len - 2, nose - nose_len
    n_sec = rng.randint(2, 4) if L > 120 else rng.randint(1, 3)
    cuts = sorted(rng.uniform(0.2, 0.8) for _ in range(n_sec - 1))
    edges = [body0] + [body0 + (body1 - body0) * c for c in cuts] + [body1]
    spine = []   # (x0, x1, wb, wf) for hw_at
    for i in range(n_sec):
        x0, x1 = edges[i], edges[i + 1] + 2
        t0 = (x0 - body0) / (body1 - body0)
        t1 = min(1, (x1 - body0) / (body1 - body0))
        if style["step"]:
            w = S * prof((t0 + t1) / 2) * rng.uniform(0.9, 1.08)
            wb = wf = w
        else:
            wb, wf = S * prof(t0), S * prof(t1)
        spine.append((x0, x1, wb, wf))
    # nose
    last_w = spine[-1][3]
    tip_kind = rng.choice(["point", "blunt", "blunt", "chisel"] if role != "hauler" else ["blunt", "blunt", "chisel"])
    tip_w = {"point": 0, "blunt": last_w * rng.uniform(0.45, 0.75), "chisel": last_w * rng.uniform(0.2, 0.35)}[tip_kind]
    nose_wb = last_w * rng.uniform(0.75, 1.0)
    paint_main = "primary"
    paint_acc = "secondary"
    for i, (x0, x1, wb, wf) in enumerate(spine):
        paint = paint_acc if (style["accent"] == "alternate" and i % 2 == 1) else paint_main
        b.add(geom.section(x0, x1, wb, wf, cham(wb), cham(wf)), name="hull %d" % (i + 1), paint=paint,
              core=True, breakable=False, role="hull", kind="spine")
    nose_part = b.add(geom.section(body1 - 2, nose, nose_wb, tip_w, cham(nose_wb), cham(tip_w) * 0.5),
                      name="nose", paint=paint_acc if style["accent"] == "nose" else paint_main,
                      core=True, breakable=False, role="cockpit", kind="nose")

    def hw_at(x):
        best = 0
        for x0, x1, wb, wf in spine:
            if x0 <= x <= x1:
                best = max(best, wb + (wf - wb) * (x - x0) / max(1e-6, x1 - x0))
        if body1 - 2 <= x <= nose:
            best = max(best, nose_wb + (tip_w - nose_wb) * (x - body1 + 2) / (nose - body1 + 2))
        return best

    # --- side attachments --------------------------------------------------
    side_pool = {
        "fighter": ["wing", "wing", "fin", "sponson", "pod"],
        "gunship": ["wing", "sponson", "pod", "fin", "boom"],
        "hauler": ["cargo", "cargo", "pod", "radiator"],
        "heavy": ["sponson", "pod", "cargo", "wing", "boom"],
        "yacht": ["wing", "fin", "pod"],
        "carrier": ["deck"],
    }[role]
    out_w = W / 2   # target outer half-width

    def side_plan():
        plan = []
        if not has_side:
            return [rng.choice(["fin", "wing"])] if rng.random() < 0.6 and role in ("fighter", "yacht") else []
        k = rng.randint(1, 2) if L < 150 else rng.randint(1, 3)
        for _ in range(k):
            plan.append(rng.choice(side_pool))
        if role in ("hauler",) and "cargo" not in plan:
            plan[0] = "cargo"
        if role == "carrier":
            plan = ["deck"]
        return plan

    def attach(kind, sgn, scale=1.0, slot=None):
        """Hang one attachment off side sgn (-1 or +1); returns parts and
        mount points [(x, y, what)]."""
        made, mounts = [], []
        span = max(4.0, (out_w - S) * scale)
        if kind == "wing":
            xa = rng.uniform(body0 + (body1 - body0) * 0.05, body0 + (body1 - body0) * 0.45)
            chord = (body1 - body0) * rng.uniform(0.3, 0.55)
            xb = min(body1, xa + chord)
            r = hw_at((xa + xb) / 2) - 2
            sweep = chord * rng.uniform(-0.1, 0.6)
            tipc = chord * rng.uniform(0.25, 0.6)
            sp = span * rng.uniform(0.9, 1.3)
            xt1 = max(tail + 4, xb - sweep)
            xt0 = max(tail + 2, xt1 - tipc)
            poly = [(xa, sgn * r), (xb, sgn * r), (xt1, sgn * (r + sp)), (xt0, sgn * (r + sp))]
            made.append(dict(poly=geom.dedupe(poly), name="wing", paint=paint_main, role="wing", kind="wing"))
            mounts.append((xb - chord * 0.15, sgn * (r + 2), "lead"))
            mounts.append(((xt0 + xt1) / 2, sgn * (r + sp - 2), "tip"))
        elif kind == "fin":
            xa = tail + eng_len * rng.uniform(0.6, 1.6)
            c = L * rng.uniform(0.1, 0.18)
            r = hw_at(xa + c / 2) - 2
            sp = max(5.0, span * rng.uniform(0.5, 0.9) if has_side else W * rng.uniform(0.12, 0.22))
            poly = [(xa, sgn * r), (xa + c, sgn * r), (xa + c * 0.25, sgn * (r + sp)), (xa - c * 0.15, sgn * (r + sp))]
            made.append(dict(poly=geom.dedupe(poly), name="fin", paint=paint_acc, role="fin", kind="fin", mass=0.5))
            mounts.append((xa + c * 0.1, sgn * (r + sp - 2), "tip"))
        elif kind in ("pod", "boom"):
            ln = (body1 - body0) * (rng.uniform(0.35, 0.65) if kind == "pod" else rng.uniform(0.6, 0.9))
            pw = max(5.0, span * (rng.uniform(0.45, 0.7) if kind == "pod" else rng.uniform(0.25, 0.4)))
            x0 = rng.uniform(body0, body1 - ln * 0.6) if kind == "pod" else body0 + (body1 - body0) * rng.uniform(0.1, 0.35)
            x1 = x0 + ln
            if kind == "boom":
                x1 = min(x1, nose + L * 0.04)
            r = hw_at(min(max(x0 + 6, body0), body1))
            gap = span - pw if rng.random() < 0.6 else 0
            gap = max(0.0, gap)
            yc = sgn * (r + gap + pw / 2 - 1)
            made.append(dict(poly=geom.section(x0, x1, pw / 2, pw / 2 * rng.uniform(0.6, 1.0), cham(pw / 2) + 1, cham(pw / 2) + 1.5, yc),
                             name=kind, paint=paint_acc if style["accent"] == "pods" else paint_main, role=kind, kind=kind))
            if gap > 1:
                sx = x0 + (x1 - x0) * rng.uniform(0.25, 0.55)
                sw = max(5.0, (x1 - x0) * rng.uniform(0.15, 0.3))
                rr = hw_at(sx + sw / 2)
                made.append(dict(poly=geom.box(sx, sgn * (rr - 3), sx + sw, yc - sgn * (pw / 2 - 2)),
                                 name="strut", shade=0.8, role="strut", kind="strut"))
            mounts.append((x1 - 3, yc, "front"))
            mounts.append((x0 + 2, yc, "back"))
        elif kind == "sponson":
            x0 = body0 + (body1 - body0) * rng.uniform(0.45, 0.85)
            ln = L * rng.uniform(0.08, 0.16)
            x1 = min(x0 + ln, nose - nose_len * 0.3)
            r = hw_at(x0) - 3
            sp = max(6.0, min(span, W * 0.15) * rng.uniform(0.6, 1.0))
            made.append(dict(poly=geom.box(x0, sgn * r, x1, sgn * (r + sp), cham(sp / 2)), name="sponson",
                             paint=paint_acc, role="weapon", kind="sponson"))
            mounts.append((x1 - 3, sgn * (r + sp / 2), "gun"))
        elif kind == "cargo":
            n = rng.randint(2, 4) if L > 150 else rng.randint(1, 3)
            cw = max(8.0, span * rng.uniform(0.6, 1.0))
            gapx = rng.uniform(2, 6)
            run0 = body0 + (body1 - body0) * rng.uniform(0.0, 0.15)
            run1 = body1 - (body1 - body0) * rng.uniform(0.0, 0.2)
            bl = (run1 - run0 - gapx * (n - 1)) / n
            for i in range(n):
                xa = run0 + i * (bl + gapx)
                r = min(hw_at(xa + 2), hw_at(xa + bl - 2)) - 2
                made.append(dict(poly=geom.box(xa, sgn * r, xa + bl, sgn * (r + cw), 3 if style["chamfer"] else 0),
                                 name="cargo", paint=paint_main if i % 2 == 0 or style["accent"] != "pods" else paint_acc,
                                 cargo=True, role="cargo", kind="cargo"))
                mounts.append((xa + bl / 2, sgn * (r + cw / 2), "cargo"))
        elif kind == "radiator":
            x0 = body0 + (body1 - body0) * rng.uniform(0.1, 0.5)
            ln = (body1 - body0) * rng.uniform(0.2, 0.35)
            r = min(hw_at(x0 + 3), hw_at(x0 + ln - 3)) - 2
            sp = max(6.0, span * rng.uniform(0.5, 0.9))
            made.append(dict(poly=geom.box(x0, sgn * r, x0 + ln, sgn * (r + sp)), name="radiator", shade=0.7,
                             role="radiator", kind="radiator", mass=0.5, armor=0.6))
            for k in range(1, 4):
                yy = sgn * (r + sp * k / 4)
                made.append(dict(poly=geom.box(x0 + 2, yy - 0.6, x0 + ln - 2, yy + 0.6), name="radiator fin", shade=0.45,
                                 layer="detail", collide=False, kind="detail"))
        elif kind == "deck":
            x0 = body0 + (body1 - body0) * 0.02
            x1 = body1 - (body1 - body0) * 0.02
            r = hw_at((x0 + x1) / 2) - 2
            berth_w = slot or 44
            dw = berth_w + 6
            made.append(dict(poly=geom.box(x0, sgn * r, x1, sgn * (r + dw), 4), name="deck", paint=paint_main,
                             role="dock", kind="deck"))
            rail = sgn * (r + dw)
            made.append(dict(poly=geom.box(x0 - 2, rail - sgn * 3, x1 + 2, rail + sgn * 1), name="deck rail",
                             paint=paint_acc, kind="rail"))
            mounts.append(((x0 + x1) / 2, sgn * (r + dw / 2), "deck"))
            mounts.append((x0, x1))
        return made, mounts

    berth_w = 44 if role == "carrier" else None
    plan = side_plan()
    mounts = {-1: [], 1: []}
    side_parts = []
    if sym or not plan:
        for kind in plan:
            made, m = attach(kind, -1, slot=berth_w)
            for p in made:
                p["mirror"] = True
            side_parts += made
            mounts[-1] += m
            mounts[1] += [(t[0], -t[1], t[2]) if len(t) == 3 else t for t in m]
    else:
        for sgn in (-1, 1):
            if asym_kind == "side_module" and sgn == 1:
                p2 = [rng.choice(["fin", "sponson", "radiator"])] if rng.random() < 0.7 else []
            elif asym_kind == "uneven":
                p2 = [rng.choice(side_pool) if rng.random() < 0.5 else k for k in plan]
            else:
                p2 = plan
            for kind in p2:
                scale = rng.uniform(1.2, 1.7) if (asym_kind == "side_module" and sgn == -1) else rng.uniform(0.75, 1.15)
                made, m = attach(kind, sgn, scale, slot=berth_w)
                side_parts += made
                mounts[sgn] += m
    # side parts go under the spine
    b.parts = side_parts + b.parts

    # --- engines ------------------------------------------------------------
    eng_paint = paint_acc if style["accent"] == "engines" else None
    back_w = spine[0][2]
    if n_eng == 1:
        ew = back_w * rng.uniform(0.55, 0.95)
        b.add(geom.section(tail, body0 + 3, ew, back_w * 0.95, cham(ew) * 0.5, 0), name="engine block",
              paint=eng_paint, shade=None if eng_paint else 0.85, core=True, breakable=False, role="engine", kind="engine", mass=1.5)
        b.add(geom.box(tail - 4, -max(2.5, ew * 0.6), tail + 1, max(2.5, ew * 0.6)), name="nozzle", shade=0.55, role="engine", kind="nozzle", core=True, breakable=False)
        eng_pts = [(tail - 4, 0)]
    else:
        d = max(back_w * rng.uniform(0.5, 0.85), 4)
        if rng.random() < 0.4 and back_w > 8:
            d = back_w * 1.05   # outboard nacelles
        ew = max(3.5, min(back_w * 0.45, d * 0.8) * rng.uniform(0.8, 1.1))
        nl = eng_len * rng.uniform(1.1, 2.2)
        eng_pts = []
        for k in range(n_eng):
            y = -d + 2 * d * k / (n_eng - 1)
            b.add(geom.section(tail, tail + nl, ew, ew * 0.85, cham(ew) * 0.6, cham(ew), y), name="nacelle",
                  paint=eng_paint, shade=None if eng_paint else 0.85, core=True, breakable=False, role="engine", kind="engine", mass=1.5)
            b.add(geom.box(tail - 4, y - max(2.5, ew * 0.7), tail + 1, y + max(2.5, ew * 0.7)), name="nozzle", shade=0.55, core=True, breakable=False,
                  role="engine", kind="nozzle")
            eng_pts.append((tail - 4, y))
        if d > back_w - 2:   # pylon joining outboard nacelles to the spine
            b.add(geom.box(tail + nl * 0.2, -d, tail + nl * 0.75, d), name="engine pylon", shade=0.75, core=True,
                  breakable=False, role="strut", kind="strut")

    # --- cockpit / bridge ---------------------------------------------------
    cy = 0.0
    if asym_kind == "offset_bridge":
        cy = rng.choice([-1, 1]) * max(0.0, hw_at(body1 - 10) * rng.uniform(0.3, 0.55))
    cw = max(2.5, min(hw_at(body1) * 0.45, 7 if L < 140 else 11))
    cl = max(8.0, min(nose_len * 0.8, L * 0.12))
    if role in ("fighter", "yacht") or rng.random() < 0.35:
        cx1 = body1 + nose_len * rng.uniform(0.1, 0.35)
        canopy = geom.section(cx1 - cl, cx1, cw * 0.8, cw * 0.5, cw * 0.3, cw * 0.4, cy)
        b.add(canopy, name="canopy", color=GLASS, layer="detail", collide=False, kind="canopy",
              lights=[{"kind": "window", "x": cx1 - cl * 0.35, "y": cy, "w": 2, "h": 1.5, "color": WINDOW}])
    else:   # a bridge block with a row of windows
        bx0 = body1 - cl * rng.uniform(0.6, 1.4)
        bw = max(4.0, hw_at(bx0) * rng.uniform(0.35, 0.6))
        bridge = geom.box(bx0, cy - bw, bx0 + cl, cy + bw, bw * 0.4)
        n_win = max(2, int(bw * 2 / 4))
        wins = [{"kind": "window", "x": bx0 + cl - 3, "y": cy - bw + 2 + (2 * bw - 4) * k / max(1, n_win - 1), "w": 1.5, "h": 2,
                 "color": WINDOW} for k in range(n_win)]
        b.add(bridge, name="bridge", paint=paint_acc, shade=0.9, layer="detail", collide=False, kind="bridge", lights=wins)

    # --- detail panels -------------------------------------------------------
    for (x0, x1, wb, wf) in spine:
        if x1 - x0 > 18 and rng.random() < 0.6:
            w = min(wb, wf)
            if w < 6:
                continue
            inset = max(2.5, w * 0.3)
            b.add(geom.box(x0 + 4, -w + inset, x1 - 4, w - inset), name="panel", shade=0.85, layer="detail", collide=False,
                  kind="detail", paint=paint_main)
    if L > 110 and rng.random() < 0.5:   # a spine stripe
        sw = max(1.0, S * 0.08)
        b.add(geom.box(body0 + 4, -sw, body1 - 2, sw), name="stripe", paint=paint_acc, layer="detail", collide=False, kind="detail")
    if rng.random() < 0.4:   # antenna mast
        ax = body0 + (body1 - body0) * rng.uniform(0.3, 0.8)
        side = rng.choice([-1, 1])
        hw = hw_at(ax)
        b.add(geom.box(ax, side * (hw - 3), ax + 1.2, side * (hw + max(5.0, L * 0.05))), name="antenna", shade=0.6,
              layer="detail", collide=False, kind="detail", role="antenna",
              lights=[{"kind": "strobe", "rate": 1, "phase": round(rng.random(), 2), "x": ax + 0.6,
                       "y": side * (hw + max(5.0, L * 0.05) - 1)}])

    # --- slots onto the geometry --------------------------------------------
    all_mounts = mounts[-1] + mounts[1]
    gun_spots = [(x, y) for x, y, w in (m for m in all_mounts if len(m) == 3) if w in ("gun", "front", "lead")]
    gun_spots.sort(key=lambda p: -p[0])
    nose_x = body1 + nose_len * 0.3
    nose_pair = [(nose_x, -(hw_at(nose_x) - 2.5)), (nose_x, hw_at(nose_x) - 2.5)]
    centre = [(body1 + nose_len * 0.55, 0)]
    hard_pts = []
    pool = []
    # pairs first, so twin guns sit symmetrically when the ship is
    by_x = {}
    for p in gun_spots:
        by_x.setdefault(round(p[0]), []).append(p)
    for xs in sorted(by_x, reverse=True):
        pool += by_x[xs]
    pool += nose_pair + centre
    if n_hard % 2 == 1:
        pool = centre + pool
    for p in pool:
        if len(hard_pts) >= n_hard:
            break
        if all(math.dist(p, q) > 5 for q in hard_pts):
            hard_pts.append(p)
    while len(hard_pts) < n_hard:   # stack more down the spine
        x = body1 - 8 * len(hard_pts)
        hard_pts.append((x, (hw_at(x) - 3) * (1 if len(hard_pts) % 2 else -1)))

    mid = (body0 + body1) / 2
    bay_pts = []
    for k in range(n_bay):
        if n_bay == 1:
            bay_pts.append((mid + (body1 - body0) * 0.15, 0))
        else:
            x = mid + (body1 - body0) * (0.2 - 0.25 * (k // 2))
            bay_pts.append((x, (hw_at(x) * 0.55) * (-1 if k % 2 == 0 else 1)))

    ih, ib, ie = 0, 0, 0
    reactor_x = spine[len(spine) // 2][0] + (spine[len(spine) // 2][1] - spine[len(spine) // 2][0]) / 2
    if len(spine) == 1:
        reactor_x = (body0 + body1) / 2 - (body1 - body0) * 0.15
    for s in slots:
        f = s["family"]
        if f == "hardpoint":
            s["x"], s["y"] = hard_pts[ih]
            ih += 1
        elif f == "bay":
            s["x"], s["y"] = bay_pts[ib]
            ib += 1
        elif f == "engine":
            s["x"], s["y"] = eng_pts[ie]
            ie += 1
        elif f == "reactor":
            s["x"], s["y"] = reactor_x, 0
        else:
            s.pop("x", None)
            s.pop("y", None)

    # --- berths on decks -----------------------------------------------------
    berths = None
    if role == "carrier":
        decks = [m for m in all_mounts if len(m) == 3 and m[2] == "deck"]
        spans = [m for m in all_mounts if len(m) == 2]
        size = 56
        berths = []
        for (dx, dy, _), (x0, x1) in zip(decks, spans):
            n = max(1, int((x1 - x0) // (size * 1.9)))
            for k in range(n):
                bx = x0 + (x1 - x0) * (k + 0.5) / n
                berths.append({"x": bx, "y": dy, "heading": 0, "size": size, "maxWidth": berth_w})

    return {
        "seed": seed, "role": role, "plan": brief, "L_range": spec["L"], "aspect": spec["aspect"],
        "parts": b.parts, "slots": slots, "berths": berths,
        "sym": sym, "asym": asym_kind, "profile": prof_kind, "style": style, "sides": plan,
        "name": ship_name(rng),
    }


def add_lights(ship):
    """Nav lights on the outermost hull points each side, strobes fore and
    aft. Done after recentring so they land on the final geometry."""
    hull = [p for p in ship["parts"] if p.get("layer") is None]

    def reach(sgn):
        best = None
        for p in hull:
            pts = p["poly"] + (geom.mirror(p["poly"]) if p.get("mirror") else [])
            for x, y in pts:
                if y * sgn > 0 and (best is None or y * sgn > best[2]):
                    best = (p, (x, y), y * sgn)
        return best

    lit = set()
    for sgn in (-1, 1):
        r = reach(sgn)
        if not r or id(r[0]) in lit:
            continue
        p, (x, y), _ = r
        if p.get("mirror"):   # its twin gets the reflected light
            lit.add(id(p))
            if y > 0:
                y = -y
        p.setdefault("lights", []).append({"kind": "nav", "x": x + (1 if x < 0 else -1), "y": y + (1.5 if y < 0 else -1.5)})
    nose = max(hull, key=lambda p: max(x for x, _ in p["poly"]))
    nx, ny = max(nose["poly"], key=lambda q: (q[0], -abs(q[1])))
    nose.setdefault("lights", []).append({"kind": "strobe", "rate": 1, "x": nx - 2, "y": ny})
    tailp = [p for p in hull if p.get("kind") == "engine"]
    if tailp:
        tp = tailp[0]
        tx = min(x for x, _ in tp["poly"])
        ty = sum(y for _, y in tp["poly"]) / len(tp["poly"])
        tp.setdefault("lights", []).append({"kind": "strobe", "rate": 1, "phase": 0.5, "x": tx + 3, "y": ty})
