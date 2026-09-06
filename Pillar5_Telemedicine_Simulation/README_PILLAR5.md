# SIH26038: Pillar 5 Telemedicine Workflow & Capacity Simulation

This folder contains the complete simulation package for **Pillar 5 of SIH Problem Statement SIH26038** (*Explainable AI for Diabetic Retinopathy Screening in Rural India* sponsored by **MathWorks**).

---

## 1. Mathematical Formulation & Architecture

The objective is to model a district-level screening program capable of screening **100,000+ patients annually** across **50 rural Primary Health Centres (PHCs)** under realistic infrastructure constraints (intermittent 2G/3G connectivity and an acute shortage of ophthalmologists).

### Mathematical Breakdown:
* **Target Throughput**:
  $$\text{Annual Target} = 100,000\text{ patients}$$
  $$\text{Operating Days} = 250\text{ days/year} \implies \lambda_{\text{district}} \approx 400\text{ patients/day}$$
  $$\lambda_{\text{phc}} \approx 8\text{ patients/day per PHC}$$
* **Arrival Process**: Poisson arrival process $P(k) = \frac{\lambda^k e^{-\lambda}}{k!}$ over a 6-hour camp window ($9:00\text{ AM} - 3:00\text{ PM}$).
* **Pillar 1 Edge Quality Gating**:
  $$p_{\text{ungradeable}} = 12\%, \quad p_{\text{recapture\_success}} = 95\%$$
  $$t_{\text{recapture}} = 90\text{ seconds (operator re-alignment guidance)}$$
* **Pillar 2 & 3 Edge AI Triage**:
  * Clinical Referable DR Prevalence: $\approx 20\%$ (ICDR Levels 2, 3, 4).
  * Edge Sensitivity: $94\%$ ($\ge 90\%$ requirement).
  * Edge Specificity: $88\%$ ($\ge 85\%$ requirement).
  * Local Resolution: $\approx 75-80\%$ of patients (Grade 0/1) are diagnosed locally, requiring **zero** specialist doctor review.
* **Pillar 4 & 5 Ophthalmologist Review Dynamics**:
  * Number of doctors allocated at District Civil Hospital: $N_{\text{doc}} = 2$.
  * **Traditional Manual Reading**: $T_{\text{manual}} = 240\text{ s}$ ($4\text{ min}$) $\implies \mu_{\text{manual}} = \frac{2}{240} = 0.0083\text{ cases/sec}$.
  * **Proposed XAI Reading**: $T_{\text{xai}} = 25\text{ s}$ ($<30\text{ s}$) $\implies \mu_{\text{xai}} = \frac{2}{25} = 0.0800\text{ cases/sec}$.
  * **Queue Stability Condition**:
    * Baseline: $\lambda = 0.0185 > \mu_{\text{manual}} = 0.0083 \implies \rho = 2.22$ (**System unstable, queue blows up to infinity, massive backlog**).
    * Proposed: $\lambda_{\text{referable}} = 0.0046 \ll \mu_{\text{xai}} = 0.0800 \implies \rho = 0.058$ (**System stable, queue length $\approx 0$, $0$ backlog**).

---

## 2. File Manifest

| File | Description |
| :--- | :--- |
| `simulate_telemedicine_district.m` | High-precision Monte Carlo & Discrete-Event Simulation (DES) engine. Simulates all 50 PHCs, network transmission, edge gating, server queuing, and doctor review. |
| `build_simulink_telemed_model.m` | Programmatic Simulink model builder. Uses MATLAB Simulink APIs to construct, wire, and simulate `telemedicine_screening_model.slx`. |
| `telemedicine_screening_model.slx` | Interactive visual Simulink block diagram with Pulse Generators, Edge Gating Gains, Transport Delays, Integrators, and Scopes. |
| `run_capacity_analysis.m` | Master script that runs both the MATLAB DES and the Simulink model, outputs summary metrics, and generates publication plots. |
| `telemed_simulation_dashboard.png` | 4-panel dashboard showing Turnaround Time distribution, screening progress curves, review queue length over time, and resource savings. |
| `doctor_capacity_comparison.png` | Sensitivity analysis showing required ophthalmologist staffing vs. annual screening volume and network transmission latency vs. bandwidth. |

---

## 3. How to Run

In MATLAB or from the Windows command line:

### In MATLAB:
```matlab
run_capacity_analysis
```

### From Windows Terminal / PowerShell:
```powershell
matlab -batch "run_capacity_analysis"
```

---

## 4. Key Results & Differentiators for Hackathon Submission

| Metric | Traditional Telemedicine | Proposed SIH26038 XAI Architecture | Impact / Benefit |
| :--- | :--- | :--- | :--- |
| **Annual Patients Screened** | $100,000$ (Target) | $100,000+$ (Target) | Target fully met |
| **Edge-Filtered Cases** | $0$ ($0\%$) | $\approx 260-300$ ($70-75\%$) | Patients receive immediate reassurance on-site |
| **Cases Sent to Specialist** | $100\%$ ($400$/day) | $\approx 25\%$ ($100$/day) | **$75\%$ reduction in specialist burden** |
| **Doctor Review Time / Case** | $240\text{ sec}$ ($4.0\text{ min}$) | **$25\text{ sec}$** ($<30\text{ s}$) | Satisfies Pillar 4 human-in-the-loop requirement |
| **Total Doctor Hours / Day** | $24.6\text{ hours}$ | **$0.75\text{ hours}$** | **$97\%$ reduction in doctor workload** |
| **Doctor Utilization (2 Docs)** | $100\%$ (Overloaded) | **$5.4\%$** | Doctors have ample time for complex surgeries |
| **Unreviewed Backlog at 5 PM**| $>160\text{ cases}$ | **$0\text{ cases}$** | **Zero patient backlog at end of day** |
| **District Network Data / Day**| $14.4\text{ GB}$ | **$0.52\text{ GB}$** | **$96.4\%$ data savings**, ideal for rural 2G/3G |
| **Quality Gate Recaptures** | $0$ (Unusable cases lost) | $\approx 40$ recaptured on-site | Eliminates wasted hospital visits |
