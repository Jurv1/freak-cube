"""15 монстриков «Пекарни». Перёд = +Z, верх = +Y, единицы ≈ студы."""
import math

import numpy as np

from kit import GRADS, G, Model, Rx, Ry, Rz, euler, look, nrm, sq_front, sq_points_pair, TAU

BLACK = '#1A1A28'
WHITE = '#FFFFFF'
BLUSH = '#FF8FA8'
RB = ['#FF3B4E', '#FF8A1F', '#FFD93B', '#3DDC6B', '#2FB8FF', '#7A5CFF', '#E04CFF']

GRADS['wrap'] = sum([['#2FC4C2'] * 3 + ['#EFFFFD'] * 3 for _ in range(12)], [])
GRADS['wrap_gold'] = sum([['#F7C948'] * 3 + ['#FFE9A6'] * 3 for _ in range(10)], [])


def V(*a):
    return np.array(a, float)


def spike(m, p, n, length, rad, color, sink=0.06, **kw):
    return m.cone(p - n * sink, p + n * length, rad, color, **kw)


def gumdrop(m, p, n, s, color):
    prof = np.array([(0, 1.0), (0.3, 0.93), (0.52, 0.7), (0.62, 0.38), (0.64, 0.05), (0.6, -0.2), (0, -0.2)]) * s
    return m.lathe(prof, color, pos=p, rot=look(n) @ Rx(90), seg=12, crease=180)


def torus_pt(c, R, r, a, b):
    rad = V(math.cos(a), 0, math.sin(a))
    n = math.cos(b) * rad + math.sin(b) * V(0, 1, 0)
    return V(*c) + rad * R + n * r, n


def scatter(m, c, r, colors, count, pitch=(35, 80), yaw=(0, 360), out=0.05, kind='sprinkle', size=0.16):
    for i in range(count):
        y = m.rng.uniform(*yaw)
        p = m.rng.uniform(*pitch)
        pt, n = m.on(c, r, y, p, out)
        col = colors[i % len(colors)]
        if kind == 'sprinkle':
            m.sprinkle(pt, n, col, length=size)
        else:
            m.disc(pt, n, size, col, thick=0.028, seg=(8, 4))


# 1 ─────────────────────────────────────────────────────────── Сырный Булкотик
def bulkotik():
    m = Model('cheese+flour', 'Сырный Булкотик', 'Сыр + Мука', 3.6)
    BUN, CH, HOLE = G('bun', 'y'), '#FFC42E', '#EE9E12'
    bc, br = V(0, 1.0, -0.2), V(1.5, 1.0, 1.55)
    m.ell(bc, br, BUN)
    m.glaze(bc, br, CH, y0=0.3, amp=0.55, lobes=7, seed=3, calm=0.5)
    for yaw, pitch, s in [(-75, 38, .2), (-115, 55, .14), (80, 42, .17), (125, 34, .21), (178, 48, .19),
                          (150, 68, .12), (-150, 50, .2), (-40, 30, .13), (48, 28, .1)]:
        p, n = m.on(bc, br, yaw, pitch, out=0.04)
        m.disc(p, n, s, HOLE, thick=0.03)
    hc, hr = V(0, 2.2, 0.75), V(1.2, 1.0, 1.05)
    m.ell(hc, hr, G('bun', 'y', 0.0, 0.7))
    for sg in (-1, 1):
        R = euler(0, 0, -sg * 16)
        base = V(sg * 0.66, 2.86, 0.72)
        m.prism([(-0.46, 0), (0.46, 0), (0, 0.9)], 0.34, CH, pos=base, rot=R)
        m.prism([(-0.25, 0.1), (0.25, 0.1), (0, 0.58)], 0.08, '#FF9A3D', pos=base + R @ V(0, 0, 0.16), rot=R)
        m.disc(base + R @ V(sg * 0.14, 0.3, -0.17), R @ V(0, 0, -1), 0.1, HOLE, thick=0.03)
    m.eyes(hc, hr, yaw=25, pitch=3, s=0.3)
    p, n = m.on(hc, hr, 0, -9)
    m.ell(p, (0.11, 0.08, 0.07), '#FF6F91', rot=look(n), seg=(10, 6))
    m.mouth_w(hc, hr, yaw=9, pitch=-17, depth=5)
    m.blush(hc, hr, yaw=46, pitch=-14, s=0.19)
    for sg in (-1, 1):
        for dy in (-0.14, 0.12):
            p, n = m.on(hc, hr, sg * 52, -8 + dy * 30)
            m.tube([p - n * 0.03, p + V(sg * 0.62, dy, 0.02)], [0.028, 0.012], '#8A5A2B', seg=5)
    for yaw in (-14, 0, 14):
        m.line_on(hc, hr, [(yaw, 44), (yaw * 0.85, 58), (yaw * 0.6, 72)], rad=0.055, color='#C8781F')
    for sg in (-1, 1):
        m.ell((sg * 0.5, 0.2, 0.98), (0.34, 0.22, 0.42), '#FBE6B8')
    m.tube([(0, 0.7, -1.6), (0.25, 1.0, -2.1), (0.6, 1.7, -2.3), (0.8, 2.4, -2.05), (0.65, 2.85, -1.6)],
           [0.2, 0.22, 0.2, 0.18, 0.16], '#EBA646', n=18)
    m.ell((0.63, 2.92, -1.52), 0.24, CH)
    return m


# 2 ─────────────────────────────────────────────────────────── Чизкейк-Хрюша
def hrusha():
    m = Model('cheese+strawberry', 'Чизкейк-Хрюша', 'Сыр + Клубника', 3.5)
    CAKE, CRUST, SAUCE, PIG, PIGD = '#FFE7A0', '#C8883F', '#E8274B', '#FF9DB5', '#EE6690'
    bc, br, e1 = V(0, 1.5, 0), V(1.6, 1.15, 1.5), 0.4
    m.sq(bc, br, CAKE, e1=e1, e2=1, seg=(32, 16))
    m.sq((0, 0.64, 0), (1.66, 0.3, 1.56), CRUST, e1=0.5, e2=1, seg=(32, 10))
    m.glaze(bc, br, SAUCE, y0=0.74, amp=0.45, lobes=9, e1=e1, e2=1, seed=5, thick=0.06, calm=0.75)

    def wall(yaw, y, out=0.0):
        a = math.radians(yaw)
        n = nrm([math.sin(a) / br[0], 0, math.cos(a) / br[2]])
        return V(br[0] * math.sin(a), y, br[2] * math.cos(a)) + n * out, n

    for sg in (-1, 1):
        p, n = wall(sg * 27, 1.74)
        m.eye(p, n, 0.28)
        p, n = wall(sg * 50, 1.36)
        m.disc(p, n, 0.2, BLUSH, thick=0.035, squash=(1, 0.62))
    m.ell((0, 1.42, 1.5), (0.48, 0.36, 0.26), PIG)
    for sg in (-1, 1):
        m.ell((sg * 0.16, 1.44, 1.74), (0.07, 0.1, 0.04), PIGD, seg=(8, 5))
    m.tube([wall(a, 1.0 + 0.08 * (a / 11) ** 2, 0.0)[0] for a in (-11, -5.5, 0, 5.5, 11)], 0.035, '#8A3B2A', seg=6, n=10)
    for sg in (-1, 1):
        R = euler(35, 0, -sg * 25)
        c = V(sg * 1.0, 2.82, 0.55)
        m.ell(c, (0.38, 0.46, 0.13), PIG, rot=R)
        m.ell(c + R @ V(0, -0.03, 0.06), (0.24, 0.31, 0.1), PIGD, rot=R)
    for sx in (-1, 1):
        for sz in (-1, 1):
            m.capsule((sx * 0.9, 0.55, sz * 0.8), (sx * 0.9, 0.2, sz * 0.8), 0.3, PIG, seg=12)
            m.ell((sx * 0.9, 0.02, sz * 0.8), (0.31, 0.14, 0.31), PIGD)
    m.tube([V(0.2 * math.cos(a), 1.5 + 0.2 * math.sin(a), -1.5 - 0.07 * a) for a in np.linspace(0, 3.2 * math.pi, 22)],
           0.075, PIG, seg=7)
    m.ell((0.3, 2.68, 0.1), (0.62, 0.24, 0.62), '#FFFDF5')
    m.strawberry((0.3, 2.86, 0.1), size=0.78, rot=euler(8, 30, -14))
    return m


# 3 ─────────────────────────────────────────────────────── Клубничный Пончозавр
def ponchozavr():
    m = Model('flour+strawberry', 'Клубничный Пончозавр', 'Мука + Клубника', 3.8)
    DOUGH, DOUGH_D, GLAZE = '#F6C47C', '#E4A254', '#FF74A8'
    bc, br = V(0, 1.2, 0), V(1.0, 1.15, 0.95)
    m.ell(bc, br, DOUGH)
    dc = (0, 1.1, 0)
    m.torus(dc, 1.12, 0.46, DOUGH_D, seg=14, n=36)
    m.torus((0, 1.25, 0), 1.12, 0.42, GLAZE, seg=10, n=42, wave=0.05, waves=7)
    for i in range(16):
        a = TAU * i / 16 + m.rng.uniform(-0.12, 0.12)
        p, n = torus_pt((0, 1.25, 0), 1.12, 0.42, a, math.radians(m.rng.uniform(40, 140)))
        m.sprinkle(p, n, [WHITE, '#FFE14D', '#7DF9E0', '#FF3B4E', '#7A5CFF'][i % 5], length=0.17)
    hc, hr = V(0, 2.55, 0.3), V(1.15, 0.95, 1.05)
    m.ell(hc, hr, DOUGH)
    sc, sr = V(0, 2.32, 1.08), V(0.74, 0.5, 0.56)
    m.ell(sc, sr, DOUGH)
    m.glaze(hc, hr, GLAZE, y0=0.5, amp=0.32, lobes=8, seed=2, calm=0.85)
    scatter(m, hc, hr, [WHITE, '#FFE14D', '#7DF9E0', '#FF3B4E', '#7A5CFF'], 12, pitch=(48, 82), out=0.05)
    m.eyes(hc, hr, yaw=37, pitch=2, s=0.28)
    m.blush(hc, hr, yaw=60, pitch=-16, s=0.17)
    for sg in (-1, 1):
        p, n = m.on(sc, sr, sg * 24, 38)
        m.disc(p, n, 0.05, '#B8763A', thick=0.02, seg=(8, 4))
        p, n = m.on(sc, sr, sg * 17, -24)
        m.cone(p + V(0, 0.04, -0.04), p + V(0, -0.17, 0.0), 0.075, WHITE, seg=8, crease=180)
    m.line_on(sc, sr, [(-48, -8), (-25, -18), (0, -21), (25, -18), (48, -8)], rad=0.035, color='#8A4B2A')
    # клубничные шипы по спине
    for (c, r, pitch, s) in [(hc, hr, 86, 0.5), (hc, hr, 50, 0.56), (hc, hr, 12, 0.5), (bc, br, 24, 0.42)]:
        p, n = m.on(c, r, 180, pitch)
        m.strawberry(p + n * 0.42 * s, size=s, rot=look(n) @ Rx(-90), leaves=False)
    tail = [(0, 0.95, -0.7), (0.25, 0.7, -1.5), (0.85, 0.58, -1.95), (1.5, 0.8, -1.9)]
    m.tube(tail, [0.62, 0.42, 0.24, 0.1], DOUGH, n=16, seg=14)
    for sg in (-1, 1):
        m.capsule((sg * 0.8, 1.9, 0.5), (sg * 0.95, 1.78, 1.0), 0.17, DOUGH, r1=0.14)
        m.ell((sg * 0.6, 0.22, 0.38), (0.42, 0.26, 0.62), DOUGH)
        for dx in (-0.22, 0, 0.22):
            m.ell((sg * 0.6 + dx, 0.14, 0.95), 0.09, WHITE, seg=(8, 5))
    return m


# 4 ─────────────────────────────────────────────────────────────── Фондю-Пёс
def fondue():
    m = Model('cheese+chocolate', 'Фондю-Пёс', 'Сыр + Шоколад', 3.8)
    POT, POT_D, CH, CHOC, FUR, CREAM = '#E5413A', '#A9241E', '#FFCB36', '#55301A', '#9A6236', '#FFE8C7'
    m.lathe([(0, 0.0), (0.95, 0.0), (1.4, 0.25), (1.56, 0.7), (1.5, 1.15), (1.57, 1.3), (1.44, 1.35), (1.32, 1.25),
             (0, 1.2)], POT, seg=32, crease=180)
    m.torus((0, 1.32, 0), 1.5, 0.09, POT_D, seg=8, n=32)
    m.lathe([(0, 1.34), (0.9, 1.32), (1.36, 1.25), (1.3, 1.1), (0, 1.1)], CH, seg=28, crease=180)
    for deg, ln in [(40, 0.55), (118, 0.35), (155, 0.6), (-25, 0.4), (-70, 0.65), (-140, 0.45), (80, 0.3)]:
        a = math.radians(deg)
        d = V(math.sin(a), 0, math.cos(a))
        m.tube([d * 1.38 + V(0, 1.3, 0), d * 1.55 + V(0, 1.38, 0), d * 1.63 + V(0, 1.2, 0),
                d * 1.63 + V(0, 1.2 - ln, 0)], [0.13, 0.13, 0.11, 0.13], CH, n=10, seg=8)
    m.capsule((-1.5, 0.95, 0), (-2.2, 1.08, 0), 0.14, '#3B2A22')
    # пёс
    m.ell((0, 1.6, -0.1), (0.85, 0.75, 0.78), FUR)
    hc, hr = V(0, 2.5, 0.15), V(1.08, 0.95, 1.0)
    m.ell(hc, hr, FUR)
    m.glaze(hc, hr, CH, y0=0.6, amp=0.42, lobes=7, seed=4, calm=0.85)
    mc, mr = V(0, 2.25, 0.95), V(0.52, 0.4, 0.42)
    m.ell(mc, mr, CREAM)
    m.ell((0, 2.44, 1.33), (0.17, 0.12, 0.1), BLACK)
    m.mouth_w(mc, mr, yaw=34, pitch=-22, depth=14, rad=0.032)
    m.ell((0, 1.99, 1.24), (0.14, 0.2, 0.055), '#FF7A9C', rot=euler(22, 0, 0), seg=(10, 6))
    p, n = m.on(hc, hr, -27, 4)
    m.disc(p, n, 0.42, CHOC, thick=0.04, squash=(0.9, 1.05))
    for sg in (-1, 1):
        p, n = m.on(hc, hr, sg * 27, 3, out=0.03 if sg < 0 else 0)
        m.eye(p, n, 0.27)
        p, n = m.on(hc, hr, sg * 24, 30)
        m.disc(p, n, 0.1, CREAM, thick=0.05, squash=(1.2, 0.8))
        m.ell((sg * 1.06, 2.42, 0.05), (0.3, 0.62, 0.42), CHOC, rot=euler(0, 0, sg * 16))
    m.blush(hc, hr, yaw=52, pitch=-18, s=0.16)
    m.ell((-0.55, 1.44, 1.36), (0.3, 0.2, 0.26), FUR)
    # лапа с вилкой для фондю
    m.tube([(0.6, 1.6, 0.4), (0.9, 1.7, 0.75), (1.0, 1.85, 0.9)], [0.22, 0.2, 0.2], FUR, n=8)
    m.ell((1.02, 1.9, 0.93), 0.27, FUR)
    m.capsule((0.95, 1.45, 1.0), (1.08, 2.15, 0.92), 0.085, '#3B2A22', seg=8)
    m.capsule((1.08, 2.15, 0.92), (1.42, 3.3, 0.78), 0.04, '#CBD1DA', seg=6)
    R = euler(10, 25, -16)
    cb = V(1.45, 3.42, 0.77)
    m.sq(cb, (0.3, 0.3, 0.3), '#F5DCA6', e1=0.35, e2=0.35, rot=R)
    m.glaze(cb, (0.3, 0.3, 0.3), CH, y0=0.1, amp=0.7, lobes=5, e1=0.35, e2=0.35, rot=R, thick=0.035, seed=1, nv=7)
    m.tube([(0, 1.7, -0.75), (0.1, 2.15, -1.2), (0.3, 2.55, -1.25)], [0.18, 0.16, 0.13], FUR, n=10)
    m.ell((0.33, 2.62, -1.25), 0.18, CH)
    return m


# 5 ───────────────────────────────────────────────────────────── Шоко-Кексозавр
def keksozavr():
    m = Model('chocolate+flour', 'Шоко-Кексозавр', 'Шоколад + Мука', 3.9)
    SKIN, SKIN_L, CHOC, CHOCD, CREAM = '#B5773F', '#E2B27A', '#6B3E22', '#3B1F10', '#FFF1DC'
    m.lathe([(0, 0.2), (1.0, 0.2), (1.4, 1.45), (1.26, 1.45), (0, 1.3)], G('wrap', 'u'), seg=96,
            flute=lambda ph, k: 1 + 0.045 * np.cos(24 * ph), crease=180)
    m.lathe([(0, 2.25), (0.5, 2.2), (1.0, 2.02), (1.38, 1.75), (1.54, 1.5), (1.44, 1.36), (1.2, 1.3), (0, 1.3)],
            CHOC, seg=32, crease=180)
    dc, dr = V(0, 1.45, 0), V(1.52, 0.82, 1.52)
    for yaw, pitch in [(35, 30), (75, 45), (120, 28), (160, 50), (-160, 30), (-120, 48), (-80, 30), (-40, 48),
                       (100, 12), (-25, 22), (-100, 14), (10, 44)]:
        p, n = m.on(dc, dr, yaw, pitch, out=-0.02)
        m.ell(p, (0.11, 0.11, 0.08), CHOCD, rot=look(n), seg=(8, 5))
    for sx in (-1, 1):
        for sz in (-1, 1):
            m.ell((sx * 0.82, 0.2, sz * 0.78), (0.36, 0.24, 0.42), SKIN)
    neck = [(0, 1.85, 0.72), (0, 2.3, 1.36), (0, 2.95, 1.5)]
    m.tube(neck, [0.56, 0.45, 0.42], SKIN, n=14, seg=16)
    hc, hr = V(0, 3.2, 1.65), V(0.74, 0.64, 0.82)
    m.ell(hc, hr, SKIN)
    m.eyes(hc, hr, yaw=40, pitch=10, s=0.24)
    m.blush(hc, hr, yaw=64, pitch=-14, s=0.13)
    m.line_on(hc, hr, [(-34, -22), (-17, -30), (0, -33), (17, -30), (34, -22)], rad=0.032, color='#5A3317')
    for sg in (-1, 1):
        p, n = m.on(hc, hr, sg * 13, 24)
        m.disc(p, n, 0.045, '#7A4A22', thick=0.02, seg=(8, 4))
    for yaw, pitch, s in [(150, 40, 0.13), (-140, 10, 0.1), (120, -5, 0.08)]:
        p, n = m.on(hc, hr, yaw, pitch)
        m.disc(p, n, s, SKIN_L, thick=0.03)
    for (y, z, s) in [(3.72, 1.1, 0.2), (3.2, 0.82, 0.22), (2.62, 0.95, 0.22), (2.1, 0.75, 0.2)]:
        spike(m, V(0, y, z), nrm(V(0, 0.45, -1)), s * 1.5, s, CHOCD)
    # крем-завиток и вишенка
    amax = 3.1 * TAU
    sw = [V(0.74 * (1 - a / amax) ** 0.85 * math.cos(a), 2.08 + 1.0 * a / amax, -0.3 + 0.74 * (1 - a / amax) ** 0.85 * math.sin(a))
          for a in np.linspace(0, amax, 64)]
    m.tube(sw, np.linspace(0.33, 0.13, 64), CREAM, seg=10)
    m.ell((0, 3.24, -0.3), 0.23, '#EE2A4F')
    m.tube([(0, 3.42, -0.3), (0.05, 3.62, -0.28), (0.16, 3.72, -0.25)], 0.028, '#3FAE49', seg=5, n=6)
    scatter(m, V(0, 2.3, -0.3), V(0.95, 0.5, 0.95), RB, 9, pitch=(-10, 40), out=0.02, size=0.14)
    m.tube([(0, 1.4, -1.2), (0, 1.0, -1.9), (0, 0.95, -2.4), (0, 1.25, -2.75)], [0.5, 0.32, 0.2, 0.08], SKIN, n=14, seg=12)
    return m


# 6 ─────────────────────────────────────────────────────────── Трюфельный Зайка
def zayka():
    m = Model('chocolate+strawberry', 'Трюфельный Зайка', 'Шоколад + Клубника', 3.9)
    CHOC, CHOCD, PK, PKL = '#6E3C22', '#4A2616', '#FF7FA5', '#FFC2D4'
    bc, br = V(0, 1.4, 0), V(1.3, 1.25, 1.25)
    m.ell(bc, br, CHOC)
    m.lathe([(0, 0.05), (0.85, 0.05), (1.44, 0.95), (1.3, 0.95), (0, 0.8)], G('wrap_gold', 'u'), seg=80,
            flute=lambda ph, k: 1 + 0.04 * np.cos(20 * ph), crease=180)
    m.glaze(bc, br, PK, y0=0.56, amp=0.4, lobes=8, seed=11, calm=0.9)
    scatter(m, bc, br, [WHITE, '#FFE9F0', '#FFE14D'], 14, pitch=(50, 80), out=0.06, kind='disc', size=0.055)
    m.eyes(bc, br, yaw=23, pitch=8, s=0.3)
    p, n = m.on(bc, br, 0, -3)
    m.ell(p, (0.1, 0.075, 0.06), '#FF4F84', rot=look(n), seg=(10, 6))
    m.mouth_w(bc, br, yaw=8, pitch=-11, depth=5, color='#2B1208')
    p, n = m.on(bc, br, 0, -19)
    m.sq(p, (0.1, 0.085, 0.035), WHITE, e1=0.5, e2=0.5, rot=look(n), seg=(10, 8))
    m.blush(bc, br, yaw=45, pitch=-9, s=0.19)
    ears = [([(-0.45, 2.4, 0), (-0.6, 3.2, -0.05), (-0.66, 4.0, -0.05)], [0.22, 0.38, 0.14]),
            ([(0.45, 2.4, 0), (0.62, 3.15, -0.05), (0.8, 3.7, 0.12), (1.12, 3.82, 0.5)], [0.22, 0.38, 0.32, 0.13])]
    for pts, rad in ears:
        pts = np.array(pts, float)
        m.tube(pts, rad, CHOC, n=14, seg=12, squash=(1, 0.42), up=(1, 0, 0))
        m.tube(pts[1:] * [1, 0.985, 1] + V(0, 0, 0.1), np.array(rad[1:]) * 0.55, PK, n=10, seg=10, squash=(1, 0.42),
               up=(1, 0, 0))
    m.ell((0, 1.15, -1.3), 0.36, PKL)
    for sg in (-1, 1):
        m.ell((sg * 0.5, 1.0, 1.22), (0.26, 0.2, 0.24), CHOCD)
    m.strawberry((0.02, 2.62, 0.3), size=0.5, rot=euler(18, 0, 6))
    return m


# 7 ─────────────────────────────────────────────────────────────── Пицца-Попугай
def popugai():
    m = Model('cheese+rainbow', 'Пицца-Попугай', 'Сыр + Радуга', 3.9)
    RED, CH, CRUST, PEP, BEAK = '#FF4B3A', '#FFD046', '#DF9C4C', '#C5302A', '#FFB21A'
    bc, br = V(0, 1.3, 0), V(1.0, 1.2, 0.95)
    m.ell(bc, br, RED)
    hc, hr = V(0, 2.75, 0.12), V(0.95, 0.9, 0.9)
    m.ell(hc, hr, RED)
    p, n = m.on(bc, br, 0, -8)
    R = look(n)
    m.disc(p - n * 0.02, n, 0.78, CRUST, thick=0.1, squash=(1, 1.08))
    m.disc(p + n * 0.04, n, 0.63, CH, thick=0.1, squash=(1, 1.08))
    for dx, dy in [(-0.26, 0.3), (0.28, 0.24), (0.02, -0.08), (-0.3, -0.36), (0.28, -0.4)]:
        k = math.sqrt(max(1 - (dx / 0.63) ** 2 - (dy / 0.68) ** 2, 0))
        m.disc(p + R @ V(dx, dy, 0.04 + 0.1 * k), n, 0.13, PEP, thick=0.035, seg=(10, 5))
    for dx, dy in [(0.0, 0.42), (-0.05, 0.16), (0.3, -0.08), (-0.38, -0.05), (0.02, -0.42)]:
        k = math.sqrt(max(1 - (dx / 0.63) ** 2 - (dy / 0.68) ** 2, 0))
        m.sprinkle(p + R @ V(dx, dy, 0.04 + 0.1 * k), n, '#3FAE49', length=0.12, rad=0.03)
    for sg in (-1, 1):
        p, n = m.on(hc, hr, sg * 33, 8)
        m.disc(p, n, 0.36, WHITE, thick=0.05)
        m.eye(p + n * 0.035, n, 0.24)
    m.blush(hc, hr, yaw=60, pitch=-22, s=0.14, color='#FFB09E')
    m.tube([(0, 2.82, 0.88), (0, 2.8, 1.35), (0, 2.52, 1.56), (0, 2.28, 1.46)], [0.4, 0.33, 0.2, 0.05], BEAK, n=12,
           seg=12, squash=(0.8, 1))
    m.ell((0, 2.43, 1.0), (0.25, 0.17, 0.3), '#F08C1A')
    for dx, col in [(-0.22, '#FFD93B'), (0, '#3DDC6B'), (0.22, '#2FB8FF')]:
        m.tube([(dx, 3.5, 0.12), (dx * 1.7, 3.98, -0.02), (dx * 2.6, 4.25, -0.35)], [0.14, 0.2, 0.06], col, n=10,
               seg=8, squash=(1, 0.5), up=(1, 0, 0))
    for sg in (-1, 1):
        R = Rz(sg * 24) @ Ry(sg * 90)
        pos = V(sg * 1.0, 2.0, 0.0)
        m.prism([(-0.55, 0), (0.55, 0), (0, -1.4)], 0.16, CH, pos=pos, rot=R)
        m.capsule(pos + R @ V(-0.55, 0.02, 0), pos + R @ V(0.55, 0.02, 0), 0.16, CRUST)
        for x, y in [(0.0, -0.36), (-0.14, -0.72), (0.16, -0.62), (0.0, -1.02)]:
            m.disc(pos + R @ V(x, y, 0.08), R @ V(0, 0, 1), 0.12, PEP, thick=0.035, seg=(10, 5))
    for i, col in enumerate(['#FF3B4E', '#FFD93B', '#3DDC6B', '#2FB8FF', '#7A5CFF']):
        a = math.radians((i - 2) * 15)
        m.tube([(0, 0.8, -0.75), (math.sin(a) * 0.85, 0.55, -1.5), (math.sin(a) * 1.6, 0.32, -2.2)],
               [0.12, 0.26, 0.08], col, n=10, seg=8, squash=(0.35, 1))
    for sg in (-1, 1):
        m.ell((sg * 0.42, 0.1, 0.42), (0.3, 0.12, 0.42), BEAK)
    return m


# 8 ───────────────────────────────────────────────────────── Радужный Бубликорог
def bublikorog():
    m = Model('flour+rainbow', 'Радужный Бубликорог', 'Мука + Радуга', 4.0)
    WH, HOOF, GOLD, MUZ = '#FFF7EE', '#B58CFF', '#FFD23F', '#FFD3DD'
    cz = -0.1
    m.torus((0, 1.25, cz), 0.82, 0.56, G('bun', 'y'), seg=16, n=40)
    m.torus((0, 1.43, cz), 0.82, 0.5, G('rainbow_loop', 'v'), seg=12, n=48, wave=0.022, waves=9)
    m.ell((0, 1.5, cz), (0.42, 0.3, 0.42), '#FFFDF5')
    for i in range(14):
        a = TAU * i / 14 + m.rng.uniform(-0.15, 0.15)
        p, n = torus_pt((0, 1.42, cz), 0.82, 0.5, a, math.radians(m.rng.uniform(45, 135)))
        m.sprinkle(p, n, WHITE, length=0.13, rad=0.032)
    for sx in (-1, 1):
        for sz in (-1, 1):
            m.capsule((sx * 0.55, 0.95, sz * 0.6 + cz), (sx * 0.58, 0.32, sz * 0.62 + cz), 0.27, WH, seg=12)
            m.ell((sx * 0.58, 0.16, sz * 0.62 + cz), (0.3, 0.17, 0.3), HOOF)
    m.tube([(0, 1.5, 0.6), (0, 2.1, 0.95), (0, 2.5, 1.05)], [0.5, 0.46, 0.45], WH, n=10, seg=14)
    hc, hr = V(0, 2.75, 1.1), V(0.95, 0.88, 0.92)
    m.ell(hc, hr, WH)
    mc, mr = V(0, 2.5, 1.8), V(0.52, 0.4, 0.4)
    m.ell(mc, mr, MUZ)
    for sg in (-1, 1):
        p, n = m.on(mc, mr, sg * 26, 18)
        m.disc(p, n, 0.045, '#F08DA6', thick=0.02, seg=(8, 4))
        R = euler(0, 0, -sg * 22)
        c = V(sg * 0.56, 3.58, 0.95)
        m.ell(c, (0.17, 0.32, 0.11), WH, rot=R)
        m.ell(c + V(0, -0.02, 0.06), (0.09, 0.2, 0.08), '#FFB3C7', rot=R, seg=(8, 6))
    m.smile(mc, mr, yaw=26, pitch=-22, depth=14, rad=0.03, color='#B0566E')
    m.eyes(hc, hr, yaw=40, pitch=6, s=0.27)
    for sg in (-1, 1):
        for k in (0, 1):
            p, n = m.on(hc, hr, sg * (52 + 6 * k), 20 - 9 * k)
            m.tube([p - n * 0.02, p + V(sg * 0.16, 0.12 - 0.07 * k, -0.02)], [0.03, 0.012], BLACK, seg=5)
    m.blush(hc, hr, yaw=62, pitch=-14, s=0.16)
    h0, h1 = V(0, 3.5, 1.38), V(0, 4.5, 1.62)
    m.cone(h0, h1, 0.21, GOLD, seg=14, crease=180)
    ax = nrm(h1 - h0)
    ex = nrm(np.cross(ax, V(0, 0, 1)))
    ez = np.cross(ax, ex)
    hel = [h0 + (h1 - h0) * t + (0.2 * (1 - t) + 0.012) * (math.cos(t * 4 * TAU) * ex + math.sin(t * 4 * TAU) * ez)
           for t in np.linspace(0.04, 0.96, 40)]
    m.tube(hel, np.linspace(0.05, 0.015, 40), '#FFAA1D', seg=5)
    mane = [((0, 3.62, 0.98), 0.3), ((0, 3.56, 0.52), 0.34), ((0, 3.3, 0.18), 0.35), ((0, 2.9, 0.06), 0.33),
            ((0, 2.5, 0.2), 0.3), ((0, 2.14, 0.42), 0.27)]
    for (c, r), col in zip(mane, ['#FF3B4E', '#FF8A1F', '#FFD93B', '#3DDC6B', '#2FB8FF', '#7A5CFF']):
        m.ell(c, (r * 0.85, r, r), col)
    m.ell((0.3, 3.42, 1.68), (0.2, 0.26, 0.2), '#E04CFF', rot=euler(0, 0, -25))
    m.tube([(0, 1.5, -1.35), (0, 2.1, -1.85), (0.15, 2.2, -2.4), (0.3, 1.6, -2.75), (0.25, 1.1, -2.6)],
           [0.22, 0.36, 0.4, 0.3, 0.08], G('rainbow', 'v'), n=22, seg=12)
    return m


# 9 ───────────────────────────────────────────────────────── Мармеладный Дракоша
def drakosha():
    m = Model('rainbow+strawberry', 'Мармеладный Дракоша', 'Радуга + Клубника', 3.9)
    BODY, LIGHT, YEL, WING = '#FF4F9E', '#FF8CC0', '#FFE14D', '#FFB03A'
    bc, br = V(0, 1.15, 0), V(1.0, 1.1, 0.9)
    m.ell(bc, br, BODY)
    p, n = m.on(bc, br, 0, -8)
    m.disc(p - n * 0.09, n, 0.68, G('rainbow', 'y', 1, 0), thick=0.17, squash=(0.95, 1.15))
    hc, hr = V(0, 2.55, 0.25), V(1.15, 0.95, 1.05)
    m.ell(hc, hr, BODY)
    sc, sr = V(0, 2.33, 1.1), V(0.62, 0.44, 0.48)
    m.ell(sc, sr, LIGHT)
    m.eyes(hc, hr, yaw=36, pitch=7, s=0.29)
    m.blush(hc, hr, yaw=60, pitch=-14, s=0.16, color='#FF2F78')
    for sg in (-1, 1):
        p, n = m.on(sc, sr, sg * 24, 36)
        m.disc(p, n, 0.045, '#D62E7A', thick=0.02, seg=(8, 4))
        p, n = m.on(sc, sr, sg * 20, -26)
        m.cone(p + V(0, 0.03, -0.03), p + V(0, -0.15, 0.0), 0.06, WHITE, seg=8, crease=180)
        p, n = m.on(hc, hr, sg * 38, 60)
        spike(m, p, nrm(n + V(sg * 0.25, 0.3, 0)), 0.5, 0.19, YEL, seg=12, crease=180)
    m.line_on(sc, sr, [(-50, -10), (-25, -20), (0, -23), (25, -20), (50, -10)], rad=0.035, color='#A31F5E')
    drops = [(hc, hr, 82, 0.3), (hc, hr, 46, 0.34), (hc, hr, 8, 0.32), (bc, br, 34, 0.32), (bc, br, -2, 0.28)]
    for (c, r, pitch, s), col in zip(drops, RB):
        p, n = m.on(c, r, 180, pitch)
        gumdrop(m, p, n, s, col)
    tail = np.array([(0, 0.75, -0.7), (0.35, 0.45, -1.4), (1.0, 0.36, -1.62), (1.55, 0.5, -1.15)])
    m.tube(tail, [0.55, 0.38, 0.24, 0.14], BODY, n=18, seg=12)
    gumdrop(m, V(0.3, 0.82, -1.38), nrm(V(0.1, 1, -0.2)), 0.22, RB[5])
    gumdrop(m, V(0.98, 0.58, -1.6), nrm(V(0, 1, -0.3)), 0.17, RB[6])
    d = nrm(tail[-1] - tail[-2] + V(0, 0.15, 0.2))
    m.strawberry(tail[-1] + d * 0.34, size=0.42, rot=look(d) @ Rx(-90))
    for sg in (-1, 1):
        Rw = Ry(sg * 28) @ Rx(-8)
        root = V(sg * 0.7, 1.85, -0.55)

        def W(u, v, z=0.0):
            return root + Rw @ V(sg * u, v, z)

        wing = [(0.0, 0.12), (0.34, 0.86), (1.2, 1.02), (1.04, 0.66), (0.86, 0.52), (0.9, 0.22), (0.64, 0.16),
                (0.6, -0.12), (0.32, -0.04), (0.22, -0.22), (0.0, -0.12)]
        m.prism([(sg * u, v) for u, v in wing], 0.09, WING, pos=root, rot=Rw, crease=60)
        m.tube([W(0, 0, 0.0), W(0.34, 0.86, 0.0), W(1.2, 1.02, 0.0)], [0.12, 0.1, 0.05], BODY, n=10, seg=7)
        for (u, v) in [(0.86, 0.52), (0.64, 0.16), (0.32, -0.04)]:
            m.tube([W(0.34, 0.84, 0.0), W(u, v, 0.0)], [0.06, 0.035], '#FF8A1F', seg=5)
        m.capsule((sg * 0.85, 1.62, 0.35), (sg * 1.0, 1.32, 0.82), 0.17, BODY, r1=0.15)
        m.ell((sg * 0.58, 0.22, 0.32), (0.4, 0.26, 0.6), BODY)
        for dx in (-0.2, 0, 0.2):
            m.ell((sg * 0.58 + dx, 0.14, 0.87), 0.085, WHITE, seg=(8, 5))
    return m


# 10 ──────────────────────────────────────────────────────── Конфетти-Хамелеон
def hameleon():
    m = Model('chocolate+rainbow', 'Конфетти-Хамелеон', 'Шоколад + Радуга', 3.3)
    MINT, MINT_L, MINT_D, CHOC = '#45D69B', '#A6F3CF', '#1FA573', '#5B3219'
    bc, br = V(0, 1.15, -0.2), V(0.95, 0.95, 1.35)
    m.ell(bc, br, MINT)
    m.glaze(bc, br, CHOC, y0=0.3, amp=0.42, lobes=9, seed=1)
    hc, hr = V(0, 1.8, 1.15), V(0.85, 0.75, 0.9)
    m.ell(hc, hr, MINT)
    m.glaze(hc, hr, CHOC, y0=0.58, amp=0.3, lobes=6, seed=2, calm=0.8)
    cc, cr, cR = V(0, 2.45, 0.72), V(0.4, 0.58, 0.62), euler(-28, 0, 0)
    m.ell(cc, cr, CHOC, rot=cR)
    scatter(m, bc, br, RB, 26, pitch=(38, 85), out=0.055, kind='disc', size=0.085)
    scatter(m, bc, br, RB[::-1], 8, pitch=(40, 80), out=0.05, size=0.17)
    for i, (yaw, pitch) in enumerate([(70, 20), (-70, 25), (110, 45), (-115, 40), (180, 30), (40, 60), (-35, 62)]):
        d = cR @ V(math.sin(math.radians(yaw)) * math.cos(math.radians(pitch)), math.sin(math.radians(pitch)),
                   math.cos(math.radians(yaw)) * math.cos(math.radians(pitch)))
        m.disc(cc + cR @ (cr * (np.linalg.inv(cR) @ d)) * 1.0 + d * 0.03, d, 0.075, RB[(i * 3) % 7], thick=0.028, seg=(8, 4))
    for sg, d in ((-1, nrm(V(-0.35, 0.05, 1))), (1, nrm(V(0.75, 0.5, 0.7)))):
        ec = V(sg * 0.6, 2.02, 1.5)
        m.ell(ec, 0.42, MINT_L)
        m.eye(ec + d * 0.36, d, 0.23)
    m.line_on(hc, hr, [(-52, -20), (-26, -31), (0, -34), (26, -31), (52, -20)], rad=0.035, color=MINT_D)
    for sg in (-1, 1):
        p, n = m.on(hc, hr, sg * 11, 4)
        m.disc(p, n, 0.04, MINT_D, thick=0.02, seg=(8, 4))
    m.blush(hc, hr, yaw=50, pitch=-8, s=0.14)
    tongue = [(0, 1.42, 1.82), (0.05, 1.3, 2.25), (0.15, 1.38, 2.6), (0.2, 1.66, 2.72), (0.12, 1.84, 2.56)]
    m.tube(tongue, 0.085, '#FF6FA5', n=16, seg=8)
    m.ell(tongue[-1], 0.14, '#FF6FA5')
    for sx in (-1, 1):
        for z0, z1 in ((0.55, 0.78), (-0.95, -0.85)):
            m.tube([(sx * 0.7, 0.95, z0), (sx * 1.02, 0.6, z1), (sx * 1.08, 0.2, z1)], [0.22, 0.19, 0.17], MINT, n=8, seg=9)
            m.ell((sx * 1.1, 0.13, z1 + 0.1), (0.24, 0.14, 0.3), MINT)
            for dz in (-0.12, 0.14):
                m.ell((sx * 1.16, 0.12, z1 + 0.34 + dz * 0.3), (0.11, 0.1, 0.13), MINT_L, seg=(8, 5))
    C = V(0, 1.78, -2.0)
    tmax = 1.6 * TAU
    sp = [V(0, 1.05, -1.3), V(0, 1.0, -1.65)]
    for th in np.linspace(0, tmax, 44):
        Rr = 0.78 * (1 - 0.82 * th / tmax)
        sp.append(C + V(0.3 * th / tmax, -Rr * math.cos(th), -Rr * math.sin(th)))
    m.tube(sp, np.linspace(0.34, 0.1, len(sp)), G('rainbow', 'v'), seg=10)
    return m


# 11 ───────────────────────────────────────────────────────── Моцарелла-Йети
def yeti():
    m = Model('cheese+ice', 'Моцарелла-Йети', 'Сыр + Лёд', 3.9)
    MOZ, MOZ_S, ICE, ICE_D, ICE_L = '#FFFBEA', '#F1E6C2', '#8ED8FF', '#4FB6F2', '#D6F3FF'
    bc, br = V(0, 1.25, 0), V(1.35, 1.25, 1.15)
    m.ell(bc, br, MOZ)
    hc, hr = V(0, 2.6, 0.1), V(1.12, 0.95, 1.0)
    m.ell(hc, hr, MOZ)
    for i in range(12):
        a = TAU * (i + 0.5) / 12
        m.ell((1.14 * math.cos(a), 1.84 + 0.04 * math.cos(3 * a), 0.06 + 1.0 * math.sin(a)), 0.27, MOZ, seg=(10, 7))
    p, n = m.on(bc, br, 0, -12)
    m.disc(p - n * 0.04, n, 0.6, '#F8EFCF', thick=0.07, squash=(1, 1.1))
    fc, fr = V(0, 2.62, 0.7), V(0.8, 0.66, 0.46)
    m.ell(fc, fr, ICE)
    m.eyes(fc, fr, yaw=30, pitch=14, s=0.25)
    p, n = m.on(fc, fr, 0, -30)
    m.open_mouth(p, n, w=0.21, h=0.14)
    R = look(n)
    for sg in (-1, 1):
        q = p + R @ V(sg * 0.11, -0.1, 0.04)
        m.cone(q, q + R @ V(0, 0.15, 0.02), 0.05, WHITE, seg=8, crease=180)
    m.blush(fc, fr, yaw=58, pitch=-12, s=0.12)
    for sg in (-1, 1):
        m.tube([(sg * 0.72, 3.2, 0.1), (sg * 1.12, 3.5, 0.1), (sg * 1.16, 3.98, 0.1)], [0.21, 0.16, 0.03], ICE_D, n=10, seg=10)
        m.ell((sg * 0.65, 0.22, 0.42), (0.5, 0.25, 0.68), ICE)
        for dx in (-0.28, 0, 0.28):
            m.ell((sg * 0.65 + dx, 0.2, 1.05), 0.13, ICE_L, seg=(10, 6))
    m.tube([(-1.1, 2.0, 0.1), (-1.66, 1.56, 0.3), (-1.72, 0.98, 0.46)], [0.38, 0.36, 0.34], MOZ, n=10, seg=14)
    m.ell((-1.72, 0.82, 0.5), (0.36, 0.34, 0.36), ICE)
    m.tube([(1.1, 2.0, 0.1), (1.74, 2.3, 0.2), (1.96, 3.0, 0.25)], [0.38, 0.35, 0.33], MOZ, n=10, seg=14)
    m.ell((1.98, 3.22, 0.27), 0.36, ICE)
    for x, y, ln in [(1.3, 1.85, 0.3), (1.52, 1.98, 0.52), (1.74, 2.1, 0.34)]:
        m.tube([(x, y + 0.1, 0.22), (x, y - ln, 0.22)], [0.1, 0.075], MOZ_S, seg=8)
    for x, ln in [(-1.42, 0.3), (-1.2, 0.2)]:
        m.cone((x, 1.72 + (x + 1.2) * 0.5, 0.25), (x, 1.72 + (x + 1.2) * 0.5 - ln, 0.25), 0.07, ICE_L, seg=8, crease=180)
    for yaw, pitch in [(-120, 55), (140, 40), (180, 70), (-60, 72), (75, 66)]:
        p, n = m.on(hc, hr, yaw, pitch)
        m.ell(p, 0.24, MOZ, seg=(10, 7))
    m.ell((-0.22, 3.68, 0.18), 0.27, '#F03A2E')
    for i in range(5):
        a = TAU * i / 5
        m.ell((-0.22 + 0.1 * math.cos(a), 3.93, 0.18 + 0.1 * math.sin(a)), (0.12, 0.03, 0.06), '#3FAE49',
              rot=euler(0, -math.degrees(a), -15), seg=(8, 4))
    m.ell((0.26, 3.56, 0.25), (0.44, 0.06, 0.26), '#3FAE49', rot=euler(0, 30, 16))
    m.ell((0.3, 3.6, 0.2), (0.36, 0.05, 0.2), '#58C45C', rot=euler(10, -40, 10))
    return m


# 12 ──────────────────────────────────────────────────── Снежный Вафлепингвин
def pingvin():
    m = Model('flour+ice', 'Снежный Вафлепингвин', 'Мука + Лёд', 3.9)
    BLUE, BLUE_D, WAF, WAF_D, ORANGE, RED = '#3F8FE0', '#2A6CC0', '#F6CB74', '#D08E38', '#FF9A1F', '#FF5A5F'
    bc, br = V(0, 1.5, 0), V(1.25, 1.5, 1.15)
    m.ell(bc, br, BLUE)
    p, n = m.on(bc, br, 0, -22)
    m.disc(p - n * 0.1, n, 0.74, WAF_D, thick=0.15, squash=(1, 1.02))
    for i in range(4):
        for j in range(4):
            if (i in (0, 3)) and (j in (0, 3)):
                continue
            q, nn = m.on(bc, br, (i - 1.5) * 14.5, -22 + (j - 1.5) * 11.5, out=0.06)
            m.sq(q, (0.135, 0.135, 0.05), WAF, e1=0.35, e2=0.35, rot=look(nn), seg=(8, 6))
    for sg in (-1, 1):
        p, n = m.on(bc, br, sg * 20, 37, out=0.045)
        m.eye(p + V(0, 0.02, 0), n, 0.25)
        p, n = m.on(bc, br, sg * 43, 22, out=0.02)
        m.disc(p, n, 0.14, BLUSH, thick=0.035, squash=(1, 0.65))
        m.ell((sg * 1.22, 1.5, 0.05), (0.2, 0.72, 0.45), BLUE_D, rot=euler(0, 0, sg * 24))
        m.ell((sg * 0.5, 0.1, 0.55), (0.4, 0.13, 0.52), ORANGE)
    p, n = m.on(bc, br, 0, 36)
    m.disc(p - n * 0.14, n, 0.66, WHITE, thick=0.2, squash=(1.28, 0.92))
    p, n = m.on(bc, br, 0, 25)
    m.ell(p, (0.2, 0.13, 0.27), ORANGE, rot=look(n))
    m.glaze(bc, br, WHITE, y0=0.8, amp=0.12, lobes=7, seed=3, thick=0.07)
    ring = [V(1.24 * math.cos(a), 1.78 + 0.02 * math.sin(2 * a), 1.14 * math.sin(a)) for a in np.linspace(0, TAU, 36, endpoint=False)]
    m.tube(ring, 0.17, RED, seg=10, closed=True, squash=(1.25, 0.8))
    m.tube([(0.72, 1.78, 0.98), (0.86, 1.4, 1.08), (0.84, 1.05, 1.1)], [0.16, 0.17, 0.17], RED, n=8, seg=10, squash=(1, 0.5),
           caps='flat')
    for k in range(3):
        m.capsule((0.72 + 0.12 * k, 1.05, 1.1), (0.72 + 0.12 * k, 0.92, 1.11), 0.04, WHITE, seg=6)
    h0, h1 = V(0.22, 2.95, 0.0), V(0.62, 3.8, -0.12)
    m.cone(h0, h1, 0.4, WAF, seg=16, crease=180)
    ax = nrm(h1 - h0)
    ex = nrm(np.cross(ax, V(0, 0, 1)))
    ez = np.cross(ax, ex)
    for sgn in (-1, 1):
        for k in range(4):
            hel = [h0 + (h1 - h0) * t + (0.4 * (1 - t) + 0.015) * (math.cos(sgn * t * 4.2 + k * TAU / 4) * ex +
                                                                    math.sin(sgn * t * 4.2 + k * TAU / 4) * ez)
                   for t in np.linspace(0.12, 0.92, 9)]
            m.tube(hel, 0.022, WAF_D, seg=4)
    m.ell(h1, 0.15, WHITE, seg=(10, 7))
    return m


# 13 ──────────────────────────────────────────────────────── Пломбирный Тюлень
def tulen():
    m = Model('ice+strawberry', 'Пломбирный Тюлень', 'Лёд + Клубника', 3.1)
    ICEC, FLIP, SYR, WAF, WAF_D = '#FFF6E9', '#FFC4D6', '#FF5F92', '#EDB862', '#C4863A'
    hc, hr = V(0, 1.3, 0.8), V(1.2, 1.15, 1.15)
    m.ell(hc, hr, ICEC)
    m.tube([(0, 1.14, 0.4), (0, 1.08, -0.3), (0, 1.04, -0.9)], [1.0, 0.94, 0.8], ICEC, n=8, seg=20, caps='flat')
    cR = Rx(-78)
    cpos = V(0, 1.0, -0.75)
    m.lathe([(0, 0.0), (0.92, 0.0), (0.99, 0.06), (0.94, 0.14), (0.1, 2.0), (0, 2.05)], WAF, pos=cpos, rot=cR, seg=28,
            crease=180)
    for sgn in (-1, 1):
        for k in range(6):
            hel = [cpos + cR @ V((0.94 * (1 - t) + 0.1 * t + 0.012) * math.cos(sgn * t * 3.6 + k * TAU / 6), 0.14 + 1.86 * t,
                                 (0.94 * (1 - t) + 0.1 * t + 0.012) * math.sin(sgn * t * 3.6 + k * TAU / 6))
                   for t in np.linspace(0.02, 0.93, 11)]
            m.tube(hel, 0.026, WAF_D, seg=4)
    tip = cpos + cR @ V(0, 2.0, 0)
    for sg in (-1, 1):
        m.ell(tip + V(sg * 0.32, 0.08, -0.22), (0.26, 0.09, 0.42), FLIP, rot=euler(-12, sg * 38, 0))
        m.ell((sg * 1.22, 0.3, 0.8), (0.62, 0.14, 0.36), FLIP, rot=euler(0, -sg * 28, -sg * 14))
    m.glaze(hc, hr, SYR, y0=0.5, amp=0.4, lobes=8, seed=6, calm=0.9)
    scatter(m, hc, hr, ['#FFFFFF', '#FFE14D', '#7DF9E0', '#7A5CFF'], 12, pitch=(45, 78), out=0.05, size=0.15)
    m.strawberry((0.12, 2.42, 0.72), 0.52, rot=euler(12, 0, -12))
    m.eyes(hc, hr, yaw=28, pitch=3, s=0.3)
    for sg in (-1, 1):
        m.ell((sg * 0.2, 1.06, 1.88), (0.27, 0.2, 0.17), WHITE)
        for k in (-1, 0, 1):
            m.tube([(sg * 0.38, 1.06 + 0.03 * k, 1.9), (sg * 0.98, 1.08 + 0.16 * k, 1.72)], [0.024, 0.01], '#6B5B53', seg=5)
    m.ell((0, 1.24, 1.98), (0.11, 0.08, 0.07), BLACK, seg=(10, 6))
    m.blush(hc, hr, yaw=50, pitch=-10, s=0.18)
    return m


# 14 ──────────────────────────────────────────────────────────── Эскимо-Морж
def morzh():
    m = Model('chocolate+ice', 'Эскимо-Морж', 'Шоколад + Лёд', 3.8)
    VAN, CHOC, CHOC_L, WOOD, NUT = '#FFF3D6', '#4E2B1A', '#7A4A2E', '#E8BE7E', '#F2D29B'
    bc, br, e = V(0, 1.95, 0), V(1.25, 1.5, 0.82), 0.5
    m.sq(bc, br, VAN, e1=e, e2=e, seg=(28, 18))
    m.glaze(bc, br, CHOC, y0=-0.5, amp=0.22, lobes=8, e1=e, e2=e, seed=2, thick=0.06, nv=12)
    m.sq((0, 0.3, 0), (0.3, 0.5, 0.09), WOOD, e1=0.5, e2=0.3)

    def F(x, y, out=0.06):
        return sq_front(bc, br, e, e, x, y, out)

    for sg in (-1, 1):
        p, n = F(sg * 0.48, 0.66)
        m.eye(p, n, 0.27)
        m.tube([F(sg * 0.26, 1.02, 0.08)[0], F(sg * 0.5, 1.1, 0.08)[0], F(sg * 0.74, 1.02, 0.08)[0]], [0.05, 0.065, 0.045],
               VAN, n=8, seg=7)
        p, n = F(sg * 0.88, 0.18)
        m.disc(p, n, 0.15, BLUSH, thick=0.035, squash=(1, 0.65))
        p, n = F(sg * 0.34, 0.06)
        m.ell(p + n * 0.1, (0.42, 0.36, 0.28), VAN)
        for dx, dy in [(-0.14, 0.08), (0.1, 0.1), (-0.02, -0.08)]:
            m.ell(p + V(sg * (0.05 + dx), dy, 0.375 - 0.12 * (abs(dx) + abs(dy))), 0.03, '#8A6A4A', seg=(6, 4))
        m.tube([(sg * 0.3, 1.86, 1.02), (sg * 0.35, 1.4, 1.14), (sg * 0.38, 1.0, 1.1)], [0.15, 0.11, 0.035], WHITE, n=10, seg=10)
        m.ell((sg * 1.38, 1.45, 0.15), (0.2, 0.5, 0.36), CHOC_L, rot=euler(0, 0, sg * 30))
        m.ell((sg * 0.95, 0.0, 0.45), (0.5, 0.2, 0.62), CHOC_L, rot=euler(0, sg * 25, 0))
    m.ell((0, 2.25, 1.14), (0.17, 0.12, 0.1), '#2A1A16')
    for i in range(16):
        v = math.radians(m.rng.uniform(30, 82))
        u = m.rng.uniform(0, TAU)
        pt = sq_points_pair(np.array([v]), np.array([u]), br + 0.07, e, e)[0]
        m.ell(bc + pt, (0.075, 0.05, 0.06), NUT, rot=euler(*m.rng.uniform(0, 180, 3)), seg=(6, 4))
    return m


# 15 ───────────────────────────────────────────────────── Лис Северного Сияния
def lis():
    m = Model('ice+rainbow', 'Лис Северного Сияния', 'Лёд + Радуга', 3.9)
    FUR, FUR_S, TEAL = '#EEF8FF', '#CBE6FA', '#3FE0C8'
    bc, br = V(0, 0.95, -0.1), V(0.88, 0.95, 0.9)
    m.ell(bc, br, FUR)
    m.ell((0, 1.22, 0.55), (0.55, 0.5, 0.42), WHITE)
    hc, hr = V(0, 2.3, 0.25), V(1.1, 0.9, 0.95)
    m.ell(hc, hr, FUR)
    mc, mr = V(0, 2.07, 1.0), V(0.42, 0.3, 0.45)
    m.ell(mc, mr, WHITE)
    m.ell((0, 2.18, 1.44), (0.1, 0.075, 0.07), BLACK, seg=(10, 6))
    m.mouth_w(mc, mr, yaw=40, pitch=-28, depth=16, rad=0.028)
    for sg in (-1, 1):
        m.ell((sg * 0.9, 2.04, 0.42), (0.46, 0.27, 0.32), FUR, rot=euler(0, 0, -sg * 24))
        m.ell((sg * 0.98, 2.3, 0.38), (0.38, 0.2, 0.28), FUR, rot=euler(0, 0, -sg * 2))
        m.tube([(sg * 0.6, 2.92, 0.2), (sg * 0.84, 3.9, 0.08)], [0.44, 0.03], G('ear_aurora', 'v'), seg=14, caps='flat',
               squash=(1, 0.45), up=(1, 0, 0), crease=180)
        m.tube([(sg * 0.63, 3.0, 0.36), (sg * 0.81, 3.62, 0.22)], [0.26, 0.02], '#FFB8E6', seg=10, caps='flat',
               squash=(1, 0.3), up=(1, 0, 0), crease=180)
        m.capsule((sg * 0.4, 1.0, 0.55), (sg * 0.42, 0.24, 0.72), 0.24, FUR, r1=0.22, seg=12)
        m.ell((sg * 0.42, 0.16, 0.8), (0.27, 0.17, 0.33), '#7DF9E0')
        m.ell((sg * 0.8, 0.18, 0.25), (0.3, 0.18, 0.5), FUR_S)
    m.eyes(hc, hr, yaw=28, pitch=3, s=0.28)
    m.blush(hc, hr, yaw=50, pitch=-15, s=0.17, color='#C9B2FF')
    p, n = m.on(hc, hr, 0, 40, out=0.02)
    star = [(0.2 * math.cos(TAU * i / 8 + math.pi / 2) * (1 if i % 2 == 0 else 0.36),
             0.2 * math.sin(TAU * i / 8 + math.pi / 2) * (1 if i % 2 == 0 else 0.36) * 1.25) for i in range(8)]
    m.prism(star, 0.06, TEAL, pos=p, rot=look(n))
    ring = [V(0.96 * math.cos(a), 1.72 + 0.1 * math.sin(3 * a), 0.12 + 0.9 * math.sin(a)) for a in np.linspace(0, TAU, 48, endpoint=False)]
    m.tube(ring, 0.2, G('aurora_loop', 'v'), seg=8, closed=True, squash=(1, 0.3))
    m.tube([(0, 0.55, -0.8), (0.9, 0.75, -1.45), (1.8, 1.6, -1.3), (1.95, 2.7, -0.9), (1.5, 3.55, -0.55)],
           [0.3, 0.7, 0.85, 0.6, 0.08], G('aurora', 'v'), n=26, seg=16)
    for (x, z, s, rz, col) in [(-1.15, -0.7, 1.0, 14, '#9EE7FF'), (-1.5, -0.25, 0.62, 28, '#C9F3FF'), (-0.85, -1.2, 0.72, -10, '#7DD3FF')]:
        prof = np.array([(0, 1.0), (0.2, 0.68), (0.2, 0.0), (0, 0.0)]) * s
        m.lathe(prof, col, pos=(x, 0, z), rot=euler(0, 20, rz), seg=6, crease=20)
    return m


ALL = [bulkotik, hrusha, ponchozavr, fondue, keksozavr, zayka, popugai, bublikorog, drakosha, hameleon, yeti,
       pingvin, tulen, morzh, lis]
