"""Ascend Imagery — proposed mark.

Sibling to the Verde House arch. Same construction language, same weights, the
same terracotta disc — but the aperture turns angular (a roofline, for real
estate) and the disc moves from inside the aperture to above it. Contained
becomes aloft.
"""
import math, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from arch import capsule, circle

def build(w=820, stroke=93, apex_y=262, eave_y=762, leg_inset=100,
          disc_r=72, disc_y=124, th_y=922, th_h=64):
    cx = w/2
    base = th_y + th_h/2
    parts = {
        "roof": capsule(leg_inset, eave_y, cx, apex_y, stroke)
              + capsule(cx, apex_y, w-leg_inset, eave_y, stroke),
        "threshold": capsule(th_h/2, base, w-th_h/2, base, th_h),
        "disc": circle(cx, disc_y, disc_r),
    }
    m = dict(w=w, h=base+th_h/2, cx=cx,
             stroke_pct=100*stroke/(base+th_h/2),
             disc_gap=(apex_y - stroke/2) - (disc_y + disc_r),
             pitch=math.degrees(math.atan2(cx-leg_inset, eave_y-apex_y)))
    return parts, m
