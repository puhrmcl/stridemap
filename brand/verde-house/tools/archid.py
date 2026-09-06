"""Verde House — the arch identity. Assembles every mark from arch.py + serif.py."""
import os, sys, math, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import arch, serif as T

OUT = "/home/user/stridemap/brand/verde-house"
GREEN, TERRA, WARM, BLACK, WHITE = "#1A3925", "#B76F43", "#F4F1E9", "#131614", "#FFFFFF"

CAP      = 100.0
SYM_H    = 450.0    # symbol height = 4.5 cap
STACK_GAP= 26.0     # symbol bottom to wordmark cap line
HGAP     = 44.0     # horizontal lockup channel

# optical kerning: how much white each side gives away
_OPEN = dict(V_r=4.4, E_r=2.2, R_r=2.6, D_r=1.2, O_r=1.2, U_r=0.5, S_r=2.4, H_r=0.0,
             V_l=4.4, E_l=0.0, R_l=0.0, D_l=0.0, O_l=1.2, U_l=0.5, S_l=2.4, H_l=0.0)

def _deltas(word, scale=1.0):
    raw = [_OPEN[f"{word[i]}_r"] + _OPEN[f"{word[i+1]}_l"] for i in range(len(word)-1)]
    mean = sum(raw)/len(raw)
    return [(mean - v) * scale for v in raw]

def line(word, gap):
    out, x = [], 0.0
    d = _deltas(word)
    for i, c in enumerate(word):
        out.append((c, x))
        if i < len(word)-1:
            x += T.W[c] + gap + d[i]
    return out, x + T.W[word[-1]]

def wordmark(gap=14.0, word_space=36.0):
    l1, w1 = line("VERDE", gap)
    l2, w2 = line("HOUSE", gap)
    off = w1 + word_space
    placed = l1 + [(c, x + off) for c, x in l2]
    return placed, off + w2

def wordmark_svg(fill=GREEN, gap=14.0, word_space=36.0):
    T.build()
    placed, w = wordmark(gap, word_space)
    body = "".join(f'<g transform="translate({x:.3f} 0)">{T.glyph_svg(c, fill)}</g>' for c, x in placed)
    return body, w

# ---------------------------------------------------------------- symbol
STD   = dict(arch_t=92, trunk_w=120, arm_w=100, sun_r=62, sun_x=576)
MICRO = dict(arch_t=118, trunk_w=136, arm_w=116, th_h=78, th_gap=74, sun=False)

def symbol(height=SYM_H, micro=False, fill=GREEN, sun_fill=TERRA):
    parts, m = arch.build(**(MICRO if micro else STD))
    s = height / m['h']
    g = [f'<path d="{parts["arch"]}" fill="{fill}" fill-rule="evenodd"/>',
         f'<path d="{parts["threshold"]}" fill="{fill}"/>']
    if "sun" in parts:
        g.append(f'<path d="{parts["sun"]}" fill="{sun_fill}"/>')
    g.append(f'<path d="{parts["cactus"]}" fill="{fill}"/>')
    return (f'<g transform="scale({s:.6f})">{"".join(g)}</g>', m['w']*s, height, m)

# ---------------------------------------------------------------- monogram
def monogram(fill=GREEN):
    """V and H set tight, in the display serif. The arch is the symbol's job."""
    T.build()
    gap = 15.0
    w = T.W['V'] + gap + T.W['H']
    body = (f'{T.glyph_svg("V", fill)}'
            f'<g transform="translate({T.W["V"]+gap:.2f} 0)">{T.glyph_svg("H", fill)}</g>')
    return body, w

# ---------------------------------------------------------------- lockups
def primary(fill=GREEN, sun_fill=TERRA, micro=False):
    sy, sw, sh, _ = symbol(SYM_H, micro, fill, sun_fill)
    wm, ww = wordmark_svg(fill)
    W = max(sw, ww)
    sx = (W - sw)/2
    wx = (W - ww)/2
    wy = sh + STACK_GAP
    body = (f'<g transform="translate({sx:.3f} 0)">{sy}</g>'
            f'<g transform="translate({wx:.3f} {wy:.3f})">{wm}</g>')
    return body, W, wy + CAP

def horizontal(fill=GREEN, sun_fill=TERRA):
    h = 252.0
    sy, sw, sh, _ = symbol(h, False, fill, sun_fill)
    wm, ww = wordmark_svg(fill)
    wy = (sh - CAP)/2
    body = (f'{sy}<g transform="translate({sw+HGAP:.3f} {wy:.3f})">{wm}</g>')
    return body, sw + HGAP + ww, sh

# ---------------------------------------------------------------- emit
def svg(w, h, body, bg=None, pad=0):
    b = f'<rect x="{-pad}" y="{-pad}" width="{w+2*pad:.3f}" height="{h+2*pad:.3f}" fill="{bg}"/>' if bg else ""
    return (f'<svg xmlns="http://www.w3.org/2000/svg" '
            f'viewBox="{-pad} {-pad} {w+2*pad:.3f} {h+2*pad:.3f}" '
            f'width="{w+2*pad:.1f}" height="{h+2*pad:.1f}">{b}{body}</svg>')

def _w(name, s):
    p = os.path.join(OUT, "svg", name)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    open(p, "w").write(s)
    return name

def emit():
    files = []
    for suf, fill, sun, bg in (("", GREEN, TERRA, None),
                               ("-reversed", WARM, TERRA, GREEN),
                               ("-black", BLACK, BLACK, None)):
        b, w, h = primary(fill, sun)
        files.append(_w(f"lockup-primary{suf}.svg", svg(w, h, b, bg, 40 if bg else 0)))
        b, w, h = horizontal(fill, sun)
        files.append(_w(f"lockup-horizontal{suf}.svg", svg(w, h, b, bg, 30 if bg else 0)))
        s, sw, sh, _ = symbol(1000, False, fill, sun)
        files.append(_w(f"symbol{suf}.svg", svg(sw, sh, s, bg, 60 if bg else 0)))
        m, mw = monogram(fill)
        files.append(_w(f"monogram-vh{suf}.svg", svg(mw, CAP, m, bg, 24 if bg else 0)))
    s, sw, sh, _ = symbol(1000, True, GREEN, TERRA)
    files.append(_w("symbol-micro.svg", svg(sw, sh, s)))
    s, sw, sh, _ = symbol(1000, True, WARM, WARM)
    files.append(_w("symbol-micro-reversed.svg", svg(sw, sh, s, GREEN, 60)))
    wm, ww = wordmark_svg()
    files.append(_w("wordmark.svg", svg(ww, CAP, wm)))

    def icon(size, radius, frac, micro, bg=GREEN, fg=WARM, sun=TERRA):
        s, sw, sh, _ = symbol(size*frac, micro, fg, sun)
        return (f'<rect width="{size}" height="{size}" rx="{radius}" fill="{bg}"/>'
                f'<g transform="translate({(size-sw)/2:.3f} {(size-sh)/2:.3f})">{s}</g>')
    files.append(_w("app-icon.svg", svg(512, 512, icon(512, 112, 0.62, False))))
    files.append(_w("avatar.svg",   svg(512, 512, icon(512, 256, 0.60, False))))
    files.append(_w("favicon-32.svg", svg(32, 32, icon(32, 6, 0.72, True))))
    m, mw = monogram(WARM)
    sc = 16*0.60/CAP
    files.append(_w("favicon-16.svg", svg(16, 16,
        f'<rect width="16" height="16" rx="3" fill="{GREEN}"/>'
        f'<g transform="translate({(16-mw*sc)/2:.3f} {(16-CAP*sc)/2:.3f}) scale({sc:.5f})">{m}</g>')))
    return files
