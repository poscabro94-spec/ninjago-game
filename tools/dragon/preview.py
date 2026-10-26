# Renders the dragon geometry to PNGs (faces + glowing seam lines, with a fake bloom) so the shape
# can be checked without Roblox. Usage: python preview.py out_dir
import sys, math, os
import numpy as np
from PIL import Image, ImageFilter
import geometry as G


def tube(pts, r):
    """the same strips build.lua makes for a seam line: a 4-sided prism per segment"""
    tris = []
    for a, b in zip(pts[:-1], pts[1:]):
        d = b - a
        L = np.linalg.norm(d)
        if L < 1e-6:
            continue
        d = d / L
        ref = np.array([0, 1.0, 0]) if abs(d[1]) < 0.9 else np.array([1.0, 0, 0])
        s = np.cross(d, ref); s /= np.linalg.norm(s)
        u = np.cross(s, d)
        a2, b2 = a - d * r * 0.5, b + d * r * 0.5
        corners = [s * r, u * r, -s * r, -u * r]
        for k in range(4):
            c0, c1 = corners[k], corners[(k + 1) % 4]
            tris.append((a2 + c0, b2 + c0, b2 + c1))
            tris.append((a2 + c0, b2 + c1, a2 + c1))
    return tris


class Scene:
    def __init__(self):
        self.items = []  # (tris[(p,q,r)], colors[(rgb)], glow, alpha)

    def mesh(self, m, cf, color, edge_color, alpha=1.0, glow=0.0):
        R, t = cf
        tr = [(R @ p + t, R @ q + t, R @ r + t) for p, q, r, _ in m.tris]
        cols = [(np.array(color) * s[0], np.array(color) * s[1], np.array(color) * s[2]) for *_, s in m.tris]
        if tr:
            self.items.append((tr, cols, glow, alpha))
        et = []
        for pts, r in zip(m.lines, m.radius):
            et += tube([R @ p + t for p in pts], r)
        if et:
            ec = np.array(edge_color, float)
            self.items.append((et, [(ec, ec, ec)] * len(et), 1.0, 1.0))

    def render(self, view, size=520, span=14.0, center=(0, 0, 0)):
        img = np.zeros((size, size, 3)); img[:] = (92, 96, 104)
        glowimg = np.zeros((size, size, 3))
        zb = np.full((size, size), -1e9)
        layers = []
        c = np.array(center, float)
        for tris, cols, glow, alpha in self.items:
            buf = np.zeros((size, size, 3)); cov = np.zeros((size, size), bool); bz = np.full((size, size), -1e9)
            for (p, q, r), col in zip(tris, cols):
                P = np.array([view @ (p - c), view @ (q - c), view @ (r - c)])
                xy = P[:, :2] / span * size + size / 2
                xy[:, 1] = size - xy[:, 1]
                z = P[:, 2]
                x0, x1 = int(max(xy[:, 0].min(), 0)), int(min(xy[:, 0].max() + 1, size - 1))
                y0, y1 = int(max(xy[:, 1].min(), 0)), int(min(xy[:, 1].max() + 1, size - 1))
                if x1 < x0 or y1 < y0:
                    continue
                A, B, C = xy
                d = (B[1] - C[1]) * (A[0] - C[0]) + (C[0] - B[0]) * (A[1] - C[1])
                if abs(d) < 1e-12:
                    continue
                xs, ys = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
                w0 = ((B[1] - C[1]) * (xs - C[0]) + (C[0] - B[0]) * (ys - C[1])) / d
                w1 = ((C[1] - A[1]) * (xs - C[0]) + (A[0] - C[0]) * (ys - C[1])) / d
                w2 = 1 - w0 - w1
                msk = (w0 >= 0) & (w1 >= 0) & (w2 >= 0)
                zz = w0 * z[0] + w1 * z[1] + w2 * z[2]
                sub = bz[y0:y1 + 1, x0:x1 + 1]
                upd = msk & (zz > sub)
                sub[upd] = zz[upd]
                shade = w0[..., None] * col[0] + w1[..., None] * col[1] + w2[..., None] * col[2]
                buf[y0:y1 + 1, x0:x1 + 1][upd] = shade[upd]
                cov[y0:y1 + 1, x0:x1 + 1] |= upd
            layers.append((buf, cov, bz, glow, alpha))
        # opaque layers first (z-buffered), translucent ones blended over
        for buf, cov, bz, glow, alpha in sorted(layers, key=lambda l: -l[4]):
            vis = cov & (bz >= zb - 1e-6) if alpha >= 1 else cov & (bz >= zb)
            if alpha >= 1:
                img[vis] = buf[vis]
                zb[vis] = bz[vis]
            else:
                img[vis] = img[vis] * (1 - alpha) + buf[vis] * alpha
            if glow:
                glowimg[vis] = buf[vis]
        g = Image.fromarray(np.clip(glowimg, 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(size / 90))
        out = np.clip(img + np.array(g, float) * 0.9, 0, 255)
        return out.astype(np.uint8)


def rot(yaw=0.0, pitch=0.0):
    cy, sy, cp, sp = math.cos(yaw), math.sin(yaw), math.cos(pitch), math.sin(pitch)
    Ry = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]])
    Rx = np.array([[1, 0, 0], [0, cp, -sp], [0, sp, cp]])
    return Rx @ Ry


def ident():
    return (np.eye(3), np.zeros(3))


if __name__ == "__main__":
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    GREEN, DARK, EDGE = (60, 230, 40), (30, 150, 25), (200, 255, 170)
    sc = Scene()
    head, hot = G.build_head()
    sc.mesh(head, ident(), DARK, EDGE)
    sc.mesh(hot, ident(), EDGE, EDGE, glow=1.0)
    jaw, jhot = G.build_jaw()
    a = 0.22
    Rj = np.array([[1, 0, 0], [0, math.cos(a), math.sin(a)], [0, -math.sin(a), math.cos(a)]])
    sc.mesh(jaw, (Rj, G.JAW_HINGE - Rj @ G.JAW_HINGE), DARK, EDGE)
    sc.mesh(jhot, (Rj, G.JAW_HINGE - Rj @ G.JAW_HINGE), EDGE, EDGE, glow=1.0)
    views = [("side", rot(-math.pi / 2, 0)), ("threequarter", rot(-0.7, 0.35)), ("top", rot(0, -math.pi / 2 + 0.01)),
             ("front", rot(math.pi, 0.2))]
    imgs = [sc.render(v, span=7.5, center=(0, 0.4, -1.6)) for _, v in views]
    Image.fromarray(np.concatenate([np.concatenate(imgs[:2], 1), np.concatenate(imgs[2:], 1)], 0)).save(os.path.join(out, "head.png"))
    print("ok")
