"""Verde House — the arch mark.

A saguaro standing in a doorway, with the desert sun behind it. Drawn from
capsules and arcs on a 1000-unit field so every weight is a stated number.

The reference artwork failed three tests this build has to pass: a 3.8 %-of-height
arch stroke that vanishes below 32 px, a sun that reads as damage in one colour,
and no defined clear space between elements. Weights here are set against those.
"""
import math

F = 1000.0            # field height, arch top to threshold bottom

def capsule(x1, y1, x2, y2, w):
    """A stroke segment with round caps, as a closed path."""
    r = w / 2
    dx, dy = x2 - x1, y2 - y1
    L = math.hypot(dx, dy)
    ux, uy = dx / L, dy / L
    nx, ny = -uy * r, ux * r
    return (f"M{x1+nx:.2f} {y1+ny:.2f}"
            f"A{r:.2f} {r:.2f} 0 0 1 {x1-nx:.2f} {y1-ny:.2f}"
            f"L{x2-nx:.2f} {y2-ny:.2f}"
            f"A{r:.2f} {r:.2f} 0 0 1 {x2+nx:.2f} {y2+ny:.2f}Z")

def circle(cx, cy, r):
    return (f"M{cx-r:.2f} {cy:.2f}A{r:.2f} {r:.2f} 0 0 1 {cx+r:.2f} {cy:.2f}"
            f"A{r:.2f} {r:.2f} 0 0 1 {cx-r:.2f} {cy:.2f}Z")

def arch(W, t, y_bottom):
    """Closed band: outer rounded-top rect, inner returned along the same path."""
    R = W / 2
    ri = R - t
    return (f"M0 {y_bottom:.2f}L0 {R:.2f}"
            f"A{R:.2f} {R:.2f} 0 0 1 {W:.2f} {R:.2f}L{W:.2f} {y_bottom:.2f}"
            f"L{W-t:.2f} {y_bottom:.2f}L{W-t:.2f} {R:.2f}"
            f"A{ri:.2f} {ri:.2f} 0 0 0 {t:.2f} {R:.2f}L{t:.2f} {y_bottom:.2f}Z")

def build(arch_w=820, arch_t=80, leg_bottom=858,
          trunk_w=112, trunk_top=232,
          arm_w=92, larm_y=572, larm_x=220, larm_top=356,
          rarm_y=688, rarm_x=600, rarm_top=486,
          sun_r=66, sun_x=572, sun_y=260,
          th_y=922, th_h=64, th_gap=62,
          sun=True):
    cx = arch_w / 2
    base = th_y + th_h / 2
    parts = {
        "arch": arch(arch_w, arch_t, leg_bottom),
        "cactus": "".join([
            capsule(cx, trunk_top + trunk_w / 2, cx, base, trunk_w),
            capsule(cx, larm_y, larm_x, larm_y, arm_w),
            capsule(larm_x, larm_y, larm_x, larm_top + arm_w / 2, arm_w),
            capsule(cx, rarm_y, rarm_x, rarm_y, arm_w),
            capsule(rarm_x, rarm_y, rarm_x, rarm_top + arm_w / 2, arm_w),
        ]),
        "threshold": "".join([
            capsule(th_h / 2, base, cx - trunk_w / 2 - th_gap, base, th_h),
            capsule(cx + trunk_w / 2 + th_gap, base, arch_w - th_h / 2, base, th_h),
        ]),
    }
    if sun:
        parts["sun"] = circle(sun_x, sun_y, sun_r)
    m = dict(w=arch_w, h=base + th_h / 2, cx=cx,
             arch_pct=100 * arch_t / (base + th_h / 2),
             sun_trunk_gap=(sun_x - sun_r) - (cx + trunk_w / 2),
             sun_arch_gap=(arch_w / 2 - arch_t) - (math.hypot(sun_x - cx, sun_y - arch_w / 2) + sun_r),
             sun_arm_gap=math.hypot(sun_x - rarm_x, sun_y - rarm_top) - sun_r - arm_w / 2)
    return parts, m
