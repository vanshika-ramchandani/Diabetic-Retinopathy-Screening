# decision.md — Decision Register

> Terse, scannable. One row per decision. Full reasoning lives in `thinking.md`; plain-English defence lives in `explaination.md`.
> **Never edit a row to reverse it.** Mark it `Superseded` and add a new row.

---

## Active decisions

| ID | Date | Decision | Rationale (one line) | Status | Reversible? |
|---|---|---|---|---|---|
| **D1** | 2026-09-04 | Use the **MATLAB 30-day free trial** (desktop), not MATLAB Online Basic and not Octave | Trial = MATLAB + Simulink + 80+ products, unlimited, local GPU; Basic lacks Computer Vision Toolbox and caps compute at 15 min; Octave has no Deep Learning Toolbox or App Designer | Active | Yes — switch to college TAH licence if eligible |
| **D2** | 2026-09-04 | **Train inside MATLAB** with `trainnet`, not Colab→ONNX import | Avoids a 2-hour ONNX conversion debugging risk on a 1-day deadline; ResNet-18 on 3,662 images at 224px is only 20–40 min on the laptop GPU | Active | Yes — Colab is the documented fallback if GPU fails |
| **D3** | 2026-09-04 | Download the **pre-resized APTOS mirror (~0.5–1 GB)**, not the raw 9.5 GB set | Bandwidth is the binding constraint tonight; same labels, ~10× faster download and training | Active | Yes |
| **D4** | 2026-09-04 | **Classical CV for lesion detection + CNN for grading** (hybrid, not end-to-end deep) | Lesion path needs zero training data so it always runs — it is the insurance policy if training fails; it also makes explanations *clinical* rather than *pixel-level* | Active | No — it is the architecture |
| **D5** | 2026-09-04 | Select the **operating point on the ROC curve for sensitivity ≥ 90%**, then report specificity at that point | Exactly what FDA-cleared systems do (Gulshan 2016 publishes two operating points); legitimate and defensible under questioning | Active | No — it is the evaluation protocol |
| **D6** | 2026-09-04 | **P0/P1/P2 scope tiers**; neovascularisation detection **cut to roadmap** | Solo builder, ~20 working hours. NV detection is the hardest module with the least demo value | Active | Yes — restore for SIH finals |
| **D7** | 2026-09-04 | Product name **NETRA**; positioning = *"abstain + dual-evidence"*, not accuracy | Every competing team will present a CNN classifier; differentiation must come from the safety behaviour, not the metric | Active | Yes |
| **D8** | 2026-09-04 | **Skip Medical Imaging Toolbox as a dependency** (list it for PS compliance only) | It targets 3D/DICOM volumes; Image Processing Toolbox covers 100% of fundus work. Reduces install size on the critical path | Active | Yes |
| **D9** | 2026-09-04 | Deck built **on the official SIH template**; AI generators used only to *produce infographics*, never the final file | SIH rule: "You can only use provided template… without changing the idea details pointers." Gamma/Tome impose their own identity and would violate the format | Active | No — it is a competition rule |
| **D10** | 2026-09-04 | **Napkin.ai** as primary infographic tool, PowerPoint for assembly | Purpose-built text→diagram, free, exports editable SVG; better per-diagram output than a whole-deck generator | Active | Yes |
| **D11** | 2026-09-04 | Convert documents via **Word COM automation** | pandoc absent, `python` is a Store stub with no pip, LibreOffice absent. Word 16 COM was the only working path — zero installs | Active | Yes |
| **D12** | 2026-09-04 | **Record a 90-second screen capture** of the working GUI as demo insurance | A live demo crash in front of judges is unrecoverable; a recording is not | Active | No — do it regardless |
| **D13** | 2026-09-04 | **Do not fabricate** the "NETRA (ours)" benchmark row, build-status percentages, or synthetic retinal images | A single invented number destroys credibility the moment a MathWorks judge asks how it was measured | Active | No — integrity constraint |

---

| **D14** | 2026-09-05 | **Restore APTOS from the Recycle Bin** rather than re-download | `Train Images` (3,662 files) and `train.csv` were still recoverable, deleted the same afternoon. Restoring took seconds against a multi-hour re-download on the deadline | Active | Yes |
| **D15** | 2026-09-05 | Keep `CFG.useAptosPretrain = false` **even though APTOS is back** | That flag makes `run_all` retrain the segmentation net. It has already been evaluated once on the sealed 27-image test set; retraining would silently invalidate `results/metrics.csv`. The grader gets its own track (s10–s15) | Active | No — protects the sealed result |
| **D16** | 2026-09-05 | Quality-gate thresholds fitted to a **target overall reject rate (5%)**, not per-axis percentiles | Four reject criteria each at their own 5th percentile reject the *union*, measured at 16% — an operationally different and much costlier gate. One shared percentile (p=1.14) puts the union at 4.8% | Active | Yes — change the target |
| **D17** | 2026-09-05 | Build D3 in **core Simulink, not SimEvents** | SimEvents is licensed and `ver` reports it, but the product is **not installed** — no `toolbox/simevents`, `load_system('simevents')` fails. Claiming a SimEvents model that cannot be opened on the demo machine is indefensible in front of MathWorks judges | Active | Yes — if SimEvents is installed later |
| **D18** | 2026-09-05 | GUI as a **programmatic `uifigure` .m file**, not a binary `.mlapp` | Same App Designer components and appearance, but readable in a diff and not corruptible. One builder carrying the whole codebase cannot afford an opaque binary | Active | Yes |
| **D19** | 2026-09-05 | The deck may use **only numbers present in `results/deck_facts.txt`** | Generated by `s14_integration` from the scripts that measured them. A missing fact renders as "n/a" in the deck, never as a plausible guess. This is D13 made mechanical instead of remembered | Active | No — integrity constraint |
| **D20** | 2026-09-05 | `enhanceFundus` is **display-only**; the network input path stays `applyClahe` | The segmentation net was trained on `applyClahe(retinalCrop(I))`. Inserting richer enhancement in front of it shifts the input distribution away from training and degrades masks silently — no error, just worse results | Active | No — it is a correctness constraint |
| **D21** | 2026-09-05 | Slide 6 reports the **referable-DR row on APTOS**, labelled as a different dataset from Gulshan/IDx-DR | The task matches (referable DR, sensitivity/specificity at a chosen operating point); the dataset does not. Presenting it as a like-for-like benchmark would be the fabrication D13 forbids | Active | No |

## Superseded decisions

*(none yet)*

---

## Decisions still open — need input

| ID | Question | Blocking? | Owner |
|---|---|---|---|
| **O1** | Does the college hold a MathWorks TAH campus licence? | No — trial covers it either way | User |
| **O2** | Team Name / Team ID / college name for Slide 1 | Blocks final deck export only | User |
| **O3** | Live demo or recorded video on the day? | Decide after the GUI is stable | User |
