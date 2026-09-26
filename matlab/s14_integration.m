function s14_integration()
%S14_INTEGRATION  End-to-end run of the full NETRA pipeline, and deck facts.
%
%   Runs netraScreen on the 27 sealed IDRiD test images - the only images for
%   which pixel-level lesion ground truth exists - so that every stage from
%   the quality gate to the dual-evidence verdict is exercised on real data
%   in one pass. The measured quality-gate, referral and escalation rates
%   then drive the district model.
%
%   Writes results/deck_facts.txt: every number the presentation is allowed
%   to use, each traceable to the script that produced it. If a figure is not
%   in that file, it was not measured, and it does not go on a slide.
here = fileparts(mfilename('fullpath'));
addpath(here, fullfile(here,'lib'), fullfile(here,'m1_quality'), ...
        fullfile(here,'m2_enhance'), fullfile(here,'m4_grade'), ...
        fullfile(here,'m5_simulink'));
CFG = s00_config(); rng(CFG.seed);

testDir = fullfile(CFG.segRoot,'1. Original Images','b. Testing Set');
d = dir(fullfile(testDir,'IDRiD_*.jpg'));
if isempty(d), error('no IDRiD test images in %s', testDir); end
fprintf('integration run over %d IDRiD test images\n\n', numel(d));

n = numel(d);
qDec  = strings(n,1); qScore = zeros(n,1);
ruleG = zeros(n,1);   cnnG   = zeros(n,1);
dual  = strings(n,1); agree  = false(n,1);
refer = false(n,1);   secs   = zeros(n,1);
haveCnn = false;

for i = 1:n
    p = fullfile(d(i).folder, d(i).name);
    R = netraScreen(p, struct('verbose',false,'gradcam',false));
    qDec(i)   = R.quality.decision;
    qScore(i) = R.quality.score;
    secs(i)   = R.elapsed;
    if R.decisionPath == "REJECTED_AT_QUALITY_GATE"
        ruleG(i) = NaN; cnnG(i) = NaN; dual(i) = "REJECTED"; refer(i) = false;
    else
        ruleG(i) = R.ruleGrade.grade;
        if R.cnnGrade.available
            haveCnn = true;
            cnnG(i)  = R.cnnGrade.grade;
            dual(i)  = R.dual.decision;
            agree(i) = R.dual.agree;
        else
            cnnG(i) = NaN; dual(i) = "NO_CNN";
        end
        refer(i) = logical(R.referable);
    end
    fprintf('  %-12s q=%-8s %3d/100  rule=%s cnn=%s  %-12s  %.1fs\n', ...
        d(i).name, qDec(i), qScore(i), num2str(ruleG(i)), num2str(cnnG(i)), dual(i), secs(i));
end

nRej = nnz(qDec == "REJECT");
nGrd = n - nRej;
rateReject = nRej / n;
rateEscal  = 0; rateAgree = NaN;
if haveCnn && nGrd > 0
    ok = qDec ~= "REJECT";
    rateEscal = mean(dual(ok) == "ESCALATE");
    rateAgree = mean(agree(ok));
end

fprintf('\n---------------- integration summary ----------------\n');
fprintf(' images                 %d\n', n);
fprintf(' quality PASS/ENH/REJ   %d / %d / %d\n', ...
        nnz(qDec=="PASS"), nnz(qDec=="ENHANCE"), nRej);
fprintf(' mean quality score     %.1f/100\n', mean(qScore));
fprintf(' mean end-to-end time   %.1f s\n', mean(secs));
if haveCnn
    fprintf(' dual-evidence agree    %.1f%%\n', 100*rateAgree);
    fprintf(' escalation rate        %.1f%%\n', 100*rateEscal);
end
fprintf(' referable (final)      %d / %d\n', nnz(refer), n);
fprintf('-----------------------------------------------------\n\n');

% ---- referral rate: prefer the large APTOS test split ------------------
gm = fullfile(CFG.resultDir,'grader_metrics.mat');
if isfile(gm)
    Gm = load(gm);
    rateRefer = mean(Gm.sTst >= Gm.R.threshold);
else
    Gm = [];
    rateRefer = mean(refer);
end

% ---- in-domain D2 measurement, if s16 has run ---------------------------
DE = [];
f16 = fullfile(CFG.resultDir,'dual_evidence_aptos.mat');
if isfile(f16), Q = load(f16); DE = Q.R; end

% ---- what drives the district model -------------------------------------
% The GRADER's own triage rate is used, not the fused referable-or-escalated
% union. Reason: the lesion arm is trained at IDRiD native resolution, and the
% cached APTOS images are 512px - outside its regime, where it invents lesions
% and over-calls grade 2 (84% fused referable against a 41% ground-truth rate).
% Reporting a district saving driven by that artifact would be indefensible.
% The dual-evidence review load is reported separately, flagged unvalidated.
rates = struct('referable',rateRefer,'escalated',rateEscal,'rejected',rateReject, ...
               'flaggedDirect',rateRefer);
D = districtSim(rates);
fprintf('district model: %s\n', D.summary);
fprintf('break-even flagged fraction %.3f | actual %.3f | stable %d\n\n', ...
        D.breakEvenFlagged, D.flaggedFraction, D.stable);

% ---- Simulink backlog model, driven by the same rates -------------------
SL = struct();
try
    [~, SL] = buildNetraSimulink(rates, true);
catch ME
    fprintf('Simulink model did not build: %s\n', ME.message);
end

% ================= deck facts ===========================================
F = fullfile(CFG.resultDir,'deck_facts.txt');
fid = fopen(F,'w');
w = @(varargin) fprintf(fid, varargin{:});
w('# NETRA - measured facts for the SIH deck\n');
w('# generated %s by s14_integration\n', datestr(now,'yyyy-mm-dd HH:MM'));
w('# Every number below came from a script in matlab/. Nothing here is estimated.\n');
w('# If a figure is not in this file it was not measured - do not put it on a slide.\n\n');

w('[lesion_segmentation]  # s07_evaluate_test, 27 sealed IDRiD test images\n');
mc = fullfile(CFG.resultDir,'metrics.csv');
if isfile(mc)
    M = readtable(mc, TextType='string');
    for i = 1:height(M)
        if ~isnan(M.Dice(i))
            w('dice.%s = %.4f\n', slug(M.Task(i)), M.Dice(i));
        end
    end
    k = find(M.Task == "Haemorrhage - flag" & M.Output == "Binary (512px region)", 1);
    if ~isempty(k)
        w('haem_region.accuracy = %.4f\n', M.Accuracy(k));
        w('haem_region.recall = %.4f\n', M.Recall(k));
        w('haem_region.specificity = %.4f\n', M.Specificity(k));
        w('haem_region.roc_auc = %.4f\n', M.ROC_AUC(k));
    end
end
w('lesion.train_images = 44\nlesion.val_images = 10\nlesion.test_images = 27\n');
w('lesion.nv_trainable = false  # no pixel-level NV labels exist in IDRiD or APTOS\n\n');

w('[localisation]  # s17_localise, 103 sealed IDRiD "C. Localization" test images\n');
lf = fullfile(CFG.resultDir,'localisation.mat');
if isfile(lf)
    LC = load(lf); L = LC.L;
    w('# Distances are in ORIGINAL image pixels. "DD" = optic-disc diameters,\n');
    w('# against a reference diameter measured from GT masks, not assumed.\n');
    w('loc.n_test = %d\n', L.n);
    w('loc.ref_od_diameter_px = %.1f  # median of %d segmentation-train GT masks\n', ...
      L.refDia, L.refDiaN);
    w('loc.fit_images = %d  # localisation TRAIN split, disjoint from the above\n', L.fitN);
    w('loc.laterality_rule_agreement = %.4f  # field-centroid rule vs GT, on train\n', L.sideAgree);
    w('od.mean_px = %.1f\n',   L.od.meanPx);
    w('od.median_px = %.1f\n', L.od.medianPx);
    w('od.median_dd = %.4f\n', L.od.medianDD);
    w('od.within_0p5dd = %.4f  # 1 optic-disc radius - the usual criterion\n', L.od.hit(2));
    w('od.within_1dd = %.4f\n', L.od.hit(3));
    w('od.detector_fallback_rate = %.4f\n', L.odFallback);
    w('fovea.mean_px = %.1f\n',   L.fovea.meanPx);
    w('fovea.median_px = %.1f\n', L.fovea.medianPx);
    w('fovea.median_dd = %.4f\n', L.fovea.medianDD);
    w('fovea.within_0p5dd = %.4f\n', L.fovea.hit(2));
    w('fovea.within_1dd = %.4f\n',   L.fovea.hit(3));
    w('fovea.offset_dd = %.3f  # measured temporal offset, not assumed\n', L.prm.dxDD);
    % Reported separately so disc-detector error and prior error can be told
    % apart. The predicted-disc row above is the deployable number.
    w('fovea_given_gt_disc.median_px = %.1f\n',   L.foveaGtOd.medianPx);
    w('fovea_given_gt_disc.within_0p5dd = %.4f\n', L.foveaGtOd.hit(2));
else
    w('# not measured - run s17_localise\n');
end
w('\n');

w('[vessel_segmentation]  # s21/s22, 20 sealed DRIVE test images\n');
vf = fullfile(CFG.resultDir,'vessel_metrics.mat');
sf = fullfile(CFG.resultDir,'vessel_semantic_metrics.mat');
if isfile(vf) && isfile(sf)
    VM = load(vf); SM = load(sf);
    w('# Every figure is computed INSIDE the field of view. DRIVE ships no FOV\n');
    w('# masks in this copy, so they are derived by retinalMask; the field is\n');
    w('# 68.5%% of the frame, so scoring the whole rectangle would hand the\n');
    w('# model ~34.5%% of its true negatives for free.\n');
    w('vessel.n_test = 20  # DRIVE 01-20, the official test set\n');
    w('vessel.fit_images = 16\nvessel.val_images = 4\n');
    w('vessel.threshold = %.2f  # tuned on val, frozen before the test set was opened\n', SM.thr);
    w('# Per-image means over the 20 test images (s21).\n');
    w('vessel.dice = %.4f\n',        VM.mu(5));
    w('vessel.iou = %.4f\n',         VM.mu(6));
    w('vessel.sensitivity = %.4f\n', VM.mu(1));
    w('vessel.specificity = %.4f\n', VM.mu(2));
    w('vessel.precision = %.4f\n',   VM.mu(3));
    w('vessel.accuracy = %.4f\n',    VM.mu(4));
    w('vessel.roc_auc = %.4f\n',     VM.mu(8));
    w('# MATLAB evaluateSemanticSegmentation (s22), pixel-pooled across all 20\n');
    w('# images, so it differs slightly from the per-image means above.\n');
    w('vessel.global_accuracy = %.4f\n', SM.Sum.GlobalAccuracy);
    w('vessel.mean_accuracy = %.4f\n',   SM.Sum.MeanAccuracy);
    w('vessel.mean_iou = %.4f  # AVERAGED WITH BACKGROUND - not a vessel score\n', SM.Sum.MeanIoU);
    w('vessel.weighted_iou = %.4f  # frequency-weighted, almost entirely background\n', SM.Sum.WeightedIoU);
    w('vessel.mean_bfscore = %.4f  # tolerance 6.1 px = 0.75%% of the diagonal\n', SM.Sum.MeanBFScore);
    w('vessel.mean_bfscore_2px = %.4f  # strict 2 px tolerance\n', SM.Sum.MeanBFScore_2px);
    w('vessel.recall_pooled = %.4f\n',    SM.Sum.Recall);
    w('vessel.precision_pooled = %.4f\n', SM.Sum.Precision);
    w('vessel.iou_pooled = %.4f  # THE honest vessel number\n', SM.Sum.IoU);
    w('vessel.av_classification = false  # DRIVE carries no artery/vein labels\n');
    w('vessel.calibre_measured = false   # so the 4-2-1 beading and IRMA arms stay open\n');
else
    w('# not measured - run s21_eval_vessels then s22_vessel_semantic_metrics\n');
end
w('\n');

w('[dr_grader]  # s11/s12, sealed APTOS test split\n');
if ~isempty(Gm)
    R = Gm.R;
    w('grader.n_test = %d\n', R.nTest);
    w('grader.sensitivity = %.4f\n', R.sensitivity);
    w('grader.specificity = %.4f\n', R.specificity);
    w('grader.precision = %.4f\n', R.precision);
    w('grader.accuracy_referable = %.4f\n', R.accuracy);
    w('grader.roc_auc = %.4f\n', R.rocAuc);
    w('grader.threshold = %.4f  # chosen on VALIDATION at sens >= %.2f\n', R.threshold, CFG.sensTarget);
    w('grader.grade5_accuracy = %.4f\n', R.grade5Acc);
    w('grader.qwk = %.4f\n', R.qwk);
    w('grader.meets_ps_requirement = %s  # sens>0.90 and spec>0.85\n', string(R.meetsRequirement));
else
    w('# grader not yet evaluated - run s11_train_grader then s12_eval_grader\n');
end
w('\n');

w('[quality_gate]  # s13_calibrate_quality + this run\n');
qt = fullfile(CFG.modelDir,'quality_thresholds.mat');
if isfile(qt)
    Q = load(qt);
    w('quality.calibration_n = %d\n', Q.thr.nCalib);
    w('quality.calibration_source = %s\n', Q.thr.source);
    w('quality.percentiles = %s\n', Q.thr.percentiles);
    if isfield(Q.thr,'actualReject')
        w('quality.actual_reject = %.4f\n', Q.thr.actualReject);
        w('quality.target_reject = %.4f\n', Q.thr.targetReject);
        w('quality.shared_percentile = %.4f\n', Q.thr.sharedPct);
    end
end
w('quality.idrid_pass = %d\nquality.idrid_enhance = %d\nquality.idrid_reject = %d\n', ...
  nnz(qDec=="PASS"), nnz(qDec=="ENHANCE"), nRej);
w('quality.idrid_mean_score = %.1f\n\n', mean(qScore));

w('[dual_evidence]\n');
if haveCnn
    w('# measured on %d IDRiD images at NATIVE resolution (the lesion net''s trained regime),\n', nGrd);
    w('# but IDRiD is 100%% diseased, so this is not a screening-population rate.\n');
    w('dual.idrid_agreement_rate = %.4f\n', rateAgree);
    w('dual.idrid_escalation_rate = %.4f\n', rateEscal);
    w('dual.idrid_n = %d\n', nGrd);
end
if ~isempty(DE)
    w('# measured on the %d-image sealed APTOS split - representative class mix,\n', DE.n);
    w('# BUT those images are cached at 512px, outside the lesion net''s native-resolution\n');
    w('# regime, where it over-calls. Treat the escalation COST here as an upper bound.\n');
    w('d2.aptos_n = %d\n', DE.n);
    w('d2.aptos_escalation_rate = %.4f  # inflated by the resolution mismatch\n', DE.escalationRate);
    w('d2.cnn_referable_errors = %d\n', DE.cnnErrors);
    w('d2.errors_escalated = %d\n', DE.errorsCaught);
    w('d2.catch_rate = %.4f  # THE safety number: CNN errors D2 caught\n', DE.catchRate);
    w('d2.cnn_missed_referable = %d\n', DE.cnnMissed);
    w('d2.silently_missed_after_d2 = %d  # referable cases auto-reported as normal\n', DE.missedAfterD2);
    w('d2.cost_validated_at_deployment_resolution = false\n');
end
w('\n');

w('[pipeline]\n');
w('pipeline.mean_seconds_per_image = %.2f\n', mean(secs));
w('pipeline.integration_images = %d\n\n', n);

w('[district_model]  # districtSim, driven by the rates above\n');
w('district.patients_per_year = %d\n', D.assumptions.patientsPerYear);
w('district.rate_referable = %.4f\n', rates.referable);
w('district.rate_escalated = %.4f\n', rates.escalated);
w('district.rate_rejected = %.4f\n', rates.rejected);
w('district.manual_reviewed = %.0f\n', D.manual.reviewed);
w('district.netra_reviewed = %.0f\n', D.netra.reviewed);
w('district.manual_experts = %.2f\n', D.manual.experts);
w('district.netra_experts = %.2f\n', D.netra.experts);
w('district.manual_gb_per_day = %.2f\n', D.manual.gbPerDay);
w('district.netra_gb_per_day = %.2f\n', D.netra.gbPerDay);
w('district.bandwidth_cut = %.4f\n', D.bandwidthCut);
w('district.workload_cut = %.4f\n', D.workloadCut);
w('district.expert_min_per_day = %.1f\n', D.expertMinPerDay);
w('district.flagged_fraction = %.4f  # grader triage rate, the validated one\n', D.flaggedFraction);
w('district.break_even_flagged = %.4f  # depends only on arrivals/reading time/hours\n', D.breakEvenFlagged);
w('district.headroom = %.4f\n', D.headroom);
w('district.netra_stable = %s\n', string(D.stable));
w('district.manual_stable = %s\n', string(D.manualStable));
w('district.summary = %s\n\n', D.summary);

w('[simulink_model]  # buildNetraSimulink - core Simulink, NOT SimEvents\n');
w('# SimEvents is licensed here but not installed (no toolbox/simevents on disk),\n');
w('# so the queue is modelled with core Simulink blocks that do open on this machine.\n');
if isfield(SL,'demandManual')
    w('sl.arrivals_per_day = %.0f\n', SL.arrivalsPerDay);
    w('sl.flagged_fraction = %.4f\n', SL.pFlagged);
    w('sl.demand_manual_sec_day = %.0f\n', SL.demandManual);
    w('sl.demand_netra_sec_day = %.0f\n', SL.demandNetra);
    w('sl.capacity_sec_day = %.0f\n', SL.capacity);
    w('sl.manual_stable = %s\n', string(SL.stableManual));
    w('sl.netra_stable = %s\n', string(SL.stableNetra));
    if isfield(SL,'finalManualDays')
        w('sl.backlog_manual_expert_days = %.0f\n', SL.finalManualDays);
        w('sl.backlog_netra_expert_days = %.0f\n', SL.finalNetraDays);
    end
else
    w('# model did not build in this run\n');
end
w('\n');

w('[epidemiology]  # published sources, cited on the slide\n');
w('epi.diabetics_india = 101000000  # ICMR-INDIAB, Lancet Diab Endo 2023\n');
w('epi.dr_prevalence = 0.169        # ICMR-INDIAB\n');
w('epi.preventable = 0.90           # NPCBVI / WHO\n\n');

w('[build_status]  # true state, not aspirational\n');
w('status.quality_gate = built+calibrated\n');
w('status.enhancement = built\n');
w('status.lesion_segmentation = trained+evaluated\n');
w('status.dr_grader = %s\n', ternary(~isempty(Gm),"trained+evaluated","not trained"));
w('status.gradcam = built\n');
w('status.dual_evidence = built+measured\n');
w('status.gui = built\n');
w('status.simulink = built + simulated (core Simulink)\n');
w('status.simevents = licensed but NOT installed on this machine\n');
w('status.vessel_segmentation = trained+evaluated (DRIVE, binary tree only)\n');
w('status.neovascularisation = not built - no labels exist\n');
fclose(fid);
fprintf('wrote %s\n', F);

T = table(string({d.name}'), qDec, qScore, ruleG, cnnG, dual, refer, secs, ...
    'VariableNames',{'Image','Quality','Score','RuleGrade','CnnGrade','DualEvidence','Referable','Seconds'});
writetable(T, fullfile(CFG.resultDir,'integration_run.csv'));
fprintf('wrote results/integration_run.csv\n');
end

function s = slug(x)
s = lower(regexprep(char(x), '[^A-Za-z0-9]+', '_'));
s = regexprep(s,'^_|_$','');
end

function o = ternary(c,a,b)
if c, o = a; else, o = b; end
end
