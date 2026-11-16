#!/usr/bin/env python3
"""Ship generator: many ships fast, only the good ones kept.

    python tools/shipgen/shipgen.py                       # 8 of every role
    python tools/shipgen/shipgen.py --role hauler -n 24   # 24 haulers
    python tools/shipgen/shipgen.py --role fighter --seeds 12,40,77 --out <folder>

Every candidate goes through validate.py; failures are dropped (and counted
by reason, -v lists them). Keepers are written as Shipyard data files
(gen_<role>_<seed>.lua) and drawn on a contact sheet, best score first, seed
under each. A seed always makes the same ship, so `--seeds` regenerates
just the ones you liked.

To try ships in the game or refine them in the Shipyard (F2), copy their
.lua files into the save folder's mods/shipyard/data/ (on Windows,
%APPDATA%/LOVE/spacegame_proto/mods/shipyard/data/) or pass that as --out.

Needs Python 3.8+ and Pillow.
"""

import argparse
import collections
import glob
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import geom  # noqa: E402
import generate  # noqa: E402
import luatable  # noqa: E402
import render  # noqa: E402
import validate  # noqa: E402

REPO = os.path.normpath(os.path.join(HERE, "..", ".."))

# hull fields copied from the template as they are
COPY = ["class", "drag", "mount", "paints", "spoolTime", "turnSpeed", "turnResponse", "turretTurn", "bonuses",
        "helm", "compartments", "loadout", "variants", "tags", "playable"]


def load_templates():
    out = {}
    for f in sorted(glob.glob(os.path.join(REPO, "data", "ships", "*.lua"))):
        for name, h in luatable.read_calls(open(f, encoding="utf-8").read()):
            if name != "hull":
                continue
            parts = h.get("parts") or [{"shape": h["shape"]}]
            polys = []
            for p in parts:
                s = p["shape"]
                poly = list(zip(s[0::2], s[1::2]))
                polys.append(poly)
                if p.get("mirror"):
                    polys.append(geom.mirror(poly))
            x0, y0, x1, y1 = geom.bounds(polys)
            h["_L"], h["_W"] = x1 - x0, y1 - y0
            h["_parts"] = [dict(p, poly=list(zip(p["shape"][0::2], p["shape"][1::2]))) for p in parts]
            out[h["id"]] = h
    return out


def recentre(ship):
    """Move the ship so its centre of area sits on the origin (asymmetric
    ships end up with the spine off the axis, which is the point)."""
    parts = validate.expand(ship["parts"])
    hull = [p for p in parts if p.get("layer") is None]
    R = validate.Raster(hull)
    cx, cy = validate.centroid(R.mask([p["poly"] for p in hull]))
    cx, cy = cx / validate.RES + R.ox, cy / validate.RES + R.oy
    if ship["sym"]:
        cy = 0   # mirrored parts must stay mirrored about y = 0
    dx, dy = -round(cx), -round(cy)
    for p in ship["parts"]:
        p["poly"] = [(x + dx, y + dy) for x, y in p["poly"]]
        for l in p.get("lights", []):
            l["x"] += dx
            l["y"] += dy
    for s in ship["slots"]:
        if "x" in s:
            s["x"] += dx
            s["y"] += dy
    for b in ship.get("berths") or []:
        b["x"] += dx
        b["y"] += dy


def tpl_area(tpl):
    hull = [p for p in validate.expand(tpl["_parts"]) if p.get("layer") is None]
    R = validate.Raster(hull)
    return validate.count(R.mask([p["poly"] for p in hull])) / validate.RES ** 2


def stats(ship, metrics, tpl):
    """The template's stats, scaled to the new hull's size."""
    k = max(0.75, min(1.35, metrics["area"] / tpl["_area"]))
    lk = max(0.8, min(1.25, metrics["L"] / tpl["_L"]))
    h = {}
    for f in COPY:
        if f in tpl:
            h[f] = tpl[f]
    h["mass"] = round(tpl["mass"] * k)
    h["armor"] = round(tpl["armor"] * k / 5) * 5
    h["hold"] = max(1, round(tpl["hold"] * k))
    if "price" in tpl:
        h["price"] = round(tpl["price"] * k ** 0.5 / 500) * 500
    for f in ("sideThrust", "retroThrust"):
        if f in tpl:
            h[f] = round(tpl[f] * k)
    if "turn" in tpl:
        h["turn"] = round(tpl["turn"] * k * lk * lk)
    return h


def r1(v):
    return round(v * 2) / 2 if abs(v) < 40 else round(v)


def to_hull(ship, metrics):
    tpl = ship["tpl"]
    sid = "gen_%s_%d" % (ship["role"], ship["seed"])
    h = {"id": sid, "name": ship["name"]}
    h.update(stats(ship, metrics, tpl))
    h["maker"] = "Shipgen"
    h["description"] = "Generated %s, seed %d, flying %s's stats and fit." % (ship["role"], ship["seed"], tpl.get("name", tpl["id"]))
    slots = []
    for s in ship["slots"]:
        s = dict(s)
        if "x" in s:
            s["x"], s["y"] = r1(s["x"]), r1(s["y"])
        slots.append(s)
    h["slots"] = slots
    if ship.get("berths"):
        h["berths"] = [dict(b, x=r1(b["x"]), y=r1(b["y"])) for b in ship["berths"]]
    parts = []
    for i, p in enumerate(ship["parts"]):
        q = {"name": p.get("name") or "part %d" % (i + 1)}
        q["shape"] = [r1(v) for v in geom.flat(p["poly"])]
        for f in luatable_fields:
            if p.get(f) is not None and f not in ("name", "shape"):
                q[f] = p[f]
        if p.get("lights"):
            q["lights"] = [{k: (r1(v) if k in ("x", "y") else v) for k, v in l.items()} for l in p["lights"]]
        parts.append(q)
    h["parts"] = parts
    return h


# the part fields a data file holds, in Shipyard export order (src/editor/export.lua)
luatable_fields = ["name", "shape", "shade", "fill", "tint", "color", "paint", "mirror", "layer", "badge", "under", "collide",
                   "sensor", "cargo", "core", "coreSide", "breakable", "armor", "mass", "explode", "lights", "role"]

ORDER = ["id", "name", "armor", "berths", "bonuses", "class", "compartments", "drag", "helm", "hold", "loadout", "maker",
         "description", "mass", "mount", "paints", "playable", "price", "retroThrust", "sideThrust", "slots", "spoolTime",
         "tags", "turn", "turnResponse", "turnSpeed", "turretTurn", "variants", "parts"]


def hull_source(h, ship, metrics):
    lines = ["-- Made by tools/shipgen (role %s, seed %d, after %s, score %.0f). Base hull: %s" % (
        ship["role"], ship["seed"], ship["template"], metrics["score"], ship["template"]), "hull {"]
    lines.append('\tid = %s, name = %s,' % (luatable.write(h["id"]), luatable.write(h["name"])))
    for k in ORDER[2:]:
        if k in h:
            lines.append("\t%s = %s," % (k, luatable.write(h[k], "\t")))
    lines.append("}")
    return "\n".join(lines) + "\n"


def make(role, seed, templates, keepers):
    ship = generate.build(seed, role, templates)
    recentre(ship)
    generate.add_lights(ship)
    problems, metrics = validate.check(ship, keepers)
    return ship, problems, metrics


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--role", default="all", help="fighter, gunship, hauler, heavy, yacht, carrier or all")
    ap.add_argument("-n", "--count", type=int, default=8, help="keepers wanted per role")
    ap.add_argument("--seed", type=int, default=1, help="first seed to try")
    ap.add_argument("--seeds", help="comma list: build exactly these seeds (keeps failures out, says why)")
    ap.add_argument("--out", default=os.path.join(REPO, "shipgen_out"), help="folder for the .lua files and sheet")
    ap.add_argument("--sheet", default=None, help="contact sheet path (default <out>/sheet_<role>.png)")
    ap.add_argument("--no-files", action="store_true", help="only draw the sheet")
    ap.add_argument("-v", "--verbose", action="store_true")
    a = ap.parse_args()

    templates = load_templates()
    for t in templates.values():
        t["_area"] = tpl_area(t)
    roles = list(generate.ROLES) if a.role == "all" else a.role.split(",")
    existing = [(tid, validate.signature({"parts": t["_parts"]})) for tid, t in templates.items()]
    os.makedirs(a.out, exist_ok=True)
    kept_all = []
    for role in roles:
        keepers = list(existing)
        kept, fails, tried = [], collections.Counter(), 0
        seeds = [int(s) for s in a.seeds.split(",")] if a.seeds else None
        seed = a.seed
        while (len(kept) < a.count and tried < a.count * 40) if not seeds else seeds:
            s = seeds.pop(0) if seeds else seed
            seed += 1
            tried += 1
            ship, problems, metrics = make(role, s, templates, keepers)
            if problems:
                for p in set(q.split(":")[0] for q in problems):
                    fails[p] += 1
                if a.verbose or a.seeds:
                    print("  %s %d rejected: %s" % (role, s, "; ".join(problems)))
                continue
            keepers.append(("gen_%s_%d" % (role, s), metrics["sig"]))
            h = to_hull(ship, metrics)
            src = hull_source(h, ship, metrics)
            # round-trip: the file must read back as the same hull
            back = luatable.read_calls(src)
            assert back and back[0][0] == "hull" and back[0][1]["id"] == h["id"], "file doesn't read back"
            if not a.no_files:
                with open(os.path.join(a.out, h["id"] + ".lua"), "w", encoding="utf-8") as f:
                    f.write(src)
            kept.append((ship, metrics, h))
        rate = 100 * len(kept) / max(1, tried)
        print("%-8s kept %d of %d (%.0f%%)%s" % (role, len(kept), tried, rate,
              ("  rejected for: " + ", ".join("%s %d" % kv for kv in fails.most_common())) if fails else ""))
        kept.sort(key=lambda k: -k[1]["score"])
        kept_all += kept
        if kept and len(roles) > 1:
            render.sheet(kept, os.path.join(a.out, "sheet_%s.png" % role), role)
    if kept_all:
        path = a.sheet or os.path.join(a.out, "sheet_%s.png" % (a.role if len(roles) == 1 else "all"))
        render.sheet(kept_all, path, a.role)
        print("sheet:", path)


if __name__ == "__main__":
    main()
