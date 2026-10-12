"""Мини-набор процедурного моделирования для монстриков «Пекарни».

Модель собирается из замкнутых примитивов (эллипсоиды, трубки, тела вращения,
глазурь с потёками, призмы). Цвета кладутся в маленький атлас-палитру, поэтому
каждый монстрик — это ОДИН меш с ОДНОЙ текстурой: в Roblox он импортируется
как один MeshPart.
"""
import io
import json
import math
import os
import struct
import zlib

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

TAU = 2 * math.pi


# ----------------------------------------------------------------- математика

def nrm(v):
    v = np.asarray(v, float)
    n = np.linalg.norm(v)
    return v / n if n > 1e-12 else v


def Rx(d):
    c, s = math.cos(math.radians(d)), math.sin(math.radians(d))
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]], float)


def Ry(d):
    c, s = math.cos(math.radians(d)), math.sin(math.radians(d))
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]], float)


def Rz(d):
    c, s = math.cos(math.radians(d)), math.sin(math.radians(d))
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]], float)


def euler(rx=0, ry=0, rz=0):
    return Ry(ry) @ Rx(rx) @ Rz(rz)


def look(n, up=(0, 1, 0), spin=0):
    """Матрица, у которой локальная ось Z смотрит вдоль n."""
    z = nrm(n)
    x = np.cross(up, z)
    if np.linalg.norm(x) < 1e-6:
        x = np.array([1.0, 0, 0])
    x = nrm(x)
    y = np.cross(z, x)
    m = np.stack([x, y, z], 1)
    return m @ Rz(spin) if spin else m


def as_rot(rot):
    if rot is None:
        return np.eye(3)
    rot = np.asarray(rot, float)
    if rot.shape == (3, 3):
        return rot
    return euler(*rot)


def smooth(pts, n=24):
    """Сплайн Катмулла—Рома через точки (работает и для радиусов)."""
    pts = np.asarray(pts, float)
    one_d = pts.ndim == 1
    if one_d:
        pts = pts[:, None]
    if len(pts) < 3:
        out = np.array([pts[0] + (pts[-1] - pts[0]) * t for t in np.linspace(0, 1, n)])
        return out[:, 0] if one_d else out
    P = np.vstack([2 * pts[0] - pts[1], pts, 2 * pts[-1] - pts[-2]])
    segs = len(pts) - 1
    out = []
    for u in np.linspace(0, segs, n):
        i = min(int(u), segs - 1)
        t = u - i
        p0, p1, p2, p3 = P[i], P[i + 1], P[i + 2], P[i + 3]
        out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
                          + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    out = np.array(out)
    return out[:, 0] if one_d else out


def hex2rgb(h):
    h = h.lstrip('#')
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], float) / 255


# ----------------------------------------------------------------- градиенты

GRADS = {
    'rainbow': ['#FF3B4E', '#FF8A1F', '#FFD93B', '#3DDC6B', '#2FB8FF', '#7A5CFF', '#E04CFF'],
    'rainbow_loop': ['#FF3B4E', '#FF8A1F', '#FFD93B', '#3DDC6B', '#2FB8FF', '#7A5CFF', '#E04CFF', '#FF3B4E'],
    'aurora': ['#F4FBFF', '#8CFBE6', '#3DE39A', '#35B8FF', '#8E6BFF', '#FF7AD9'],
    'aurora_loop': ['#3DE39A', '#35C8FF', '#8E6BFF', '#FF7AD9', '#8E6BFF', '#35C8FF', '#3DE39A'],
    'bun': ['#FBE6B8', '#F6CC84', '#EBA646', '#DC8C2C'],
    'ear_aurora': ['#EAF6FF', '#7DF9E0', '#8E6BFF'],
}


def grad_eval(name, t):
    stops = np.array([hex2rgb(h) for h in GRADS[name]])
    t = np.clip(np.asarray(t, float), 0, 1) * (len(stops) - 1)
    i = np.minimum(t.astype(int), len(stops) - 2)
    f = (t - i)[..., None]
    return stops[i] * (1 - f) + stops[i + 1] * f


class G:
    """Градиентная заливка. mode: 'x'/'y'/'z' — по локальной оси примитива,
    'u' — вокруг оси, 'v' — вдоль трубки/профиля."""

    def __init__(self, name, mode='y', lo=0.0, hi=1.0):
        self.name, self.mode, self.lo, self.hi = name, mode, lo, hi


# ----------------------------------------------------------------- сетка

def grid(P, top=None, bot=None):
    """P: (nv, nu, 3) — кольца точек. Возвращает V, F, tu, tv (со швом по u)."""
    P = np.asarray(P, float)
    nv, nu = P.shape[:2]
    P2 = np.concatenate([P, P[:, :1]], 1)
    V = P2.reshape(-1, 3)
    tu = np.tile(np.arange(nu + 1) / nu, nv)
    tv = np.repeat(np.arange(nv) / max(nv - 1, 1), nu + 1)
    w = nu + 1
    i, j = np.meshgrid(np.arange(nv - 1), np.arange(nu), indexing='ij')
    a = (i * w + j).ravel()
    b = (i * w + j + 1).ravel()
    c = ((i + 1) * w + j + 1).ravel()
    d = ((i + 1) * w + j).ravel()
    F = [np.stack([a, b, c], 1), np.stack([a, c, d], 1)]
    V = [V]
    tu, tv = [tu], [tv]
    n = nv * w
    jj = np.arange(nu)
    if top is not None:
        V.append(np.asarray(top, float)[None])
        tu.append([0.5]); tv.append([0.0])
        F.append(np.stack([np.full(nu, n), jj + 1, jj], 1))
        n += 1
    if bot is not None:
        V.append(np.asarray(bot, float)[None])
        tu.append([0.5]); tv.append([1.0])
        base = (nv - 1) * w
        F.append(np.stack([np.full(nu, n), base + jj, base + jj + 1], 1))
    V = np.vstack(V)
    F = np.vstack(F)
    # ориентация наружу: знак объёма
    p = V[F]
    vol = np.einsum('ij,ij->i', p[:, 0], np.cross(p[:, 1], p[:, 2])).sum()
    c0 = V.mean(0)
    p = p - c0
    vol = np.einsum('ij,ij->i', p[:, 0], np.cross(p[:, 1], p[:, 2])).sum()
    if vol < 0:
        F = F[:, ::-1]
    return V, F, np.concatenate(tu), np.concatenate(tv)


def auto_seg(rmax):
    nu = int(np.clip(round(8 + 13 * rmax ** 0.7), 8, 26))
    nu += nu % 2
    return nu, max(5, int(round(nu * 0.6)))


class Part:
    __slots__ = ('V', 'F', 'color', 't', 'crease')

    def __init__(self, V, F, color, t, crease):
        self.V, self.F, self.color, self.t, self.crease = V, F, color, t, crease


# ----------------------------------------------------------------- модель

class Model:
    def __init__(self, key, title, recipe, height=3.6):
        self.key, self.title, self.recipe, self.height = key, title, recipe, height
        self.parts = []
        self.rng = np.random.RandomState(zlib.crc32(key.encode()) % (2 ** 31))

    # --- базовое добавление
    def add(self, V, F, color, tu=None, tv=None, pos=(0, 0, 0), rot=None, crease=55):
        t = None
        if isinstance(color, G):
            if color.mode == 'u':
                t = tu
            elif color.mode == 'v':
                t = tv
            else:
                a = V[:, 'xyz'.index(color.mode)]
                t = (a - a.min()) / max(np.ptp(a), 1e-9)
            t = color.lo + (color.hi - color.lo) * np.asarray(t, float)
        R = as_rot(rot)
        Vw = V @ R.T + np.asarray(pos, float)
        self.parts.append(Part(Vw, np.asarray(F), color, t, crease))
        return self

    # --- эллипсоид
    def ell(self, c, r, color, rot=None, seg=None, crease=180):
        r = np.ones(3) * np.asarray(r, float)
        nu, nv = seg or auto_seg(r.max())
        th = np.pi * np.arange(1, nv) / nv
        ph = TAU * np.arange(nu) / nu
        P = np.stack([np.outer(np.sin(th), np.cos(ph)),
                      np.outer(np.cos(th), np.ones(nu)),
                      np.outer(np.sin(th), np.sin(ph))], 2) * r
        V, F, tu, tv = grid(P, top=(0, r[1], 0), bot=(0, -r[1], 0))
        return self.add(V, F, color, tu, tv, c, rot, crease)

    # --- суперэллипсоид (скруглённая коробка / таблетка)
    def sq(self, c, r, color, e1=0.5, e2=0.5, rot=None, seg=None, crease=180):
        r = np.ones(3) * np.asarray(r, float)
        nu, nv = seg or auto_seg(r.max())
        nv = max(nv, 10)
        P = sq_points(np.pi / 2 - np.pi * np.arange(1, nv) / nv, TAU * np.arange(nu) / nu, r, e1, e2)
        V, F, tu, tv = grid(P, top=(0, r[1], 0), bot=(0, -r[1], 0))
        return self.add(V, F, color, tu, tv, c, rot, crease)

    # --- трубка вдоль пути
    def tube(self, pts, rad, color, seg=10, n=None, caps='round', squash=(1, 1), up=(0, 1, 0),
             closed=False, twist=0, crease=180, capn=3):
        pts = np.asarray(pts, float)
        rad = np.ones(len(pts)) * np.asarray(rad, float)
        if n:
            pts, rad = smooth(pts, n), np.maximum(smooth(rad, n), 1e-3)
        m = len(pts)
        if closed:
            T = np.roll(pts, -1, 0) - np.roll(pts, 1, 0)
        else:
            T = np.gradient(pts, axis=0)
        T = np.array([nrm(t) for t in T])
        N = np.zeros_like(pts)
        n0 = np.asarray(up, float) - np.dot(up, T[0]) * T[0]
        if np.linalg.norm(n0) < 1e-6:
            n0 = np.array([1.0, 0, 0]) - T[0][0] * T[0]
        N[0] = nrm(n0)
        for i in range(1, m):
            v = N[i - 1] - np.dot(N[i - 1], T[i]) * T[i]
            N[i] = nrm(v)
        B = np.cross(T, N)
        a = TAU * np.arange(seg) / seg
        tw = np.radians(twist) * np.linspace(0, 1, m)
        rings, tvs = [], []

        def ring(p, r, i, k=0.0):
            ca, sa = np.cos(a + tw[i]), np.sin(a + tw[i])
            return p + r * (squash[0] * ca[:, None] * N[i] + squash[1] * sa[:, None] * B[i])

        top = bot = None
        nc = capn
        if not closed and caps == 'round':
            for k in range(nc - 1, 0, -1):
                ang = math.pi / 2 * k / nc
                rings.append(ring(pts[0] - T[0] * rad[0] * math.sin(ang) * min(squash), rad[0] * math.cos(ang), 0))
                tvs.append(0.0)
            top = pts[0] - T[0] * rad[0] * min(squash)
        elif not closed:
            top = pts[0]
        L = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(pts, axis=0), axis=1))])
        L = L / max(L[-1], 1e-9)
        for i in range(m):
            rings.append(ring(pts[i], rad[i], i))
            tvs.append(L[i])
        if closed:
            rings.append(rings[0])
            tvs.append(1.0)
        elif caps == 'round':
            for k in range(1, nc):
                ang = math.pi / 2 * k / nc
                rings.append(ring(pts[-1] + T[-1] * rad[-1] * math.sin(ang) * min(squash), rad[-1] * math.cos(ang), m - 1))
                tvs.append(1.0)
            bot = pts[-1] + T[-1] * rad[-1] * min(squash)
        else:
            bot = pts[-1]
        V, F, tu, tv = grid(np.array(rings), top=top, bot=bot)
        tvs = np.array(tvs)
        tvv = np.repeat(tvs, seg + 1)
        if top is not None:
            tvv = np.append(tvv, 0.0)
        if bot is not None:
            tvv = np.append(tvv, 1.0)
        return self.add(V, F, color, tu, tvv, crease=crease)

    def capsule(self, p0, p1, r0, color, r1=None, seg=10, **kw):
        return self.tube([p0, p1], [r0, r0 if r1 is None else r1], color, seg=seg, **kw)

    def cone(self, p0, p1, r0, color, r1=0.02, seg=12, crease=50):
        """Конус с плоским основанием и скруглённым кончиком."""
        return self.tube([p0, p1], [r0, r1], color, seg=seg, caps='flat', crease=crease)

    def torus(self, c, R, r, color, rot=None, seg=10, n=32, squash=(1, 1), wave=0, waves=8):
        a = TAU * np.arange(n) / n
        pts = np.stack([R * np.cos(a), wave * np.sin(waves * a), R * np.sin(a)], 1)
        Rm = as_rot(rot)
        pts = pts @ Rm.T + np.asarray(c, float)
        return self.tube(pts, r, color, seg=seg, closed=True, up=Rm @ np.array([0, 1.0, 0]), squash=squash)

    # --- тело вращения вокруг Y: profile = [(r, y), ...] сверху вниз или снизу вверх
    def lathe(self, prof, color, pos=(0, 0, 0), rot=None, seg=24, flute=None, crease=55):
        prof = np.asarray(prof, float)
        ph = TAU * np.arange(seg) / seg
        top = bot = None
        body = prof
        if prof[0, 0] < 1e-6:
            top, body = (0, prof[0, 1], 0), body[1:]
        else:
            top = (0, prof[0, 1], 0)
        if prof[-1, 0] < 1e-6:
            bot, body = (0, prof[-1, 1], 0), body[:-1]
        else:
            bot = (0, prof[-1, 1], 0)
        k = np.linspace(0, 1, len(body))
        rings = []
        for (r, y), kk in zip(body, k):
            rr = r * (flute(ph, kk) if flute else np.ones(seg))
            rings.append(np.stack([rr * np.cos(ph), np.full(seg, y), rr * np.sin(ph)], 1))
        V, F, tu, tv = grid(np.array(rings), top=top, bot=bot)
        return self.add(V, F, color, tu, tv, pos, rot, crease)

    # --- призма: многоугольник в XY, вытянутый по Z
    def prism(self, poly, depth, color, pos=(0, 0, 0), rot=None, crease=40):
        poly = np.asarray(poly, float)
        n = len(poly)
        c = poly.mean(0)
        V = [np.append(c, depth / 2), np.append(c, -depth / 2)]
        for z in (depth / 2, -depth / 2):
            V += [np.append(p, z) for p in poly]
        V = np.array(V)
        F = []
        for i in range(n):
            j = (i + 1) % n
            F += [[0, 2 + i, 2 + j], [1, 2 + n + j, 2 + n + i],
                  [2 + i, 2 + n + i, 2 + n + j], [2 + i, 2 + n + j, 2 + j]]
        F = np.array(F)
        p = V[F] - V.mean(0)
        if np.einsum('ij,ij->i', p[:, 0], np.cross(p[:, 1], p[:, 2])).sum() < 0:
            F = F[:, ::-1]
        return self.add(V, F, color, pos=pos, rot=rot, crease=crease)

    # --- глазурь с потёками поверх (супер)эллипсоида
    def glaze(self, c, r, color, y0=0.3, amp=0.3, lobes=8, e1=1.0, e2=1.0, rot=None, thick=0.05,
              seed=0, nv=8, per=8, minamp=0.3, calm=0.0, calm_w=55):
        r = np.ones(3) * np.asarray(r, float)
        nu = lobes * per
        ph = TAU * np.arange(nu) / nu
        rs = np.random.RandomState(seed + 7)
        amps = minamp + (1 - minamp) * rs.rand(lobes)
        widths = rs.rand(lobes) * 0.5 + 0.75
        fr = ph / TAU * lobes
        k = np.minimum(fr.astype(int), lobes - 1)
        d = amps[k] * np.sin(np.pi * (fr - k)) ** (2 * widths[k])
        dphi = (ph - np.pi / 2 + np.pi) % TAU - np.pi
        d = d * (1 - calm * np.exp(-(dphi / math.radians(calm_w)) ** 2))
        yf = np.clip(y0 - amp * d, -0.97, 0.97)
        v_edge = np.arcsin(np.sign(yf) * np.abs(yf) ** (1 / e1))
        ro, ri = r + thick, np.maximum(r - 2.5 * thick, r * 0.5)
        rings = []
        for i in range(1, nv + 1):
            v = np.pi / 2 - (i / nv) * (np.pi / 2 - v_edge)
            rings.append(sq_points_pair(v, ph, ro, e1, e2))
        rings.append(sq_points_pair(v_edge, ph, ri, e1, e2))
        V, F, tu, tv = grid(np.array(rings), top=(0, ro[1], 0), bot=(0, 0, 0))
        return self.add(V, F, color, tu, tv, c, rot, crease=65)

    # ------------------------------------------------------- удобные детали
    def on(self, c, r, yaw, pitch, out=0.0):
        """Точка и нормаль на эллипсоиде. yaw: 0 = перёд (+Z), + вправо (+X); pitch: вверх."""
        r = np.ones(3) * np.asarray(r, float)
        y, p = math.radians(yaw), math.radians(pitch)
        d = np.array([math.sin(y) * math.cos(p), math.sin(p), math.cos(y) * math.cos(p)])
        n = nrm(d / r)
        return np.asarray(c, float) + r * d + n * out, n

    def disc(self, p, n, rad, color, thick=0.04, squash=(1, 1), spin=0, seg=None):
        return self.ell(p, (rad * squash[0], rad * squash[1], thick), color, rot=look(n, spin=spin), seg=seg)

    def eye(self, p, n, s=0.3, color='#1A1A28', wide=0.82, shine=True):
        R = look(n)
        self.ell(p, (s * wide, s, s * 0.36), color, rot=R)
        if shine:
            self.ell(p + R @ np.array([-0.26 * s, 0.36 * s, 0.27 * s]), (0.27 * s, 0.27 * s, 0.1 * s), '#FFFFFF', rot=R, seg=(10, 6))
            self.ell(p + R @ np.array([0.26 * s, -0.34 * s, 0.29 * s]), (0.13 * s, 0.13 * s, 0.07 * s), '#FFFFFF', rot=R, seg=(8, 5))
        return self

    def eyes(self, c, r, yaw=24, pitch=5, s=0.3, **kw):
        for sg in (-1, 1):
            p, n = self.on(c, r, sg * yaw, pitch)
            self.eye(p, n, s, **kw)
        return self

    def blush(self, c, r, yaw=42, pitch=-12, s=0.2, color='#FF8FA8'):
        for sg in (-1, 1):
            p, n = self.on(c, r, sg * yaw, pitch)
            self.disc(p, n, s, color, thick=0.035, squash=(1, 0.62), seg=(12, 6))
        return self

    def line_on(self, c, r, yp, rad=0.035, color='#3A1F1F', out=0.0, n=14, seg=6):
        pts = [self.on(c, r, y, p, out)[0] for y, p in yp]
        return self.tube(pts, rad, color, seg=seg, n=n)

    def smile(self, c, r, yaw=10, pitch=-18, depth=6, rad=0.035, color='#3A1F1F', center=0):
        yp = [(center + y, pitch - depth * (1 - (y / yaw) ** 2)) for y in np.linspace(-yaw, yaw, 7)]
        return self.line_on(c, r, yp, rad, color)

    def mouth_w(self, c, r, yaw=7, pitch=-16, depth=5, rad=0.032, color='#3A1F1F'):
        for sg in (-1, 1):
            self.smile(c, r, yaw / 2, pitch, depth, rad, color, center=sg * yaw / 2)
        return self

    def open_mouth(self, p, n, w=0.22, h=0.16, color='#7A1F2B', tongue='#FF7A9C'):
        R = look(n)
        self.ell(p, (w, h, 0.05), color, rot=R, seg=(14, 7))
        self.ell(p + R @ np.array([0, -h * 0.42, 0.025]), (w * 0.6, h * 0.45, 0.045), tongue, rot=R, seg=(10, 6))
        return self

    def sprinkle(self, p, n, color, length=0.16, rad=0.035, ang=None):
        ang = self.rng.rand() * TAU if ang is None else ang
        R = look(n)
        d = R @ np.array([math.cos(ang), math.sin(ang), 0])
        p = np.asarray(p, float) + n * rad * 0.6
        return self.tube([p - d * length / 2, p + d * length / 2], rad, color, seg=5, capn=2)

    def strawberry(self, pos, size=0.4, rot=None, seeds=True, leaves=True):
        R = as_rot(rot)
        pos = np.asarray(pos, float)
        prof = np.array([(0, 0.98), (0.3, 0.97), (0.52, 0.86), (0.64, 0.62), (0.6, 0.34), (0.44, 0.08),
                         (0.24, -0.14), (0.08, -0.24), (0, -0.26)]) * size
        self.lathe(prof, '#EE2A4F', pos, R, seg=14 if leaves else 10, crease=180)
        top = pos + R @ np.array([0, 0.97 * size, 0])
        if leaves:
            for i in range(5):
                a = TAU * i / 5
                d = R @ np.array([math.cos(a), -0.12, math.sin(a)])
                self.ell(top + d * 0.26 * size, (0.3 * size, 0.07 * size, 0.15 * size), '#3FBF4F',
                         rot=R @ Ry(-math.degrees(a)) @ Rz(-12), seg=(8, 5))
            self.capsule(top, top + R @ np.array([0.03, 0.22, 0]) * size, 0.06 * size, '#2F9E44', seg=6)
        if seeds:
            for i, (a, y, rr) in enumerate([(0.3, 0.7, 0.6), (2.4, 0.7, 0.6), (4.5, 0.7, 0.6), (1.3, 0.42, 0.61),
                                            (3.4, 0.42, 0.61), (5.5, 0.42, 0.61), (0.4, 0.14, 0.47), (2.5, 0.14, 0.47),
                                            (4.6, 0.14, 0.47)]):
                d = np.array([math.cos(a), 0, math.sin(a)])
                self.ell(pos + R @ (d * rr * size + np.array([0, y * size, 0])), 0.045 * size, '#FFE27A', seg=(6, 4))
        return self

    # ------------------------------------------------------- запекание
    def colors_used(self):
        solids, grads = [], []
        for p in self.parts:
            if isinstance(p.color, G):
                if p.color.name not in grads:
                    grads.append(p.color.name)
            elif p.color not in solids:
                solids.append(p.color)
        return solids, grads

    def atlas(self, size=256, cell=16):
        solids, grads = self.colors_used()
        img = np.zeros((size, size, 3), np.uint8)
        img[:] = 255
        for k, g in enumerate(grads):
            strip = grad_eval(g, np.linspace(0, 1, size)) * 255
            img[k * cell:(k + 1) * cell] = strip.astype(np.uint8)[None]
        per = size // cell
        for i, h in enumerate(solids):
            y0 = (len(grads) + i // per) * cell
            x0 = (i % per) * cell
            img[y0:y0 + cell, x0:x0 + cell] = (hex2rgb(h) * 255).astype(np.uint8)
        return Image.fromarray(img, 'RGB'), solids, grads

    def bake(self):
        """Возвращает P, N, UV, RGB, I — сваренный меш (перёд смотрит в +Z, низ на y=0)."""
        size, cell = 256, 16
        _, solids, grads = self.atlas(size, cell)
        per = size // cell
        Ps, Ns, UVs, Cs = [], [], [], []
        for part in self.parts:
            F, N = corner_normals(part.V, part.F, part.crease)
            if isinstance(part.color, G):
                k = grads.index(part.color.name)
                t = np.clip(part.t, 0, 1)
                uv = np.stack([(0.5 + t * (size - 1)) / size, np.full(len(t), (k * cell + cell / 2) / size)], 1)
                col = grad_eval(part.color.name, t)
            else:
                i = solids.index(part.color)
                u = ((i % per) * cell + cell / 2) / size
                v = ((len(grads) + i // per) * cell + cell / 2) / size
                uv = np.tile([u, v], (len(part.V), 1))
                col = np.tile(hex2rgb(part.color), (len(part.V), 1))
            Ps.append(part.V[F].reshape(-1, 3))
            Ns.append(N.reshape(-1, 3))
            UVs.append(uv[F].reshape(-1, 2))
            Cs.append(col[F].reshape(-1, 3))
        P, N, UV, C = map(np.vstack, (Ps, Ns, UVs, Cs))
        # посадить на землю, отцентровать, привести к целевой высоте
        mn, mx = P.min(0), P.max(0)
        s = self.height / (mx[1] - mn[1])
        P = (P - [(mn[0] + mx[0]) / 2, mn[1], (mn[2] + mx[2]) / 2]) * s
        allv = np.round(np.hstack([P, N, UV, C]), 5)
        uniq, inv = np.unique(allv, axis=0, return_inverse=True)
        I = inv.reshape(-1, 3)
        return uniq[:, 0:3], uniq[:, 3:6], uniq[:, 6:8], uniq[:, 8:11], I


def _f(w, e):
    c = np.cos(w)
    return np.sign(c) * np.abs(c) ** e


def _g(w, e):
    s = np.sin(w)
    return np.sign(s) * np.abs(s) ** e


def sq_points(v, u, r, e1, e2):
    """Сетка суперэллипсоида: v — широты (nv,), u — долготы (nu,)."""
    return np.stack([np.outer(_f(v, e1), _f(u, e2)) * r[0],
                     np.outer(_g(v, e1), np.ones(len(u))) * r[1],
                     np.outer(_f(v, e1), _g(u, e2)) * r[2]], 2)


def sq_points_pair(v, u, r, e1, e2):
    """Одно кольцо, где широта своя для каждой долготы."""
    return np.stack([_f(v, e1) * _f(u, e2) * r[0], _g(v, e1) * r[1], _f(v, e1) * _g(u, e2) * r[2]], 1)


def sq_front(c, r, e1, e2, x, y, out=0.0):
    """Точка и нормаль на передней (+Z) стороне суперэллипсоида по локальным x, y."""
    c = np.asarray(c, float)

    def z_of(x, y):
        a = max(1 - abs(y / r[1]) ** (2 / e1), 0) ** (e1 / e2) - abs(x / r[0]) ** (2 / e2)
        return r[2] * max(a, 0) ** (e2 / 2)

    h = 1e-3
    z = z_of(x, y)
    n = nrm([-(z_of(x + h, y) - z_of(x - h, y)) / (2 * h), -(z_of(x, y + h) - z_of(x, y - h)) / (2 * h), 1])
    return c + np.array([x, y, z]) + n * out, n


def corner_normals(V, F, crease):
    P = V[F]
    fn = np.cross(P[:, 1] - P[:, 0], P[:, 2] - P[:, 0])
    area = np.linalg.norm(fn, axis=1)
    keep = area > 1e-9
    F, fn, area = F[keep], fn[keep], area[keep]
    fu = fn / area[:, None]
    key = np.round(V * 2000).astype(np.int64)
    _, inv = np.unique(key, axis=0, return_inverse=True)
    cid = inv.ravel()[F]
    m = len(F)
    if crease >= 179:
        acc = np.zeros((cid.max() + 1, 3))
        for k in range(3):
            np.add.at(acc, cid[:, k], fn)
        N = acc[cid]
    else:
        flat = cid.ravel()
        order = np.argsort(flat, kind='stable')
        bounds = np.flatnonzero(np.diff(flat[order])) + 1
        N = np.zeros((m * 3, 3))
        cosc = math.cos(math.radians(crease))
        for g in np.split(order, bounds):
            fi = g // 3
            U = fu[fi]
            N[g] = ((U @ U.T) >= cosc) @ fn[fi]
        N = N.reshape(m, 3, 3)
    ln = np.linalg.norm(N, axis=2, keepdims=True)
    N = np.where(ln > 1e-12, N / np.maximum(ln, 1e-12), fu[:, None, :])
    return F, N


# ----------------------------------------------------------------- экспорт

def to_roblox(P, N):
    """Поворот на 180° вокруг Y: в Roblox «лицо» детали — это −Z."""
    f = np.array([-1.0, 1.0, -1.0])
    return P * f, N * f


def write_glb(path, name, P, N, UV, I, png):
    P, N = to_roblox(P, N)
    P32, N32, UV32 = P.astype('<f4'), N.astype('<f4'), UV.astype('<f4')
    big = len(P) > 65535
    I32 = I.astype('<u4' if big else '<u2')
    chunks, views = [], []
    off = 0

    def push(b, target=None):
        nonlocal off
        pad = (-len(b)) % 4
        v = {"buffer": 0, "byteOffset": off, "byteLength": len(b)}
        if target:
            v["target"] = target
        views.append(v)
        chunks.append(b + b'\0' * pad)
        off += len(b) + pad

    push(P32.tobytes(), 34962)
    push(N32.tobytes(), 34962)
    push(UV32.tobytes(), 34962)
    push(I32.tobytes(), 34963)
    push(png)
    gltf = {
        "asset": {"version": "2.0", "generator": "monster-bakery-kit"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"mesh": 0, "name": name}],
        "meshes": [{"name": name, "primitives": [{
            "attributes": {"POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2}, "indices": 3, "material": 0}]}],
        "materials": [{"name": name + "_mat", "pbrMetallicRoughness": {
            "baseColorTexture": {"index": 0}, "metallicFactor": 0.0, "roughnessFactor": 0.7}}],
        "textures": [{"source": 0, "sampler": 0}],
        "samplers": [{"magFilter": 9729, "minFilter": 9987, "wrapS": 33071, "wrapT": 33071}],
        "images": [{"bufferView": 4, "mimeType": "image/png", "name": name + "_palette"}],
        "accessors": [
            {"bufferView": 0, "componentType": 5126, "count": len(P), "type": "VEC3",
             "min": P32.min(0).tolist(), "max": P32.max(0).tolist()},
            {"bufferView": 1, "componentType": 5126, "count": len(N), "type": "VEC3"},
            {"bufferView": 2, "componentType": 5126, "count": len(UV), "type": "VEC2"},
            {"bufferView": 3, "componentType": 5125 if big else 5123, "count": int(I.size), "type": "SCALAR"},
        ],
        "bufferViews": views,
        "buffers": [{"byteLength": off}],
    }
    js = json.dumps(gltf, separators=(',', ':')).encode('utf-8')
    js += b' ' * ((-len(js)) % 4)
    binary = b''.join(chunks)
    with open(path, 'wb') as f:
        f.write(struct.pack('<4sII', b'glTF', 2, 12 + 8 + len(js) + 8 + len(binary)))
        f.write(struct.pack('<I4s', len(js), b'JSON'))
        f.write(js)
        f.write(struct.pack('<I4s', len(binary), b'BIN\0'))
        f.write(binary)


def write_obj(folder, name, P, N, UV, I, atlas_img):
    P, N = to_roblox(P, N)
    os.makedirs(folder, exist_ok=True)
    atlas_img.save(os.path.join(folder, name + '.png'))
    with open(os.path.join(folder, name + '.mtl'), 'w', encoding='utf-8') as f:
        f.write(f"newmtl palette\nKa 1 1 1\nKd 1 1 1\nKs 0 0 0\nd 1\nillum 1\nmap_Kd {name}.png\n")
    with open(os.path.join(folder, name + '.obj'), 'w', encoding='utf-8') as f:
        f.write(f"mtllib {name}.mtl\no {name}\n")
        for p in P:
            f.write("v %.5f %.5f %.5f\n" % tuple(p))
        for t in UV:
            f.write("vt %.5f %.5f\n" % (t[0], 1 - t[1]))
        for n in N:
            f.write("vn %.4f %.4f %.4f\n" % tuple(n))
        f.write("usemtl palette\ns 1\n")
        for a, b, c in I + 1:
            f.write(f"f {a}/{a}/{a} {b}/{b}/{b} {c}/{c}/{c}\n")


# ----------------------------------------------------------------- превью-рендер

def render(P, N, C, I, size=560, yaw=28, pitch=10, ss=2, fit=None, bg=((255, 247, 236), (255, 222, 196))):
    R = Rx(pitch) @ Ry(-yaw)
    Pc, Nc = P @ R.T, N @ R.T
    mn, mx = Pc.min(0), Pc.max(0)
    ctr = (mn + mx) / 2
    ext = fit or max(mx[0] - mn[0], mx[1] - mn[1])
    W = H = size * ss
    s = W * 0.8 / ext
    x = (Pc[:, 0] - ctr[0]) * s + W / 2
    y = H * 0.5 - (Pc[:, 1] - ctr[1]) * s
    z = Pc[:, 2]
    zbuf = np.full((H, W), -1e9)
    nb = np.zeros((H, W, 3))
    cb = np.zeros((H, W, 3))
    X, Y, Z = x[I], y[I], z[I]
    area = (X[:, 1] - X[:, 0]) * (Y[:, 2] - Y[:, 0]) - (Y[:, 1] - Y[:, 0]) * (X[:, 2] - X[:, 0])
    for f in np.flatnonzero(area < -1e-9):
        x0, x1, x2 = X[f]
        y0, y1, y2 = Y[f]
        ax, bx = max(int(min(x0, x1, x2)), 0), min(int(max(x0, x1, x2)) + 1, W - 1)
        ay, by = max(int(min(y0, y1, y2)), 0), min(int(max(y0, y1, y2)) + 1, H - 1)
        if ax > bx or ay > by:
            continue
        gx, gy = np.meshgrid(np.arange(ax, bx + 1) + 0.5, np.arange(ay, by + 1) + 0.5)
        w0 = ((x2 - x1) * (gy - y1) - (y2 - y1) * (gx - x1)) / area[f]
        w1 = ((x0 - x2) * (gy - y2) - (y0 - y2) * (gx - x2)) / area[f]
        w2 = 1 - w0 - w1
        zz = w0 * Z[f, 0] + w1 * Z[f, 1] + w2 * Z[f, 2]
        sub = zbuf[ay:by + 1, ax:bx + 1]
        upd = (w0 >= -1e-6) & (w1 >= -1e-6) & (w2 >= -1e-6) & (zz > sub)
        if not upd.any():
            continue
        sub[upd] = zz[upd]
        i0, i1, i2 = I[f]
        w = np.stack([w0[upd], w1[upd], w2[upd]], 1)
        nb[ay:by + 1, ax:bx + 1][upd] = w @ Nc[[i0, i1, i2]]
        cb[ay:by + 1, ax:bx + 1][upd] = w @ C[[i0, i1, i2]]
    mask = zbuf > -1e8
    n = nb / np.maximum(np.linalg.norm(nb, axis=2, keepdims=True), 1e-9)
    L = nrm([-0.45, 0.75, 0.6])
    h = np.clip(n @ L * 0.5 + 0.5, 0, 1)
    diff = 0.56 + 0.54 * h ** 1.4
    hemi = (0.5 + 0.5 * n[..., 1])[..., None]
    tint = np.array([0.87, 0.83, 0.93]) * (1 - hemi) + np.array([1.0, 1.0, 1.0]) * hemi
    Hh = nrm(L + np.array([0, 0, 1.0]))
    spec = np.clip(n @ Hh, 0, 1) ** 48 * 0.35
    rim = np.clip(1 - n[..., 2], 0, 1) ** 4 * 0.10
    col = cb * diff[..., None] * tint + spec[..., None] + rim[..., None]
    # «затемнение по глубине» — дешёвая имитация мягких теней в складках
    zf = np.where(mask, zbuf, zbuf[mask].min() if mask.any() else 0)
    zbl = box_blur(zf, max(int(W / 40), 1))
    ao = np.clip(1 - np.maximum(zbl - zf, 0) * 0.55, 0.55, 1)
    col = np.clip(col * ao[..., None], 0, 1)
    # фон + тень
    yy, xx = np.mgrid[0:H, 0:W]
    d = np.sqrt(((xx - W / 2) / W) ** 2 + ((yy - H * 0.45) / H) ** 2)
    k = np.clip(d * 1.6, 0, 1)[..., None]
    back = np.array(bg[0]) / 255 * (1 - k) + np.array(bg[1]) / 255 * k
    shadow = Image.new('L', (W, H), 0)
    gy0 = H * 0.5 - (mn[1] - ctr[1]) * s
    wx = (mx[0] - mn[0]) * s * 0.5
    ImageDraw.Draw(shadow).ellipse([W / 2 - wx, gy0 - wx * 0.2, W / 2 + wx, gy0 + wx * 0.2], fill=110)
    sh = np.asarray(shadow.filter(ImageFilter.GaussianBlur(W / 40))) / 255.0
    back = back * (1 - sh[..., None] * 0.45)
    out = np.where(mask[..., None], col, back)
    img = Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8), 'RGB')
    return img.resize((size, size), Image.LANCZOS)


def box_blur(a, r):
    """Три прохода box-фильтра ≈ гауссово размытие."""
    for _ in range(3):
        for ax in (0, 1):
            pad = [(0, 0), (0, 0)]
            pad[ax] = (r + 1, r)
            c = np.cumsum(np.pad(a, pad, mode='edge'), axis=ax)
            n = a.shape[ax]
            hi = np.take(c, np.arange(2 * r + 1, 2 * r + 1 + n), axis=ax)
            lo = np.take(c, np.arange(0, n), axis=ax)
            a = (hi - lo) / (2 * r + 1)
    return a


def font(px, bold=True):
    for name in (['segoeuib.ttf', 'arialbd.ttf'] if bold else ['segoeui.ttf', 'arial.ttf']):
        try:
            return ImageFont.truetype(os.path.join(os.environ.get('WINDIR', 'C:/Windows'), 'Fonts', name), px)
        except OSError:
            pass
    return ImageFont.load_default()
