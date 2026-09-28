"""Retinal field geometry: ports of matlab/lib/retinalCrop.m and retinalMask.m."""
from __future__ import annotations

import numpy as np
from scipy import ndimage as ndi

from . import mimage as mi
from .config import CFG


def retinal_crop(I):
    """Crop to the retinal field. Returns (crop, bbox) with bbox = MATLAB [x y w h] (1-based)."""
    g = mi.im2gray(I)
    m = ndi.binary_fill_holes(g > 10)
    H, W = g.shape
    if m.any():
        m = mi.largest_component(m)
        rows = np.flatnonzero(m.any(axis=1))
        cols = np.flatnonzero(m.any(axis=0))
        # regionprops BoundingBox = [xmin-0.5 ymin-0.5 w h]; round() lands on xmin (1-based)
        x = cols[0] + 1
        y = rows[0] + 1
        w = cols[-1] - cols[0] + 1
        h = rows[-1] - rows[0] + 1
        x, y = max(x, 1), max(y, 1)
        w = min(w, W - x)
        h = min(h, H - y)
    else:
        x, y, w, h = 1, 1, W - 1, H - 1
    # MATLAB indexes bbox(2):bbox(2)+bbox(4) inclusive -> h+1 rows
    return I[y - 1:y + h, x - 1:x + w], (int(x), int(y), int(w), int(h))


def retinal_mask(I):
    """Returns (mask, frac, clipped)."""
    g = mi.im2gray(I)
    M = ndi.binary_fill_holes(g > 10)
    if not M.any():
        return np.ones(g.shape, bool), 1.0, True
    M = mi.largest_component(M)
    M = mi.imopen(M, CFG.strel('disk5'))
    if not M.any():
        M = ndi.binary_fill_holes(g > 10)
    frac = M.sum() / M.size
    clipped = (M[0, :].mean() > 0.20 or M[-1, :].mean() > 0.20
               or M[:, 0].mean() > 0.20 or M[:, -1].mean() > 0.20)
    return M, float(frac), bool(clipped)


def apply_clahe(I):
    return np.stack([mi.adapthisteq(I[..., c]) for c in range(I.shape[2])], axis=2)


def normalise(I):
    X = I.astype(np.float32) / 255.0
    return (X - CFG.im_mean) / CFG.im_std
