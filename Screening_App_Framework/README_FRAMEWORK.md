# Screening Application Framework (Pillars 1 to 4 + Telemedicine Bridge)

This folder contains the **Interactive Screening & Validation Application Framework** for **SIH Problem Statement SIH26038** (*Explainable AI for Diabetic Retinopathy Screening in Rural India*).

---

## 1. Overview

This application acts as the front-end clinician interface shown in hackathon demonstrations. It allows users to:
1. **Upload an eye photo** (or pick from pre-loaded demonstration retinas).
2. Watch the **4-stage screening pipeline** execute live:
   * **Stage 1 (Pillar 1)**: Quality Gate & CLAHE Contrast Enhancement.
   * **Stage 2 (Pillar 2)**: Retinal Blood Vessel Tree and Lesion Candidate Map.
   * **Stage 3 (Pillar 3)**: ICDR Severity Grading & Clinical Risk Stratification.
   * **Stage 4 (Pillar 4)**: Explainable AI Attention Heatmap (Grad-CAM style).
3. **Bridge to Pillar 5**: One-click **"Dispatch to Telemedicine Queue"** to route referable cases into the District Civil Hospital queue model.

> **Lightweight & Self-Contained**:  
> This framework uses pure algorithmic image processing from MATLAB's `Image Processing Toolbox`. It does **not** require multi-gigabyte external deep learning weights or cloud accounts, so it runs out-of-the-box on any computer.

---

## 2. Directory Structure

```
Screening_App_Framework/
│
├── run_screening_app.m             # Main Interactive MATLAB GUI Application
│
├── sample_images/                  # Synthetic realistic demonstration fundus images
│   ├── sample_normal.png           # Grade 0: Normal Retina (Clean)
│   ├── sample_mild_npdr.png        # Grade 1: Mild NPDR (Microaneurysms only)
│   ├── sample_moderate_npdr.png    # Grade 2: Moderate NPDR (MAs + Hard Exudates)
│   ├── sample_severe_pdr.png       # Grade 4: Proliferative DR (Extensive lesions)
│   └── generate_sample_retinas.m   # Script that generated these sample images
│
├── modules/                        # Plug-and-Play Processing Modules
│   ├── assess_quality.m            # Pillar 1: Sharpness, illumination, CLAHE
│   ├── detect_structures.m         # Pillar 2: Vessel segmentation & lesion detection
│   ├── classify_severity.m         # Pillar 3: ICDR clinical grade mapping (0-4)
│   └── generate_explainability.m   # Pillar 4: Saliency / attention heatmap overlay
│
└── README_FRAMEWORK.md             # This documentation
```

---

## 3. How to Launch the Application

### In the MATLAB Desktop GUI:
In the MATLAB Command Window, simply type:
```matlab
cd 'c:\Users\user\Programing files\Yajat\Projects\SIH Retinopathy\Screening_App_Framework'
run_screening_app
```

The interactive interface will pop up immediately.

---

## 4. Step-by-Step Live Demo Instructions

1. **Select a Sample Retina**:
   * Click the dropdown menu at the top (`or select demo sample:`).
   * Choose **`Sample 3: Grade 2 (Moderate NPDR)`** (or any other sample).
   * The image will load instantly in **Window 1**.
2. **Run Full Screening**:
   * Click the green button: **`⚡ Run Full Screening Pipeline`**.
   * Within 1–2 seconds, all 4 visual windows and the diagnostic card will populate:
     * **Window 2**: Green-channel CLAHE enhanced image with focus score.
     * **Window 3**: Segmented green blood vessels with microaneurysms and exudates circled.
     * **Window 4**: Grad-CAM attention heatmap highlighting lesion hot spots.
     * **Bottom Card**: Shows `DIAGNOSIS: Grade 2`, `⚠ REFERRAL REQUIRED`, and $94.1\%$ confidence.
3. **Dispatch to Telemedicine**:
   * Click the orange button: **`📡 Dispatch to Telemedicine Queue`**.
   * It logs the referral package ($4.8\text{ MB}$) for transmission to the District Hospital modeled in **`Pillar5_Telemedicine_Simulation/`**.

---

## 5. Developer Note: How to Plug In Deep Learning Weights Later

If your team trains a PyTorch or MATLAB CNN (e.g., EfficientNet or ResNet50) in the future:
1. Export your model to ONNX: `model.onnx`.
2. Open [`modules/classify_severity.m`](file:///c:/Users/user/Programing%20files/Yajat/Projects/SIH%20Retinopathy/Screening_App_Framework/modules/classify_severity.m).
3. Replace the rule-based logic with:
   ```matlab
   persistent net
   if isempty(net)
       net = importNetworkFromONNX('model.onnx');
   end
   pred = predict(net, img);
   ```
The rest of the GUI, pre-processing, and explainability heatmaps will continue working seamlessly without any modifications!
