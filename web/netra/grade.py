"""Model 1b: the ResNet-18 DR grader, plus the two checks that sit outside the networks.

  grade          port of the grader block in matlab/netraAnalyze.m
  quality_gate   port of matlab/m1_quality/assessQuality.m + qualityMetrics.m
  rule_grade     port of matlab/m4_grade/ruleGradeICDR.m
  dual_evidence  port of matlab/m4_grade/dualEvidence.m

Grad-CAM without autograd. The grader ends feature map A (HxWxK) -> global
average pool -> dense (W, b) -> softmax. For that head the gradient of the
softmax output p_c with respect to A_k is uniform over space and equal to
p_c (W_ck - sum_j p_j W_jk) / (H*W), so Grad-CAM is
    ReLU( sum_k (W_ck - sum_j p_j W_jk) A_k )
up to a positive factor that the final rescale removes. That is computed
exactly from one forward pass, which is why onnxruntime (no gradients) is enough.
"""
from __future__ import annotations

import numpy as np

from . import mimage as mi
from . import models
from .config import CFG
from .preprocess import normalise, retinal_mask

GRADE_NAMES = ['No DR', 'Mild NPDR', 'Moderate NPDR', 'Severe NPDR', 'PDR']


# ------------------------------------------------------------------ model 1b
def grade(Inet):
    """Inet: CLAHE'd retinal crop (the input the lesion net also reads).

    crop -> CLAHE -> 512 -> 384 -> ImageNet normalisation is the exact path the
    grader was trained and measured on (s01 cache, s11, s12)."""
    n = CFG.grader_size
    x = mi.imresize(mi.imresize(Inet, (CFG.grader_cache_size,) * 2), (n, n))
    feat, prob = models.run('grader', normalise(x)[None])
    p = prob.reshape(-1).astype(np.float64)
    gi = int(np.argmax(p))
    ref_prob = float(p[CFG.referable_from:].sum())
    thr = CFG.grader_referable_thr

    A = feat[0].astype(np.float64)                      # h x w x K
    W = np.asarray(CFG.grader_fc_weights, np.float64)   # 5 x K
    wc = W[gi] - p @ W
    cam = np.maximum(A @ wc, 0)
    cam = mi.imresize(cam, (n, n))
    cam = np.maximum(cam, 0)
    if cam.max() > cam.min():
        cam = (cam - cam.min()) / (cam.max() - cam.min())
    else:
        cam = np.zeros_like(cam)
    return {'grade': gi, 'prob': p, 'confidence': float(p[gi]), 'referable_prob': ref_prob,
            'referable': ref_prob >= thr, 'threshold': thr, 'input': x, 'cam': cam}


def cam_overlay(I, cam, alpha=0.45):
    """Jet heatmap over the image the grader saw (resized to I)."""
    c = mi.imresize(cam.astype(np.float64), I.shape[:2])
    c = np.clip(c, 0, 1)
    jet = np.stack([np.clip(1.5 - np.abs(4 * c - 3), 0, 1),
                    np.clip(1.5 - np.abs(4 * c - 2), 0, 1),
                    np.clip(1.5 - np.abs(4 * c - 1), 0, 1)], axis=2)
    out = (1 - alpha) * I.astype(np.float64) / 255 + alpha * jet
    return mi.to_uint8(out * 255)


# ------------------------------------------------------------------ quality gate
def quality_metrics(I):
    M, frac, clipped = retinal_mask(I)
    g = I[..., 1].astype(np.float32) / 255.0
    target = 1024
    if g.shape[1] != target:
        s = target / g.shape[1]
        g = mi.imresize(g, s)
        M = mi.imresize(M, s, 'nearest')
    if not M.any():
        M = np.ones(g.shape, bool)
    L = mi.laplacian_filter(g, 0.2)
    q = {'focus': float(np.var(L[M].astype(np.float64), ddof=1))}
    bg = mi.gauss_filter(g, 40)
    v = bg[M].astype(np.float64)
    q['illumUniformity'] = float(1 - min(v.std(ddof=1) / max(v.mean(), np.finfo(float).eps), 1))
    r = g[M]
    q['underExposed'] = float(np.mean(r < 0.10))
    q['overExposed'] = float(np.mean(r > 0.95))
    p = mi.prctile(r, [2, 98])
    q['contrast'] = float(p[1] - p[0])
    q['fovCoverage'], q['clipped'], q['meanLum'] = frac, clipped, float(r.mean())
    return q


def _ramp(x, lo, hi):
    if hi <= lo:
        return float(x >= hi)
    return min(max((x - lo) / (hi - lo), 0.0), 1.0)


def quality_gate(I):
    t = CFG.quality_thr
    q = quality_metrics(I)
    reasons, instr = [], []
    if q['focus'] < t['focusMin']:
        reasons.append(f"out of focus ({q['focus']:.2e} < {t['focusMin']:.2e})")
        instr.append('image is blurred - hold the camera steady and refocus')
    if q['underExposed'] > t['underMax']:
        reasons.append(f"underexposed ({100 * q['underExposed']:.1f}% of retina below 0.10)")
        instr.append('image is too dark - increase flash intensity and recapture')
    if q['overExposed'] > t['overMax']:
        reasons.append(f"overexposed ({100 * q['overExposed']:.1f}% of retina above 0.95)")
        instr.append('image is washed out - reduce flash intensity and recapture')
    if q['contrast'] < t['contrastMin']:
        reasons.append(f"insufficient contrast ({q['contrast']:.3f} < {t['contrastMin']:.3f})")
        instr.append('retinal detail is not visible - clean the lens and recapture')
    soft = q['illumUniformity'] < t['illumMin']
    if reasons:
        decision, instruction = 'REJECT', '; '.join(instr)
    elif soft:
        decision, instruction = 'ENHANCE', ''
        reasons.append(f"uneven illumination ({q['illumUniformity']:.2f} < {t['illumMin']:.2f}) - correctable")
    else:
        decision, instruction = 'PASS', ''
    terms = [_ramp(q['focus'], t['focusMin'], t['focusRef']),
             _ramp(q['contrast'], t['contrastMin'], t['contrastRef']),
             _ramp(q['illumUniformity'], t['illumMin'], t['illumRef']),
             _ramp(t['underMax'] - q['underExposed'], 0, t['underMax']),
             _ramp(t['overMax'] - q['overExposed'], 0, t['overMax'])]
    return {'decision': decision, 'instruction': instruction, 'reasons': reasons,
            'score': int(mi.mround(100 * np.mean(terms))), 'metrics': q,
            'gradeable': decision != 'REJECT'}


# ------------------------------------------------------------------ lesion rules
def rule_grade(masks, retina):
    MA, HE, EX, SE = (masks[..., c] for c in range(4))
    n = {k: mi.count_blobs(B) for k, B in zip(('MA', 'HE', 'EX', 'SE'), (MA, HE, EX, SE))}
    if retina.any():
        ys, xs = np.nonzero(retina)
        cx, cy = xs.mean() + 1, ys.mean() + 1           # 1-based centroid, as regionprops
    else:
        cy, cx = HE.shape[0] / 2, HE.shape[1] / 2
    ry, rx = int(mi.mround(cy)), int(mi.mround(cx))
    q = [mi.count_blobs(HE[:ry, :rx]), mi.count_blobs(HE[:ry, rx:]),
         mi.count_blobs(HE[ry:, :rx]), mi.count_blobs(HE[ry:, rx:])]
    severe = all(v > 20 for v in q)
    if n['MA'] + n['HE'] + n['EX'] + n['SE'] == 0:
        grade, why = 0, 'no lesions detected'
    elif severe:
        grade, why = 3, f"4-2-1 met: >20 haemorrhages in all four quadrants [{' '.join(map(str, q))}]"
    elif n['HE'] or n['EX'] or n['SE']:
        grade = 2
        parts = [f'{n[k]} {lbl}' for k, lbl in (('HE', 'haemorrhage(s)'), ('EX', 'hard exudate(s)'),
                                                 ('SE', 'soft exudate(s)')) if n[k]]
        why = 'beyond microaneurysms only: ' + ', '.join(parts)
    else:
        grade, why = 1, f"{n['MA']} microaneurysm(s) only"
    return {'grade': grade, 'referable': grade >= 2, 'counts': n, 'quadrantHaem': q,
            'rule421': severe, 'rationale': why, 'gradeName': GRADE_NAMES[grade]}


def dual_evidence(cnn_grade, cnn_prob, rg, cnn_referable, conf_min=0.60, grade_tol=1):
    conf = float(np.max(cnn_prob))
    rule_ref = rg['referable']
    delta = abs(cnn_grade - rg['grade'])
    tf = lambda b: 'REFERABLE' if b else 'not referable'  # noqa: E731
    reasons, escalate = [], False
    if cnn_referable != rule_ref:
        escalate = True
        reasons.append(f'referable-status conflict: CNN says {tf(cnn_referable)}, lesion rules say '
                       f'{tf(rule_ref)} - this is the disagreement that changes patient management')
    if delta > grade_tol:
        escalate = True
        reasons.append(f"grade gap of {delta} levels (CNN {cnn_grade} vs rules {rg['grade']}), "
                       f'tolerance is {grade_tol}')
    if conf < conf_min:
        escalate = True
        reasons.append(f'CNN confidence {conf:.2f} below {conf_min:.2f}')
    if rg['rule421']:
        reasons.append('4-2-1 severe-NPDR criterion met on lesion counts')
    if escalate:
        decision, final = 'ESCALATE', max(cnn_grade, rg['grade'])
        action = 'route to ophthalmologist for manual review'
    else:
        decision, final = 'AUTO_REPORT', cnn_grade
        action = 'auto-generate report'
        reasons.append(f"CNN and lesion rules agree ({cnn_grade} vs {rg['grade']}), confidence {conf:.2f}")
    return {'decision': decision, 'finalGrade': final, 'action': action, 'agree': not escalate,
            'reasons': reasons, 'referable': final >= 2}
