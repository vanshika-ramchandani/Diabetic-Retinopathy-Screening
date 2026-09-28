"""NETRA live screening prototype - Gradio web app.

    python app.py            local, http://127.0.0.1:7860
    python app.py --share    public *.gradio.live link (Colab)

Layout follows the team's MATLAB screening app (Screening_App_Framework/
run_screening_app.m): controls on top, four image panels, a diagnostic card
and a telemedicine bar. Every number on it comes from our two real models;
the panels fill in as each model finishes.
"""
from __future__ import annotations

import argparse
import html
import json
from pathlib import Path

import gradio as gr
import numpy as np
from PIL import Image

from netra import models
from netra.grade import GRADE_NAMES
from netra.pipeline import analyze_stream

HERE = Path(__file__).resolve().parent
SAMPLES = sorted((HERE / 'samples').glob('*.jpg'))
METRICS = json.loads((HERE / 'models' / 'metrics.json').read_text(encoding='utf-8')) \
    if (HERE / 'models' / 'metrics.json').exists() else {}

CSS = """
.gradio-container {max-width: 1400px !important}
#hdr {background:#0b2545; color:#fff; padding:14px 20px; border-radius:10px}
#hdr h1 {color:#fff; margin:0; font-size:22px}
#hdr p {color:#cfe0f5; margin:4px 0 0 0; font-size:13px}
.card {border:1px solid #d6dde6; border-radius:10px; padding:14px 18px; background:#fff; color:#15202b}
.card h3 {margin:0 0 8px 0; font-size:15px; color:#0b2545}
.mono {font-family: Consolas, Menlo, monospace; font-size:13px; line-height:1.55; white-space:pre-wrap}
.badge {display:inline-block; padding:10px 18px; border-radius:8px; font-weight:700; font-size:16px}
.b-ref {background:#f6d5d5; color:#9b1c1c} .b-ok {background:#d5f0da; color:#1c6b2e}
.b-esc {background:#fde7c7; color:#8a4b00} .b-rej {background:#e5e7eb; color:#374151}
.b-wait {background:#e8eef5; color:#1d4f91}
.legend span {margin-right:14px; font-size:12px}
.foot {font-size:12px; color:#6b7280}
"""

LEGEND = ('<div class="legend"><span style="color:#e00">&#9679; microaneurysm</span>'
          '<span style="color:#0059ff">&#9679; haemorrhage</span>'
          '<span style="color:#c9a800">&#9679; hard exudate</span>'
          '<span style="color:#00b3b3">&#9679; soft exudate</span>'
          '<span style="color:#0a0">&#9675; optic disc</span></div>')


def badge(cls, text):
    return f'<span class="badge {cls}">{text}</span>'


def card_html(R, stage):
    q = R.get('quality')
    L = []
    if q:
        L.append(f"Quality gate      : {q['decision']}  (gradeability {q['score']}/100)")
        for r in q['reasons']:
            L.append(f'                    - {r}')
    if R.get('decision_path') == 'REJECTED_AT_QUALITY_GATE':
        L.append('')
        L.append(f"ACTION            : {q['instruction']}")
        L.append('No grade produced - NETRA does not grade what it cannot read.')
    if 'rule_grade' in R:
        c = R['rule_grade']['counts']
        L.append(f"Lesion model      : MA {c['MA']} | HE {c['HE']} | EX {c['EX']} | SE {c['SE']}"
                 f"   -> lesion-rule grade {R['rule_grade']['grade']}")
        L.append(f"                    {R['rule_grade']['rationale']}")
    elif q and q['gradeable']:
        L.append('Lesion model      : running...')
    if 'grader' in R:
        g = R['grader']
        L.append(f"ResNet-18 grader  : grade {g['grade']} ({GRADE_NAMES[g['grade']]})  "
                 f"confidence {100 * g['confidence']:.1f}%   P(referable) {g['referable_prob']:.2f}"
                 f" (threshold {g['threshold']:.2f})")
    elif q and q['gradeable']:
        L.append('ResNet-18 grader  : running...')
    if 'vessels' in R:
        v = R['vessels']
        dom = '' if v['in_domain'] else '   [camera outside DRIVE training domain - qualitative]'
        L.append(f"Vessel model      : {100 * v['area_frac']:.1f}% of retinal field{dom}")
    elif q and q['gradeable']:
        L.append('Vessel model      : running...')
    if 'dual' in R:
        D = R['dual']
        L.append('')
        L.append(f"Dual-evidence     : {D['decision']} - {D['action']}")
        for r in D['reasons']:
            L.append(f'                    - {r}')
    if 'timing' in R and stage == 'done':
        t = R['timing']
        parts = ' | '.join(f'{k} {v:.1f}s' for k, v in t.items())
        L.append('')
        L.append(f"Time              : {R['elapsed']:.1f} s total on {models.device()}  ({parts})")
    body = html.escape('\n'.join(L)) if L else 'Load a fundus photo and press Run screening.'
    return f'<div class="card"><h3>Clinical diagnostic summary</h3><div class="mono">{body}</div></div>'


def verdict_html(R, stage):
    if stage != 'done':
        return badge('b-wait', 'SCREENING...') if R else badge('b-wait', 'AWAITING INPUT')
    if R['decision_path'] == 'REJECTED_AT_QUALITY_GATE':
        return badge('b-rej', 'NOT GRADED - RECAPTURE')
    line = R['report_line']
    if R['dual']['decision'] == 'ESCALATE':
        return badge('b-esc', '&#9888; ESCALATE - OPHTHALMOLOGIST REVIEW') + f'<p>{html.escape(line)}</p>'
    if R['referable']:
        return badge('b-ref', '&#9888; REFERRAL REQUIRED') + f'<p>{html.escape(line)}</p>'
    return badge('b-ok', '&#10003; RESOLVED ON-SITE') + f'<p>{html.escape(line)}</p>'


CAM_LABEL = 'Model 1 - Grad-CAM (DR grade)'
DISPLAY_WIDTH = 1600   # panels show ~340 px tall; full 4288 px frames only slow the public tunnel


def for_display(a):
    """Downscale a panel for the browser. Analysis always runs at full resolution."""
    if a.shape[1] <= DISPLAY_WIDTH:
        return a
    h = round(a.shape[0] * DISPLAY_WIDTH / a.shape[1])
    return np.asarray(Image.fromarray(a).resize((DISPLAY_WIDTH, h), Image.LANCZOS))


def run(img, state):
    if img is None:
        raise gr.Error('Upload a fundus photo or pick a sample first.')
    img = np.asarray(img)
    sent = set()                     # each panel goes over the wire once, when its model finishes
    first = True
    for stage, R in analyze_stream(img):
        panels = {'orig': R['image'],
                  'les': R['lesions']['overlay'] if 'lesions' in R else None,
                  'ves': R['vessels']['overlay'] if 'vessels' in R else None,
                  'cam': R['grader']['overlay'] if 'grader' in R else None}
        upd = {}
        for k, a in panels.items():
            if a is not None and k not in sent:
                upd[k] = gr.update(value=for_display(a))
                sent.add(k)
            elif first:
                upd[k] = gr.update(value=None)     # clear the previous photo's panels
            else:
                upd[k] = gr.update()
        if 'grader' in R:
            g = R['grader']
            upd['cam']['label'] = (f"Model 1 - Grad-CAM: grade {g['grade']} {GRADE_NAMES[g['grade']]}"
                                   f" - conf {100 * g['confidence']:.0f}%")
        elif first:
            upd['cam']['label'] = CAM_LABEL
        first = False
        state = {'done': stage == 'done', 'referable': bool(R.get('referable', False)),
                 'rejected': R.get('decision_path') == 'REJECTED_AT_QUALITY_GATE',
                 'escalate': R.get('dual', {}).get('decision') == 'ESCALATE'}
        yield (upd['orig'], upd['les'], upd['ves'], upd['cam'], verdict_html(R, stage), card_html(R, stage),
               TELEMED_READY, state)


TELEMED_READY = ('<div class="card mono">Telemedicine link: ready - a referable result can be dispatched '
                 'to the district hospital queue (simulated; see Pillar 5 Simulink model).</div>')


def dispatch(state):
    if not state or not state.get('done'):
        return '<div class="card mono">Run the screening first.</div>'
    if state['rejected']:
        return '<div class="card mono">Not dispatched: image was not gradeable. Recapture on site.</div>'
    if state['referable'] or state['escalate']:
        return ('<div class="card mono" style="background:#fdf1e4;color:#8a3d00">DISPATCH CONFIRMED (simulated): '
                'compressed referral package (4.8 MB) queued for the district hospital ophthalmologist, '
                'with lesion map, vessel map and Grad-CAM attached.</div>')
    return ('<div class="card mono" style="background:#e6f5e9;color:#1c6b2e">Telemedicine not required: '
            'patient cleared locally at the PHC. 0 bytes transmitted.</div>')


def load_sample(name):
    if not name:
        return None
    return Image.open(HERE / 'samples' / name).convert('RGB')


def metrics_md():
    if not METRICS:
        return ''
    rows = '\n'.join(f"| {m['model']} | {m['metric']} | {m['value']} | {m['test_set']} |" for m in METRICS['rows'])
    return ('| Model | Metric | Value | Held-out test set |\n|---|---|---|---|\n' + rows
            + f"\n\n_Source: {METRICS['source']}_")


def build():
    with gr.Blocks(title='NETRA - DR screening') as demo:
        state = gr.State({})
        gr.HTML('<div id="hdr"><h1>NETRA &middot; Explainable Diabetic Retinopathy Screening</h1>'
                '<p>SIH 2026 &middot; PS 26038 &middot; one fundus photo &rarr; two AI models (DR assessment + vessels) '
                '&rarr; one screen for the doctor</p></div>')
        with gr.Row(equal_height=True):
            upload = gr.Image(label='Fundus photo (upload or drag)', type='numpy', height=220, scale=2,
                              sources=['upload', 'clipboard'])
            with gr.Column(scale=1):
                sample = gr.Dropdown(choices=[p.name for p in SAMPLES], label='or pick a sample (IDRiD test set)',
                                     value=None)
                run_btn = gr.Button('Run screening', variant='primary', size='lg')
                disp_btn = gr.Button('Dispatch to telemedicine queue', variant='secondary')
            verdict = gr.HTML(badge('b-wait', 'AWAITING INPUT'))
        with gr.Row():
            p1 = gr.Image(label='Original fundus (retinal field)', interactive=False, height=340)
            p2 = gr.Image(label='Model 1 - Lesions (IDRiD-trained)', interactive=False, height=340)
            p3 = gr.Image(label='Model 2 - Vessels (DRIVE-trained)', interactive=False, height=340)
            p4 = gr.Image(label=CAM_LABEL, interactive=False, height=340)
        gr.HTML(LEGEND)
        card = gr.HTML(card_html({}, ''))
        telemed = gr.HTML(TELEMED_READY)
        with gr.Accordion('How this works, and what each model was measured at', open=False):
            gr.Markdown(
                '**Model 1** assesses DR: a lesion network marks microaneurysms, haemorrhages and exudates, and a '
                'ResNet-18 grader gives the ICDR grade with a Grad-CAM heatmap. **Model 2** traces the vessel tree. '
                'No network sees another network\'s output. A quality gate runs first (an unreadable photo gets a recapture instruction, not a grade), '
                'and a dual-evidence check runs last: if the CNN grade and the grade implied by the '
                'lesion counts disagree about referral, the case is escalated to an ophthalmologist.\n\n'
                + metrics_md())
        gr.HTML('<p class="foot">Screening aid only - not a diagnosis. Every referable or escalated result needs '
                'ophthalmologist review. Neovascularisation is not assessed (no pixel-level training labels exist).</p>')

        sample.change(load_sample, sample, upload)
        run_btn.click(run, [upload, state], [p1, p2, p3, p4, verdict, card, telemed, state])
        disp_btn.click(dispatch, state, telemed)
    return demo


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('--share', action='store_true')
    ap.add_argument('--port', type=int, default=7860)
    a = ap.parse_args()
    models.warmup()
    print(f'NETRA models loaded - running on {models.device()}', flush=True)
    build().queue(default_concurrency_limit=2).launch(share=a.share, server_port=a.port,
                                                      css=CSS, theme=gr.themes.Soft())
