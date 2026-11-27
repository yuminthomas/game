"""Part-based pixel sprite generator: original 'dungeon slasher'-style swordswoman.
Faces RIGHT. Canvas 48x48, feet on y=GROUND."""
import math, sys
import numpy as np
from PIL import Image

W, H, GROUND = 48, 48, 46

def hexc(h):
    h = h.lstrip('#'); return np.array([int(h[i:i+2], 16) for i in (0, 2, 4)] + [255], np.uint8)

C = {k: hexc(v) for k, v in dict(
    out='1c1220',
    hair='e2b450', hairD='a7742f', hairL='f6d880', hairX='fff4c4',
    skin='f6d0b1', skinD='dca084', blush='ec8d8d',
    eye='e8434f', eyeD='8c1d2e', white='ffffff',
    armor='2f5566', armorD='1f3644', armorL='4f8296',
    plate='9aa3bd', plateD='6c7392', plateL='d4daea',
    scarf='c8323f', scarfD='8e1f2e', scarfL='ef5a5a',
    belt='6b4630', beltL='a0703f', gold='f0c050', goldD='b0802a',
    leg='4a3a4e', legD='2e2434', legL='6c5873',
    boot='8a5c3c', bootD='5a3a2a', bootL='b98354',
    blade='dfe6f2', bladeD='93a0b8', bladeL='ffffff',
).items()}

# ---------- layer helpers ----------
class Layer:
    def __init__(s): s.a = np.zeros((H, W, 4), np.uint8)
    def px(s, x, y, c):
        x, y = int(round(x)), int(round(y))
        if 0 <= x < W and 0 <= y < H: s.a[y, x] = C[c] if isinstance(c, str) else c
    def mask(s): return s.a[..., 3] > 0

def line_pts(x0, y0, x1, y1):
    x0, y0, x1, y1 = map(lambda v: int(round(v)), (x0, y0, x1, y1))
    pts = []; dx, dy = abs(x1-x0), -abs(y1-y0); sx = 1 if x0 < x1 else -1; sy = 1 if y0 < y1 else -1; e = dx+dy
    while True:
        pts.append((x0, y0))
        if x0 == x1 and y0 == y1: break
        e2 = 2*e
        if e2 >= dy: e += dy; x0 += sx
        if e2 <= dx: e += dx; y0 += sy
    return pts

def stroke(L, pts, w, c):
    """thick polyline; w can be list per point (taper)"""
    for i in range(len(pts)-1):
        seg = line_pts(*pts[i], *pts[i+1])
        for j, (x, y) in enumerate(seg):
            ww = w if not isinstance(w, list) else w[i] + (w[i+1]-w[i]) * j / max(1, len(seg)-1)
            ww = max(1, int(round(ww)))
            o = -(ww-1)//2
            for dy in range(ww):
                for dx in range(ww):
                    if ww >= 3 and (dx in (0, ww-1)) and (dy in (0, ww-1)): continue
                    L.px(x+o+dx, y+o+dy, c)

def shade(L, dark, light, base=None):
    m = L.mask(); a = L.a.copy()
    up = np.zeros_like(m); up[1:] = m[:-1]
    dn = np.zeros_like(m); dn[:-1] = m[1:]
    lf = np.zeros_like(m); lf[:, 1:] = m[:, :-1]
    rt = np.zeros_like(m); rt[:, :-1] = m[:, 1:]
    sel = m if base is None else m & np.all(L.a == C[base], -1)
    d = sel & (~lf | ~dn); l = sel & ~d & (~up | ~rt)
    a[d] = C[dark]; a[l] = C[light]; L.a = a

def outline(L, col='out'):
    m = L.mask(); o = np.zeros_like(m)
    o[1:] |= m[:-1]; o[:-1] |= m[1:]; o[:, 1:] |= m[:, :-1]; o[:, :-1] |= m[:, 1:]
    o &= ~m; L.a[o] = C[col]

def comp(dst, L):
    m = L.mask(); dst.a[m] = L.a[m]

def ik(hx, hy, fx, fy, a, b, bend):
    """2-bone IK; bend=+1 knee toward +x, -1 toward -x"""
    dx, dy = fx-hx, fy-hy; d = math.hypot(dx, dy)
    d2 = min(d, a+b-0.01)
    if d > d2: fx, fy = hx+dx/d*d2, hy+dy/d*d2; d = d2
    x = (a*a - b*b + d*d) / (2*d); h = math.sqrt(max(0, a*a - x*x))
    ux, uy = dx/d, dy/d
    mx, my = hx+ux*x, hy+uy*x
    k1 = (mx - uy*h, my + ux*h); k2 = (mx + uy*h, my - ux*h)
    k = k1 if (k1[0]-k2[0])*bend > 0 else k2
    return k, (fx, fy)

# ---------- head (hand-pixeled, 18x17, faces right) ----------
HEAD = [
    "......oooooo........",
    "....ooHHHHHHoo......",
    "...oHHHXLLHHHHoo....",
    "..oHHHLLLHHHHHHHo...",
    ".oHHHHHHHHHHHHHHHo..",
    ".oHHHHHHHHHHHHHHHHo.",
    "oHHHHHHHHHHHHHHHHHo.",
    "oHHHHHHHHHHHHdHHHHHo",
    "oHHHHHHHHHdHHsdHHdHo",
    "oHHHHHHHdHsssdsssdHo",
    "odHHHHHdHsoosssoosso",
    "odHHHHHdHseWsssWesso",
    ".odHHHHdHseessseesso",
    ".odHHHHdHsEEsssEEsso",
    "..odHHdHdbssssssbso.",
    "...oddoHdsssssmsso..",
    "....oo.odSssssssso..",
    "........oSSssoo.....",
    ".........oooo.......",
]
HMAP = {'o': 'out', 'H': 'hair', 'd': 'hairD', 'L': 'hairL', 'X': 'hairX', 's': 'skin', 'S': 'skinD',
        'e': 'eye', 'E': 'eyeD', 'W': 'white', 'b': 'blush', 'm': 'skinD'}
HEAD_NECK = (11, 17)  # pixel in head map that sits on the neck point

def draw_head(dst, nx, ny):
    L = Layer()
    for y, row in enumerate(HEAD):
        for x, ch in enumerate(row):
            if ch in HMAP: L.px(nx - HEAD_NECK[0] + x, ny - HEAD_NECK[1] + y, HMAP[ch])
    comp(dst, L)
    return nx - HEAD_NECK[0], ny - HEAD_NECK[1]  # head origin

# ---------- full character ----------
def chain(ax, ay, n, seg, base_ang, wave, phase, freq=0.9):
    pts = [(ax, ay)]; x, y = ax, ay
    for i in range(1, n+1):
        ang = base_ang + wave * math.sin(phase - i*freq) * (i/n)
        x += math.cos(ang)*seg; y += math.sin(ang)*seg; pts.append((x, y))
    return pts

def character(p):
    """p: dict with hipx, hipy, lean, feet[(x,y) near, far], hands[(x,y) near, far] (rel shoulder),
       hair_phase, hair_ang, hair_wave, scarf_phase, scarf_ang, scarf_wave, sword_ang, breath, head_dy"""
    cv = Layer()
    hx, hy, lean = p['hipx'], p['hipy'], p['lean']
    neck = (hx + lean, hy - 10 + p.get('breath', 0))
    tx = lambda y: hx + lean * (hy - y) / (hy - neck[1])
    sh_near = (tx(neck[1]+2) + 2.5, neck[1] + 2)
    sh_far = (tx(neck[1]+2) - 2.5, neck[1] + 2)
    head_n = (neck[0], neck[1] + p.get('head_dy', 0))
    hox, hoy = head_n[0] - HEAD_NECK[0], head_n[1] - HEAD_NECK[1]

    # scarf tail (behind everything)
    S = Layer()
    sp = chain(neck[0] - 2, neck[1] + 1, 6, 2.2, p['scarf_ang'], p['scarf_wave'], p['scarf_phase'])
    stroke(S, sp, [3, 3, 3, 3, 2, 2, 2], 'scarf'); shade(S, 'scarfD', 'scarfL'); outline(S); comp(cv, S)
    # ponytail
    P = Layer()
    pp = chain(hox + 3, hoy + 6, 7, 2.4, p['hair_ang'], p['hair_wave'], p['hair_phase'])
    stroke(P, pp, [6, 5, 5, 4, 3, 3, 2, 1], 'hair'); shade(P, 'hairD', 'hairL'); outline(P); comp(cv, P)

    def leg(L, hip, foot, dark):
        (kx, ky), (fx, fy) = ik(hip[0], hip[1], foot[0], foot[1], 6.6, 6.6, +1)
        cl = 'legD' if dark else 'leg'
        stroke(L, [hip, (kx, ky)], 4, cl)
        # shin / boot
        mid = (kx + (fx-kx)*0.35, ky + (fy-ky)*0.35)
        stroke(L, [(kx, ky), mid], 3, cl)
        bc = 'bootD' if dark else 'boot'
        stroke(L, [mid, (fx, fy)], 3, bc)
        # toe pointing forward-ish along ground; lifted feet point down-back
        toe = (fx + 2, fy) if fy >= GROUND - 1 else (fx + 1, fy + 1)
        stroke(L, [(fx, fy), toe], 2, bc)
        if not dark:
            shade(L, 'legD', 'legL', 'leg'); shade(L, 'bootD', 'bootL', 'boot')
            L.px(kx, ky-1, 'legL')
        outline(L)

    def arm(L, sh, hand, dark, sword=None):
        (ex, ey), (fx, fy) = ik(sh[0], sh[1], sh[0]+hand[0], sh[1]+hand[1], 4.3, 4.3, -1)
        if sword is not None:
            a = sword; bl = 11
            tip = (fx + math.cos(a)*bl, fy + math.sin(a)*bl)
            base = (fx + math.cos(a)*2, fy + math.sin(a)*2)
            pom = (fx - math.cos(a)*2, fy - math.sin(a)*2)
            B = Layer(); stroke(B, [base, tip], [3, 2], 'blade'); shade(B, 'bladeD', 'bladeL')
            stroke(B, [pom, (fx, fy)], 2, 'belt')
            ga = a + math.pi/2
            stroke(B, [(base[0]+math.cos(ga)*2, base[1]+math.sin(ga)*2), (base[0]-math.cos(ga)*2, base[1]-math.sin(ga)*2)], 1, 'gold')
            outline(B); comp(L, B)
        A = Layer()
        stroke(A, [sh, (ex, ey)], 3, 'armorD' if dark else 'armor')
        stroke(A, [(ex, ey), (fx, fy)], 3, 'skinD' if dark else 'skin')
        stroke(A, [((ex+fx)/2+(fx-ex)*0.15, (ey+fy)/2+(fy-ey)*0.15), (fx, fy)], 3, 'armorD' if dark else 'armorL')  # gauntlet
        if not dark: shade(A, 'armorD', 'armorL', 'armor')
        outline(A); comp(L, A)

    # far arm & far leg
    FA = Layer(); arm(FA, sh_far, p['hands'][1], True); comp(cv, FA)
    FL = Layer(); leg(FL, (hx - 1, hy), p['feet'][1], True); comp(cv, FL)

    # torso
    T = Layer()
    prof = {0: 4, 1: 5, 2: 5, 3: 5, 4: 4.5, 5: 4, 6: 3.5, 7: 3.5, 8: 4, 9: 4, 10: 4}
    for i in range(0, 11):
        y = neck[1] + i; c = tx(y)
        hw = prof[i] + (0.5 if i <= 4 else 0) * (p.get('breath_w', 0))
        for x in range(int(round(c - hw)), int(round(c + hw)) + 1):
            col = 'armor'
            if 2 <= i <= 6 and x >= c - 1: col = 'plate'
            if i == 8 or i == 9: col = 'belt'
            T.px(x, y, col)
    shade(T, 'armorD', 'armorL', 'armor'); shade(T, 'plateD', 'plateL', 'plate')
    bx = tx(neck[1]+8); T.px(bx + 1, neck[1]+8, 'gold'); T.px(bx + 1, neck[1]+9, 'goldD')
    outline(T); comp(cv, T)
    # coat tail: hangs behind the hips, flares back when running
    CT = Layer(); fl = p.get('flap', 0); top = (tx(hy-1) - 2, hy - 1)
    cp = chain(top[0], top[1], 4, 2.0, math.radians(100 + fl * 18), 0.25 * (1 + fl/2), p.get('flap_phase', 0), 0.8)
    stroke(CT, cp, [5, 5, 4, 4, 3], 'armorD')
    shade(CT, 'scarfD', 'armor', 'armorD')
    outline(CT); comp(cv, CT)
    # shorts
    SH = Layer()
    for i in range(0, 3):
        y = hy + i; c = hx + lean * -i / 10
        for x in range(int(round(c - 3)), int(round(c + 3)) + 1): SH.px(x, y, 'armor')
    shade(SH, 'armorD', 'armorL'); outline(SH); comp(cv, SH)
    # redraw torso on top of the coat tail
    comp(cv, T)


    NL = Layer(); leg(NL, (hx + 1, hy), p['feet'][0], False); comp(cv, NL)

    draw_head(cv, *head_n)
    # scarf wrap around neck
    SW = Layer()
    for dx in range(-3, 4): SW.px(neck[0] + dx, neck[1], 'scarf'); SW.px(neck[0] + dx, neck[1] + 1, 'scarf')
    SW.px(neck[0] - 3, neck[1] + 2, 'scarf'); SW.px(neck[0] - 2, neck[1] + 2, 'scarfD')
    shade(SW, 'scarfD', 'scarfL'); outline(SW); comp(cv, SW)

    NA = Layer(); arm(NA, sh_near, p['hands'][0], False, sword=p.get('sword')); comp(cv, NA)
    return cv.a

# ---------- animations ----------
def idle_frames():
    fr = []
    n = 6
    for f in range(n):
        t = f / n * 2 * math.pi
        b = (1 - math.cos(t)) / 2            # 0..1 breathing
        hipy = GROUND - 13 + round(b * 1)
        fr.append(character(dict(
            hipx=22, hipy=hipy, lean=1,
            breath=0 if b < 0.5 else 0, head_dy=round(b * 1.0 + (0.4 if f in (2, 3) else 0)),
            feet=[(26, GROUND), (19, GROUND)],
            hands=[(3, 6 - round(b)), (-2, 7)], sword=math.radians(-35 + 6 * b),
            hair_ang=math.radians(105), hair_wave=0.3, hair_phase=t,
            scarf_ang=math.radians(150), scarf_wave=0.45, scarf_phase=t + 1,
            flap=0, flap_phase=t)))
    return fr

def run_frames():
    fr = []
    n = 8
    # near-foot keyframes (x rel hip, y rel ground)
    FOOT = [(6, 0), (3, 0), (0, 0), (-4, -1), (-7, -4), (-4, -7), (2, -6), (6, -3)]
    BOB = [1, 2, 1, 0, 1, 2, 1, 0]
    BOB = [0, 1, 0, -1, 0, 1, 0, -1]
    for f in range(n):
        t = f / n * 2 * math.pi
        hipx, hipy = 21, GROUND - 13 + BOB[f]
        nf = FOOT[f]; ff = FOOT[(f + 4) % n]
        sw = math.cos(t)  # arm swing: near arm opposite near leg
        fr.append(character(dict(
            hipx=hipx, hipy=hipy, lean=4,
            head_dy=1 if BOB[f] > 0 else 0,
            feet=[(hipx + 1 + nf[0], GROUND + nf[1]), (hipx - 1 + ff[0], GROUND + ff[1])],
            hands=[(-4 * sw + 1, 5 - 1.5 * abs(sw)), (4 * sw + 1, 5 - 1.5 * abs(sw))],
            sword=math.radians(160 + 12 * sw),
            hair_ang=math.radians(152), hair_wave=0.7, hair_phase=t * 2,
            scarf_ang=math.radians(185), scarf_wave=0.6, scarf_phase=t * 2 + 0.7,
            flap=2, flap_phase=t * 2)))
    return fr

if __name__ == '__main__':
    out = sys.argv[1] if len(sys.argv) > 1 else 'frames'
    import os
    for name, fs in (('idle', idle_frames()), ('walk', run_frames())):
        os.makedirs(f'{out}/{name}', exist_ok=True)
        for i, a in enumerate(fs, 1): Image.fromarray(a).save(f'{out}/{name}/{name}_{i}.png')
    # preview
    k = 8
    rows = []
    for fs in (idle_frames(), run_frames()):
        strip = Image.new('RGBA', (8 * (W * k + 8), H * k), (45, 42, 55, 255))
        for i, a in enumerate(fs): strip.alpha_composite(Image.fromarray(a).resize((W * k, H * k), 0), (i * (W * k + 8), 0))
        rows.append(strip)
    pv = Image.new('RGBA', (rows[0].width, rows[0].height * 2 + 8), (20, 20, 25, 255))
    pv.paste(rows[0], (0, 0)); pv.paste(rows[1], (0, rows[0].height + 8)); pv.save(f'{out}/preview.png')
