"""Verde House — the prickly pear symbol.

One canonical pad, instantiated three times.
Linear scale ratio r = 1/sqrt(phi) = 0.7862  ->  each pad's AREA is phi times the next.
"""
import sys, math; sys.path.insert(0, '/home/user/stridemap/brand/verde-house/tools')
from geom import pad_path, sample_pad, poly_area_centroid, bbox, min_gap

PHI  = (1 + 5 ** 0.5) / 2
R    = 1 / math.sqrt(PHI)          # 0.786151
PAD  = dict(Rt=29.0, Rb=17.5, WmR=35.0)   # the canonical pad

def _place(scale, deg, anchor, target_gap, main_pts, out_dir):
    """Slide a pad along `out_dir` from `anchor` until its min gap to the main pad == target."""
    def pts_at(k):
        # local base point (0,100) must land at anchor + out_dir*k
        bx, by = 0.0, 100.0
        r = math.radians(deg); c, s = math.cos(r), math.sin(r)
        rx, ry = bx*scale*c - by*scale*s, bx*scale*s + by*scale*c
        tx, ty = anchor[0] + out_dir[0]*k - rx, anchor[1] + out_dir[1]*k - ry
        return (tx, ty), sample_pad(560, scale=scale, deg=deg, tx=tx, ty=ty, **PAD)
    lo, hi = -60.0, 60.0
    for _ in range(70):
        mid = (lo + hi) / 2
        _, p = pts_at(mid)
        if min_gap(p[::3], main_pts[::3]) < target_gap: lo = mid
        else: hi = mid
    return pts_at((lo + hi) / 2)

def build(gap=2.55, theta_main=-3.0, theta_up=41.0, theta_left=-67.0,
          up_anchor=0.20, left_anchor=0.36):
    """Returns (paths, metrics). `gap` is in main-pad units (main pad length = 100)."""
    main_pts = sample_pad(1400, scale=1.0, deg=theta_main, **PAD)
    def anchor_at(y_frac, side):
        """Outline point on the main pad at height y_frac (0=apex,1=base) on the given side,
        plus its outward normal."""
        x0, y0, x1, y1 = bbox(main_pts)
        yt = y0 + (y1 - y0) * y_frac
        cand = [p for p in main_pts if abs(p[1] - yt) < (y1 - y0) * 0.012]
        p = (max if side > 0 else min)(cand, key=lambda q: q[0])
        i = min(range(len(main_pts)), key=lambda j: (main_pts[j][0]-p[0])**2 + (main_pts[j][1]-p[1])**2)
        a, b = main_pts[(i-6) % len(main_pts)], main_pts[(i+6) % len(main_pts)]
        tx, ty = b[0]-a[0], b[1]-a[1]; n = math.hypot(tx, ty)
        return p, (ty/n, -tx/n)            # outward normal for a clockwise outline
    au, nu = anchor_at(up_anchor, +1)
    al, nl = anchor_at(left_anchor, -1)
    (tu, up_pts) = _place(R,      theta_up,   au, gap, main_pts, nu)
    (tl, lf_pts) = _place(R * R,  theta_left, al, gap, main_pts, nl)
    paths = [
        pad_path(scale=1.0,   deg=theta_main, tx=0, ty=0,          **PAD),
        pad_path(scale=R,     deg=theta_up,   tx=tu[0], ty=tu[1],  **PAD),
        pad_path(scale=R*R,   deg=theta_left, tx=tl[0], ty=tl[1],  **PAD),
    ]
    allp = main_pts + up_pts + lf_pts
    x0, y0, x1, y1 = bbox(allp)
    areas, cxs, cys = zip(*[poly_area_centroid(p) for p in (main_pts, up_pts, lf_pts)])
    tot = sum(areas)
    m = dict(bbox=(x0, y0, x1, y1), w=x1-x0, h=y1-y0, wh=(x1-x0)/(y1-y0),
             shares=[a/tot for a in areas],
             cx=sum(a*c for a, c in zip(areas, cxs))/tot,
             cy=sum(a*c for a, c in zip(areas, cys))/tot,
             gap_up=min_gap(up_pts[::2], main_pts[::2]),
             gap_left=min_gap(lf_pts[::2], main_pts[::2]),
             gap_ul=min_gap(up_pts[::2], lf_pts[::2]))
    m['cx_off'] = (m['cx'] - (x0+x1)/2) / m['w']
    m['cy_off'] = (m['cy'] - (y0+y1)/2) / m['h']
    return paths, m
