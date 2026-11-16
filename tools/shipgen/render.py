"""Contact sheet of generated ships, nose to the right, seed under each."""

import math

from PIL import Image, ImageDraw, ImageFont

import validate

PAINTS = {
    "Bone": (0.88, 0.88, 0.84), "Khaki": (0.66, 0.64, 0.44), "Ash": (0.62, 0.6, 0.57), "Taupe": (0.5, 0.43, 0.38),
    "Gunmetal": (0.27, 0.31, 0.38), "Charcoal": (0.17, 0.17, 0.18), "Umber": (0.26, 0.17, 0.1),
    "Primer": (0.62, 0.12, 0.1), "Terracotta": (0.9, 0.56, 0.36), "Plum": (0.42, 0.16, 0.42), "Sage": (0.6, 0.68, 0.55),
    "Olive Drab": (0.48, 0.5, 0.3), "Moss": (0.36, 0.5, 0.24), "Forest": (0.17, 0.34, 0.2), "Pine": (0.12, 0.3, 0.28),
    "Old Gold": (0.55, 0.42, 0.08), "Champagne": (0.96, 0.8, 0.58), "Signal": (1.0, 0.92, 0.15),
    "Tanker": (0.18, 0.5, 0.52), "Cargo Blue": (0.28, 0.36, 0.55), "Cobalt": (0.25, 0.45, 0.95),
    "Hazard": (1.0, 0.55, 0.1), "Orchid": (0.85, 0.55, 0.95),
}
BARE = (0.58, 0.59, 0.62)
BG = (14, 16, 22)
SCALE = 2   # sheet pixels per ship pixel, the same for every ship so sizes compare


def rgb(c, shade=1.0):
    return tuple(max(0, min(255, int(v * shade * 255))) for v in c[:3])


def draw_ship(d, ship, h, ox, oy, s):
    paints = h.get("paints") or ["Ash"]
    c1 = PAINTS.get(paints[0], BARE)
    c2 = PAINTS.get(paints[1], None) if len(paints) > 1 else None
    if c2 is None:
        c2 = tuple(v * 0.7 for v in c1)
    for p in validate.expand(ship["parts"]):
        base = p.get("color") or {"primary": c1, "secondary": c2}.get(p.get("paint"), BARE)
        fill = rgb(base, p.get("shade") or 1.0)
        pts = [(ox + x * s, oy + y * s) for x, y in p["poly"]]
        if p.get("layer") is None:
            d.polygon(pts, fill=fill, outline=rgb(base, 0.35))
        else:
            d.polygon(pts, fill=fill)
    for p in validate.expand(ship["parts"]):
        for l in p.get("lights", []):
            y = -l["y"] if p.get("twin") else l["y"]
            x = l["x"]
            col = {"nav": (255, 70, 60) if y < 0 else (60, 255, 110), "strobe": (255, 255, 255)}.get(l["kind"], (255, 236, 200))
            r = 1.2 * s
            d.rectangle([ox + x * s - r, oy + y * s - r, ox + x * s + r, oy + y * s + r], fill=col)
    for sl in ship["slots"]:
        if "x" not in sl:
            continue
        col = {"engine": (255, 150, 40), "hardpoint": (255, 60, 60), "bay": (200, 90, 255), "reactor": (80, 200, 255)}.get(sl["family"])
        if col:
            x, y = ox + sl["x"] * s, oy + sl["y"] * s
            d.ellipse([x - 3, y - 3, x + 3, y + 3], outline=col, width=2)
            if sl["family"] == "engine":
                d.line([x - 4, y, x - 18, y], fill=col, width=2)
    for b in ship.get("berths") or []:
        hw, hl = b.get("maxWidth", 44) / 2 * s, b.get("size", 56) / 2 * s
        x, y = ox + b["x"] * s, oy + b["y"] * s
        d.rectangle([x - hl, y - hw, x + hl, y + hw], outline=(120, 220, 255), width=1)


def sheet(kept, path, title):
    try:
        font = ImageFont.truetype("DejaVuSans.ttf", 14)
        small = ImageFont.truetype("DejaVuSans.ttf", 11)
    except OSError:
        font = small = ImageFont.load_default()
    cells = []
    for ship, m, h in kept:
        cw = int(m["L"] * SCALE + 60)
        ch = int(m["W"] * SCALE + 70)
        cells.append((ship, m, h, max(cw, 220), max(ch, 120)))
    width = 1800
    rows, row, x = [], [], 0
    for c in cells:
        if row and x + c[3] > width:
            rows.append(row)
            row, x = [], 0
        row.append(c)
        x += c[3]
    if row:
        rows.append(row)
    height = 40 + sum(max(c[4] for c in r) for r in rows)
    im = Image.new("RGB", (width, height), BG)
    d = ImageDraw.Draw(im)
    d.text((12, 10), "shipgen: %s  (%d ships, all at the same scale, nose right)" % (title, len(kept)), fill=(220, 220, 230), font=font)
    y = 40
    for r in rows:
        rh = max(c[4] for c in r)
        x = 0
        for ship, m, h, cw, ch in r:
            d.rectangle([x + 2, y + 2, x + cw - 2, y + rh - 2], outline=(40, 44, 56))
            cx, cy = x + cw / 2 - (m["cx"] if abs(m["cx"]) < 1e3 else 0), y + (rh - 34) / 2 + 4
            draw_ship(d, ship, h, cx, cy, SCALE)
            label = "%s  seed %d" % (h["name"], ship["seed"])
            d.text((x + 8, y + rh - 32), label, fill=(230, 230, 236), font=font)
            info = "%s · %s · %dx%d · %s%s" % (ship["role"], ship["template"], m["L"], m["W"],
                                                "sym" if ship["sym"] else ship["asym"], "")
            d.text((x + 8, y + rh - 15), info, fill=(140, 146, 160), font=small)
            x += cw
        y += rh
    im.save(path)
