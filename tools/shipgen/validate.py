"""Quality checks for generated ships. A ship that fails any hard check is
thrown away; the ones that pass get a score so the best show first.

Hard checks
  outline     every part is a simple polygon (the game triangulates it)
  slivers     no hull part too thin or too small to read or to hit
  connected   the hull parts form one piece (nothing floating)
  hidden      every hull part shows at least a little (no buried junk)
  size        length and width stay near the borrowed hull's, so the
              ship keeps its size class (berths, docks, hangar fit)
  fill        not a sparse scribble and not a featureless slab
  balance     the hull's centre of area sits near the ship's origin and
              axis, asymmetric or not
  slots       weapons, bays, reactor and engines sit on the hull
  exhaust     nothing of the ship sits in an engine's exhaust plume
  lights      every light sits on (or right by) its part
  berths      every berth sits on the hull and fits inside it
  unique      not a near copy of an existing ship or another keeper
"""

import math

from PIL import Image, ImageChops, ImageDraw

import geom

RES = 2   # raster pixels per ship pixel


def expand(parts):
    """Parts with mirror twins added, as the game does."""
    out = []
    for p in parts:
        out.append(p)
        if p.get("mirror"):
            q = dict(p)
            q["poly"] = geom.mirror(p["poly"])
            q["mirror"] = None
            q["twin"] = True
            out.append(q)
    return out


class Raster:
    def __init__(self, parts):
        polys = [p["poly"] for p in parts]
        x0, y0, x1, y1 = geom.bounds(polys)
        self.ox, self.oy = x0 - 8, y0 - 8
        self.w = int((x1 - x0 + 16) * RES) + 1
        self.h = int((y1 - y0 + 16) * RES) + 1

    def pt(self, x, y):
        return ((x - self.ox) * RES, (y - self.oy) * RES)

    def mask(self, polys):
        im = Image.new("1", (self.w, self.h), 0)
        d = ImageDraw.Draw(im)
        for poly in polys:
            d.polygon([self.pt(x, y) for x, y in poly], fill=1)
        return im

    def at(self, im, x, y, r=0):
        px, py = self.pt(x, y)
        for dx in range(-r, r + 1):
            for dy in range(-r, r + 1):
                qx, qy = int(px) + dx, int(py) + dy
                if 0 <= qx < self.w and 0 <= qy < self.h and im.getpixel((qx, qy)):
                    return True
        return False


def count(im):
    h = im.histogram()
    return sum(h[1:])


def grow(im, r=1):
    from PIL import ImageFilter
    return im.convert("L").filter(ImageFilter.MaxFilter(2 * r + 1)).point(lambda v: 255 if v else 0).convert("1")


def centroid(im):
    sx = sy = n = 0
    w, h = im.size
    px = im.load()
    for y in range(0, h, 2):
        for x in range(0, w, 2):
            if px[x, y]:
                sx += x
                sy += y
                n += 1
    return (sx / n, sy / n) if n else (0, 0)


def signature(ship, size=48):
    """A small normalised silhouette for near-duplicate checks."""
    parts = [p for p in expand(ship["parts"]) if p.get("layer") is None]
    polys = [p["poly"] for p in parts]
    x0, y0, x1, y1 = geom.bounds(polys)
    s = (size - 2) / max(x1 - x0, y1 - y0)
    im = Image.new("1", (size, size), 0)
    d = ImageDraw.Draw(im)
    cy = (y0 + y1) / 2
    for poly in polys:
        d.polygon([(1 + (x - x0) * s, size / 2 + (y - cy) * s) for x, y in poly], fill=1)
    return im


def iou(a, b):
    inter = count(ImageChops.logical_and(a, b))
    union = count(ImageChops.logical_or(a, b))
    return inter / union if union else 0


def check(ship, others=()):
    """Returns (problems, metrics). No problems means keep it."""
    problems = []
    parts = expand(ship["parts"])
    hull = [p for p in parts if p.get("layer") is None and p.get("collide") is not False]

    for i, p in enumerate(parts):
        if not geom.is_simple(p["poly"]):
            problems.append("outline: part %d (%s) crosses itself" % (i + 1, p.get("name")))
    if problems:
        return problems, {}
    for p in hull:
        a = geom.area(p["poly"])
        thick = 2 * a / geom.perimeter(p["poly"])
        if a < 20 or thick < 1.6:
            problems.append("slivers: %s is %.0f px2, %.1f px thick" % (p.get("name"), a, thick))

    R = Raster(parts)
    masks = [R.mask([p["poly"]]) for p in hull]
    union = R.mask([p["poly"] for p in hull])
    # connected: flood over overlaps
    grown = [grow(m, 1) for m in masks]
    seen, todo = {0}, [0]
    while todo:
        i = todo.pop()
        for j in range(len(masks)):
            if j not in seen and ImageChops.logical_and(grown[i], masks[j]).getbbox():
                seen.add(j)
                todo.append(j)
    if len(seen) != len(masks):
        loose = [hull[j].get("name") for j in range(len(masks)) if j not in seen]
        problems.append("connected: %s float free" % ", ".join(loose))
    # hidden: parts are drawn in order, later on top
    above = Image.new("1", union.size, 0)
    for j in range(len(masks) - 1, -1, -1):
        vis = count(ImageChops.logical_and(masks[j], ImageChops.invert(above)))
        tot = count(masks[j])
        if tot and vis / tot < 0.06:
            problems.append("hidden: %s barely shows (%.0f%%)" % (hull[j].get("name"), 100 * vis / tot))
        above = ImageChops.logical_or(above, masks[j])

    x0, y0, x1, y1 = geom.bounds([p["poly"] for p in hull])
    L, W = x1 - x0, y1 - y0
    lo, hi = ship["L_range"]
    if not (lo * 0.9 <= L <= hi * 1.1):
        problems.append("size: length %.0f outside %s's %d..%d" % (L, ship["role"], lo, hi))
    alo, ahi = ship["aspect"]
    if not (alo * 0.75 <= W / L <= ahi * 1.4):
        problems.append("size: width %.0f is %.2f of its length (%s: %.2f..%.2f)" % (W, W / L, ship["role"], alo, ahi))
    area = count(union) / RES / RES
    fill = area / (L * W)
    if not (0.32 <= fill <= 0.88):
        problems.append("fill: hull covers %.0f%% of its box" % (100 * fill))
    cx, cy = centroid(union)
    cx, cy = cx / RES + R.ox, cy / RES + R.oy
    if abs(cy) > 0.06 * W + 1:
        problems.append("balance: centre %.1f px off axis" % cy)
    if abs(cx) > 0.12 * L:
        problems.append("balance: centre %.1f px off the origin lengthwise" % cx)

    near = grow(union, 2)
    for s in ship["slots"]:
        if "x" not in s:
            continue
        if not R.at(near, s["x"], s["y"]):
            problems.append("slots: %s at (%.0f, %.0f) is off the hull" % (s["family"], s["x"], s["y"]))
        if s["family"] == "engine":
            # plume: a band behind the nozzle, as wide as a nozzle, 40% of the length
            plume = R.mask([geom.box(s["x"] - 3 - L * 0.4, s["y"] - 3, s["x"] - 3, s["y"] + 3)])
            if ImageChops.logical_and(plume, union).getbbox():
                problems.append("exhaust: engine at (%.0f, %.0f) fires into the hull" % (s["x"], s["y"]))
    for p in parts:
        if p.get("twin"):
            continue
        pm = grow(R.mask([p["poly"]]), 3)
        for l in p.get("lights", []):
            if not R.at(pm, l["x"], l["y"]):
                problems.append("lights: %s light off its part %s" % (l["kind"], p.get("name")))
    for bth in ship.get("berths") or []:
        hw, hl = bth.get("maxWidth", 44) / 2, bth.get("size", 56)
        foot = R.mask([geom.box(bth["x"] - hl * 0.5, bth["y"] - hw * 0.7, bth["x"] + hl * 0.5, bth["y"] + hw * 0.7)])
        if count(ImageChops.logical_and(foot, union)) < 0.9 * count(foot):
            problems.append("berths: berth at (%.0f, %.0f) hangs off the deck" % (bth["x"], bth["y"]))

    sig = signature(ship)
    for name, other in others:
        v = iou(sig, other)
        if v > 0.9:
            problems.append("unique: %.0f%% the same as %s" % (100 * v, name))
            break

    # score (soft): an outline with some bite, a few distinct pieces, a
    # filled-but-not-solid silhouette
    perim = sum(geom.perimeter(p["poly"]) for p in hull)
    complexity = perim * perim / max(1, area) / 4 / math.pi
    pieces = len(hull)
    score = 0
    score += 30 * math.exp(-((fill - 0.6) / 0.18) ** 2)
    score += 30 * math.exp(-((math.log(max(1.0, complexity)) - math.log(9)) / 0.7) ** 2)
    score += 20 * math.exp(-((pieces - 9) / 5) ** 2)
    score += 20 * (1 - min(1, abs(cy) / (0.06 * W + 1)))
    cargo_area = sum(geom.area(p["poly"]) for p in hull if p.get("cargo"))
    metrics = {"cargo_area": cargo_area, "L": L, "W": W, "area": area, "fill": fill, "complexity": complexity, "pieces": pieces,
               "score": round(score, 1), "sig": sig, "cx": cx, "cy": cy}
    return problems, metrics
