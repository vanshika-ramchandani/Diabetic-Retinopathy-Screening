# thinking.md — Reasoning Log

> The reasoning *as it was formed*, including the options that were rejected.
> Terse register in `decision.md`; plain-English version for teammates in `explaination.md`.

---

## Decision 1 — MATLAB licensing route

**Context.** MathWorks PS, so MATLAB is effectively mandatory. Team has no licence, no subscription, and asked directly whether the free tiers are enough or whether they must pay.

**Options considered.**
1. MATLAB Online Basic (free tier)
2. 30-day desktop trial
3. GNU Octave / open-source substitutes
4. Buying a Student licence

**Trade-offs.**
- *Online Basic* looked attractive (free, no download) and does include Deep Learning, Image Processing, Stats and Simulink. But checking the actual spec page killed it: **no Computer Vision Toolbox, no Medical Imaging Toolbox**, a **15-minute continuous compute cap**, and 5 GB storage. Training a CNN is impossible under a 15-minute cap, and APTOS alone exceeds 5 GB.
- *Octave* is the reflexive "open source MATLAB" answer and is wrong here. No Deep Learning Toolbox, no `gradCAM`, no App Designer, no Simulink. Four of the five PS modules are unbuildable.
- *Trial* gives MATLAB + Simulink + 80+ products, desktop, unlimited, on the local GPU. Every named toolbox included.
- *Buying* is unnecessary if the trial and the campus licence exist.

**What tipped it.** The trial has no feature restrictions at all — it is the full product. The only cost is a 30-day clock, which does not bind before an internal round tomorrow. And the team has 6 members = 6 accounts = ~6 months of staggered cover for the finals.

**The thing I nearly missed.** The real constraint is not licensing, it is the **15–25 GB download on the critical path**. Getting the licensing answer right is worthless if the installer isn't running by tonight. That reframed the entire schedule and became step one of the plan.

**Also worth flagging:** most AICTE colleges hold a TAH campus licence that students never hear about. Two-minute check, and it makes the whole question moot permanently.

---

## Decision 2 — Train in MATLAB vs Colab → ONNX

**Context.** GPU laptop *and* Colab available. Obvious instinct: train in PyTorch on Colab where the ecosystem is friendlier, export ONNX, import to MATLAB.

**Options considered.** (a) Train natively in MATLAB with `trainnet`; (b) train in PyTorch/Colab and import via `importNetworkFromONNX`.

**Trade-offs.** Colab is faster to iterate and the user likely knows PyTorch better. But ONNX import is a known source of layer-compatibility failures — unsupported ops, placeholder layers, subtly different preprocessing. Debugging that is unbounded work.

**What tipped it.** Time asymmetry. Native MATLAB training on 3,662 images at 224px with ResNet-18 is 20–40 minutes on a laptop GPU — genuinely small. The ONNX path adds a debugging risk that could consume 2+ hours with no ceiling, on a build with roughly 20 working hours total. Choosing the slower-per-epoch path to avoid an unbounded tail risk is correct here.

**Secondary benefit.** Grad-CAM, the confusion matrix, and the GUI all live in MATLAB. Keeping the model native avoids a second conversion boundary. Colab stays documented as the fallback if `gpuDevice` fails.

---

## Decision 3 — Which APTOS to download

**Context.** Raw APTOS is ~9.5 GB. MATLAB is 15–25 GB. Both on one connection, one night.

**What tipped it.** Bandwidth contention is the binding constraint, and the raw resolution is thrown away anyway — the network trains at 224px. A pre-resized mirror gives identical labels at a fraction of the size, and also trains faster because there is no per-epoch decode-and-downsample cost. Strictly better on both axes.

**Note.** IDRiD is still downloaded at full fidelity. It is small (~0.5 GB), it carries the **pixel-level lesion masks** the lesion module needs for validation, and it is the *Indian* dataset — narrative value in front of Indian judges that APTOS does not have.

---

## Decision 4 — Hybrid architecture: classical CV for lesions, CNN for grading

**Context.** The PS asks for both lesion-level detection and severity grading. Could be done end-to-end deep (segmentation network per lesion type) or classically.

**Options considered.** (a) Deep segmentation (U-Net per lesion class) using IDRiD's 81 annotated images; (b) classical morphology for lesions + CNN for grading.

**Trade-offs.** Deep segmentation is more accurate and more modern. But 81 annotated images is very little, it means training 4 more models, and every one of them is another thing that can fail before tomorrow night.

**What tipped it — two reasons, and the second matters more.**
1. *Insurance.* Classical morphology needs no training data and no GPU. It runs on day one and it cannot "fail to converge." If CNN training goes badly, there is still a working demo.
2. *It makes the explanation clinical.* This is the real argument. A CNN heatmap says "the model looked here." A lesion count says "**14 microaneurysms, 6 haemorrhages, 3 exudates**" — which maps directly onto the International Clinical DR scale an ophthalmologist already uses. That is the difference between a pretty picture and evidence a clinician can act on.

**Which produced Decision 7.** Once both a CNN grade and a rule-based grade exist, they can be *compared* — and disagreement becomes a signal. That is D2 (the dual-evidence check) and it is the strongest idea in the project. It fell out of an architecture chosen for risk reasons, which is worth noticing.

---

## Decision 5 — Operating point selection

**Context.** PS demands >90% sensitivity AND >85% specificity for referable DR. A model trained in one afternoon may not hit both at the default 0.5 threshold.

**What tipped it.** This is not a workaround, it is standard clinical practice. Gulshan et al. (JAMA 2016) publish **two different operating points** for the same model — 90.3%/98.1% at high specificity and 97.5%/93.4% at high sensitivity — precisely because the threshold is a deployment choice, not a model property. In screening, false negatives (missed blindness) cost far more than false positives (an unnecessary review), so the threshold should favour sensitivity.

**How to present it honestly.** State it explicitly on the slide: *"Operating point selected on the validation ROC to meet the ≥90% sensitivity clinical requirement, following FDA-cleared precedent."* Choosing a threshold and saying so is rigour. Choosing one and hiding it is not.

---

## Decision 6 — Scope tiers and cutting neovascularisation

**Context.** Five PS modules, one technical builder, ~20 working hours including sleep.

**What tipped it.** Judges at an internal round see 40+ teams and decide in ~90 seconds. Five half-working modules read as "nothing works." Three solid ones plus a live GUI read as "these people shipped." Depth beats breadth under time pressure — so the scope had to be tiered *in advance*, because a tired builder at 2 a.m. makes bad triage decisions.

**Why neovascularisation specifically.** It is the hardest module (requires vessel tortuosity and branching analysis near the optic disc, no clean classical method), it has the least demo value (rare in the datasets, so it may never fire during a demo), and it is honestly presentable as roadmap. Highest effort, lowest return — the obvious cut.

**Also cut to P2:** PDF report export and confidence calibration. Both are genuinely nice, neither changes a judge's mind in 90 seconds.

---

## Decision 7 — Naming and positioning

**Context.** Roughly every DR team at every hackathon presents "CNN classifies fundus image, here is my accuracy." Accuracy is not a differentiator — it is table stakes, and any claimed number is unverifiable in a 90-second pitch.

**What tipped it.** The differentiation had to come from **behaviour**, not metrics. Three behaviours no one else will show:
- The system **refuses to answer** when the image is inadequate (D1)
- The system **escalates when its two independent methods disagree** (D2)
- The system is **designed for the actual deployment constraint** — rural bandwidth — and this is proven in Simulink (D3)

All three are demonstrable live in under 30 seconds each. Accuracy is not demonstrable at all.

**On the name.** NETRA (नेत्र, "eye") decodes to *Neural Explainable Triage for Retinal Assessment*, which is both a real acronym and culturally resonant for Indian judges. The word **triage** is doing deliberate work: it frames the system as sorting a queue for a human, not as replacing a doctor. That framing pre-empts the most common hostile question in medical-AI pitches.

---

## Decision 9 — AI tooling for the deck

**Context.** User asked which AI makes the best SIH deck. Reflexive answer: Gamma.

**What tipped it — a constraint most teams miss.** The template's own instruction slide reads: *"You can only use provided template for making the PPT without changing the idea details pointers."* Gamma, Tome, and Beautiful.ai all impose their own design system and cannot preserve a supplied master. Using one for the final file risks a format violation.

**So the recommendation had to be split by role:** AI generates the *infographics*; PowerPoint assembles them on the *real template*. Napkin.ai fits this better than Gamma because it is a text→diagram tool rather than a deck generator — which is precisely the shape of the need, given the template supplies the layout and the team supplies the diagrams.

**Caveat recorded honestly.** Knowledge cutoff is May 2026; current free-tier limits for both tools should be verified before a teammate commits an evening to either.

---

## Decision 11 — Document conversion path

**Context.** User asked for the plan as a .docx.

**What I checked.** pandoc (absent), Python (Microsoft Store *stub* — reports "Python was not found", so no pip and no python-docx), LibreOffice (absent), Word COM (**available, v16.0**).

**What went wrong, and the lesson.** First conversion attempt produced a file that opened fine and contained all the text — but **zero tables**. Word had silently fallen back to its plain-text converter because the HTML lacked `<html>`/`<body>` wrappers. Adding the wrapper and forcing `Format:=7` (wdOpenFormatWebPages) produced all 12 tables.

**Generalisable point.** The save succeeded and the file looked right by size and page count. Only an explicit structural check (`$doc.Tables.Count`) caught the failure. Verify the *property you actually care about*, not that the operation returned without error.
