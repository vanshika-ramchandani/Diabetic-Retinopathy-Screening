"""Faithful numpy ports of the MATLAB Image Processing Toolbox calls NETRA uses.

The three networks were trained on images produced by MATLAB. A "close enough"
CLAHE or resize shifts the input distribution the nets see, so the functions
here reproduce MATLAB's arithmetic - including its rounding between passes -
and are parity-tested against MATLAB's own outputs in tests/test_parity.py.

Coordinates are 0-based numpy throughout; MATLAB's 1-based quirks are
translated where they matter (retinal_crop's inclusive bounding box).
"""
from __future__ import annotations

import numpy as np
from scipy import ndimage as ndi

CONN8 = np.ones((3, 3), bool)


# ---------------------------------------------------------------- rounding
def mround(x):
    """MATLAB round: half away from zero."""
    return np.sign(x) * np.floor(np.abs(x) + 0.5)


def to_uint8(x):
    return np.clip(mround(x), 0, 255).astype(np.uint8)


# ---------------------------------------------------------------- imresize
def _cubic(x):
    ax = np.abs(x)
    ax2, ax3 = ax * ax, ax * ax * ax
    return ((1.5 * ax3 - 2.5 * ax2 + 1) * (ax <= 1)
            + (-0.5 * ax3 + 2.5 * ax2 - 4 * ax + 2) * ((ax > 1) & (ax <= 2)))


def _box(x):
    return ((x >= -0.5) & (x < 0.5)).astype(float)


def _contributions(in_len, out_len, scale, kernel, width, antialias):
    if scale < 1 and antialias:
        h = lambda x: scale * kernel(scale * x)  # noqa: E731
        width = width / scale
    else:
        h = kernel
    x = np.arange(1, out_len + 1, dtype=float)[:, None]
    u = x / scale + 0.5 * (1 - 1 / scale)
    left = np.floor(u - width / 2)
    P = int(np.ceil(width)) + 2
    ind = left + np.arange(P)[None, :]
    w = h(u - ind)
    w = w / w.sum(axis=1, keepdims=True)
    aux = np.concatenate([np.arange(in_len), np.arange(in_len - 1, -1, -1)])
    idx = aux[np.mod(ind - 1, 2 * in_len).astype(int)]
    keep = np.any(w != 0, axis=0)
    return w[:, keep], idx[:, keep]


def _resize_dim(A, dim, w, idx, integer):
    A = np.moveaxis(A, dim, 0).astype(np.float64)
    out = np.einsum('op,op...->o...', w, A[idx])
    if integer:
        out = np.clip(mround(out), 0, 255)
    return np.moveaxis(out, 0, dim)


def imresize(A, size_or_scale, method='bicubic'):
    """MATLAB imresize for 2-D or HxWxC arrays (uint8, float, or bool)."""
    in_hw = A.shape[:2]
    if np.isscalar(size_or_scale):
        s = float(size_or_scale)
        scale = (s, s)
        out_hw = (int(np.ceil(s * in_hw[0])), int(np.ceil(s * in_hw[1])))
    else:
        out_hw = tuple(int(v) for v in size_or_scale)
        scale = (out_hw[0] / in_hw[0], out_hw[1] / in_hw[1])
    if method == 'nearest':
        kernel, width, aa = _box, 1.0, False
    else:
        kernel, width, aa = _cubic, 4.0, True

    is_bool = A.dtype == bool
    integer = A.dtype == np.uint8
    B = A.astype(np.float64) if is_bool else A
    for dim in np.argsort(scale, kind='stable'):
        w, idx = _contributions(in_hw[dim], out_hw[dim], scale[dim], kernel, width, aa)
        B = _resize_dim(B, dim, w, idx, integer)
    if is_bool:
        return B > 0.5 if method != 'nearest' else B.astype(bool)
    if integer:
        return B.astype(np.uint8)
    return B.astype(A.dtype)


# ---------------------------------------------------------------- adapthisteq
def _clip_histogram(hist, clip, nbins):
    hist = hist.astype(np.int64).copy()
    total = int(np.maximum(hist - clip, 0).sum())
    avg = total // nbins
    upper = clip - avg
    for k in range(nbins):
        if hist[k] > clip:
            hist[k] = clip
        elif hist[k] > upper:
            total -= clip - hist[k]
            hist[k] = clip
        else:
            total -= avg
            hist[k] += avg
    k = 0
    while total != 0:
        step = max(nbins // total, 1)
        for m in range(k, nbins, step):
            if hist[m] < clip:
                hist[m] += 1
                total -= 1
                if total == 0:
                    break
        k += 1
        if k >= nbins:
            k = 0
    return hist


def adapthisteq(I, clip_limit=0.01, num_tiles=(8, 8), nbins=256):
    """MATLAB adapthisteq on a uint8 2-D image, 'uniform' distribution, full range."""
    assert I.dtype == np.uint8 and I.ndim == 2
    H, W = I.shape
    nt = num_tiles
    pad = [[0, 0], [0, 0]]
    tile = [H / nt[0], W / nt[1]]
    divisible = H % nt[0] == 0 and W % nt[1] == 0
    even = divisible and tile[0] % 2 == 0 and tile[1] % 2 == 0
    no_pad = None
    if not even:
        pads = []
        for d, n in ((H, nt[0]), (W, nt[1])):
            if d % n:
                td = d // n + 1
                p = td * n - d
            else:
                td = d // n
                p = 0
            if td % 2:
                p += n
            pads.append(p)
        pad = [[pads[0] // 2, pads[0] - pads[0] // 2], [pads[1] // 2, pads[1] - pads[1] // 2]]
        I = np.pad(I, pad, mode='symmetric')
        no_pad = (pad[0][0], pad[0][0] + H, pad[1][0], pad[1][0] + W)
    Hp, Wp = I.shape
    th, tw = Hp // nt[0], Wp // nt[1]
    npix = th * tw
    min_clip = int(np.ceil(npix / nbins))
    clip = min_clip + int(mround(clip_limit * (npix - min_clip)))

    # tile LUTs: uint8 -> uint8, as grayxform(uint8, map in [0,1]) produces
    luts = np.zeros((nt[0], nt[1], 256), np.float64)
    for r in range(nt[0]):
        for c in range(nt[1]):
            t = I[r * th:(r + 1) * th, c * tw:(c + 1) * tw]
            hist = np.bincount(t.ravel(), minlength=256)
            hist = _clip_histogram(hist, clip, nbins)
            mapping = np.minimum(np.cumsum(hist) * (255.0 / npix), 255.0) / 255.0
            luts[r, c] = np.floor(mapping * 255 + 0.5)

    out = np.zeros_like(I, dtype=np.uint8)
    row0 = 0
    for k in range(nt[0] + 1):
        if k == 0:
            nr, mr = th // 2, (0, 0)
        elif k == nt[0]:
            nr, mr = th // 2, (nt[0] - 1, nt[0] - 1)
        else:
            nr, mr = th, (k - 1, k)
        col0 = 0
        for l in range(nt[1] + 1):
            if l == 0:
                nc, mc = tw // 2, (0, 0)
            elif l == nt[1]:
                nc, mc = tw // 2, (nt[1] - 1, nt[1] - 1)
            else:
                nc, mc = tw, (l - 1, l)
            v = I[row0:row0 + nr, col0:col0 + nc]
            rw = np.arange(nr, dtype=float)[:, None]
            cw = np.arange(nc, dtype=float)[None, :]
            rrev = np.arange(nr, 0, -1, dtype=float)[:, None]
            crev = np.arange(nc, 0, -1, dtype=float)[None, :]
            ul, ur = luts[mr[0], mc[0]][v], luts[mr[0], mc[1]][v]
            bl, br = luts[mr[1], mc[0]][v], luts[mr[1], mc[1]][v]
            val = (rrev * (crev * ul + cw * ur) + rw * (crev * bl + cw * br)) / (nr * nc)
            out[row0:row0 + nr, col0:col0 + nc] = to_uint8(val)
            col0 += nc
        row0 += nr
    if no_pad:
        out = out[no_pad[0]:no_pad[1], no_pad[2]:no_pad[3]]
    return out


# ---------------------------------------------------------------- morphology
def im2gray(I):
    if I.ndim == 2:
        return I
    x = I.astype(np.float64)
    return to_uint8(0.298936021293775 * x[..., 0] + 0.587043074451121 * x[..., 1]
                    + 0.114020904255103 * x[..., 2])


def label8(B):
    return ndi.label(B, structure=CONN8)


def largest_component(B):
    L, n = label8(B)
    if n == 0:
        return B.copy()
    sizes = np.bincount(L.ravel())[1:]
    return L == (1 + int(np.argmax(sizes)))


def bwareaopen(B, p):
    L, n = label8(B)
    if n == 0:
        return B.copy()
    sizes = np.bincount(L.ravel())
    keep = sizes >= p
    keep[0] = False
    return keep[L]


def count_blobs(B):
    return int(label8(B)[1])


def imdilate(B, se):
    return ndi.binary_dilation(B, structure=se)


def imopen(B, se):
    return ndi.binary_dilation(ndi.binary_erosion(B, structure=se, border_value=1), structure=se)


def bwperim(B):
    """MATLAB bwperim, 2-D default connectivity 4."""
    cross = ndi.generate_binary_structure(2, 1)
    return B & ~ndi.binary_erosion(B, structure=cross, border_value=0)


def prctile(x, p):
    """MATLAB prctile (midpoint interpolation, clamped)."""
    x = np.sort(np.asarray(x, np.float64).ravel())
    n = x.size
    q = np.asarray(p, float) / 100.0 * n + 0.5   # 1-based fractional rank
    q = np.clip(q, 1, n)
    lo = np.floor(q).astype(int)
    hi = np.minimum(lo + 1, n)
    f = q - lo
    return x[lo - 1] * (1 - f) + x[hi - 1] * f


def gauss_filter(img, sigma):
    """imgaussfilt with MATLAB's default size 2*ceil(2*sigma)+1 and replicate padding."""
    r = int(np.ceil(2 * sigma))
    x = np.arange(-r, r + 1, dtype=np.float64)
    k = np.exp(-(x ** 2) / (2 * sigma ** 2))
    k /= k.sum()
    out = ndi.correlate1d(img.astype(np.float64), k, axis=0, mode='nearest')
    out = ndi.correlate1d(out, k, axis=1, mode='nearest')
    return out.astype(img.dtype)


def laplacian_filter(img, alpha=0.2):
    """imfilter(img, fspecial('laplacian', alpha), 'replicate')."""
    a = alpha
    h1 = a / (a + 1)
    h2 = (1 - a) / (a + 1)
    k = np.array([[h1, h2, h1], [h2, -4 / (a + 1), h2], [h1, h2, h1]])
    return ndi.correlate(img.astype(np.float64), k, mode='nearest').astype(img.dtype)
