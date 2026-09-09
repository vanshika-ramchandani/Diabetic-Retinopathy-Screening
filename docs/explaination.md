# explaination.md — Plain-English Explanations

> **What this file is for:** every decision explained so a non-technical teammate can defend it out loud.
> **This is your Q&A prep document.** Read it before the internal round.
> Each entry: *what we did · why · how to say it if a judge asks.*
---

# ⚡ SESSION-3 UPDATE (5 Sep 2026) — READ THIS FIRST

**The build is finished and measured.** The pitch below supersedes the older 90-second script
further down this file, which still carries pre-results placeholders.

## The numbers you can now say out loud

Every one of these is in `results/deck_facts.txt`, produced by a named script. If it is not in
that file, do not say it.

| Claim | Number | Where it came from |
|---|---|---|
| Referable DR sensitivity | **91.9%** | sealed APTOS test split, n=549, `s12_eval_grader` |
| Referable DR specificity | **95.4%** | same |
| ROC-AUC | **0.983** | same |
| 5-class agreement (QWK) | **0.876** | same |
| Quality gate reject rate | **4.8%** | fitted on 400 real captures, `s13_calibrate_quality` |
| CNN errors caught by dual evidence | **84%** (36 of 43) | `s16_dual_evidence_aptos` |
| Referable cases silently missed | **0** | same |
| Manual-review backlog, 1 year | **167 expert-days** | Simulink model, `buildNetraSimulink` |
| Break-even flagged fraction | **72%** — we flag **40%** | `districtSim` |

**The problem statement asked for >90% sensitivity and >85% specificity. We met both.**

## The 90-second pitch (revised)

1. **The gap.** "India has 101 million diabetics — the ICMR-INDIAB study, *Lancet* 2023. About
   17% develop retinopathy. Ninety percent of the resulting blindness is preventable. Rural India
   has roughly one ophthalmologist per 100,000 people. The gap isn't treatment. It's screening capacity."
2. **Show the refusal.** Load a bad image. *"It won't guess. It rejects the image and tells the
   operator exactly what to fix — and that threshold was fitted to real capture data, not picked by us."*
3. **Show the evidence.** Load a real case. *"It doesn't just say Level 2. It shows the Grad-CAM,
   and it counts actual lesions — microaneurysms, haemorrhages, exudates — and grades them against
   the international clinical scale."*
4. **Show the escalation.** *"When its two independent methods disagree, it refuses to auto-report.
   On our held-out set that caught 84% of the CNN's referable-status errors, and not one referable
   patient was silently reported as normal."*
5. **The system claim.** *"Manual review isn't understaffed — it's unstable. Our Simulink model shows
   the backlog growing without bound: 167 expert-days in a single year. One expert can absorb 72% of
   captures before the queue diverges. We flag 40%. That's the whole argument."*

## Hard questions, and the honest answers

**"Your sensitivity is 91.9% — how do we know you didn't tune that on the test set?"**
> "We didn't. The operating point was chosen on the *validation* split to hit 90% sensitivity, and
> then applied unchanged to a test split that script opens exactly once. That's the same protocol
> Gulshan 2016 and the IDx-DR pivotal trial used. The code is `s12_eval_grader.m` — the threshold is
> fitted on lines that only ever see validation data."

**"You're comparing yourself to Google's 90.3% on EyePACS. Same thing?"**
> "Same *task*, different *dataset*. We're on a held-out APTOS split; they're on EyePACS-1 and
> Messidor-2. We say that on the slide. It's a like-for-like task, not a like-for-like benchmark,
> and we'd need external validation to make that claim."

**"Why does the deck say Simulink and not SimEvents?"**
> "SimEvents is licensed on our machine but isn't actually installed — `ver` reports it, but there's
> no toolbox directory and the library won't load. We found that when we tried to build the model.
> So we built the same queueing result out of core Simulink blocks that genuinely open on this laptop.
> We'd rather demo something real than claim a model we can't open in front of you."

**"Your dual-evidence check escalates 48–62% of cases. Isn't that useless in practice?"**
> "That's the honest weak point, and we know why. The lesion network is trained at IDRiD's native
> resolution — around 4288×2848 — and the APTOS images we measured against are cached at 512 pixels.
> That's outside its trained regime, so it over-calls lesions and disagreement is inflated. The
> *safety* result stands: it caught 84% of the CNN's errors. The *cost* number is an upper bound, and
> re-measuring it on full-resolution originals is our top next task. We're not going to quote a
> flattering escalation rate we haven't earned."

**"Only 54 annotated training images?"**
> "That's IDRiD's own limit — it's the benchmark, and 81 pixel-annotated images is all that exists.
> It's also why we don't lead with lesion Dice. The grading result rests on 3,662 APTOS images."

**"What about proliferative DR / neovascularisation?"**
> "We don't detect it, and we say so rather than implying 'not PDR'. No pixel-level neovascularisation
> labels exist in either public dataset. The rule grader exposes a `pdrDetectable = false` flag
> specifically so a downstream caller can't mistake silence for a negative."

## What changed since the earlier notes in this file

- The benchmark row is **no longer blank** — it has real held-out numbers.
- Build status is shown as **status words, not percentages**; a percentage of a module isn't measurable.
- Epidemiology updated to ICMR-INDIAB 2023 (101 million, 16.9%), replacing the older 77 million figure.
- The district claim is now the **stability argument**, not a bandwidth percentage — it holds without
  depending on our own accuracy.

---

---

## THE 90-SECOND PITCH (memorise this shape)

1. **The problem number.** "India has 77 million diabetics. About 18% develop diabetic retinopathy. 90% of that blindness is preventable — but rural India has one ophthalmologist per 100,000 people. The gap isn't treatment. It's screening capacity."
2. **Show the refusal.** Load a bad image. *"Watch — it won't guess. It rejects the image and tells the operator exactly what to fix."*
3. **Show the explanation.** Load a real case. *"It doesn't just say Level 2. It shows you the heatmap, and it counts the actual lesions — 14 microaneurysms, 6 haemorrhages."*
4. **Show the escalation.** *"And when its two independent methods disagree, it refuses to auto-report and escalates to a human."*
5. **The district number.** "Our Simulink model shows this lets **one** ophthalmologist cover 100,000 patients a year, instead of the four to seven you'd otherwise need."

---

## Why MATLAB, and how are you affording it?

**What we did.** Using the MATLAB 30-day free trial (and checking whether our college has a campus licence).

**Why.** The trial isn't a crippled demo — it's the full product: MATLAB, Simulink, and 80+ toolboxes, unlimited use, installed on our own machine using our own GPU. Everything this problem statement asks for is included.

**If a judge asks "what happens after 30 days?"**
> "Three answers. Our college may hold a MathWorks campus licence, which is free and permanent — we're checking. Failing that, the trial is per-account, and we're a six-member team, so we have staggered coverage. And MathWorks has partnered with SIH since 2019 and provides complimentary licences to participants."

**If asked "why not just use Python?"**
> "The problem statement is from MathWorks and specifies the MATLAB toolchain. But it's also genuinely the right tool here — Grad-CAM, CLAHE, morphological segmentation and the discrete-event simulation are all single function calls in MATLAB. And Simulink has no real Python equivalent for the deployment modelling."

---

## Why is your system different from every other DR classifier?

**What we did.** Built the pitch around three *behaviours*, not around an accuracy number.

**Why.** Every team at every hackathon presents "a CNN that classifies fundus images, and here's my accuracy." Accuracy is table stakes — and no judge can verify a claimed number in 90 seconds. What they *can* verify is behaviour they watch happen on screen.

**How to say it:**
> "Most AI screening tools are black boxes that always produce an answer, even when they shouldn't. Ours does three things they don't. **One** — it refuses to guess on an unusable image and tells the operator how to retake it. **Two** — it cross-checks the neural network's grade against a rule-based clinical grade from actual lesion counts, and if the two disagree it escalates to a human instead of auto-reporting. **Three** — it's designed for rural bandwidth, running at the edge so only flagged cases get uploaded. That's an 80% bandwidth reduction."

**The one-liner:**
> "Not a black box — an evidence-based triage system that shows its work and knows when to abstain."

---

## Why does the quality gate matter? Isn't it just preprocessing?

**What we did.** Made image-quality assessment a **gate** that can reject, not just a preprocessing step.

**Why.** The problem statement calls this out directly — existing AI "fails with variable image quality from portable fundus cameras in field conditions." A model that silently produces a confident grade from an out-of-focus image is worse than no model, because a health worker will trust it.

**How to say it:**
> "In a real PHC, a health worker with limited training is operating a portable camera in bad light. If the image is unusable, the honest answer is 'retake it,' not a confident wrong grade. So we score focus, illumination and field-of-view *before* the classifier ever runs, and if it fails we send back a specific instruction — 'underexposed, increase flash' — not just an error."

**Why this wins points:** it shows you thought about the *deployment reality*, not just the dataset.

---

## What does "dual-evidence" actually mean? (This is your best answer — know it cold.)

**What we did.** Grade every image **twice, independently**, then compare.
- **Method 1** — the neural network looks at the whole image and outputs a grade 0–4.
- **Method 2** — classical image processing counts the actual lesions (microaneurysms, haemorrhages, exudates), then applies the *published clinical rules* (the International Clinical DR scale, including the "4-2-1 rule") to derive a grade.

If the two agree → auto-report. If they disagree by more than one level → **escalate to a human, flagged as uncertain.**

**Why this is the strongest idea in the project.** It turns explainability from decoration into a **safety mechanism**. A heatmap is nice to look at but doesn't change what the system *does*. A disagreement check changes the system's behaviour — it's the difference between "here's why I think this" and "I'm not confident enough to answer alone."

**How to say it:**
> "Grad-CAM heatmaps are the standard answer to explainability, but a heatmap doesn't actually protect the patient — it just shows where the model looked. We grade every image twice by completely independent methods: the neural network, and classical lesion counting run through the published clinical criteria. When they agree, we auto-report with high confidence. When they disagree, the system refuses to auto-report and escalates. The explanation isn't decoration — it's a second opinion."

**If asked "what if both methods are wrong in the same way?"**
> "Fair — they're not fully independent, they see the same image. But they fail differently: the CNN fails on unusual presentations and domain shift, the rule-based method fails on subtle or atypical lesions. Correlated failure is much less likely than either failing alone. And every case still goes to a human eventually — we're triaging the queue, not replacing the ophthalmologist."

---

## Why classical image processing? Isn't deep learning better?

**What we did.** Hybrid — classical morphology for lesion detection, deep learning for grading.

**Why (two reasons — the second is the real one).**
1. **It always works.** Classical methods need no training data and no GPU. If our model training had failed the night before submission, we'd still have a working demo.
2. **It makes the explanation clinical.** A heatmap says "the model looked here." A lesion count says "14 microaneurysms, 6 haemorrhages, 3 exudates" — which is *exactly the vocabulary an ophthalmologist already uses* to grade DR. That's the difference between a picture and evidence.

**How to say it:**
> "Deep learning is better at grading — it sees patterns we can't specify. But it can't tell you *why* in language a clinician can act on. Classical morphology can: it produces lesion counts that map directly onto the clinical scale. So we use each for what it's good at, and the fact that we have both is what makes the cross-check possible."

---

## Your model hits exactly 90% sensitivity. Did you tune that?

**Answer honestly — yes, deliberately, and it's correct practice.**

**What we did.** Trained the model, then chose the decision threshold on the validation ROC curve to meet the ≥90% sensitivity requirement, and reported the specificity at that point.

**Why this is legitimate.** The threshold is a **deployment choice**, not a property of the model. Gulshan et al. in JAMA 2016 publish *two different operating points* for the same Google model — 90.3%/98.1% at one setting, 97.5%/93.4% at another — for exactly this reason. In screening, a false negative means missed preventable blindness; a false positive means one unnecessary review. Those costs are not symmetric, so the threshold should favour sensitivity.

**How to say it:**
> "Yes — and that's the correct thing to do. The threshold is a clinical decision, not a model parameter. We set it to meet the sensitivity requirement because in screening, missing a case that goes blind costs far more than flagging one extra case for review. We state the operating point explicitly on the slide, which is the same thing the FDA-cleared systems do."

**What NOT to say:** never claim the number without mentioning the threshold. Being asked and *then* admitting it looks like concealment. Saying it first looks like rigour.

---

## Why did you build a Simulink model? Isn't that just extra work?

**What we did.** Modelled the whole district screening programme as a discrete-event system — patient arrivals, image capture, bandwidth-limited upload, inference throughput, and the ophthalmologist review queue.

**Why.** The problem statement explicitly asks for it, and almost no team will do it. It's free differentiation in front of MathWorks judges. But it also produced our single best number.

**The number:**
> "For a district screening 100,000 patients a year — that's about 400 a day — manual grading needs four to seven full-time ophthalmologists. With our triage, only about 21,000 images a year need human review, each taking under 30 seconds with the Grad-CAM and lesion evidence in front of them. That's about 42 minutes of expert time per day. **One ophthalmologist can cover the entire district.**"

**The bandwidth finding:**
> "The model also showed that uploading everything needs 1.2 GB a day — over an hour on a rural 2 Mbps link. So we run inference at the edge, on the PHC laptop, and upload only flagged cases. 250 MB a day, about 17 minutes. An 80% reduction. We only found that by simulating it."

---

## Why is neovascularisation "roadmap" and not built?

**Be straightforward. Do not pretend it's done.**

> "We prioritised. Neovascularisation detection is the hardest module — it needs vessel tortuosity and branching analysis near the optic disc, and there's no clean classical method. It's also rare in the public datasets, so it wouldn't even trigger in a demo. With one developer and a day, we chose to make the referable-DR pathway genuinely work rather than have five modules half-finished. It's on the roadmap and it's honestly marked as such on our slide."

**Why this answer is strong:** judges respect visible prioritisation. Teams that claim everything works get probed until something breaks. Teams that say "we cut X deliberately, here's why" get trusted on everything else.

---

## Why did you use the provided template instead of a nicer design?

> "Because SIH requires it. The template's own instructions say you can only use the provided template without changing the idea pointers. We put the design effort into the infographics instead — the layout is fixed, the content isn't."

---

## The integrity rules we set for ourselves

These were deliberate decisions, and they're worth stating if asked how the deck was built:

- **No invented metrics.** The "our results" row on the benchmark slide stays blank until the model is evaluated on a held-out test set we never touched during training.
- **No fabricated build status.** The progress bars show our true state. A fake 100% invites a probe we can't survive.
- **No synthetic retinal images.** Every fundus image in the deck is a real one from a public dataset, or a real output from our own pipeline. Generated medical imagery in a clinical deck is indefensible if a judge asks where it came from.

**If asked why the results row is blank at internal round:**
> "We'd rather show you a blank than a number we haven't earned. It gets filled the moment evaluation finishes on the held-out set."
