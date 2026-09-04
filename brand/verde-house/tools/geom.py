"""Verde House identity — core geometry primitives.

A pad is built as FOUR mutually tangent circular arcs:
  - a top cap circle       (radius Rt, on axis)
  - a base cap circle      (radius Rb, on axis, Rb < Rt)
  - two flank arcs         (large radius, bulging outward, internally tangent to both caps)
Everything is exact circle geometry; nothing is eyeballed.
"""
import math

def _solve_flank(L, Rt, Rb, Wm):
    """Flank circle centre (-a, yc) radius Rf = Wm + a, internally tangent to both caps.
    Returns (a, yc, Rf). Axis runs from apex (0,0) to base (0,L), y down."""
    B = L - Rb
    def a1(yc):  # from top-cap tangency
        return (yc*yc - 2*Rt*yc + 2*Wm*Rt - Wm*Wm) / (2*(Wm - Rt))
    def a2(yc):  # from base-cap tangency
        return (yc*yc - 2*B*yc + B*B - Rb*Rb + 2*Wm*Rb - Wm*Wm) / (2*(Wm - Rb))
    f = lambda yc: a1(yc) - a2(yc)
    lo, hi = Rt*0.05, L - Rb*0.05
    flo = f(lo)
    for _ in range(200):
        mid = (lo + hi) / 2
        if (f(mid) > 0) == (flo > 0): lo, flo = mid, f(mid)
        else: hi = mid
    yc = (lo + hi) / 2
    a = a1(yc)
    return a, yc, Wm + a

def _tangent_point(Cf, Rf, Cc):
    """Tangent point between flank circle (Cf,Rf) and internally tangent cap circle centred Cc."""
    dx, dy = Cc[0]-Cf[0], Cc[1]-Cf[1]
    d = math.hypot(dx, dy)
    return (Cf[0] + Rf*dx/d, Cf[1] + Rf*dy/d)

def pad_arcs(L=100.0, Rt=30.0, Rb=16.5, WmR=34.0, WmL=None):
    """Return the pad outline as a list of arc segments, clockwise, y down.
    WmL != WmR gives the pad a whisper of hand-drawn asymmetry."""
    WmL = WmR if WmL is None else WmL
    Ct, Cb = (0.0, Rt), (0.0, L - Rb)
    aR, ycR, RfR = _solve_flank(L, Rt, Rb, WmR)
    aL, ycL, RfL = _solve_flank(L, Rt, Rb, WmL)
    CfR, CfL = (-aR, ycR), (aL, ycL)              # right flank bulges right, left flank left
    T_tr = _tangent_point(CfR, RfR, Ct)
    T_br = _tangent_point(CfR, RfR, Cb)
    T_tl = _tangent_point(CfL, RfL, Ct)
    T_bl = _tangent_point(CfL, RfL, Cb)
    # segments: (start, end, centre, radius, sweep) traced clockwise in a y-down frame
    return [
        (T_tl, T_tr, Ct,  Rt,  1),   # over the top cap
        (T_tr, T_br, CfR, RfR, 1),   # down the right flank  (centre left of axis)
        (T_br, T_bl, Cb,  Rb,  1),   # under the base cap
        (T_bl, T_tl, CfL, RfL, 1),   # up the left flank     (centre right of axis)
    ], dict(Ct=Ct, Cb=Cb, CfR=CfR, CfL=CfL, RfR=RfR, RfL=RfL, ycR=ycR, ycL=ycL)

def _arc_span(p0, p1, c):
    a0 = math.atan2(p0[1]-c[1], p0[0]-c[0]); a1 = math.atan2(p1[1]-c[1], p1[0]-c[0])
    while a1 < a0: a1 += 2*math.pi
    return a1 - a0

def xf(p, scale, deg, tx, ty):
    r = math.radians(deg); c, s = math.cos(r), math.sin(r)
    x, y = p[0]*scale, p[1]*scale
    return (x*c - y*s + tx, x*s + y*c + ty)

def pad_path(scale=1.0, deg=0.0, tx=0.0, ty=0.0, **kw):
    segs, _ = pad_arcs(**kw)
    d = []
    for i, (p0, p1, c, r, sw) in enumerate(segs):
        a, b = xf(p0, scale, deg, tx, ty), xf(p1, scale, deg, tx, ty)
        la = 1 if _arc_span(p0, p1, c) > math.pi else 0
        if i == 0: d.append(f"M{a[0]:.4f} {a[1]:.4f}")
        d.append(f"A{r*scale:.4f} {r*scale:.4f} 0 {la} {sw} {b[0]:.4f} {b[1]:.4f}")
    d.append("Z")
    return " ".join(d)

def sample_pad(n=720, scale=1.0, deg=0.0, tx=0.0, ty=0.0, **kw):
    """Dense point sampling of the outline, for measuring gaps / areas / centroids."""
    segs, _ = pad_arcs(**kw)
    pts = []
    for (p0, p1, c, r, sw) in segs:
        cx, cy = c
        a0 = math.atan2(p0[1]-cy, p0[0]-cx); a1 = math.atan2(p1[1]-cy, p1[0]-cx)
        while a1 < a0: a1 += 2*math.pi
        m = max(8, int(n * (a1-a0) / (2*math.pi)))
        for i in range(m):
            t = a0 + (a1-a0)*i/m
            pts.append(xf((cx + r*math.cos(t), cy + r*math.sin(t)), scale, deg, tx, ty))
    return pts

def poly_area_centroid(pts):
    A = cx = cy = 0.0
    for i in range(len(pts)):
        x0, y0 = pts[i]; x1, y1 = pts[(i+1) % len(pts)]
        cr = x0*y1 - x1*y0
        A += cr; cx += (x0+x1)*cr; cy += (y0+y1)*cr
    A *= 0.5
    return abs(A), cx/(6*A), cy/(6*A)

def min_gap(a, b):
    best = float("inf")
    for p in a:
        for q in b:
            d = (p[0]-q[0])**2 + (p[1]-q[1])**2
            if d < best: best = d
    return math.sqrt(best)

def bbox(pts):
    xs = [p[0] for p in pts]; ys = [p[1] for p in pts]
    return min(xs), min(ys), max(xs), max(ys)
