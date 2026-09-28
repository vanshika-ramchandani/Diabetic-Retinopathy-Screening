"""Parity: the Python port must reproduce MATLAB netraAnalyze on the golden images.

Golden files come from matlab/s26_golden_refs.m (not committed - they are large).
Image-processing tests need only the golden files; model tests also need the
ONNX files from matlab/s25_export_onnx.m and are skipped until those exist.

    pytest web/tests -q
"""
from __future__ import annotations

from pathlib import Path

import numpy as np
import pytest
from scipy.io import loadmat

from netra import mimage as mi
from netra.config import MODEL_DIR
from netra.preprocess import apply_clahe, retinal_crop, retinal_mask

GOLDEN = sorted((Path(__file__).parent / 'golden').glob('*.mat'))
HAVE_ONNX = all((MODEL_DIR / f'{n}.onnx').exists() for n in ('lesion', 'vessel', 'grader'))
needs_onnx = pytest.mark.skipif(not HAVE_ONNX, reason='ONNX models not exported yet (s25)')

if not GOLDEN:
    pytest.skip('no golden refs - run matlab/s26_golden_refs.m', allow_module_level=True)


def load(p):
    return loadmat(p, squeeze_me=True, struct_as_record=False)


def dice(a, b):
    a, b = a.astype(bool), b.astype(bool)
    s = a.sum() + b.sum()
    return 1.0 if s == 0 else 2 * (a & b).sum() / s


@pytest.fixture(params=GOLDEN, ids=[p.stem for p in GOLDEN], scope='module')
def g(request):
    return load(request.param)


# ------------------------------------------------------------ image processing
def test_crop(g):
    crop, bbox = retinal_crop(g['raw'])
    assert tuple(bbox) == tuple(int(v) for v in g['bbox'])
    assert np.array_equal(crop, g['crop'])


def test_retina_mask(g):
    M, frac, clipped = retinal_mask(g['crop'])
    assert dice(M, g['retina']) > 0.9999


def test_clahe(g):
    J = apply_clahe(g['crop'])
    diff = np.abs(J.astype(int) - g['claheOnCrop'].astype(int))
    assert diff.max() <= 1, f'max diff {diff.max()}'
    assert (diff > 0).mean() < 0.001


def test_imresize_uint8(g):
    x = mi.imresize(g['raw'], (160, 160))
    diff = np.abs(x.astype(int) - g['graderInput'].astype(int))
    assert diff.max() <= 1, f'max diff {diff.max()}'


def test_imresize_float(g):
    gg = g['crop'][..., 1].astype(np.float32) / 255
    y = mi.imresize(gg, 1024 / gg.shape[1])
    assert y.shape == g['resize1024'].shape
    assert np.abs(y - g['resize1024']).max() < 1e-4


def test_quality(g):
    from netra.grade import quality_gate
    Q = quality_gate(g['crop'])
    assert Q['decision'] == g['qDecision']
    assert abs(Q['score'] - int(g['qScore'])) <= 1
    m = g['qMetrics']
    for k in ('focus', 'illumUniformity', 'underExposed', 'overExposed', 'contrast'):
        ref = float(getattr(m, k))
        assert abs(Q['metrics'][k] - ref) <= 1e-3 * max(abs(ref), 1e-6) + 1e-6, k


# ------------------------------------------------------------ models
@needs_onnx
def test_lesions(g):
    if 'lesionProb' not in g:
        pytest.skip('rejected at quality gate')
    from netra.grade import rule_grade
    from netra.segment import detect_lesions
    L = detect_lesions(g['crop'])
    assert np.abs(L['prob'] - g['lesionProb']).mean() < 0.02
    for c in range(4):
        assert dice(L['masks'][..., c], g['lesionMasks'][..., c]) >= 0.95, f'channel {c}'
    rg = rule_grade(L['masks'], retinal_mask(g['crop'])[0])
    assert rg['grade'] == int(g['ruleGrade'])


@needs_onnx
def test_vessels(g):
    if 'vesselProb' not in g:
        pytest.skip('rejected at quality gate')
    from netra.segment import segment_vessels
    V = segment_vessels(g['crop'])
    assert dice(V['mask'], g['vesselMask']) >= 0.95


@needs_onnx
def test_grader(g):
    if 'graderProb' not in g:
        pytest.skip('rejected at quality gate')
    from netra.grade import grade
    G = grade(apply_clahe(g['crop']))
    ref = np.asarray(g['graderProb'], float)
    assert np.abs(G['prob'] - ref).max() < 0.02
    assert G['grade'] == int(np.argmax(ref))
    cam_ref = np.asarray(g['graderCam'], float)
    r = np.corrcoef(G['cam'].ravel(), cam_ref.ravel())[0, 1]
    assert r >= 0.95, f'CAM correlation {r:.3f}'


@needs_onnx
def test_end_to_end(g):
    from netra.pipeline import analyze
    R = analyze(g['raw'])
    assert R['decision_path'] == g['decisionPath']
    if 'finalGrade' in g:
        assert R['final_grade'] == int(g['finalGrade'])
