"""Eigene, prozedural erzeugte Bodentexturen fuer die Burgkarte (keine Fremddaten, keine Fotos).

- flusskiesel_pflaster: runde/laengliche Flusskiesel hochkant im Sandbett (Kachel 1,2 m)
- sandweg_hell:         heller, wassergebundener Sand-/Feinkiesweg (Kachel 2,0 m)

Je Satz albedo/normal/roughness als kachelbares PNG (1024 px) nach assets/maps/castle/kit/textures.
Aufruf: D:\\Workspace_D\\tools\\pyenv\\Scripts\\python.exe -I tools\\gen_castle_ground.py [Zielordner]
"""
import os
import sys

import numpy as np
from PIL import Image

N = 1024
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "assets", "maps", "castle", "kit", "textures")


def blur_periodic(a, sigma):
    """Gauss-Weichzeichnung mit periodischem Rand (FFT) -> kachelbar."""
    fy = np.fft.fftfreq(a.shape[0])[:, None]
    fx = np.fft.fftfreq(a.shape[1])[None, :]
    g = np.exp(-2.0 * (np.pi * sigma) ** 2 * (fx * fx + fy * fy))
    return np.real(np.fft.ifft2(np.fft.fft2(a) * g))


def noise(rng, sigma, n=N):
    a = blur_periodic(rng.standard_normal((n, n)), sigma)
    a -= a.mean()
    return a / (a.std() + 1e-9)


def normal_from_height(h, strength):
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5 * strength
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5 * strength
    nz = np.ones_like(h)
    l = np.sqrt(dx * dx + dy * dy + nz * nz)
    # OpenGL-Konvention (Godot): +Y nach oben im Bild
    n = np.stack([-dx / l, dy / l, nz / l], -1)
    return ((n * 0.5 + 0.5) * 255).clip(0, 255).astype(np.uint8)


def save(name, alb, nrm, rgh):
    os.makedirs(OUT, exist_ok=True)
    Image.fromarray((alb.clip(0, 1) * 255).astype(np.uint8), "RGB").save(os.path.join(OUT, name + "_albedo.png"), optimize=True)
    Image.fromarray(nrm, "RGB").save(os.path.join(OUT, name + "_normal.png"), optimize=True)
    Image.fromarray((rgh.clip(0, 1) * 255).astype(np.uint8), "L").save(os.path.join(OUT, name + "_roughness.png"), optimize=True)
    print("geschrieben:", name)


def pebbles():
    rng = np.random.default_rng(7101)
    cells = 17                       # 17 x 17 Zellen auf 1,2 m -> Kiesel ~ 5-10 cm
    cs = N / cells
    # Saatpunkte je Zelle (Jitter), Form je Kiesel: Halbachsen, Drehung, Farbe
    seeds = (np.stack(np.meshgrid(np.arange(cells), np.arange(cells), indexing="xy"), -1) + 0.15 + rng.random((cells, cells, 2)) * 0.7) * cs
    ang = rng.random((cells, cells)) * np.pi
    # Reihen leicht laengs ausgerichtet (Kiesel hochkant quer zur Fahrtrichtung gesetzt)
    ang = np.where(rng.random((cells, cells)) < 0.6, rng.normal(0.0, 0.35, (cells, cells)), ang)
    ax_a = cs * (0.5 + rng.random((cells, cells)) * 0.1)
    ax_b = ax_a * (0.72 + rng.random((cells, cells)) * 0.24)
    palette = np.array([
        [0.56, 0.55, 0.52], [0.63, 0.61, 0.57], [0.50, 0.50, 0.49], [0.64, 0.60, 0.53],
        [0.54, 0.55, 0.56], [0.70, 0.68, 0.64], [0.56, 0.51, 0.46], [0.45, 0.45, 0.46], [0.74, 0.72, 0.68]])
    col = palette[rng.integers(0, len(palette), (cells, cells))] * (0.88 + rng.random((cells, cells, 1)) * 0.24)

    yy, xx = np.mgrid[0:N, 0:N].astype(np.float64)
    best = np.full((N, N), 9.0)
    cid = np.zeros((N, N, 2), dtype=np.int64)
    ci = (xx // cs).astype(np.int64)
    cj = (yy // cs).astype(np.int64)
    for dj in (-1, 0, 1):
        for di in (-1, 0, 1):
            i = ci + di
            j = cj + dj
            iw = i % cells
            jw = j % cells
            sx = seeds[jw, iw, 0] + (i - iw) * cs
            sy = seeds[jw, iw, 1] + (j - jw) * cs
            px = xx - sx
            py = yy - sy
            c = np.cos(ang[jw, iw])
            s = np.sin(ang[jw, iw])
            u = (px * c + py * s) / ax_a[jw, iw]
            v = (-px * s + py * c) / ax_b[jw, iw]
            d = np.sqrt(u * u + v * v)       # 1 = Rand der Ellipse
            m = d < best
            best = np.where(m, d, best)
            cid[..., 0] = np.where(m, iw, cid[..., 0])
            cid[..., 1] = np.where(m, jw, cid[..., 1])
    inside = best < 1.0
    dome = np.sqrt(np.clip(1.0 - best * best, 0.0, 1.0))
    bed_n = noise(rng, 3.0)
    height = np.where(inside, 0.35 + 0.65 * dome ** 0.8, 0.12 + 0.04 * bed_n)
    height = height + noise(rng, 1.2) * 0.015
    pc = col[cid[..., 1], cid[..., 0]]
    speck = noise(rng, 0.8)[..., None]
    mottle = noise(rng, 6.0)[..., None]
    stone = pc * (1.0 + 0.06 * speck + 0.07 * mottle)
    # Licht von oben auf der Kuppe, Rand dunkler (Umgebungsverdeckung)
    stone = stone * (0.72 + 0.32 * dome[..., None])
    sand = np.array([0.58, 0.55, 0.49]) * (0.85 + 0.12 * bed_n[..., None]) * 0.82
    edge = np.clip((best - 0.92) / 0.16, 0.0, 1.0)[..., None]
    alb = stone * (1.0 - edge) + sand * edge
    # Fugen-Verdeckung
    alb *= np.where(inside, 1.0, 0.85)[..., None]
    nrm = normal_from_height(height, 9.0)
    rgh = np.where(inside, 0.62 + 0.12 * (1.0 - dome), 0.95) + noise(rng, 2.0) * 0.03
    save("flusskiesel_pflaster", alb, nrm, rgh)


def sand():
    rng = np.random.default_rng(4207)
    base = np.array([0.74, 0.71, 0.65])
    low = noise(rng, 40.0)
    mid = noise(rng, 10.0)
    fine = noise(rng, 1.0)
    alb = base * (1.0 + 0.025 * low[..., None] + 0.03 * mid[..., None] + 0.05 * fine[..., None])
    # Feinkies: kleine Koerner 2-6 px, heller/dunkler, leicht farbig
    height = 0.2 * mid + 0.15 * fine
    count = 9000
    pos = rng.random((count, 2)) * N
    rad = 1.0 + rng.random(count) * 2.6
    tint = np.array([[0.9, 0.9, 0.9], [0.6, 0.6, 0.62], [0.82, 0.76, 0.66], [0.5, 0.48, 0.45], [0.95, 0.94, 0.9]])
    tsel = tint[rng.integers(0, len(tint), count)]
    for k in range(count):
        r = rad[k]
        x0 = int(pos[k, 0])
        y0 = int(pos[k, 1])
        R = int(np.ceil(r)) + 1
        ys = (np.arange(y0 - R, y0 + R + 1)) % N
        xs = (np.arange(x0 - R, x0 + R + 1)) % N
        gy, gx = np.meshgrid(np.arange(-R, R + 1) + (y0 - pos[k, 1]), np.arange(-R, R + 1) + (x0 - pos[k, 0]), indexing="ij")
        d = np.sqrt(gx * gx + gy * gy) / r
        w = np.clip(1.0 - d, 0.0, 1.0)
        if not w.any():
            continue
        sub = alb[np.ix_(ys, xs)]
        a = (w > 0).astype(float)[..., None] * 0.85
        alb[np.ix_(ys, xs)] = sub * (1 - a) + (tsel[k] * (0.85 + 0.3 * w[..., None])) * a
        height[np.ix_(ys, xs)] += w * 0.9
    # Fahrspuren/Wassernasen andeuten: breite, schwache Abdunklung
    alb *= (1.0 - 0.04 * np.clip(noise(rng, 70.0), 0, None))[..., None]
    nrm = normal_from_height(height, 1.6)
    rgh = 0.9 + 0.05 * fine
    save("sandweg_hell", alb, nrm, rgh)


def hedge():
    """Geschnittene Hecke (Liguster/Buchs): dichte kleine Blaetter, dunkle Luecken (Kachel 1,0 m)."""
    rng = np.random.default_rng(9313)
    alb = np.zeros((N, N, 3)) + np.array([0.06, 0.10, 0.04])
    height = np.zeros((N, N))
    count = 26000
    pos = rng.random((count, 2)) * N
    greens = np.array([[0.20, 0.32, 0.10], [0.25, 0.38, 0.12], [0.16, 0.27, 0.09], [0.30, 0.42, 0.15], [0.22, 0.30, 0.12]])
    gsel = greens[rng.integers(0, len(greens), count)] * (0.8 + rng.random((count, 1)) * 0.45)
    ang = rng.random(count) * np.pi
    la = 5.0 + rng.random(count) * 4.0
    lb = la * (0.45 + rng.random(count) * 0.2)
    depth = rng.random(count)
    order = np.argsort(depth)                # tiefe Blaetter zuerst, vordere ueberdecken
    for k in order:
        R = int(np.ceil(la[k])) + 1
        x0 = int(pos[k, 0])
        y0 = int(pos[k, 1])
        ys = (np.arange(y0 - R, y0 + R + 1)) % N
        xs = (np.arange(x0 - R, x0 + R + 1)) % N
        gy, gx = np.meshgrid(np.arange(-R, R + 1) + (y0 - pos[k, 1]), np.arange(-R, R + 1) + (x0 - pos[k, 0]), indexing="ij")
        c = np.cos(ang[k])
        s = np.sin(ang[k])
        u = (gx * c + gy * s) / la[k]
        v = (-gx * s + gy * c) / lb[k]
        d = u * u + v * v
        m = d < 1.0
        if not m.any():
            continue
        shade = (0.55 + 0.45 * depth[k]) * (0.85 + 0.25 * (1.0 - d))
        sub = alb[np.ix_(ys, xs)]
        sub[m] = (gsel[k] * shade[..., None])[m]
        alb[np.ix_(ys, xs)] = sub
        hs = height[np.ix_(ys, xs)]
        hv = depth[k] + 0.3 * (1.0 - d)
        hs[m] = np.maximum(hs[m], hv[m])
        height[np.ix_(ys, xs)] = hs
    nrm = normal_from_height(height, 2.2)
    rgh = 0.78 + 0.1 * (1.0 - height.clip(0, 1))
    save("schnitthecke", alb, nrm, rgh)


if __name__ == "__main__":
    pebbles()
    sand()
    hedge()
