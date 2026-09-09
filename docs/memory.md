# memory.md — SIH 2026 · PS 26038 · Running Record

> Full running record of the project. Nothing gets lost here.
> Newest entries at the top. Never delete an entry — mark it superseded instead.

---

## PROJECT SNAPSHOT (always keep current)

| Field | Value |
|---|---|
| **PS ID** | 26038 |
| **PS Title** | Explainable AI for Diabetic Retinopathy Screening in Rural India |
| **Organisation** | MathWorks · Category: Software · Theme: MedTech / BioTech / HealthTech |
| **Product name** | **NETRA** — Neural Explainable Triage for Retinal Assessment |
| **Internal round deadline** | Night of **5 Sep 2026** |
| **Team** | `<<TEAM NAME>>` · Team ID `<<TEAM ID>>` · `<<COLLEGE>>` — **still unfilled, blocks final export** |
| **Technical builder** | 1 person (user). Teammates on PPT/design/pitch. |
| **Hardware** | NVIDIA RTX 4060 Laptop GPU (8 GB) — used for all training |
| **MATLAB status** | ✅ **R2026a trial active, expires 4 Oct 2026.** Installed: Image Processing, Computer Vision, Deep Learning, Statistics & ML, Parallel Computing, Simulink. ⚠️ **SimEvents is licensed but NOT installed** (no `toolbox/simevents`) |
| **Datasets** | ✅ APTOS 2019 (3,662, restored from Recycle Bin) · ✅ IDRiD segmentation (81 annotated) · ⬜ DRIVE, Messidor-2 unused |
| **Working dir** | `C:\Users\kanha\Desktop\SIH` |

### Build state tracker

| Module | State | Evidence |
|---|---|---|
| MATLAB install + toolboxes | ✅ working | `ver` verified; SimEvents absent |
| Datasets local | ✅ working | APTOS 3,662 cached at 512px; IDRiD 81 annotated |
| M1 Quality assessment | ✅ working | `m1_quality/`, calibrated on 400 raw captures → 4.8% reject |
| M2 Enhancement | ✅ working | `m2_enhance/enhanceFundus.m` — display path only (D20) |
| M3 Lesion segmentation | ✅ working | 5-channel net, sealed 27-image test, `results/metrics.csv` |
| M4a DR grader (ResNet-18) | ✅ working | **sens 0.9193 / spec 0.9540 / AUC 0.9834**, sealed n=549 |
| M4b Grad-CAM | ✅ working | `figures/gradcam_examples.png`, in GUI + report |
| M4c Dual-evidence check | ✅ working | `m4_grade/dualEvidence.m`, measured on 27 IDRiD images |
| M5 Simulink model | ✅ working | `m5_simulink/netra_district.slx`, builds + simulates |
| App Designer GUI | ✅ working | `matlab/app/netraApp.m` (programmatic uifigure, D18) |
| PPT deck | ✅ generated | `ppt/build_deck.ps1` → `ppt/NETRA_SIH2026_PS26038.pptx` + PDF |
| Neovascularisation | ⛔ cut | No pixel-level labels exist in IDRiD or APTOS |

*Legend: ⬜ not started · 🔄 in progress · ✅ working · ⛔ cut*

---

## [2026-09-05 evening] — Session 3: everything that was still missing

### What was asked
"Resume from where we left and complete what's pending." At the start of this session
the lesion segmentation net was trained and evaluated, and **nothing else existed** —
`m1_quality/`, `m2_enhance/`, `m4_grade/`, `m5_simulink/`, `app/`, `figures/` and `ppt/`
were all empty directories, and `docs/memory.md` still showed every module as not started.

### The unlock: APTOS was recoverable
`CFG.useAptosPretrain` carried the note "APTOS deleted to Recycle Bin 5 Sep ~15:20".
The Recycle Bin still held `Train Images` (3,662 files) and `train.csv`, both restorable
in seconds. That single fact unblocked the DR grader, D2 dual-evidence, and the slide-6
benchmark row — all of which had been written off as impossible. **(D14)**

### What was built
| Module | Files |
|---|---|
| D1 quality gate | `m1_quality/qualityMetrics.m`, `assessQuality.m`, `s13_calibrate_quality.m`, `lib/retinalMask.m` |
| M2 enhancement | `m2_enhance/enhanceFundus.m` |
| DR grader | `s11_train_grader.m`, `s12_eval_grader.m` |
| D2 dual evidence | `m4_grade/ruleGradeICDR.m`, `m4_grade/dualEvidence.m` |
| End-to-end | `netraScreen.m` (M1→M2→M3→M4a→M4c→Grad-CAM, short-circuits at the gate) |
| GUI | `app/netraApp.m` |
| D3 district model | `m5_simulink/districtSim.m`, `buildNetraSimulink.m` |
| Integration + facts | `s14_integration.m`, `s15_deck_figures.m` |
| Deck | `ppt/build_deck.ps1` |
| Figure theming | `lib/lightFigure.m`, `lib/lightAxes.m` |

### Measured results (all held-out, all reproducible)
- **Referable DR (ICDR 2+), sealed APTOS test n=549:** sensitivity **0.9193**, specificity **0.9540**,
  precision 0.9318, ROC-AUC **0.9834**. Operating point chosen on validation at sens ≥ 0.90
  (val: 0.9013/0.9509), then applied unchanged to test. **Meets the PS requirement** (>90% / >85%).
- **5-class ICDR grading:** accuracy 0.8015, **QWK 0.8755**.
- **Quality gate:** calibrated on 400 raw APTOS captures → 88.2% pass / 7.0% enhance / **4.8% reject**.
- **Simulink district model:** manual arm accumulates **167 expert-days** of backlog over one
  working year (unstable queue); triage arm holds at **0**.

### What broke / what surprised us
- **`ver('simevents')` reports SimEvents, but the product is not installed.** No `toolbox/simevents`
  directory exists and `load_system('simevents')` fails; only licence/template manifests are present.
  The licence feature name is also `SimEvents`, not `SimEvents_Toolbox` (which silently returns 0
  and looks exactly like a missing toolbox). D3 was rebuilt in core Simulink. **(D17)**
- **The quality gate's first calibration rejected 16% of images, not 5%.** Four reject criteria each
  at their own 5th percentile reject the *union*. Refitted against a target overall rate. **(D16)**
- **R2026a renders figures in the dark theme by default**, exporting charcoal panels into a white
  deck. Every figure now goes through `lib/lightFigure.m` + `lib/lightAxes.m`.
- **`CFG.useAptosPretrain = true` would have silently invalidated the sealed segmentation result**
  by retraining the net. Deliberately left false. **(D15)**

### Open items
- ⬜ Team Name / Team ID / college — rerun `build_deck.ps1 -TeamName "…" -TeamId "…"`
- ⬜ Record the 90-second GUI demo video (D12)
- ⬜ Export the final PDF and check it on the SIH portal
- ⬜ Overlays exist for 6 of 27 test images; `s08_figures` writes the rest if wanted

---

## [2026-09-04] — Session 1: Research, planning, licensing investigation

### What was asked
User selected PS 26038 for SIH 2026. College internal round due tomorrow night. Needed:
1. Study of the SIH PPT template format
2. Slide-wise PPT content with specific infographics
3. What to build for the internal hackathon
4. Step-by-step build plan
5. Honest verdict on MATLAB licensing — can this be done free?
6. These four documentation files

### Template analysis (completed)
Read `SIH2026-IDEA-Presentation-Format.pptx` by reading the OOXML zip entries directly.

- **7 slides in template; slide 7 is an instruction slide to be deleted → 6 slides final.**
- Canvas: `12192000 × 6858000` EMU = 13.333 × 7.5 in, 16:9 widescreen.
- Fixed slide titles: `SMART INDIA HACKATHON 2026` / `IDEA TITLE` / `TECHNICAL APPROACH` / `FEASIBILITY AND VIABILITY` / `IMPACT AND BENEFITS` / `RESEARCH AND REFERENCES`
- Master elements per slide (do not overlap):
  - Team-name oval: `off(329773, 252246) ext(1251857, 807334)` — top-left
  - Logo picture: `off(9780086, 1500) ext(2249850, 1062337)` — top-right
  - Footer bar rectangle: `off(0, 6354762) ext(12191999, 503238)` — bottom
  - Content textbox typically starts around `y = 2064921–2533653` EMU
- **Template's own rules (verbatim from slide 7):**
  - "Kindly keep the maximum slides limit up to six (6). (Including the title slide)"
  - "Try to avoid paragraphs and post your idea in points / diagrams / Infographics / pictures"
  - "You can only use provided template for making the PPT without changing the idea details pointers"
  - "You need to save the file in PDF and upload the same on portal. No PPT, Word Doc or any other format will be supported."

### MATLAB licensing research (completed — see decision.md D1)

**Verdict: no payment required, ever.**

| Route | Finding | Source |
|---|---|---|
| **College TAH campus licence** | Most AICTE-affiliated colleges have it. Check with college email at `mathworks.com/academia/tah-support-program/eligibility.html`. Free, permanent, all toolboxes. **CHECK FIRST.** | mathworks.com |
| **30-day free trial** ← chosen | **MATLAB + Simulink + 80+ products, desktop install, unlimited use, 30 days.** Covers every toolbox this PS needs. Uses local GPU. | mathworks.com/campaigns/products/trials.html |
| **Staggered team trials** | Trial is per MathWorks Account, not per machine. 6 team members = 6 email IDs ≈ 6 months of cover for the finals. | — |
| **MathWorks SIH partnership** | Partner since 2019; complimentary software/mentoring for participants. Contact `hackathon@mathworks.com` after qualifying. | mathworks.com hackathons page |
| **MATLAB Online Basic (free)** | ❌ **NOT sufficient.** 20 hrs/month, **15-min continuous compute cap**, 5 GB storage. Includes Deep Learning + Image Processing + Stats + Simulink but **NO Computer Vision Toolbox, NO Medical Imaging Toolbox**. Compute cap kills training; 5 GB can't hold APTOS. | mathworks.com/products/matlab-online/matlab-online-versions.html |
| **GNU Octave** | ❌ **Dead end.** No Deep Learning Toolbox, no `gradCAM`, no App Designer, no Simulink. | — |

**Key risk identified:** MATLAB installer is 15–25 GB, 1–3 hrs download. This is the critical path for the whole project.

### Verified benchmark numbers (for Slide 6 — all checked against source, not recalled)

| System | Dataset | Sens. | Spec. | Source |
|---|---|---|---|---|
| Gulshan et al., JAMA 2016 (Google) | EyePACS-1 | 90.3% | 98.1% | *JAMA* 316(22):2402 — high-specificity operating point |
| Gulshan et al., JAMA 2016 | Messidor-2 | 96.1% | 93.9% | high-sensitivity operating point |
| Gulshan et al., JAMA 2016 | EyePACS-1 | 97.5% | 93.4% | high-sensitivity operating point |
| IDx-DR pivotal, Abràmoff 2018 | 900 primary-care subjects | 87.2% | 90.7% | *npj Digital Medicine* 1:39 — first FDA-cleared autonomous AI |
| **PS 26038 requirement** | referable DR L2+ | >90% | >85% | the problem statement |

### Verified dataset sizes
- **APTOS 2019** — 3,662 training images, 5 classes
- **IDRiD** — 516 images total; **81 with pixel-level lesion annotations** (MA, SE, EX, HE binary masks). *The Indian dataset — narrative value.*
- **DRIVE** — 40 images, vessel ground truth
- **Messidor-2** — 1,748 images

### MATLAB capability confirmations
- `gradCAM` exists in Deep Learning Toolbox (with `FeatureLayer`, `ReductionLayer`, `OutputUpsampling` options, GPU-capable). Also `imageLIME` and `occlusionSensitivity`.
- Confirms the explainability module is natively supported — no custom implementation needed.

### Environment findings (this machine)
- ❌ `pandoc` — not installed
- ❌ `python` — Microsoft Store **stub only**, not real Python. No pip, no python-docx.
- ❌ LibreOffice — not installed
- ✅ **Microsoft Word 16.0 COM automation — available.** Used for HTML→DOCX conversion.
- Shell: PowerShell 5.1 (no `&&`, no ternary, no `??`)

### Files produced this session
| File | Purpose |
|---|---|
| `C:\Users\kanha\.claude\plans\ps-id-26038-ps-jolly-wave.md` | Master plan (source of truth) |
| `SIH_PS26038_Battle_Plan.docx` | Same plan as Word doc — 16 pages, 12 tables, ~4,950 words |
| `PPT_GENERATION_PROMPT.md` | Master prompt for AI deck generation + per-tool adaptations |
| `docs\memory.md` `thinking.md` `decision.md` `explaination.md` | This documentation set |
| Folder tree under `data\ matlab\ figures\ ppt\` | Project scaffolding |

### Tooling recommendation given for the PPT
- **Template constraint kills full-deck AI generators** (Gamma/Tome/Beautiful.ai) as the *final artifact* — SIH mandates the provided template.
- Recommended: **Napkin.ai** for hero diagrams (feed one block at a time) + **PowerPoint assembly on the real template**.
- Secondary: Gamma to generate then harvest infographics; Copilot-in-PowerPoint if licensed; Claude/ChatGPT → python-pptx for precise shape placement.

### Open items carried forward
- ⬜ Team Name, Team ID, college name — needed for Slide 1
- ⬜ Result of the college TAH campus-licence check
- ⬜ Kaggle account (needed for APTOS/IDRiD downloads)

---

## TEMPLATE FOR FUTURE ENTRIES

```
## [YYYY-MM-DD HH:MM] — <topic>

### What happened

### What was decided
(cross-reference decision.md IDs)

### What was built / changed
(files touched)

### What broke / what surprised us

### Open items
```
