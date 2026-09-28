"""One photo -> quality gate -> our two models -> dual-evidence check.

Port of matlab/netraAnalyze.m.
  Model 1  lesion net (masks, counts, rule grade) + ResNet-18 grader (grade, Grad-CAM)
  Model 2  vessel net
No network ever receives another network's output. The lesion net and the
grader share one preprocessing step (crop + CLAHE), computed once. The three
networks run concurrently (onnxruntime releases the GIL), and `analyze_stream`
yields each result the moment it finishes so the UI fills in live.
"""
from __future__ import annotations

import time
from concurrent.futures import ThreadPoolExecutor, as_completed

import numpy as np

from . import grade as G
from .preprocess import apply_clahe, retinal_crop, retinal_mask
from .segment import detect_lesions, segment_vessels

_pool = ThreadPoolExecutor(max_workers=3)


def _timed(fn, *a):
    t = time.perf_counter()
    out = fn(*a)
    return out, time.perf_counter() - t


def analyze_stream(Iraw: np.ndarray):
    """Yields (stage, partial_result_dict). Stages: quality, lesions|grader|vessels, done."""
    t0 = time.perf_counter()
    if Iraw.ndim == 2:
        Iraw = np.repeat(Iraw[..., None], 3, axis=2)
    Iraw = Iraw[..., :3].astype(np.uint8)
    I0, bbox = retinal_crop(Iraw)
    R = {'image': I0, 'bbox': bbox, 'timing': {}}

    R['quality'], R['timing']['quality'] = _timed(G.quality_gate, I0)
    yield 'quality', R
    if R['quality']['decision'] == 'REJECT':
        R['decision_path'] = 'REJECTED_AT_QUALITY_GATE'
        R['report_line'] = 'NOT GRADED - ' + R['quality']['instruction']
        R['elapsed'] = time.perf_counter() - t0
        yield 'done', R
        return

    vfut = _pool.submit(_timed, segment_vessels, I0)     # needs no CLAHE: start it first
    Inet, R['timing']['clahe'] = _timed(apply_clahe, I0)
    futs = {_pool.submit(_timed, detect_lesions, I0, Inet): 'lesions',
            _pool.submit(_timed, G.grade, Inet): 'grader',
            vfut: 'vessels'}
    for f in as_completed(futs):
        name = futs[f]
        R[name], R['timing'][name] = f.result()
        if name == 'lesions':
            R['rule_grade'] = G.rule_grade(R['lesions']['masks'], retinal_mask(I0)[0])
        if name == 'grader':
            R['grader']['overlay'] = G.cam_overlay(I0, R['grader']['cam'])
        yield name, R

    g, rg = R['grader'], R['rule_grade']
    D = G.dual_evidence(g['grade'], g['prob'], rg, g['referable'])
    R['dual'] = D
    R['decision_path'] = D['decision']
    R['final_grade'] = D['finalGrade']
    R['referable'] = D['referable'] or (D['decision'] == 'ESCALATE' and (g['referable'] or rg['referable']))
    name = G.GRADE_NAMES[R['final_grade']]
    if D['decision'] == 'ESCALATE':
        R['report_line'] = (f"ESCALATE - ophthalmologist review (grader {g['grade']}, "
                            f"lesion rules {rg['grade']})")
    elif R['referable']:
        R['report_line'] = f"REFERABLE - {name} (ICDR {R['final_grade']})"
    else:
        R['report_line'] = f"not referable - {name} (ICDR {R['final_grade']})"
    R['elapsed'] = time.perf_counter() - t0
    yield 'done', R


def analyze(Iraw):
    R = None
    for _, R in analyze_stream(Iraw):
        pass
    return R
