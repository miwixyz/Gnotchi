# SYNTHETISCH – Werkzeug, erfundenes Cover, keine Hördaten (Datenschutz-Gate, SECURE-DESIGN G16)
# 0.17.0: setzt die Ebenen aus turntable-ebenen.py mit der Perspektiv-Geometrie zusammen (Kontrolle vor dem Swift-Code).
# Aufruf: …/python3 -I tools/turntable-vorschau.py <rohordner> <plattenwinkel> <armwinkel> <aus.png>
import json
import sys

import numpy as np
from PIL import Image, ImageDraw

d, plate_deg, out = sys.argv[1], float(sys.argv[2]), sys.argv[4]
arm_deg = 0.0 if sys.argv[3] == "ablage" else float(sys.argv[3])
g = json.load(open(f"{d}/geometrie.json"))
M, P = np.array(g["M"]), np.array(g["P"])
N = g["circleSize"]
basis = Image.open(f"{d}/ebene-basis.png").convert("RGBA")
rohr = Image.open(f"{d}/ebene-arm-rohr.png").convert("RGBA")
lager = Image.open(f"{d}/ebene-arm-lager.png").convert("RGBA")
ablage = Image.open(f"{d}/ebene-arm-ablage.png").convert("RGBA")
# Armwinkel „ablage“ = Pausenfoto-Arm (ungedreht), sonst Lager fest + Rohr gedreht.
rest_mode = sys.argv[3] == "ablage"
platte = Image.open(f"{d}/ebene-platte.png").convert("RGBA")
glanz = Image.open(f"{d}/ebene-glanz.png").convert("RGBA")

def coeffs(Minv):
    m = Minv / Minv[2, 2]
    return (m[0, 0], m[0, 1], m[0, 2], m[1, 0], m[1, 1], m[1, 2], m[2, 0], m[2, 1])

def rot_about(cx, cy, deg):
    a = np.radians(deg)
    c, s = np.cos(a), np.sin(a)
    return np.array([[c, -s, cx - c * cx + s * cy], [s, c, cy - s * cx - c * cy], [0, 0, 1]])

# Platte + Etikett im Kreisraum, gedreht, dann projiziert.
disc = platte.copy()
cover = Image.new("RGBA", (600, 600))
dr = ImageDraw.Draw(cover)
for i in range(600):
    dr.line([(0, i), (600, i)], fill=(238 - i // 6, 140 - i // 8, 64 + i // 10, 255))
dr.ellipse([200, 200, 400, 400], fill=(248, 240, 236, 255))
dr.ellipse([270, 270, 330, 330], fill=(51, 25, 63, 255))
lr = int(g["labelRadius"] * N / 2)
lab = cover.resize((2 * lr, 2 * lr))
m = Image.new("L", lab.size, 0); ImageDraw.Draw(m).ellipse([0, 0, 2 * lr, 2 * lr], fill=255)
disc.paste(lab, (N // 2 - lr, N // 2 - lr), m)
disc = disc.rotate(-plate_deg, resample=Image.BICUBIC, center=(N / 2, N / 2))
W, H = basis.size
proj_disc = disc.transform((W, H), Image.PERSPECTIVE, coeffs(np.linalg.inv(M)), Image.BICUBIC)
proj_glanz = glanz.transform((W, H), Image.PERSPECTIVE, coeffs(np.linalg.inv(M)), Image.BICUBIC)

# Arm um das Lager in der Ebene drehen: T = P · R · P⁻¹.
pv = g["pivotPlane"]
T = P @ rot_about(pv[0], pv[1], arm_deg) @ np.linalg.inv(P)
proj_arm = rohr.transform((W, H), Image.PERSPECTIVE, coeffs(np.linalg.inv(T)), Image.BICUBIC)

img = basis.copy()
img.alpha_composite(proj_disc)
img = Image.fromarray(np.clip(np.asarray(img).astype(int) + np.dstack([np.asarray(proj_glanz)[..., 3:4].repeat(3, 2) * 0,
                                                                         np.zeros((H, W, 1), int)]), 0, 255).astype(np.uint8))
gl = np.asarray(proj_glanz).astype(float)[..., 3:4] / 255
arr = np.asarray(img).astype(float)
arr[..., :3] = arr[..., :3] + (255 - arr[..., :3]) * gl * 0.9       # Glanz aufhellen (wie „Bildschirm“)
img = Image.fromarray(arr.clip(0, 255).astype(np.uint8))
if rest_mode:
    img.alpha_composite(ablage)
else:
    img.alpha_composite(lager)
    img.alpha_composite(proj_arm)
img.save(out)
print("geschrieben", out)
