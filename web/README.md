---
title: NETRA DR Screening
emoji: 👁️
colorFrom: blue
colorTo: indigo
sdk: gradio
app_file: app.py
pinned: false
license: cc-by-4.0
---

# NETRA: live diabetic retinopathy screening prototype

Upload a fundus photo and the results appear side by side:

| Panel | Network | Trained on | Output |
|---|---|---|---|
| Model 1: Lesions | ResNet-18 U-Net, 5 channels | IDRiD | microaneurysm / haemorrhage / hard + soft exudate / optic disc masks |
| Model 1: Grad-CAM | ResNet-18 classifier | APTOS 2019 | ICDR grade 0-4, confidence, P(referable), Grad-CAM heatmap |
| Model 2: Vessels | ResNet-18 U-Net, 1 channel | DRIVE | vessel tree |

No network sees another network's output. Two checks sit outside the networks:

- **Quality gate (first).** An unreadable photo gets a recapture instruction, not a grade.
- **Dual-evidence check (last).** When the CNN grade and the grade implied by the lesion counts
  disagree about referral, the case goes to an ophthalmologist.

## Lesion network: v2, and one disclosed deviation

The first lesion network (v1) was trained only on IDRiD, where every image has DR. On healthy eyes
from other cameras it marked the fovea as a haemorrhage and light reflections as exudates.

v2 is v1 fine-tuned with 2,178 patches from 400 healthy APTOS eyes (`matlab/s28`, `s29`). On the
grader's sealed APTOS test split (549 eyes; `matlab/s30`):

| | v1 | v2 |
|---|---|---|
| Healthy eyes called referable by the lesion rules | 96.3% | 17.0% |
| Cases the dual-evidence check escalates | 76.0% | 37.5% |
| Referable eyes the grader missed that were auto-cleared | 0 | 0 |
| IDRiD test Dice, hard exudate | 0.732 | 0.681 |
| IDRiD test Dice, soft exudate | 0.546 | 0.600 |

`s30` has a pre-registered adoption rule: no lesion channel's Dice may fall by more than 0.05. Hard
exudate fell by 0.051, so the script's verdict was to keep v1. The team adopted v2 anyway on
28 Sep 2026, for its far lower false-referral rate. This deviation is recorded in
`results/deck_facts.txt` (`lesion_v2.adopted_by_team`).

## Run

```bash
pip install -r requirements.txt
python app.py            # http://127.0.0.1:7860
python app.py --share    # public link (used by colab_demo.ipynb)
```

The networks are ONNX exports of the MATLAB models (`matlab/s25_export_onnx.m`). Every threshold
comes from `models/config.json`, which the same script writes. `tests/test_parity.py` checks the
Python port against MATLAB's own outputs (`matlab/s26_golden_refs.m`).

A screening aid, not a diagnosis. Neovascularisation is not assessed.
