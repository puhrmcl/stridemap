"""Verde House — the wordmark.

VERDE and HOUSE are set to an IDENTICAL measure so the two lines form one
rectangle. Because the letters differ in width the tracking differs slightly
per line — that is the point: the block is designed, not typed.
"""
import sys; sys.path.insert(0, '/home/user/stridemap/brand/verde-house/tools')
import letters as T

OVERHANG = 1.8       # the V's apex hangs left of the H stem (optical flush-left)
KERN_SCALE = 1.5     # how assertively the optical kern model is applied

# how much white each side of a letter gives away
_OPEN = dict(V_r=4.0, E_r=2.0, R_r=2.5, D_r=1.2, O_r=1.2, U_r=0.4, S_r=2.2, H_r=0.0,
             V_l=0.0, E_l=0.0, R_l=0.0, D_l=0.0, O_l=1.2, U_l=0.4, S_l=2.2, H_l=0.0)

def _deltas(word):
    raw = [_OPEN[f"{word[i]}_r"] + _OPEN[f"{word[i+1]}_l"] for i in range(len(word)-1)]
    mean = sum(raw) / len(raw)
    return [(mean - v) * KERN_SCALE for v in raw]

def line(word, measure, x0=0.0):
    """Place `word` so its ink spans exactly x0 .. x0+measure."""
    widths = [T.W[c] for c in word]
    d = _deltas(word)
    gap = (measure - sum(widths) - sum(d)) / (len(word) - 1)
    out, x = [], x0
    for i, c in enumerate(word):
        out.append((c, x))
        if i < len(word) - 1:
            x += widths[i] + gap + d[i]
    return out, gap

def block(measure=531.6, leading=116.0):
    l1, g1 = line("VERDE", measure + OVERHANG, -OVERHANG)
    l2, g2 = line("HOUSE", measure, 0.0)
    return dict(l1=l1, l2=l2, gap1=g1, gap2=g2, measure=measure, leading=leading,
                width=measure + OVERHANG, height=leading + T.C, x0=-OVERHANG)

def render(b, fill="#1A3925"):
    T.build()
    g = [f'<g transform="translate(0 0)">']
    for c, x in b['l1']: g.append(f'<g transform="translate({x:.3f} 0)">{T.glyph_svg(c, fill)}</g>')
    g.append('</g>')
    g.append(f'<g transform="translate(0 {b["leading"]:.3f})">')
    for c, x in b['l2']: g.append(f'<g transform="translate({x:.3f} 0)">{T.glyph_svg(c, fill)}</g>')
    g.append('</g>')
    return "".join(g)

def render_line(word, measure, fill="#1A3925", x0=0.0):
    T.build(); pl, _ = line(word, measure, x0)
    return "".join(f'<g transform="translate({x:.3f} 0)">{T.glyph_svg(c, fill)}</g>' for c, x in pl)
