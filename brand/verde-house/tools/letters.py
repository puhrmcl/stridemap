"""Verde House — proprietary capitals.

Eight drawn capitals: V E R D  H O U S.  Cap height = 100 units, baseline at y = 100.
A modern grotesk on architectural proportions: narrow round forms, even widths,
low stroke contrast, flat-cut terminals.  Everything is parametric; no font is used.
"""
import math

C    = 100.0     # cap height
STEM = 13.2      # vertical stem
BAR  = 11.9      # horizontal bar / arm          (0.901 x stem)
SR   = 13.6      # round letters, side stroke    (1.030 x stem — optical compensation)
RO   = 11.6      # round letters, top/bottom     (0.853 x SR)
OV   = 1.3       # overshoot on round forms
K    = 0.5735    # Bezier circularity, nudged up: slightly squared grotesk curves
KI   = 0.5620    # ... and a touch less on the counters

W = dict(V=90.0, E=72.0, R=82.0, D=88.0, H=86.0, O=91.0, U=82.5, S=74.0)

def _n(v): return f"{v:.3f}".rstrip('0').rstrip('.')
def M(p):  return f"M{_n(p[0])} {_n(p[1])}"
def L(p):  return f"L{_n(p[0])} {_n(p[1])}"
def Cv(a, b, p): return f"C{_n(a[0])} {_n(a[1])} {_n(b[0])} {_n(b[1])} {_n(p[0])} {_n(p[1])}"
def rect(x, y, w, h): return f"M{_n(x)} {_n(y)}L{_n(x+w)} {_n(y)}L{_n(x+w)} {_n(y+h)}L{_n(x)} {_n(y+h)}Z"

def ellipse(cx, cy, rx, ry, k, cw=True):
    """Closed ellipse from four cubics. cw=True gives clockwise winding (y down)."""
    ox, oy = rx*k, ry*k
    pts = [(cx, cy-ry), (cx+rx, cy), (cx, cy+ry), (cx-rx, cy)]
    hs  = [((cx+ox, cy-ry), (cx+rx, cy-oy)), ((cx+rx, cy+oy), (cx+ox, cy+ry)),
           ((cx-ox, cy+ry), (cx-rx, cy+oy)), ((cx-rx, cy-oy), (cx-ox, cy-ry))]
    if not cw:
        pts = [pts[0]] + pts[1:][::-1]
        hs  = [(b, a) for a, b in hs][::-1]
    d = [M(pts[0])]
    for i in range(4):
        d.append(Cv(hs[i][0], hs[i][1], pts[(i+1) % 4]))
    return "".join(d) + "Z"

# ---------------------------------------------------------------- H E
def glyph_H():
    w = W['H']; yb = 0.476*C - BAR/2
    return rect(0, 0, STEM, C) + rect(w-STEM, 0, STEM, C) + rect(STEM, yb, w-2*STEM, BAR)

def glyph_E():
    w = W['E']; ym = 0.474*C - BAR/2
    return (rect(0, 0, STEM, C) + rect(STEM, 0, w-STEM, BAR)
            + rect(STEM, ym, w-STEM-3.6, BAR) + rect(STEM, C-BAR, w-STEM, BAR))

# ---------------------------------------------------------------- O
def glyph_O():
    w = W['O']; cx, cy = w/2, C/2
    return (ellipse(cx, cy, w/2, C/2+OV, K, cw=True)
            + ellipse(cx, cy, w/2-SR, C/2+OV-RO, KI, cw=False))

# ---------------------------------------------------------------- U
def glyph_U():
    w = W['U']; rx = w/2; ry = rx*0.855
    yb = C + OV - ry                       # where the bottom curve springs
    irx, iry = rx-SR, ry-RO
    iyb = C + OV - RO - iry
    o = [M((0, 0)), L((0, yb)),
         Cv((0, yb+ry*K), (rx-rx*K, C+OV), (rx, C+OV)),
         Cv((rx+rx*K, C+OV), (w, yb+ry*K), (w, yb)), L((w, 0)),
         L((w-STEM, 0)), L((w-STEM, iyb)),
         Cv((w-STEM, iyb+iry*KI), (rx+irx*KI, C+OV-RO), (rx, C+OV-RO)),
         Cv((rx-irx*KI, C+OV-RO), (STEM, iyb+iry*KI), (STEM, iyb)), L((STEM, 0)), "Z"]
    return "".join(o)

# ---------------------------------------------------------------- D
def glyph_D():
    w = W['D']; sh = 0.34*(w-STEM) + STEM          # where the flat top ends
    ry = C/2; cy = C/2
    isx = sh - 1.2
    o = [M((STEM, 0)), L((sh, 0)),
         Cv((sh+(w-sh)*K, 0), (w, cy-ry*K), (w, cy)),
         Cv((w, cy+ry*K), (sh+(w-sh)*K, C), (sh, C)), L((STEM, C)), "Z",
         # counter, reversed winding, its left edge flush with the stem
         M((STEM, BAR)), L((STEM, C-BAR)), L((isx, C-BAR)),
         Cv((isx+(w-SR-isx)*KI, C-BAR), (w-SR, cy+(ry-BAR)*KI), (w-SR, cy)),
         Cv((w-SR, cy-(ry-BAR)*KI), (isx+(w-SR-isx)*KI, BAR), (isx, BAR)), "Z"]
    return rect(0, 0, STEM, C) + "".join(o)

# ---------------------------------------------------------------- R
def glyph_R(bowl=54.5, bw=72.0, legx=None, legw=15.4, legtop=43.2, legspring=42.0):
    w = W['R']; legx = w if legx is None else legx; sh = 0.36*(bw-STEM) + STEM
    cy = bowl/2; ry = cy
    isx = sh - 1.2
    bowl_d = [M((STEM, 0)), L((sh, 0)),
              Cv((sh+(bw-sh)*K, 0), (bw, cy-ry*K), (bw, cy)),
              Cv((bw, cy+ry*K), (sh+(bw-sh)*K, bowl), (sh, bowl)), L((STEM, bowl)), "Z",
              M((STEM, BAR)), L((STEM, bowl-BAR)), L((isx, bowl-BAR)),
              Cv((isx+(bw-SR-isx)*KI, bowl-BAR), (bw-SR, cy+(ry-BAR)*KI), (bw-SR, cy)),
              Cv((bw-SR, cy-(ry-BAR)*KI), (isx+(bw-SR-isx)*KI, BAR), (isx, BAR)), "Z"]
    leg = [M((legspring, legtop)), L((legspring+legw, legtop)),
           L((legx, C)), L((legx-legw, C)), "Z"]
    return "".join(bowl_d) + "".join(leg) + rect(0, 0, STEM, C)

# ---------------------------------------------------------------- V
def glyph_V(tL=15.0, tR=12.9, apex=0.4955, flat=1.7):
    w = W['V']; ay = C + 1.0; ax = w*apex
    def line_at(p0, p1, y):                 # x on the line p0->p1 at height y
        return p0[0] + (p1[0]-p0[0])*(y-p0[1])/(p1[1]-p0[1])
    oL, oR = ((0, 0), (ax-flat/2, ay)), ((w, 0), (ax+flat/2, ay))
    iL, iR = ((tL, 0), (ax-flat/2+tL, ay)), ((w-tR, 0), (ax+flat/2-tR, ay))
    # inner apex: intersect the two inner edges
    def inter(a, b):
        (x1,y1),(x2,y2) = a; (x3,y3),(x4,y4) = b
        d = (x1-x2)*(y3-y4) - (y1-y2)*(x3-x4)
        px = ((x1*y2-y1*x2)*(x3-x4) - (x1-x2)*(x3*y4-y3*x4))/d
        py = ((x1*y2-y1*x2)*(y3-y4) - (y1-y2)*(x3*y4-y3*x4))/d
        return (px, py)
    ia = inter(iL, iR)
    return "".join([M((0, 0)), L((tL, 0)), L(ia), L((w-tR, 0)), L((w, 0)),
                    L((ax+flat/2, ay)), L((ax-flat/2, ay)), "Z"])

# ---------------------------------------------------------------- S
def _catmull(pts, n=24):
    """Sample a Catmull-Rom spline through pts (open)."""
    P = [pts[0]] + list(pts) + [pts[-1]]
    out = []
    for i in range(len(P)-3):
        p0, p1, p2, p3 = P[i], P[i+1], P[i+2], P[i+3]
        for j in range(n):
            t = j/n; t2, t3 = t*t, t*t*t
            x = 0.5*((2*p1[0]) + (-p0[0]+p2[0])*t + (2*p0[0]-5*p1[0]+4*p2[0]-p3[0])*t2 + (-p0[0]+3*p1[0]-3*p2[0]+p3[0])*t3)
            y = 0.5*((2*p1[1]) + (-p0[1]+p2[1])*t + (2*p0[1]-5*p1[1]+4*p2[1]-p3[1])*t2 + (-p0[1]+3*p1[1]-3*p2[1]+p3[1])*t3)
            out.append((x, y))
    out.append(pts[-1])
    return out

def _offsets(cl):
    """Two offset polylines. Stroke weight follows the tangent: thin where the
    stroke runs horizontal, full where it runs vertical — the same optical rule
    that governs O and U."""
    lft, rgt = [], []
    for i, p in enumerate(cl):
        a = cl[max(i-1, 0)]; b = cl[min(i+1, len(cl)-1)]
        tx, ty = b[0]-a[0], b[1]-a[1]; m = math.hypot(tx, ty) or 1
        tx, ty = tx/m, ty/m
        h = (RO + (SR-RO)*abs(ty)) / 2          # ty = |sin(tangent)|
        nx, ny = -ty, tx
        lft.append((p[0]+h*nx, p[1]+h*ny)); rgt.append((p[0]-h*nx, p[1]-h*ny))
    return lft, rgt

def _cut(poly, y, keep_after):
    """Truncate a polyline at its first (head) or last (tail) crossing of y."""
    rng = range(len(poly)-1) if keep_after else range(len(poly)-2, -1, -1)
    for i in rng:
        y0, y1 = poly[i][1], poly[i+1][1]
        if (y0-y)*(y1-y) <= 0 and y0 != y1:
            t = (y-y0)/(y1-y0)
            pt = (poly[i][0]+(poly[i+1][0]-poly[i][0])*t, y)
            return ([pt] + poly[i+1:]) if keep_after else (poly[:i+1] + [pt])
    return poly

def _smooth_d(pts, first=True):
    """Emit a polyline as Catmull-Rom-derived cubics."""
    d = [M(pts[0])] if first else [L(pts[0])]
    P = [pts[0]] + list(pts) + [pts[-1]]
    for i in range(1, len(P)-2):
        p0, p1, p2, p3 = P[i-1], P[i], P[i+1], P[i+2]
        c1 = (p1[0]+(p2[0]-p0[0])/6, p1[1]+(p2[1]-p0[1])/6)
        c2 = (p2[0]-(p3[0]-p1[0])/6, p2[1]-(p3[1]-p1[1])/6)
        d.append(Cv(c1, c2, p2))
    return "".join(d)

S_GUIDE = [(66.5, 26.0), (53.5, 9.6), (37.0, 4.5), (19.0, 10.1),
           (7.6, 24.5), (10.6, 37.0), (21.5, 44.3)]

def glyph_S(y_cut=15.2, step=9, guide_pts=None):
    w = W['S']; cx, cy = w/2, C/2
    def mirror(p): return (2*cx-p[0], 2*cy-p[1])
    g = list(guide_pts or S_GUIDE)
    guide = g + [(cx, cy)] + [mirror(q) for q in reversed(g)]
    cl = _catmull(guide, 26)
    lft, rgt = _offsets(cl)
    lft = _cut(_cut(lft, y_cut, True), C-y_cut, False)
    rgt = _cut(_cut(rgt, y_cut, True), C-y_cut, False)
    lft = lft[::step] + [lft[-1]]
    rgt = rgt[::step] + [rgt[-1]]
    return _smooth_d(lft) + _smooth_d(rgt[::-1], first=False) + "Z"

GLYPH = {}
def build():
    GLYPH['H'] = glyph_H(); GLYPH['E'] = glyph_E(); GLYPH['O'] = glyph_O()
    GLYPH['U'] = glyph_U(); GLYPH['D'] = glyph_D(); GLYPH['R'] = glyph_R()
    GLYPH['V'] = glyph_V()
    GLYPH['S'] = glyph_S()
    return GLYPH

def glyph_svg(ch, fill="#1A3925"):
    build()
    return f'<path d="{GLYPH[ch]}" fill="{fill}"/>'
