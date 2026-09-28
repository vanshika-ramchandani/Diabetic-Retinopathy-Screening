"""Model 1 (lesions, IDRiD) and Model 3 (vessels, DRIVE).

Ports of matlab/lib/slidingWindowPredict.m, the lesion post-processing in
netraAnalyze.m, and matlab/m6_vessels/segmentVessels.m.
"""
from __future__ import annotations

import numpy as np

from . import mimage as mi
from . import models
from .config import CFG
from .preprocess import apply_clahe, normalise, retinal_mask


def sliding_window_predict(net, I, patch, stride, nchan, batch=8):
    H, W = I.shape[:2]
    Hp, Wp = max(H, patch), max(W, patch)
    if Hp > H or Wp > W:
        J = np.zeros((Hp, Wp, 3), I.dtype)
        J[:H, :W] = I
        I = J
    rs = sorted(set(list(range(0, max(Hp - patch + 1, 1), stride)) + [max(Hp - patch, 0)]))
    cs = sorted(set(list(range(0, max(Wp - patch + 1, 1), stride)) + [max(Wp - patch, 0)]))
    w1 = 0.5 * (1 - np.cos(2 * np.pi * np.arange(patch) / (patch - 1)))
    w2d = (np.outer(w1, w1) + 1e-3).astype(np.float32)

    acc = np.zeros((Hp, Wp, nchan), np.float32)
    wacc = np.zeros((Hp, Wp), np.float32)
    # MATLAB meshgrid(rs,cs) + (:) walks rows fastest within each column start
    starts = [(r, c) for c in cs for r in rs]
    for k in range(0, len(starts), batch):
        chunk = starts[k:k + batch]
        X = np.stack([normalise(I[r:r + patch, c:c + patch]) for r, c in chunk])
        Y = models.run(net, X)[0]
        for (r, c), y in zip(chunk, Y):
            acc[r:r + patch, c:c + patch] += y * w2d[..., None]
            wacc[r:r + patch, c:c + patch] += w2d
    P = acc / np.maximum(wacc, 1e-6)[..., None]
    return P[:H, :W]


# ------------------------------------------------------------------ lesions
LESION_COLOURS = np.array([[1, 0, 0], [0, 0.35, 1], [1, 0.9, 0], [0, 1, 1], [0, 1, 0]], np.float32)


def detect_lesions(I0, Inet=None):
    """I0 is the retinal crop (uint8 HxWx3), Inet its CLAHE. Returns prob, masks, overlay."""
    if Inet is None:
        Inet = apply_clahe(I0)
    P = sliding_window_predict('lesion', Inet, CFG.patch_size, CFG.stride, 5)
    thr = CFG.lesion_thr
    od = mi.imdilate(P[..., 4] >= thr[4], CFG.strel('disk15'))
    M = np.zeros(P.shape, bool)
    for c in range(5):
        B = mi.bwareaopen(P[..., c] >= thr[c], CFG.min_comp_size[c])
        if c in (2, 3):
            B &= ~od
        M[..., c] = B
    return {'clahe': Inet, 'prob': P, 'masks': M, 'overlay': overlay_lesions(I0, M)}


def overlay_lesions(I, M):
    J = I.astype(np.float32) / 255.0
    for c in range(M.shape[2]):
        B = M[..., c]
        if c == 4:
            B = mi.bwperim(mi.imdilate(B, CFG.strel('disk3')))
        if not B.any():
            continue
        B = mi.imdilate(B, CFG.strel('disk1'))
        J[B] = 0.25 * J[B] + 0.75 * LESION_COLOURS[c]
    return mi.to_uint8(J * 255)


# ------------------------------------------------------------------ vessels
def segment_vessels(I):
    F, _, _ = retinal_mask(I)
    dia = np.sqrt(4 * F.sum() / np.pi)
    scale = CFG.vessel_ref_dia / max(dia, 1)
    if abs(np.log(scale)) > 0.05:
        Is = mi.imresize(I, scale)
        Ps = sliding_window_predict('vessel', Is, CFG.vessel_size, CFG.vessel_stride, 1, batch=16)
        P = mi.imresize(Ps[..., 0].astype(np.float32), I.shape[:2])
    else:
        scale = 1.0
        P = sliding_window_predict('vessel', I, CFG.vessel_size, CFG.vessel_stride, 1, batch=16)[..., 0]
    P = np.clip(P, 0, 1)
    M = mi.bwareaopen((P >= CFG.vessel_thr) & F, 20)
    overlay = I.copy()
    overlay[M] = (0, 255, 255)                      # cyan, distinct from every lesion hue
    return {'prob': P, 'mask': M, 'fov': F, 'area_frac': float(M.sum() / max(F.sum(), 1)),
            'scale': float(scale), 'in_domain': bool(abs(np.log(scale)) < 0.35),
            'overlay': overlay}
