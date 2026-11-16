"""Polygon helpers for the ship generator: building outlines, checking them,
and rasterising them for the validator. Ship space: +x is the nose, y is
across the ship (the game mirrors parts across y = 0)."""

import math


def dedupe(pts):
    """Drop repeated neighbouring points (chamfers of 0 make them)."""
    out = []
    for p in pts:
        p = (round(p[0], 1), round(p[1], 1))
        if not out or abs(out[-1][0] - p[0]) > 0.05 or abs(out[-1][1] - p[1]) > 0.05:
            out.append(p)
    while len(out) > 1 and abs(out[0][0] - out[-1][0]) < 0.05 and abs(out[0][1] - out[-1][1]) < 0.05:
        out.pop()
    return out


def section(x0, x1, wb, wf, chb=0.0, chf=0.0, yo=0.0):
    """A hull section from x0 (back) to x1 (front): half-width wb at the back,
    wf at the front, corners cut by chb / chf, centred on y = yo."""
    ln = x1 - x0
    chb = max(0.0, min(chb, wb * 0.6, ln / 3))
    chf = max(0.0, min(chf, wf * 0.6, ln / 3))
    if wf < 0.6:   # comes to a point
        return dedupe([(x0, yo - wb + chb), (x0 + chb, yo - wb), (x1, yo),
                       (x0 + chb, yo + wb), (x0, yo + wb - chb)])
    return dedupe([
        (x0, yo - wb + chb), (x0 + chb, yo - wb), (x1 - chf, yo - wf), (x1, yo - wf + chf),
        (x1, yo + wf - chf), (x1 - chf, yo + wf), (x0 + chb, yo + wb), (x0, yo + wb - chb)])


def box(x0, y0, x1, y1, ch=0.0):
    """Axis-aligned box from two corners, corners cut by ch."""
    xa, xb = min(x0, x1), max(x0, x1)
    ya, yb = min(y0, y1), max(y0, y1)
    hw = (yb - ya) / 2
    return section(xa, xb, hw, hw, ch, ch, (ya + yb) / 2)


def quad(pts):
    return dedupe(pts)


def mirror(poly):
    return [(x, -y) for x, y in reversed(poly)]


def area(poly):
    a = 0.0
    n = len(poly)
    for i in range(n):
        x1, y1 = poly[i]
        x2, y2 = poly[(i + 1) % n]
        a += x1 * y2 - x2 * y1
    return abs(a) / 2


def perimeter(poly):
    n = len(poly)
    return sum(math.dist(poly[i], poly[(i + 1) % n]) for i in range(n))


def bounds(polys):
    xs = [p[0] for poly in polys for p in poly]
    ys = [p[1] for poly in polys for p in poly]
    return min(xs), min(ys), max(xs), max(ys)


def _ccw(a, b, c):
    return (c[1] - a[1]) * (b[0] - a[0]) - (b[1] - a[1]) * (c[0] - a[0])


def _cross(p1, p2, p3, p4):
    d1, d2 = _ccw(p3, p4, p1), _ccw(p3, p4, p2)
    d3, d4 = _ccw(p1, p2, p3), _ccw(p1, p2, p4)
    return ((d1 > 0) != (d2 > 0)) and ((d3 > 0) != (d4 > 0)) and d1 and d2 and d3 and d4


def is_simple(poly):
    """True when no two non-neighbouring edges cross (what love.math.triangulate needs)."""
    n = len(poly)
    if n < 3 or area(poly) < 1e-3:
        return False
    for i in range(n):
        a, b = poly[i], poly[(i + 1) % n]
        for j in range(i + 1, n):
            if j == i or (j + 1) % n == i or (i + 1) % n == j:
                continue
            if _cross(a, b, poly[j], poly[(j + 1) % n]):
                return False
    return True


def point_in(poly, x, y):
    inside = False
    n = len(poly)
    j = n - 1
    for i in range(n):
        xi, yi = poly[i]
        xj, yj = poly[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
            inside = not inside
        j = i
    return inside


def flat(poly):
    out = []
    for x, y in poly:
        out += [x, y]
    return out
