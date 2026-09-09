# NETRA — Neural Explainable Triage for Retinal Assessment

SIH 2026 · PS 26038 · MathWorks · *Explainable AI for Diabetic Retinopathy Screening in Rural India*

An evidence-based DR triage system that shows its work and **abstains when it cannot see**.
It is not one model. It is a gate, two independent graders that must agree, and a
deployment model that says when the whole thing stops being affordable.

---

## Run it

```matlab
cd matlab

netra                          % the GUI - this is the demo
netra('path\to\fundus.jpg')    % or screen one image at the prompt

R = netraScreen('path\to\fundus.jpg', struct('verbose',true));
R.quality.decision             % PASS | ENHANCE | REJECT
R.quality.instruction          % what the operator should do about a REJECT
R.ruleGrade.grade              % ICDR from counted lesions
R.cnnGrade.grade               % ICDR from ResNet-18
R.dual.decision                % AUTO_REPORT | ESCALATE
R.reportLine                   % the one line a clinician reads
```

Full rebuild from data:

```matlab
run_all                        % lesion segmentation pipeline (stages 2-8)
s01_cache_aptos                % cache APTOS at 512px
s11_train_grader               % ResNet-18 DR grader
s12_eval_grader                % open the sealed grader test split, once
s13_calibrate_quality(400)     % fit the quality gate to real captures
s14_integration                % end-to-end run + results/deck_facts.txt
s15_deck_figures               % title hero + raw/enhanced/lesion triptych
s16_dual_evidence_aptos        % measure D2 in-domain
run_tests                      % 52 tests
```

---

## The three things that are not "a CNN that classifies fundus images"

### D1 — it refuses to guess

`m1_quality/` scores focus, illumination uniformity, exposure and contrast **inside the
retinal mask**, and returns PASS / ENHANCE / REJECT with a specific recapture instruction
("image is too dark — increase flash intensity and recapture").

The thresholds are **fitted, not chosen**. `s13_calibrate_quality` measures 400 raw APTOS
captures and solves for a single shared percentile such that the *overall* reject rate hits
a target. This matters: setting each of the four reject criteria at its own 5th percentile
rejects the union, which measured **16%** — a far more expensive gate than intended. At a
shared p=1.14 the union lands at **4.8%** (88.2% pass / 7.0% enhance).

`netraScreen` **short-circuits** on REJECT and leaves every downstream field empty, so no
caller can read a grade that was never computed.

### D2 — dual evidence, not a decorative heatmap

A Grad-CAM map is a picture a clinician cannot falsify. Two independent estimators that must
agree *is* a safety mechanism. `m4_grade/ruleGradeICDR.m` derives an ICDR grade from counted
lesions (including the haemorrhage arm of the **4-2-1 rule**, quadrant-wise about the retinal
centroid); `m4_grade/dualEvidence.m` compares it with the CNN grade.

Escalation is deliberately asymmetric — disagreement about *whether the patient is referable*
always escalates; one level of disagreement inside the same referable class is tolerated,
because the scale's own inter-grader agreement is not better than that. Fusion is
conservative: the higher grade carries.

**Measured on the sealed APTOS test split (n=549):** of the CNN's 43 referable-status errors,
D2 escalated **36 (83.7%)**. Of the 28 referable cases the CNN alone missed, **0** were
auto-reported as normal.

### D3 — the queue, not a percentage

`m5_simulink/districtSim.m` and `buildNetraSimulink.m` model a district programme.
The point is not a saving; it is that **manual review is an unstable system**. At 100,000
patients/year one expert faces 10 hours of reading per 6-hour day, so the backlog grows
without bound — the Simulink model accumulates **167 expert-days** in one working year.

The assumption-light number is the **break-even flagged fraction: 72%**. It depends only on
arrival rate, reading time and clinical hours — no model accuracy at all. NETRA's validated
triage rate is **40%**, leaving 32 points of headroom.

---

## Results

### Referable DR (ICDR 2+) — sealed APTOS test split, n = 549

| | value | requirement |
|---|---|---|
| Sensitivity | **0.9193** | > 0.90 ✅ |
| Specificity | **0.9540** | > 0.85 ✅ |
| ROC-AUC | 0.9834 | — |
| Precision | 0.9318 | — |

Operating point chosen **on validation** at sensitivity ≥ 0.90 (val 0.9013 / 0.9509), then
applied unchanged to the test split. Choosing it on test would report the best number the
test set can give, which is not a held-out result.

5-class ICDR grading: accuracy 0.8015, **QWK 0.8755**.

### Lesion segmentation — 27 sealed IDRiD test images

| lesion | Dice | AUPR |
|---|---|---|
| Hard exudate | 0.7315 | 0.5948 |
| Haemorrhage | 0.5904 | 0.4697 |
| Soft exudate | 0.5460 | 0.3330 |
| Microaneurysm | 0.5185 | 0.1990 |

Haemorrhage flag at 512px region level: sens 0.8505, spec 0.7776, ROC-AUC 0.8762.
Optic disc (auxiliary): Dice 0.8987.

---

## Pipeline

| script | does |
|---|---|
| `s00_config.m` | every path, hyperparameter and the fixed channel order |
| `s01_cache_aptos.m` | crop + CLAHE + resize the 3,662 APTOS images to 512px |
| `s02_cache_patches.m` | 3,520 train + 300 val patches at **native resolution** |
| `s04_build_net.m` | assembles the net, asserts wiring, runs the overfit test |
| `s05_train_seg.m` | trains with focal-Tversky + weighted BCE |
| `s06_tune_thresholds.m` | per-channel thresholds fitted on **validation only** |
| `s07_evaluate_test.m` | one pass over the sealed 27 IDRiD test images |
| `s08_figures.m` | GT-vs-prediction overlays (`s08_figures(inf)` for all 27) |
| `s11_train_grader.m` | ResNet-18 ICDR grader, stratified 70/15/15 |
| `s12_eval_grader.m` | sealed grader test split + ROC + confusion + Grad-CAM |
| `s13_calibrate_quality.m` | fits the D1 thresholds to a target reject rate |
| `s14_integration.m` | end-to-end run; writes `results/deck_facts.txt` |
| `s15_deck_figures.m` | title hero and the raw→enhanced→lesion triptych |
| `s16_dual_evidence_aptos.m` | measures D2 in-domain on the sealed APTOS split |

`ppt/build_deck.ps1` builds the 6-slide SIH deck. **It reads only `results/deck_facts.txt`** —
a fact that no script measured renders as `n/a`, never as a plausible guess.

---

## Design decisions worth defending

**U-Net, not DeepLabv3+.** Microaneurysms are ~10 px wide at 4288×2848. A stride-16 output
with 4× upsampling cannot recover them. The full-resolution `conv1` skip can.

**No downscaling anywhere in the lesion path.** Patches are cut at native resolution.
Resizing to 512² — the obvious shortcut — destroys the smallest target class outright.

**Lesion-biased patch sampling (60/40).** Raises MA from 0.057% of image pixels to 0.222% of
patch pixels. The 40% uniform-random patches preserve specificity.

**Focal Tversky with β > α.** False negatives penalised 2.3× harder than false positives.
Against a 0.057% target class, plain BCE reaches 99.94% pixel accuracy by predicting all-zero.

**Absent mask file = lesion absent.** IDRiD omits the `.tif` when a lesion does not occur.
Reading those as all-zero planes makes all 54 images usable for all five channels.

**`enhanceFundus` is display-only.** The segmentation net was trained on
`applyClahe(retinalCrop(I))`. Inserting richer enhancement in front of it shifts the input
distribution away from training and degrades masks *silently* — no error, just worse results.

**Sealed test sets, twice.** Segmentation thresholds are fitted in `s06` on 10 validation
images; `s07` is the only script that opens the 27 test images. The grader's operating point
is fitted on its validation split; `s12` is the only script that opens its test split.

**`CFG.useAptosPretrain` stays false.** APTOS was restored and the flag *would* work, but
flipping it retrains the segmentation net — silently invalidating a test set that has already
been opened once.

---

## Known limitations — state these before a judge finds them

- **Neovascularisation is not modelled.** No pixel-level annotation exists in IDRiD or APTOS.
  `ruleGradeICDR` sets `pdrDetectable = false` so it never implies "not PDR". FGADR (signed
  data-use agreement) is the route if it is needed.
- **The D2 escalation *cost* is not validated at deployment resolution.** `s16` measures 62%
  escalation on APTOS, but those images are cached at 512px — outside the lesion net's native
  resolution regime, where it over-calls (84% fused referable against a 41% true rate). The
  *safety* result above is sound; the operating cost is an upper bound. Fixing this means
  running the lesion arm on full-resolution APTOS originals. **This is the top next task.**
- **SimEvents is licensed on this machine but not installed** — no `toolbox/simevents`,
  `load_system('simevents')` fails, and `ver` reporting it is misleading. D3 is therefore
  built from core Simulink blocks. (The licence feature is `SimEvents`; `SimEvents_Toolbox`
  silently returns 0 and looks exactly like a missing toolbox.)
- **Image-level haemorrhage specificity is undefined on IDRiD** — all 27 test images contain
  haemorrhages, so there are no negatives. The 512px region figure is the meaningful one.
- **54 annotated training images.** Small by any standard; the IDRiD benchmark's own limit.
- **APTOS is disease-enriched** (41% referable), not a screening population. The district
  model's referral rate is therefore conservative — a real programme would flag fewer.
- **No external validation.** Single-centre-per-dataset. Domain shift across cameras is a
  listed risk, not a solved one.

---

## Tests

```matlab
verify_build           % 44 checks: artifacts, split integrity, facts vs sources, deck
run_tests              % all 52 unit tests
run_tests("pipeline")  % quality gate, ICDR rules, dual evidence, district model
run_tests("data")      % data integrity + helpers, no trained model needed
run_tests("model")     % trained-model behaviour
```

`verify_build` is the one to run before submitting. It does **not** trust
`results/deck_facts.txt` — it re-opens the `.mat`/`.csv` files each number came from and
compares, so a hand-edited fact or a stale facts file is caught. It also re-derives the test
metrics from the raw saved scores, confirms the three grader splits are disjoint, and checks
the deck has exactly 6 slides with no `n/a` left on them.

`NetraPipelineTests` is GPU-free and dataset-free on purpose: it tests decision *logic*,
which is where a screening system does harm when it is wrong. A grader two points off is a
worse model; a dual-evidence check that fails to escalate a referable disagreement is a
missed diagnosis.
