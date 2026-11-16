#!/usr/bin/env python3
"""Ship generator: many ships fast, only the good ones kept.

    python tools/shipgen/shipgen.py                       # 8 of every role
    python tools/shipgen/shipgen.py --role hauler -n 24   # 24 haulers
    python tools/shipgen/shipgen.py --role fighter --seeds 12,40,77 --out <folder>

Every candidate goes through validate.py; failures are dropped (and counted
by reason, -v lists them). Keepers are written as Shipyard data files
(gen_<role>_<seed>.lua) and drawn on a contact sheet, best score first, seed
under each. A seed always makes the same ship. Runs never overwrite:
each run gets its own batch_<date>_<time> folder, and seeds carry on after the
highest generated id already anywhere in the Shipyard folder, so ships you've
edited, moved or promoted keep theirs. `--seeds` builds exactly those seeds
(skipping any already on disk).

By default they go to the save folder's mods/shipyard/data/shipgen/ (on
Windows %APPDATA%/LOVE/spacegame_proto/...). That isn't a namesake folder,
so they're workspace: open them in the Shipyard (F2) or fly/park them from
the debug menu (F1, listed as [workspace]), but the simulation never uses
them. Save one into ships/ in the Shipyard to make it a game hull.

Needs Python 3.8+ and Pillow.
"""

import argparse
import collections
import glob
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import design  # noqa: E402
import geom  # noqa: E402
import generate  # noqa: E402
import luatable  # noqa: E402
import render  # noqa: E402
import validate  # noqa: E402

REPO = os.path.normpath(os.path.join(HERE, "..", ".."))


def default_out():
    """mods/shipyard/data/shipgen/ in the game's save folder when it can be
    found (not a namesake folder, so ships there are workspace: viewable,
    never in the simulation; see data.NAMESAKE in src/data.lua), else
    shipgen_out/."""
    roots = [os.environ.get("APPDATA"), os.path.expanduser("~/Library/Application Support"),
             os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")]
    for r in roots:
        save = r and os.path.join(r, "LOVE", "spacegame_proto")
        if save and os.path.isdir(save):
            return os.path.join(save, "mods", "shipyard", "data", "shipgen")
    return os.path.join(REPO, "shipgen_out")

def load_modules():
    mods = {}
    for f in [os.path.join(REPO, "data", "modules.lua")] + sorted(glob.glob(os.path.join(REPO, "data", "modules", "*.lua"))):
        for name, m in luatable.read_calls(open(f, encoding="utf-8").read()):
            if name == "module":
                mods[m["id"]] = m
    return mods


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


def describe(ship):
    fam = lambda f: [s for s in ship["slots"] if s["family"] == f]
    bits = []
    lo = ship["hull"]["loadout"]
    weapons = [lo[i] for i, s in enumerate(ship["slots"]) if s["family"] in ("hardpoint", "bay") and lo[i]]
    if weapons:
        names = {}
        for w in weapons:
            k = w.replace("_base", "").replace("_", " ")
            names[k] = names.get(k, 0) + 1
        bits.append(", ".join("%d %s" % (n, k) for k, n in names.items()))
    else:
        bits.append("unarmed")
    e = fam("engine")
    bits.append("%d %s engine%s" % (len(e), e[0]["size"], "s" if len(e) > 1 else ""))
    bits.append("%d m3 hold" % ship["hull"]["hold"])
    return ", ".join(bits)


def r1(v):
    return round(v * 2) / 2 if abs(v) < 40 else round(v)


def to_hull(ship, metrics):
    sid = "gen_%s_%d" % (ship["role"], ship["seed"])
    h = {"id": sid, "name": ship["name"]}
    h.update(ship["hull"])
    h["maker"] = "Shipgen"
    p = ship["plan"]
    h["description"] = "%s %s %s: %s." % ("An" if p["brief"][0] in "aeiou" else "A", p["brief"], ship["role"], describe(ship))
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
    lines = ["-- Made by tools/shipgen (role %s, seed %d, %s brief, score %.0f)" % (
        ship["role"], ship["seed"], ship["plan"]["brief"], metrics["score"]), "hull {"]
    lines.append('\tid = %s, name = %s,' % (luatable.write(h["id"]), luatable.write(h["name"])))
    for k in ORDER[2:]:
        if k in h:
            lines.append("\t%s = %s," % (k, luatable.write(h[k], "\t")))
    lines.append("}")
    return "\n".join(lines) + "\n"


GEN_ID = __import__("re").compile(r'id\s*=\s*"(gen_([a-z]+)_(\d+))"')


def scan_existing(root):
    """Every generated ship already on disk under root (any folder, edited or
    promoted or not): {id: (path, signature or None)}, so a run never reuses
    an id or redraws a ship that's already there."""
    found = {}
    for dirpath, _, files in os.walk(root):
        for name in files:
            if not name.endswith(".lua"):
                continue
            path = os.path.join(dirpath, name)
            try:
                src = open(path, encoding="utf-8").read()
            except OSError:
                continue
            m = GEN_ID.search(src[:4096])
            if not m:
                continue
            sig = None
            try:
                for kind, h in luatable.read_calls(src):
                    if kind == "hull" and h.get("parts"):
                        parts = [dict(p, poly=list(zip(p["shape"][0::2], p["shape"][1::2]))) for p in h["parts"]]
                        sig = validate.signature({"parts": parts})
            except Exception:
                pass
            found[m.group(1)] = (path, sig)
    return found


def next_seed(found, role):
    seeds = [int(i.rsplit("_", 1)[1]) for i in found if i.startswith("gen_%s_" % role)]
    return max(seeds) + 1 if seeds else 1


def make(role, seed, templates, keepers, modules=None, yardstick=None):
    import random
    ship = generate.build(seed, role, templates)
    recentre(ship)
    generate.add_lights(ship)
    problems, metrics = validate.check(ship, keepers)
    if metrics:
        design.finish(ship, metrics, modules, random.Random("stats:%s:%d" % (role, seed)))
        problems += design.balance(ship["perf"], yardstick)
    return ship, problems, metrics


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--role", default="all", help="fighter, gunship, hauler, heavy, yacht, carrier or all")
    ap.add_argument("-n", "--count", type=int, default=8, help="keepers wanted per role")
    ap.add_argument("--seed", type=int, default=None, help="first seed to try (default: after the highest one already on disk)")
    ap.add_argument("--seeds", help="comma list: build exactly these seeds (keeps failures out, says why)")
    ap.add_argument("--out", default=None, help="shipgen folder; each run adds a batch_<date>_<time> folder inside it "
                    "(default: the save folder's mods/shipyard/data/shipgen, else shipgen_out/)")
    ap.add_argument("--batch", default=None, help="name for this run's folder instead of batch_<date>_<time>")
    ap.add_argument("--sheet", default=None, help="contact sheet path (default <out>/sheet_<role>.png)")
    ap.add_argument("--no-files", action="store_true", help="only draw the sheet")
    ap.add_argument("-v", "--verbose", action="store_true")
    a = ap.parse_args()

    import time
    root = a.out or default_out()
    # ids are checked across the whole Shipyard folder, so moving a ship into
    # ships/ or editing it never frees its id for a new one
    norm = root.replace("\\", "/")
    scan_root = norm[:norm.index("/mods/shipyard/data") + len("/mods/shipyard/data")] if "/mods/shipyard/data" in norm else root
    found = scan_existing(scan_root) if os.path.isdir(scan_root) else {}
    a.out = os.path.join(root, a.batch or time.strftime("batch_%Y-%m-%d_%H%M%S"))
    templates = load_templates()
    modules = load_modules()
    yardstick = [design.perf_of(t, modules) for t in templates.values()
                 if t.get("playable") is not False and "price" in t and t.get("loadout")]
    roles = list(generate.ROLES) if a.role == "all" else a.role.split(",")
    existing = [(tid, validate.signature({"parts": t["_parts"]})) for tid, t in templates.items()]
    existing += [(i, sig) for i, (_, sig) in found.items() if sig is not None]
    if found:
        print("%d generated ships already in %s; new ones get new ids" % (len(found), scan_root))
    os.makedirs(a.out, exist_ok=True)
    kept_all = []
    for role in roles:
        keepers = list(existing)
        kept, fails, tried = [], collections.Counter(), 0
        seeds = [int(s) for s in a.seeds.split(",")] if a.seeds else None
        picked = seeds is not None
        seed = a.seed if a.seed is not None else next_seed(found, role)
        while seeds if picked else (len(kept) < a.count and tried < a.count * 40):
            s = seeds.pop(0) if seeds else seed
            seed += 1
            sid = "gen_%s_%d" % (role, s)
            if sid in found:   # never overwrite or duplicate a ship already on disk
                if a.seeds:
                    print("  %s already exists (%s), skipped" % (sid, found[sid][0]))
                continue
            tried += 1
            ship, problems, metrics = make(role, s, templates, keepers, modules, yardstick)
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
                with open(os.path.join(a.out, h["id"] + ".lua"), "x", encoding="utf-8") as f:
                    f.write(src)
            kept.append((ship, metrics, h))
        rate = 100 * len(kept) / max(1, tried)
        print("%-8s kept %d of %d (%.0f%%)%s" % (role, len(kept), tried, rate,
              ("  rejected for: " + ", ".join("%s %d" % kv for kv in fails.most_common())) if fails else ""))
        kept.sort(key=lambda k: -k[1]["score"])
        kept_all += kept
        if kept and len(roles) > 1:
            render.sheet(kept, os.path.join(a.out, "sheet_%s.png" % role), role)
    if not kept_all and not os.listdir(a.out):
        os.rmdir(a.out)
        print("nothing new kept")
        return
    print("ships in:", a.out)
    if kept_all:
        path = a.sheet or os.path.join(a.out, "sheet_%s.png" % (a.role if len(roles) == 1 else "all"))
        render.sheet(kept_all, path, a.role)
        print("sheet:", path)


if __name__ == "__main__":
    main()
