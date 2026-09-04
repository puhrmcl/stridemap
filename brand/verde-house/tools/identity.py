"""Verde House — identity asset builder. Emits every mark in the system."""
import sys, os, math, json
sys.path.insert(0, '/home/user/stridemap/brand/verde-house/tools')
import symbol as SYM, wordmark as WM, letters as T
from geom import sample_pad

OUT = "/home/user/stridemap/brand/verde-house"

GREEN = "#1A3925"; WARM = "#F4F1E9"; BLACK = "#131614"; WHITE = "#FFFFFF"

SYM.PAD.update(dict(Rt=29.0, Rb=17.5, WmR=33.0))
COMP = dict(theta_main=-6.0, theta_up=34.0, theta_left=-27.0,
            up_anchor=0.06, left_anchor=0.24)

MEASURE  = 531.5      # wordmark measure, in cap-height units x100
LEADING  = 116.0      # baseline to baseline
SYM_H    = 330.0      # symbol height = 3.30 cap heights
LOCK_GAP = 62.0       # clear channel between symbol and wordmark

# ------------------------------------------------------------------ symbol
def symbol(height=SYM_H, gap=2.55):
    paths, m = SYM.build(gap=gap, **COMP)
    x0, y0, x1, y1 = m['bbox']
    s = height / (y1 - y0)
    tr = f"translate({-x0*s:.4f} {-y0*s:.4f}) scale({s:.6f})"
    return dict(paths=paths, transform=tr, w=(x1-x0)*s, h=height,
                cx=(m['cx']-x0)*s, cy=(m['cy']-y0)*s, gap=gap*s,
                shares=m['shares'], raw=m)

def sym_svg(sy, fill=GREEN, dx=0.0, dy=0.0):
    inner = "".join(f'<path d="{d}"/>' for d in sy['paths'])
    return f'<g fill="{fill}" transform="translate({dx:.4f} {dy:.4f}) {sy["transform"]}">{inner}</g>'

# ------------------------------------------------------------------ monogram
def monogram(vw=67.0, tL=15.4):
    """VH — the V's right arm and the H's left stem are one shared stroke."""
    s = T.STEM; C = T.C
    a = vw - s                      # shared stem left edge
    hw = 86.0                       # H width measured from the shared stem
    bar_y = 0.476*C - T.BAR/2
    # V left arm: outer edge (0,0)->(a,C) ; inner edge (tL,0)->(a+s,C)
    tL = 15.6
    d = [f"M0 0L{tL} 0L{a+s} {C}L{a} {C}Z"]                       # left diagonal
    d.append(f"M{a} 0L{a+s} 0L{a+s} {C}L{a} {C}Z")                # shared stem
    d.append(f"M{a+hw-s} 0L{a+hw} 0L{a+hw} {C}L{a+hw-s} {C}Z")    # H right stem
    d.append(f"M{a+s} {bar_y}L{a+hw-s} {bar_y}L{a+hw-s} {bar_y+T.BAR}L{a+s} {bar_y+T.BAR}Z")
    return dict(d="".join(d), w=a+hw, h=C)

def monogram_pair():
    """The unligatured alternative: V and H set tight, same measure discipline."""
    T.build()
    gap = 26.0
    return dict(parts=[('V', 0.0), ('H', T.W['V']+gap)], w=T.W['V']+gap+T.W['H'], h=T.C)

# ------------------------------------------------------------------ lockups
def primary(sym_h=SYM_H, gap=LOCK_GAP, measure=MEASURE, leading=LEADING):
    sy = symbol(sym_h)
    b = WM.block(measure=measure, leading=leading)
    wx = sy['w'] + gap - b['x0']            # wordmark origin so its ink starts at sym.w+gap
    # optical centre: halfway between the symbol's bounding centre and its centre of
    # ink. Pure bbox centring reads top-heavy; pure mass centring reads sunk.
    ctr = 0.5*sy['cy'] + 0.5*sy['h']/2
    wy = ctr - (leading + T.C)/2
    top = min(0.0, wy - T.OV)
    bot = max(sy['h'], wy + leading + T.C + T.OV)
    return dict(sy=sy, b=b, wx=wx, wy=wy,
                w=wx + b['x0'] + b['width'], h=bot-top, top=top, bot=bot)

def horizontal(sym_h=None, gap=LOCK_GAP, measure=MEASURE):
    """VERDE HOUSE on one line. Word space = 2x the letter gap."""
    T.build()
    pl1, g = WM.line("VERDE", 0, 0)   # placeholder to read the gap
    # set both words with the block's own tracking, then space them
    m1 = measure * 0.0
    l1, gap1 = WM.line("VERDE", 404.0 + 4*32.32, -WM.OVERHANG)
    wspace = gap1 * 1.95
    x2 = l1[-1][1] + T.W['E'] + wspace
    l2, gap2 = WM.line("HOUSE", 405.5 + 4*32.32, x2)
    total = l2[-1][1] + T.W['E']
    sh = sym_h or (T.C * 1.86)
    sy = symbol(sh)
    wx = sy['w'] + gap + WM.OVERHANG
    wy = (0.5*sy['cy'] + 0.5*sy['h']/2) - T.C/2
    top = min(0.0, wy - T.OV); bot = max(sy['h'], wy + T.C + T.OV)
    return dict(sy=sy, l1=l1, l2=l2, wx=wx, wy=wy, w=wx + total, h=bot-top, top=top)

# ------------------------------------------------------------------ emit
def svg(vb, body, bg=None, extra=""):
    x, y, w, h = vb
    b = f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{bg}"/>' if bg else ""
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{x:.3f} {y:.3f} {w:.3f} {h:.3f}" '
            f'width="{w:.1f}" height="{h:.1f}"{extra}>{b}{body}</svg>')

def primary_body(p, fill=GREEN):
    return (sym_svg(p['sy'], fill) +
            f'<g transform="translate({p["wx"]:.4f} {p["wy"]:.4f})">{WM.render(p["b"], fill)}</g>')

def horizontal_body(hz, fill=GREEN):
    T.build()
    g = "".join(f'<g transform="translate({x:.3f} 0)">{T.glyph_svg(c, fill)}</g>'
                for c, x in hz['l1'] + hz['l2'])
    return sym_svg(hz['sy'], fill) + f'<g transform="translate({hz["wx"]:.4f} {hz["wy"]:.4f})">{g}</g>'

# ------------------------------------------------------------------ assets
def _f(name, content):
    path = os.path.join(OUT, name)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "w").write(content)
    return name

def icon_svg(size=512, radius=None, bg=GREEN, fg=WARM, frac=0.60, micro=False):
    sy = symbol(size*frac, gap=4.2 if micro else 2.55)
    dx = size/2 - sy['cx']; dy = size/2 - sy['cy']
    r = f' rx="{radius}"' if radius else ""
    return (f'<rect width="{size}" height="{size}"{r} fill="{bg}"/>' + sym_svg(sy, fg, dx, dy))

def emit():
    T.build()
    P = 0
    files = []
    # --- symbol
    for nm, gp in (("symbol", 2.55), ("symbol-micro", 4.2)):
        sy = symbol(1000, gap=gp)
        for suf, fill, bg in (("", GREEN, None), ("-reversed", WARM, GREEN), ("-black", BLACK, None)):
            files.append(_f(f"svg/{nm}{suf}.svg",
                            svg((0, 0, sy['w'], sy['h']), sym_svg(sy, fill), bg)))
    # --- wordmark only
    b = WM.block(measure=MEASURE, leading=LEADING)
    files.append(_f("svg/wordmark-stacked.svg",
        svg((b['x0'], -T.OV, b['width'], b['height']+2*T.OV),
            f'<g transform="translate(0 0)">{WM.render(b)}</g>')))
    hz = horizontal(sym_h=T.C*1.86, gap=52)
    # --- lockups
    p = primary()
    for suf, fill, bg in (("", GREEN, None), ("-reversed", WARM, GREEN), ("-black", BLACK, None),
                          ("-warm", GREEN, WARM)):
        files.append(_f(f"svg/lockup-primary{suf}.svg",
            svg((0, p['top'], p['w'], p['h']), primary_body(p, fill), bg)))
        files.append(_f(f"svg/lockup-horizontal{suf}.svg",
            svg((0, hz['top'], hz['w'], hz['h']), horizontal_body(hz, fill), bg)))
    # --- monogram
    m = monogram()
    for suf, fill, bg in (("", GREEN, None), ("-reversed", WARM, GREEN), ("-black", BLACK, None)):
        files.append(_f(f"svg/monogram-vh{suf}.svg",
            svg((0, 0, m['w'], m['h']), f'<path d="{m["d"]}" fill="{fill}"/>', bg)))
    files.append(_f("svg/monogram-vh-square.svg",
        svg((0, 0, 200, 200),
            f'<rect width="200" height="200" rx="42" fill="{GREEN}"/>'
            f'<g transform="translate({(200-m["w"]*0.86)/2:.3f} {(200-100*0.86)/2:.3f}) scale(0.86)">'
            f'<path d="{m["d"]}" fill="{WARM}"/></g>')))
    # --- icons
    files.append(_f("svg/app-icon.svg", svg((0, 0, 512, 512), icon_svg(512, 112))))
    files.append(_f("svg/avatar.svg", svg((0, 0, 512, 512), icon_svg(512, 256))))
    files.append(_f("svg/favicon-32.svg", svg((0, 0, 32, 32), icon_svg(32, 6, frac=0.66, micro=True))))
    files.append(_f("svg/favicon-16.svg", svg((0, 0, 16, 16),
        f'<rect width="16" height="16" rx="3" fill="{GREEN}"/>'
        f'<g transform="translate({(16-m["w"]*0.088)/2:.3f} {(16-100*0.088)/2:.3f}) scale(0.088)">'
        f'<path d="{m["d"]}" fill="{WARM}"/></g>')))
    files.append(_f("svg/favicon-16-symbol.svg", svg((0, 0, 16, 16), icon_svg(16, 3, frac=0.70, micro=True))))
    files.append(_f("svg/favicon-24.svg", svg((0, 0, 24, 24), icon_svg(24, 5, frac=0.68, micro=True))))
    return files
