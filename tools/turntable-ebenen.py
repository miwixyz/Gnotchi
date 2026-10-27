# SYNTHETISCH – Werkzeug für die KI-Fotos des Plattenspielers, keine Hördaten (Datenschutz-Gate, SECURE-DESIGN G16)
# 0.17.0: vermisst die drei KI-Fotos (Arm auf der Platte / Arm in der Ablage / ohne Arm) und schreibt die Ebenen:
#   basis.png (ohne Arm), arm.png (Arm in Spielstellung, freigestellt), platte.png (Platte, kreisrund entzerrt)
# Aufruf: /Library/Frameworks/Python.framework/Versions/3.13/bin/python3 -I tools/turntable-ebenen.py <rohordner>
import json
import sys

import numpy as np
from PIL import Image, ImageFilter

d = sys.argv[1]
load = lambda n: np.asarray(Image.open(f"{d}/{n}").convert("RGB")).astype(np.int16)
pause, play, noarm = load("pause.png"), load("spielt-fix.png"), load("ohne-arm.png")
H, W, _ = pause.shape
lum = lambda a: (a[..., 0] * 0.299 + a[..., 1] * 0.587 + a[..., 2] * 0.114)

def mask(diff, roi, thr=30):
    m = (np.abs(diff).max(axis=2) > thr)
    r = np.zeros_like(m)
    x0, y0, x1, y1 = roi
    r[y0:y1, x0:x1] = m[y0:y1, x0:x1]
    img = Image.fromarray((r * 255).astype(np.uint8))
    img = img.filter(ImageFilter.MinFilter(5)).filter(ImageFilter.MaxFilter(5))     # Rauschen weg
    img = img.filter(ImageFilter.MaxFilter(9)).filter(ImageFilter.MinFilter(9))     # Löcher zu
    return np.asarray(img) > 127

roi = (1100, 120, 1990, 980)
m_rest = mask(pause - noarm, roi)
m_play = mask(play - noarm, roi)
outside = np.ones((H, W), bool); outside[roi[1]:roi[3], roi[0]:roi[2]] = False
drift = float(np.abs(pause - noarm).max(axis=2)[outside].mean())

# Drehpunkt: dunkelster Fleck auf der Lagerplatte (ohne Arm), Suche um die Schätzung.
gx, gy = 1558, 377
win = lum(noarm[gy - 40:gy + 40, gx - 40:gx + 40])
ys, xs = np.where(win <= np.percentile(win, 0.5))
pivot = (gx - 40 + xs.mean(), gy - 40 + ys.mean())

# Platte: vom Mittelpunkt des Etiketts nach außen, bis es hell wird (Alu-Rand).
cx, cy = 880.4, 497.8
L = lum(noarm)
def reach(dx, dy, start):
    # Erst außerhalb des Etiketts beginnen: Achse (dunkel) und Etikett (hell) würden den Rand vortäuschen.
    inside = False
    for step in range(start, 900):
        px, py = int(round(cx + dx * step)), int(round(cy + dy * step))
        v = L[py, px]
        if v < 70: inside = True
        if inside and v > 150: return step
    return None
right, left, down, up = reach(1, 0, 190), reach(-1, 0, 190), reach(0, 1, 110), reach(0, -1, 110)
rx = (right + left) / 2
center = (cx + (right - left) / 2, cy + (down - up) / 2)
ry = (down + up) / 2
k = ry / rx

def tip(m):
    ys, xs = np.where(m)
    dist = np.hypot(xs - pivot[0], (ys - pivot[1]) / k)       # entzerrt
    i = int(dist.argmax())
    return (float(xs[i]), float(ys[i])), float(dist[i])

(tp, lp), (tr, lr) = tip(m_play), tip(m_rest)
ang = lambda t: float(np.degrees(np.arctan2((t[1] - pivot[1]) / k, t[0] - pivot[0])))
out = dict(size=[W, H], drift_ausserhalb=round(drift, 2), pivot=[round(pivot[0], 1), round(pivot[1], 1)],
           platte_mitte=[round(center[0], 1), round(center[1], 1)], platte_rx=rx, platte_ry=ry, k=round(k, 4),
           arm_spiel_spitze=tp, arm_spiel_laenge=round(lp, 1), arm_spiel_winkel=round(ang(tp), 2),
           arm_ablage_spitze=tr, arm_ablage_laenge=round(lr, 1), arm_ablage_winkel=round(ang(tr), 2),
           maske_spiel_flaeche=int(m_play.sum()), maske_ablage_flaeche=int(m_rest.sum()))
print(json.dumps(out, indent=1))
Image.fromarray((m_play * 255).astype(np.uint8)).save(f"{d}/maske-arm-spiel.png")
Image.fromarray((m_rest * 255).astype(np.uint8)).save(f"{d}/maske-arm-ablage.png")
json.dump(out, open(f"{d}/vermessung.json", "w"), indent=1)

# ---------------------------------------------------------------------------------------------------------------
# Teil 2: Ebenen schreiben. Perspektive als Homographie Ebene → Bild, aus vier Randpunkten der Platte um die Achse.
spx, spy = cx, cy                                   # Achse (Etikettmitte) = Projektion des Plattenmittelpunkts
src = [(1, 0), (-1, 0), (0, 1), (0, -1)]
dst = [(spx + right, spy), (spx - left, spy), (spx, spy + down), (spx, spy - up)]
A = []
for (X, Y), (x, y) in zip(src, dst):
    A += [[X, Y, 1, 0, 0, 0, -x * X, -x * Y, -x], [0, 0, 0, X, Y, 1, -y * X, -y * Y, -y]]
_, _, vt = np.linalg.svd(np.array(A, float))
Hm = vt[-1].reshape(3, 3); Hm /= Hm[2, 2]
proj = lambda M, X, Y: ((M[0, 0] * X + M[0, 1] * Y + M[0, 2]) / (M[2, 0] * X + M[2, 1] * Y + M[2, 2]),
                        (M[1, 0] * X + M[1, 1] * Y + M[1, 2]) / (M[2, 0] * X + M[2, 1] * Y + M[2, 2]))
c0 = proj(Hm, 0, 0)
print("Kontrolle Achse:", [round(v, 1) for v in c0], "soll", [spx, spy])

# Basis ohne Arm: Pausenbild, nur im Armbereich (beide Stellungen) das armlose Bild – sonst pixelgleich.
union = Image.fromarray(((m_rest | m_play) * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(25)).filter(
    ImageFilter.GaussianBlur(6))
u = np.asarray(union).astype(float)[..., None] / 255
# Seit den Greenscreen-Armen (Teil 4) ganz das armlose Foto: die Überblendung hinterließ eine sichtbare Naht (27.10.).
basis = noarm.clip(0, 255).astype(np.uint8)

# Arm (Spielstellung) freigestellt: Pixel des Spielbilds, wo es vom armlosen Bild abweicht.
am = Image.fromarray((m_play * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.GaussianBlur(1.2))
arm = np.dstack([play.clip(0, 255).astype(np.uint8), np.asarray(am)])

# Platte kreisrund entzerrt (N × N), aus der Basis abgetastet.
N = 1120
uu, vv = np.meshgrid(np.arange(N) + 0.5, np.arange(N) + 0.5)
X, Y = (uu - N / 2) / (N / 2), (vv - N / 2) / (N / 2)
px, py = proj(Hm, X, Y)
def sample(img, x, y):
    x0, y0 = np.clip(np.floor(x).astype(int), 0, W - 2), np.clip(np.floor(y).astype(int), 0, H - 2)
    fx, fy = (x - x0)[..., None], (y - y0)[..., None]
    a, b, c, e = img[y0, x0], img[y0, x0 + 1], img[y0 + 1, x0], img[y0 + 1, x0 + 1]
    return a * (1 - fx) * (1 - fy) + b * fx * (1 - fy) + c * (1 - fx) * fy + e * fx * fy
tex = sample(basis.astype(float), px, py)
r = np.hypot(X, Y)
# Glanz trennen: Mittelwert je Ring (dreht sich unsichtbar) + Abweichung (Reflexe). 35 % der Abweichung drehen mit,
# damit man die Drehung sieht; der Rest steht als Glanz still wie bei echtem Vinyl.
bins = np.clip((r * 400).astype(int), 0, 400)
ring = np.zeros((401, 3))
for ch in range(3):
    s = np.bincount(bins.ravel(), tex[..., ch].ravel(), 401); n = np.bincount(bins.ravel(), minlength=401)
    ring[:, ch] = s / np.maximum(n, 1)
mean = ring[bins]
dev = tex - mean
rot = (mean + 0.35 * dev).clip(0, 255)
alpha = ((r < 0.985) * 255).astype(np.uint8)       # Rand bleibt fest (Foto), nichts eiert
platte = np.dstack([rot.astype(np.uint8), alpha])
glanz_rgb = (0.65 * dev).clip(0, 255)
glanz_a = (glanz_rgb.max(axis=2) * (r < 0.985)).clip(0, 255)
glanz = np.dstack([np.full_like(glanz_rgb, 255).astype(np.uint8), glanz_a.astype(np.uint8)])

# Zuschnitt wie bisher (Gerät): Basis/Arm in denselben Rahmen; Homographie um den Zuschnitt verschieben.
x0, y0, cw, ch_ = 38, 156, 1991, 1080
Image.fromarray(basis).crop((x0, y0, x0 + cw, y0 + ch_)).save(f"{d}/ebene-basis.png")
Image.fromarray(arm, "RGBA").crop((x0, y0, x0 + cw, y0 + ch_)).save(f"{d}/ebene-arm.png")
Image.fromarray(platte, "RGBA").save(f"{d}/ebene-platte.png")
Image.fromarray(glanz, "RGBA").save(f"{d}/ebene-glanz.png")
T = np.array([[1, 0, -x0], [0, 1, -y0], [0, 0, 1]], float)
Sm = np.array([[2 / N, 0, -1], [0, 2 / N, -1], [0, 0, 1]], float)      # Kreisbild-Pixel → Ebene
M = T @ Hm @ Sm; M /= M[2, 2]                                           # Kreisbild-Pixel → Gerätebild-Pixel
P = T @ Hm; P /= P[2, 2]                                                # Ebene → Gerätebild-Pixel
Pi = np.linalg.inv(P)
plane = lambda x, y: proj(Pi, x, y)
pv = plane(pivot[0] - x0, pivot[1] - y0)
# Nadel: knapp hinter der vordersten Armspitze.
tipx, tipy = tp[0] - x0, tp[1] - y0
ppx, ppy = pivot[0] - x0, pivot[1] - y0
nad = plane(ppx + 0.94 * (tipx - ppx), ppy + 0.94 * (tipy - ppy))
rest_tip = plane(tr[0] - x0, tr[1] - y0)
angle_of = lambda q: np.arctan2(q[1] - pv[1], q[0] - pv[0])
d_rest = float(np.degrees(angle_of(rest_tip) - angle_of(plane(tipx, tipy))))
def swing_for(radius):
    lo, hi = -40.0, 40.0
    f = lambda deg: np.hypot(*(np.array(pv) + np.array([[np.cos(np.radians(deg)), -np.sin(np.radians(deg))],
                                                        [np.sin(np.radians(deg)), np.cos(np.radians(deg))]]) @
                               (np.array(nad) - np.array(pv)))) - radius
    for _ in range(60):
        mid = (lo + hi) / 2
        (lo, hi) = (mid, hi) if f(lo) * f(mid) > 0 else (lo, mid)
    return (lo + hi) / 2
r_nad = float(np.hypot(*nad))
geo = dict(M=M.round(6).tolist(), P=P.round(6).tolist(), circleSize=N, pivotPlane=[round(v, 5) for v in pv],
           needleRadius=round(r_nad, 4), restDelta=round(d_rest, 2), outerDelta=round(swing_for(0.93), 2),
           innerDelta=round(swing_for(0.42), 2), labelRadius=round(175 / right, 4),
           needlePlane=[round(float(v), 5) for v in nad])
print(json.dumps(geo))
json.dump(geo, open(f"{d}/geometrie.json", "w"), indent=1)

# ---------------------------------------------------------------------------------------------------------------
# Teil 3 (nach Sichtprüfung 27.10.): Arm in drei Teile – Lager fest, Rohr dreht (Spielbereich), Ablage-Arm aus dem
# Pausenfoto. Grund: weggedreht wurde der Schatten auf der Platte zum schwarzen Fleck, das Lager verzog sich.
yy, xx = np.mgrid[0:H, 0:W]
qx, qy = proj(np.linalg.inv(Hm), xx.astype(float), yy.astype(float))          # Bildpunkt → Ebene (vor Zuschnitt)
pv0 = proj(np.linalg.inv(Hm), pivot[0], pivot[1])
dist = np.hypot(qx - pv0[0], qy - pv0[1])
r_lager = 0.16
fe = np.clip((dist - r_lager) / 0.04, 0, 1)                                     # weicher Übergang
am_a = np.asarray(am).astype(float) / 255
rohr = np.dstack([play.clip(0, 255).astype(np.uint8), (am_a * fe * 255).astype(np.uint8)])
lager = np.dstack([play.clip(0, 255).astype(np.uint8), (am_a * (1 - fe) * 255).astype(np.uint8)])
rm = Image.fromarray((m_rest * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.GaussianBlur(1.2))
ablage = np.dstack([pause.clip(0, 255).astype(np.uint8), np.asarray(rm)])
for name, arr in [("ebene-arm-rohr", rohr), ("ebene-arm-lager", lager), ("ebene-arm-ablage", ablage)]:
    Image.fromarray(arr, "RGBA").crop((x0, y0, x0 + cw, y0 + ch_)).save(f"{d}/{name}.png")
geo["innerDelta"] = round(swing_for(0.5), 2)
geo["lagerRadius"] = r_lager
print("innen bei r=0.5:", geo["innerDelta"])
json.dump(geo, open(f"{d}/geometrie.json", "w"), indent=1)

# ---------------------------------------------------------------------------------------------------------------
# Teil 4 (Michael 27.10.: „Arm teiltransparent, darunter ein unschöner Schatten“): Arme per KI auf Greenscreen
# (arm-spiel-gruen.png / arm-ablage-gruen.png, Lage gegen das Original gemessen: 0/0 bzw. 0/−1 px), sauber
# ausgeschnitten; Schatten selbst erzeugt aus der Armform (weich, halbdurchsichtig, versetzt wie das Licht im Foto).
def keyed(name):
    a = np.asarray(Image.open(f"{d}/{name}").convert("RGB")).astype(float)
    spill = a[..., 1] - np.maximum(a[..., 0], a[..., 2])
    al = 1 - np.clip((spill - 25) / (110 - 25), 0, 1)
    a[..., 1] = np.minimum(a[..., 1], np.maximum(a[..., 0], a[..., 2]) + 6)      # Grünsaum entfernen
    return a, al
def shadow(al, dx=-7, dy=12, blur=8, strength=0.5):
    img = Image.fromarray((al * 255).astype(np.uint8)).transform(al.shape[::-1], Image.AFFINE, (1, 0, -dx, 0, 1, -dy))
    s = np.asarray(img.filter(ImageFilter.GaussianBlur(blur))).astype(float) / 255 * strength
    return np.dstack([np.zeros(al.shape + (3,), np.uint8), (s * 255).astype(np.uint8)])
play_rgb, play_a = keyed("arm-spiel-gruen.png")
rest_rgb, rest_a = keyed("arm-ablage-gruen.png")
rest_a = np.roll(rest_a, 1, axis=0); rest_rgb = np.roll(rest_rgb, 1, axis=0)            # gemessene 1 px
layers = {"arm-rohr": (play_rgb, play_a * fe), "arm-lager": (play_rgb, play_a * (1 - fe)), "arm-ablage": (rest_rgb, rest_a)}
for name, (rgb, al) in layers.items():
    rgba = np.dstack([rgb.clip(0, 255).astype(np.uint8), (al * 255).astype(np.uint8)])
    Image.fromarray(rgba, "RGBA").crop((x0, y0, x0 + cw, y0 + ch_)).save(f"{d}/ebene-{name}.png")
    Image.fromarray(shadow(al), "RGBA").crop((x0, y0, x0 + cw, y0 + ch_)).save(f"{d}/ebene-{name}-schatten.png")
print("Arm-Ebenen (Greenscreen) und Schatten geschrieben")
