# AI-Powered Diabetic Retinopathy Screening System
### Smart India Hackathon — Problem Statement SIH26038 (Sponsored by MathWorks)

---

## What This Project Does

India has over 77 million adults with diabetes — the second-highest number in the world. About 18% of them develop Diabetic Retinopathy (DR), a disease that can cause blindness but is almost entirely preventable *if caught early*. The problem is that rural India has only about **1 ophthalmologist per 100,000 people**, so manual eye screening for everyone simply isn't possible.

This project builds an AI system that can look at a photo of a patient's retina (a "fundus image"), automatically grade how severe their Diabetic Retinopathy is, explain *why* it made that decision in a way a doctor can quickly double-check, and simulate how such a system would actually perform if rolled out across a real rural district serving 100,000+ patients a year.

The project has two main parts:
1. **A trained AI model** that grades retinal images (this repo's core deliverable)
2. **A Simulink simulation** that models the entire real-world screening workflow — from a village camera to a district hospital doctor's desk — to prove the system can actually handle the patient volume in practice

---

## Part 1: The DR Grading Model

### What it does
The model looks at a fundus (retinal) photo and classifies it into one of 5 official severity grades, using the **International Clinical DR Severity Scale**:

| Grade | Meaning |
|---|---|
| 0 | No DR (healthy) |
| 1 | Mild DR |
| 2 | Moderate DR |
| 3 | Severe DR |
| 4 | Proliferative DR (most advanced) |

Grades 2 and above are considered **"referable"** — meaning the patient needs to see a specialist. Catching these cases reliably is the most clinically important job of the model.

### How it was built
- **Base model**: EfficientNet-B0 (a well-known, efficient image-recognition architecture), adapted using transfer learning
- **Dataset**: APTOS 2019 (Kaggle), ~3,662 real fundus images with doctor-assigned grades
- **Handling imbalance**: Some grades (like Severe DR) have far fewer example images than others. Instead of throwing away data to "balance" the dataset, the model uses **class-weighted training** — it pays extra attention to underrepresented grades during learning
- **Train/Validation/Test split**: 70% / 15% / 15%, using a fixed random seed (`rng(42)`) so the exact same split can be reproduced by anyone re-running this code
- **Training**: 15 epochs, Adam optimizer, run entirely on CPU (no GPU was available for this project)

### Results (on held-out test data the model never saw during training)

| Metric | Result |
|---|---|
| Sensitivity (catching real referable cases) | **95.07%** |
| Specificity (correctly clearing healthy patients) | **90.15%** |
| Overall 5-class accuracy | See report |
| AUC (ROC curve) | **0.972** |
| Precision / Recall / F1 | Included in code output |

Both sensitivity and specificity comfortably clear the clinical targets required for a real screening tool (>90% sensitivity, >85% specificity for referable DR).

### Explainability (Grad-CAM)
Because doctors shouldn't have to blindly trust an AI's answer, the model comes with a visual explanation tool called **Grad-CAM**. For every prediction, it produces a heatmap showing exactly which part of the retina the model was "looking at" when it made its decision — red/yellow areas mattered most, blue areas mattered least. A doctor can glance at this heatmap and sanity-check the AI's reasoning in seconds, rather than trusting a number with no context.

### Files in this repo (DR model)
| File | What it is |
|---|---|
| `DR_Severity_Grading_Pipeline.mlx` | Full MATLAB Live Script — code, comments, and results together. Open with MATLAB to run or edit. |
| `DR_Severity_Grading_Pipeline.m` | Same code as a plain text file — readable directly on GitHub, no MATLAB required. |
| `trainedNet_v3.mat` | The final trained model file. Load this in MATLAB to make predictions without retraining. |

### How to run it
1. Open `DR_Severity_Grading_Pipeline.mlx` in MATLAB (Online or Desktop)
2. Make sure `trainedNet_v3.mat` is in the same folder — the script automatically detects it and **loads it instead of retraining** (retraining from scratch takes ~30 minutes on CPU)
3. Run the script section by section, or all at once, to see data loading, evaluation metrics, confusion matrix, ROC curve, and Grad-CAM visualizations

---

## Part 2: Simulink District-Scale Workflow Simulation

### The real-world problem this solves
Having an accurate AI model isn't enough — you also need to prove the *entire screening system* can actually work at scale in the real world: patients arriving, slow rural internet, doctors with limited time, and so on. This simulation answers the question: **"If we rolled this out across a real district, would it actually keep up, or would patients get stuck waiting?"**

### The scenario being modeled
- **100,000+ patients per year**, screened across **50 rural health centres**, all connected to **one district hospital** staffed by just **2 ophthalmologists**
- Patients arrive at a rate of about 1 new patient every 54 seconds, district-wide
- Images travel over slow rural mobile networks (2G/3G/4G)

### How the pipeline works, step by step
1. **At the village clinic**: A photo is taken and instantly checked on-device by an "Edge AI" quality/triage check
2. **75% of cases** (healthy or mild) are resolved right there on the spot — nothing needs to be sent anywhere
3. **The remaining 25%** (moderate-or-worse cases) get compressed to a small ~4.8 MB package and sent over the rural network — taking about 32 seconds to transmit
4. **At the central server**: The AI grades the image and generates a Grad-CAM explanation — this takes about 4.5 seconds
5. **At the district hospital**: A doctor reviews the case with the AI's heatmap assistance in about 25 seconds (under the 30-second target) — much faster than reviewing an image with no AI help at all

### Why this matters — the key numbers

| What we're measuring | Old way (fully manual) | New way (this system) |
|---|---|---|
| Cases doctors have to review per day | 400 | 100 (75% resolved automatically on-site) |
| Time per doctor review | 4 minutes | 25 seconds |
| Total doctor-hours needed per day | 26.7 hours (needs 4+ doctors) | 0.69 hours (under 45 minutes) |
| Can the queue keep up? | **No — grows without limit** | **Yes — stays stable near zero** |
| Patients still waiting by end of day | 160+ backlogged | 0 — everyone gets same-day results |
| Data sent over the network per day | 16 GB | 0.48 GB (97% less data) |

The core finding: with the old manual approach, the math simply doesn't work — 2 doctors physically cannot review 400 cases a day in 4 minutes each. With the AI doing first-pass filtering and providing explainable assistance, the same 2 doctors can easily keep up, and the system could scale to **300,000+ patients per year** without adding more staff.

### How this was simulated (two complementary methods)
1. **A Simulink model** (`telemedicine_screening_model.slx`) — models the whole pipeline visually as a block diagram: patients arriving, the 25% filtering step, network delay, AI compute delay, and doctor review capacity, all connected together so you can watch queue behavior over time
2. **A MATLAB Monte Carlo simulation** (`simulate_telemedicine_district.m`) — a more detailed, realistic version that simulates all 50 clinics at once with randomness built in (patients don't arrive at perfectly even intervals in real life), including image quality failures (12% of photos initially fail quality checks, but 95% are fixed with an on-site retake) and fluctuating network speeds

### Files in this repo (Simulink simulation)
| File | What it is |
|---|---|
| `telemedicine_screening_model.slx` | The visual Simulink block-diagram model |
| `build_simulink_telemed_model.m` | Script that builds the Simulink model programmatically |
| `simulate_telemedicine_district.m` | The detailed Monte Carlo simulation across all 50 clinics |

### How to run it
```matlab
% In the MATLAB Command Window:
cd 'Pillar5_Telemedicine_Simulation'
run_capacity_analysis

% To open and interact with the Simulink model directly:
open_system('telemedicine_screening_model')
```

---

## Additional Project Files

Larger files, extended datasets, and supplementary materials that don't fit GitHub's file size limits are available here:

📁 **[Google Drive Folder](https://drive.google.com/drive/folders/1FY6LkvWMtRyfA4aBlf-qFRSmvLXibcOY?usp=sharing)**

---

## Project Status

- ✅ **DR Severity Grading** — complete, validated, exceeds clinical targets
- ✅ **Explainability (Grad-CAM)** — complete and working
- ✅ **Simulink Workflow Simulation** — complete, shows the system is viable at district scale
- ⚠️ **Image Quality Assessment** — implemented using classical image-processing techniques (not a separately trained model)
- ⚠️ **Retinal Structure Segmentation** (vessels, microaneurysms, exudates, etc.) — a full production system would use several additional specialized trained models for this; given hackathon time constraints, this prototype uses classical computer-vision methods as a proof-of-concept rather than training separate deep learning models for each lesion type

These scope decisions were made deliberately to prioritize a fully working, clinically validated core pipeline (grading + explainability + real-world feasibility simulation) within the time available, rather than partially implementing every module.

---

## Tools Used
MATLAB, Image Processing Toolbox, Computer Vision Toolbox, Deep Learning Toolbox, Medical Imaging Toolbox, Simulink, Statistics and Machine Learning Toolbox
