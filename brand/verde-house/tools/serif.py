"""Verde House — display serif capitals: V E R D  H O U S.

The reference wordmark measured a hairline at roughly 5 % of cap height against a
13:1 contrast. That cannot be stitched, debossed, or rendered below about 24 px.
These keep the high-contrast character at a reproducible 2.3:1, with a hairline
no thinner than 5.5 % of cap height.
"""
import math

C     = 100.0
STEM  = 12.6      # thick stroke
HAIR  = 5.5       # thin stroke — the reproduction floor
SR    = 13.2      # round letters, side (max) stroke
RO    = 5.8       # round letters, top/bottom (min) stroke
SERIF = 4.2       # serif thickness
SW    = 7.4       # serif projection each side of a stem
OV    = 1.2
K     = 0.5620

W = dict(V=78.0, E=64.0, R=70.0, D=76.0, H=78.0, O=78.0, U=76.0, S=58.0)

def _n(v): return f"{v:.3f}".rstrip('0').rstrip('.')
def M(p): return f"M{_n(p[0])} {_n(p[1])}"
def L(p): return f"L{_n(p[0])} {_n(p[1])}"
def Cv(a,b,p): return f"C{_n(a[0])} {_n(a[1])} {_n(b[0])} {_n(b[1])} {_n(p[0])} {_n(p[1])}"
def rect(x,y,w,h): return f"M{_n(x)} {_n(y)}L{_n(x+w)} {_n(y)}L{_n(x+w)} {_n(y+h)}L{_n(x)} {_n(y+h)}Z"

def serif(cx, y, half=None, top=True, w=None):
    """A flat serif centred on cx, sitting on (or under) the line y."""
    half = half or (STEM/2 + SW)
    h = SERIF
    return rect(cx-half, y if top else y-h, 2*half, h)

def stem(cx, y0, y1, w=STEM, ser_top=True, ser_bot=True, half=None):
    d = rect(cx-w/2, y0, w, y1-y0)
    if ser_top: d += serif(cx, y0, half, True)
    if ser_bot: d += serif(cx, y1, half, False)
    return d

def ellipse(cx, cy, rx, ry, k, cw=True):
    ox, oy = rx*k, ry*k
    pts = [(cx,cy-ry),(cx+rx,cy),(cx,cy+ry),(cx-rx,cy)]
    hs  = [((cx+ox,cy-ry),(cx+rx,cy-oy)),((cx+rx,cy+oy),(cx+ox,cy+ry)),
           ((cx-ox,cy+ry),(cx-rx,cy+oy)),((cx-rx,cy-oy),(cx-ox,cy-ry))]
    if not cw:
        pts = [pts[0]] + pts[1:][::-1]
        hs = [(b,a) for a,b in hs][::-1]
    d = [M(pts[0])]
    for i in range(4): d.append(Cv(hs[i][0], hs[i][1], pts[(i+1)%4]))
    return "".join(d)+"Z"

# ---------------------------------------------------------------- H E
def glyph_H():
    w = W['H']; yb = 0.478*C - HAIR/2
    return (stem(STEM/2+SW/1.0, 0, C) + stem(w-STEM/2-SW/1.0, 0, C)
            + rect(STEM/2+SW, yb, w-2*(STEM/2+SW), HAIR))

def glyph_E():
    w = W['E']; ym = 0.476*C - HAIR/2; x = STEM/2+SW
    return (rect(x-STEM/2, 0, STEM, C)
            + serif(x, 0, STEM/2+SW, True) + serif(x, C, STEM/2+SW, False)
            + rect(x-STEM/2, 0, w-(x-STEM/2), HAIR)
            + rect(x-STEM/2, ym, w-(x-STEM/2)-5.5, HAIR)
            + rect(x-STEM/2, C-HAIR, w-(x-STEM/2), HAIR)
            + rect(w-SERIF, 0, SERIF, 9.5) + rect(w-SERIF, C-9.5, SERIF, 9.5)
            + rect(w-5.5-SERIF, ym, SERIF, 8.0))

# ---------------------------------------------------------------- O
def glyph_O():
    w = W['O']; cx, cy = w/2, C/2
    return (ellipse(cx, cy, w/2, C/2+OV, K, True)
            + ellipse(cx, cy, w/2-SR, C/2+OV-RO, K+0.012, False))

# ---------------------------------------------------------------- U
def glyph_U():
    w = W['U']; rx = w/2; ry = rx*0.90
    yb = C+OV-ry; irx, iry = rx-SR, ry-RO
    iyb = C+OV-RO-iry
    o = [M((0,0)), L((0,yb)),
         Cv((0,yb+ry*K),(rx-rx*K,C+OV),(rx,C+OV)),
         Cv((rx+rx*K,C+OV),(w,yb+ry*K),(w,yb)), L((w,0)),
         L((w-STEM,0)), L((w-STEM,iyb)),
         Cv((w-STEM,iyb+iry*K),(rx+irx*K,C+OV-RO),(rx,C+OV-RO)),
         Cv((rx-irx*K,C+OV-RO),(STEM,iyb+iry*K),(STEM,iyb)), L((STEM,0)), "Z"]
    return ("".join(o) + serif(STEM/2, 0, STEM/2+SW, True)
            + serif(w-STEM/2, 0, STEM/2+SW, True))

# ---------------------------------------------------------------- D
def glyph_D():
    w = W['D']; x = STEM/2+SW; sh = 0.34*(w-STEM)+STEM
    cy = C/2; ry = C/2
    isx = sh-1.2
    o = [M((STEM,0)), L((sh,0)),
         Cv((sh+(w-sh)*K,0),(w,cy-ry*K),(w,cy)),
         Cv((w,cy+ry*K),(sh+(w-sh)*K,C),(sh,C)), L((STEM,C)), "Z",
         M((STEM,RO)), L((STEM,C-RO)), L((isx,C-RO)),
         Cv((isx+(w-SR-isx)*K,C-RO),(w-SR,cy+(ry-RO)*K),(w-SR,cy)),
         Cv((w-SR,cy-(ry-RO)*K),(isx+(w-SR-isx)*K,RO),(isx,RO)), "Z"]
    return (rect(0,0,STEM,C) + "".join(o)
            + serif(STEM/2, 0, STEM/2+SW, True) + serif(STEM/2, C, STEM/2+SW, False))

# ---------------------------------------------------------------- R
def glyph_R(bowl=52.0, bw=62.0, legx=None, legw=13.4, legtop=47.0, legspring=34.0):
    w = W['R']; legx = w if legx is None else legx
    sh = 0.36*(bw-STEM)+STEM; cy = bowl/2; ry = cy; isx = sh-1.2
    b = [M((STEM,0)), L((sh,0)),
         Cv((sh+(bw-sh)*K,0),(bw,cy-ry*K),(bw,cy)),
         Cv((bw,cy+ry*K),(sh+(bw-sh)*K,bowl),(sh,bowl)), L((STEM,bowl)), "Z",
         M((STEM,RO)), L((STEM,bowl-RO)), L((isx,bowl-RO)),
         Cv((isx+(bw-SR-isx)*K,bowl-RO),(bw-SR,cy+(ry-RO)*K),(bw-SR,cy)),
         Cv((bw-SR,cy-(ry-RO)*K),(isx+(bw-SR-isx)*K,RO),(isx,RO)), "Z"]
    leg = [M((legspring,legtop)), L((legspring+legw,legtop)),
           L((legx,C)), L((legx-legw,C)), "Z"]
    return (rect(0,0,STEM,C) + "".join(b) + "".join(leg)
            + serif(STEM/2, 0, STEM/2+SW, True) + serif(STEM/2, C, STEM/2+SW, False)
            + serif(legx-legw/2, C, legw/2+SW*0.6, False))

# ---------------------------------------------------------------- V
def glyph_V(tL=13.6, tR=6.6, apex=0.497, flat=1.4):
    w = W['V']; ay = C+1.0; ax = w*apex
    def inter(a,b):
        (x1,y1),(x2,y2)=a; (x3,y3),(x4,y4)=b
        d=(x1-x2)*(y3-y4)-(y1-y2)*(x3-x4)
        px=((x1*y2-y1*x2)*(x3-x4)-(x1-x2)*(x3*y4-y3*x4))/d
        py=((x1*y2-y1*x2)*(y3-y4)-(y1-y2)*(x3*y4-y3*x4))/d
        return (px,py)
    iL=((tL,0),(ax-flat/2+tL,ay)); iR=((w-tR,0),(ax+flat/2-tR,ay))
    ia=inter(iL,iR)
    body = "".join([M((0,0)),L((tL,0)),L(ia),L((w-tR,0)),L((w,0)),
                    L((ax+flat/2,ay)),L((ax-flat/2,ay)),"Z"])
    return body + serif(tL/2, 0, tL/2+SW, True) + serif(w-tR/2, 0, tR/2+SW*0.8, True)

# ---------------------------------------------------------------- S
S_GUIDE = [(52.5,20.5),(42.0,7.6),(29.0,3.4),(15.0,8.0),(6.0,19.5),(8.4,29.5),(17.0,35.0)]

def _catmull(pts, n=26):
    P=[pts[0]]+list(pts)+[pts[-1]]; out=[]
    for i in range(len(P)-3):
        p0,p1,p2,p3=P[i],P[i+1],P[i+2],P[i+3]
        for j in range(n):
            t=j/n; t2,t3=t*t,t*t*t
            out.append((0.5*((2*p1[0])+(-p0[0]+p2[0])*t+(2*p0[0]-5*p1[0]+4*p2[0]-p3[0])*t2+(-p0[0]+3*p1[0]-3*p2[0]+p3[0])*t3),
                        0.5*((2*p1[1])+(-p0[1]+p2[1])*t+(2*p0[1]-5*p1[1]+4*p2[1]-p3[1])*t2+(-p0[1]+3*p1[1]-3*p2[1]+p3[1])*t3)))
    out.append(pts[-1]); return out

def _offsets(cl):
    lft,rgt=[],[]
    for i,p in enumerate(cl):
        a=cl[max(i-1,0)]; b=cl[min(i+1,len(cl)-1)]
        tx,ty=b[0]-a[0],b[1]-a[1]; m=math.hypot(tx,ty) or 1; tx,ty=tx/m,ty/m
        h=(RO+(SR-RO)*abs(ty))/2
        nx,ny=-ty,tx
        lft.append((p[0]+h*nx,p[1]+h*ny)); rgt.append((p[0]-h*nx,p[1]-h*ny))
    return lft,rgt

def _cut(poly,y,keep_after):
    rng=range(len(poly)-1) if keep_after else range(len(poly)-2,-1,-1)
    for i in rng:
        y0,y1=poly[i][1],poly[i+1][1]
        if (y0-y)*(y1-y)<=0 and y0!=y1:
            t=(y-y0)/(y1-y0)
            pt=(poly[i][0]+(poly[i+1][0]-poly[i][0])*t,y)
            return ([pt]+poly[i+1:]) if keep_after else (poly[:i+1]+[pt])
    return poly

def _smooth(pts, first=True):
    d=[M(pts[0])] if first else [L(pts[0])]
    P=[pts[0]]+list(pts)+[pts[-1]]
    for i in range(1,len(P)-2):
        p0,p1,p2,p3=P[i-1],P[i],P[i+1],P[i+2]
        d.append(Cv((p1[0]+(p2[0]-p0[0])/6,p1[1]+(p2[1]-p0[1])/6),
                    (p2[0]-(p3[0]-p1[0])/6,p2[1]-(p3[1]-p1[1])/6), p2))
    return "".join(d)

def glyph_S(y_cut=12.0, step=9):
    w=W['S']; cx,cy=w/2,C/2
    mir=lambda p:(2*cx-p[0],2*cy-p[1])
    g=list(S_GUIDE)
    guide=g+[(cx,cy)]+[mir(q) for q in reversed(g)]
    cl=_catmull(guide,26)
    lft,rgt=_offsets(cl)
    lft=_cut(_cut(lft,y_cut,True),C-y_cut,False)
    rgt=_cut(_cut(rgt,y_cut,True),C-y_cut,False)
    lft=lft[::step]+[lft[-1]]; rgt=rgt[::step]+[rgt[-1]]
    return _smooth(lft)+_smooth(rgt[::-1],False)+"Z"

GLYPH={}
def build():
    GLYPH.update(H=glyph_H(), E=glyph_E(), O=glyph_O(), U=glyph_U(),
                 D=glyph_D(), R=glyph_R(), V=glyph_V(), S=glyph_S())
    return GLYPH

def glyph_svg(ch, fill="#1A3925"):
    build()
    return f'<path d="{GLYPH[ch]}" fill="{fill}"/>'

# ---------------------------------------------------------------- extended set
def ring(cx, cy, rx, ry, irx, iry, a0, a1, ccw=True):
    """Annular sector between two ellipses, degrees, y down."""
    r0, r1 = math.radians(a0), math.radians(a1)
    P  = lambda a, X, Y: (cx + X*math.cos(a), cy + Y*math.sin(a))
    span = (r0 - r1) % (2*math.pi) if ccw else (r1 - r0) % (2*math.pi)
    la = 1 if span > math.pi else 0
    sw = 0 if ccw else 1
    o0, o1 = P(r0, rx, ry), P(r1, rx, ry)
    i0, i1 = P(r0, irx, iry), P(r1, irx, iry)
    return (f"M{_n(o0[0])} {_n(o0[1])}"
            f"A{_n(rx)} {_n(ry)} 0 {la} {sw} {_n(o1[0])} {_n(o1[1])}"
            f"L{_n(i1[0])} {_n(i1[1])}"
            f"A{_n(irx)} {_n(iry)} 0 {la} {1-sw} {_n(i0[0])} {_n(i0[1])}Z")

W.update(A=80.0, C=72.0, N=80.0, I=30.0, M=98.0, G=76.0, Y=76.0)

def glyph_A(tL=6.4, tR=13.8, flat=1.6, bar=0.70):
    w = W['A']; ax = w*0.5
    def inter(a,b):
        (x1,y1),(x2,y2)=a; (x3,y3),(x4,y4)=b
        d=(x1-x2)*(y3-y4)-(y1-y2)*(x3-x4)
        return (((x1*y2-y1*x2)*(x3-x4)-(x1-x2)*(x3*y4-y3*x4))/d,
                ((x1*y2-y1*x2)*(y3-y4)-(y1-y2)*(x3*y4-y3*x4))/d)
    oL=((ax-flat/2,0),(0,C)); oR=((ax+flat/2,0),(w,C))
    iL=((ax-flat/2+tL,0),(tL,C)); iR=((ax+flat/2-tR,0),(w-tR,C))
    ia=inter(iL,iR)
    body="".join([M((ax-flat/2,0)),L((ax+flat/2,0)),L((w,C)),L((w-tR,C)),
                  L(ia),L((tL,C)),L((0,C)),"Z"])
    xb = lambda e,y: e[0][0]+(e[1][0]-e[0][0])*(y-e[0][1])/(e[1][1]-e[0][1])
    yb = bar*C
    return (body + rect(xb(iL,yb), yb, xb(iR,yb)-xb(iL,yb), HAIR)
            + serif(tL/2+2.5, C, tL/2+SW, False) + serif(w-tR/2-1.5, C, tR/2+SW, False))

def glyph_C():
    """Radial terminal cuts — a flat serif on a curve this open reads as a snag."""
    w=W['C']; cx,cy=w/2,C/2
    return ring(cx, cy, w/2, C/2+OV, w/2-SR, C/2+OV-RO, -58, 58)

def glyph_N(st=7.6, dg=13.4):
    w=W['N']
    return (rect(0,0,st,C) + rect(w-st,0,st,C)
            + "".join([M((st*0.2,0)),L((st*0.2+dg,0)),L((w-st*0.2,C)),L((w-st*0.2-dg,C)),"Z"])
            + serif(st/2,0,st/2+SW,True) + serif(st/2,C,st/2+SW,False)
            + serif(w-st/2,0,st/2+SW,True) + serif(w-st/2,C,st/2+SW,False))

def glyph_I():
    w=W['I']; return stem(w/2,0,C)

def glyph_M(st=7.4, dg=12.2, flat=1.6):
    w=W['M']
    return (rect(0,0,st,C) + rect(w-st,0,st,C)
            + "".join([M((st*0.25,0)),L((st*0.25+dg,0)),L((w/2+flat/2,C-2)),L((w/2-flat/2,C-2)),"Z"])
            + "".join([M((w-st*0.25-dg,0)),L((w-st*0.25,0)),L((w/2+flat/2,C-2)),L((w/2-flat/2,C-2)),"Z"])
            + serif(st/2,0,st/2+SW,True) + serif(st/2,C,st/2+SW,False)
            + serif(w-st/2,0,st/2+SW,True) + serif(w-st/2,C,st/2+SW,False))

def glyph_G():
    w=W['G']; cx,cy=w/2,C/2
    d = ring(cx, cy, w/2, C/2+OV, w/2-SR, C/2+OV-RO, -58, 32)
    barY = cy - HAIR/2
    spur_top = cy
    spur_h = (C/2+OV)*math.sin(math.radians(32)) + 2
    return (d + rect(cx+5, barY, w-(cx+5), HAIR)
            + rect(w-SR, spur_top, SR, spur_h))

def glyph_Y(tL=13.2, tR=6.6, mid=0.52, flat=1.4):
    w=W['Y']; my=mid*C; ax=w*0.5
    def inter(a,b):
        (x1,y1),(x2,y2)=a; (x3,y3),(x4,y4)=b
        d=(x1-x2)*(y3-y4)-(y1-y2)*(x3-x4)
        return (((x1*y2-y1*x2)*(x3-x4)-(x1-x2)*(x3*y4-y3*x4))/d,
                ((x1*y2-y1*x2)*(y3-y4)-(y1-y2)*(x3*y4-y3*x4))/d)
    iL=((tL,0),(ax-flat/2+tL,my+8)); iR=((w-tR,0),(ax+flat/2-tR,my+8))
    ia=inter(iL,iR)
    vee="".join([M((0,0)),L((tL,0)),L(ia),L((w-tR,0)),L((w,0)),
                 L((ax+flat/2,my)),L((ax-flat/2,my)),"Z"])
    return (vee + rect(ax-STEM/2, my-1, STEM, C-my+1)
            + serif(tL/2,0,tL/2+SW,True) + serif(w-tR/2,0,tR/2+SW*0.8,True)
            + serif(ax,C,STEM/2+SW,False))

def build_all():
    build()
    GLYPH.update(A=glyph_A(), C=glyph_C(), N=glyph_N(), I=glyph_I(),
                 M=glyph_M(), G=glyph_G(), Y=glyph_Y())
    return GLYPH
