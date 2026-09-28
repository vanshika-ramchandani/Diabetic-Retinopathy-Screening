function s30_eval_lesion_v2()
%S30_EVAL_LESION_V2  Lesion net v1 (s05) vs v2 (s29), on data neither model trained on.
%
%   A. IDRiD official test set (27 images, all with DR) - pooled pixel Dice
%      per lesion channel, computed exactly as s07 does. Answers: did learning
%      healthy eyes cost lesion segmentation quality?
%   B. APTOS, the grader's SEALED test split (549 eyes: 270 grade 0, 56 grade
%      1, 223 grade 2+), native resolution, crop + CLAHE as at inference. v2
%      never saw these eyes (s28 drew negatives only from the grader's train
%      and val splits). Answers: how often is a healthy eye called referable,
%      and what does the dual-evidence check (D2) cost and catch?
%
%   PRE-REGISTERED DECISION (written before either model was evaluated here):
%   the app switches to v2 only if ALL of
%     1. healthy false-referral rate (lesion-rule grade >= 2 | truth 0) falls
%        by at least 25 percentage points versus v1;
%     2. no lesion channel's IDRiD pooled Dice falls by more than 0.05;
%     3. D2 silently auto-clears no referable eye the grader missed (stays 0).
%   Otherwise v1 stays and the result is reported as is.
%
%   Writes results/lesion_v2_eval.csv, results/lesion_v2_aptos.csv, and
%   appends to results/deck_facts.txt.
here = fileparts(mfilename('fullpath'));
addpath(here, fullfile(here,'lib'), fullfile(here,'m4_grade'));
CFG = s00_config();
logf = fullfile(CFG.resultDir,'s30_log.txt'); diary(logf); diary on; c0 = onCleanup(@() diary('off'));

V1 = load(fullfile(CFG.modelDir,'netra_lesion_net.mat'));    T1 = load(fullfile(CFG.modelDir,'thresholds.mat'));
V2 = load(fullfile(CFG.modelDir,'netra_lesion_net_v2.mat')); T2 = load(fullfile(CFG.modelDir,'thresholds_v2.mat'));
nets = {V1.net, V2.net}; thrs = {T1.thr, T2.thr}; names = ["v1","v2"];
fprintf('thresholds v1: %s\nthresholds v2: %s\n', num2str(T1.thr,'%.3f '), num2str(T2.thr,'%.3f '));

% ================= A. IDRiD sealed test ==================================
px = zeros(2, CFG.nChan, 3);                          % model x channel x [tp fp fn]
for k = 1:numel(CFG.testIds)
    [I,M] = readIdridSample(CFG, CFG.testIds(k), "test");
    for v = 1:2
        B = postprocess(slidingWindowPredict(nets{v}, I, CFG), thrs{v}, CFG);
        for c = 1:CFG.nChan
            b = B(:,:,c); g = M(:,:,c);
            px(v,c,:) = squeeze(px(v,c,:)) + [nnz(b&g); nnz(b&~g); nnz(~b&g)];
        end
    end
end
dice = 2*px(:,:,1) ./ max(2*px(:,:,1) + px(:,:,2) + px(:,:,3), 1);
fprintf('\nA. IDRiD test Dice      MA      HE      EX      SE      OD\n');
for v = 1:2, fprintf('   %s              %s\n', names(v), num2str(dice(v,:),'%7.4f ')); end

% ================= B. APTOS sealed grader test ===========================
S  = load(fullfile(CFG.modelDir,'grader_split.mat')); sp = S.split;
G  = load(fullfile(CFG.modelDir,'netra_grader.mat')); grader = G.net;
GM = load(fullfile(CFG.resultDir,'grader_metrics.mat')); gThr = GM.R.threshold;
test = find(sp.isTest(:));
y  = double(sp.y(test)) - 1; n = numel(test);
[~, ids] = cellfun(@fileparts, cellstr(sp.files(test)), 'UniformOutput', false); ids = string(ids);

rule = zeros(n,2); anyLes = false(n,2,4); dec = strings(n,2);
gGrade = zeros(n,1); gRef = false(n,1); gProb = zeros(n,5);
t0 = tic;
for i = 1:n
    % grader: the cached input it was measured on (s12), unchanged
    Ic = imread(fullfile(CFG.aptosCache, ids(i) + ".png"));
    X  = dlarray(single(normaliseInput(imresize(Ic,[CFG.graderSize CFG.graderSize]),CFG)),'SSCB');
    p  = double(gather(extractdata(predict(grader, X)))); p = p(:)';
    [~, gi] = max(p); gGrade(i) = gi-1; gProb(i,:) = p;
    gRef(i) = sum(p(CFG.referableFrom+1:end)) >= gThr;

    Iraw = imread(fullfile(CFG.aptosImgDir, ids(i) + ".png"));
    if size(Iraw,3) == 1, Iraw = repmat(Iraw,1,1,3); end
    I0 = retinalCrop(Iraw); Inet = applyClahe(I0); F = retinalMask(I0);
    for v = 1:2
        B = postprocess(slidingWindowPredict(nets{v}, Inet, CFG), thrs{v}, CFG);
        RG = ruleGradeICDR(B, F);
        rule(i,v) = RG.grade;
        anyLes(i,v,:) = reshape(squeeze(any(B(:,:,1:4),[1 2])), 1, 1, 4);
        D = dualEvidence(gGrade(i), p, RG, struct('referableFrom',CFG.referableFrom,'cnnReferable',gRef(i)));
        dec(i,v) = D.decision;
    end
    if mod(i,50) == 0, fprintf('  %d/%d  %.1f min\n', i, n, toc(t0)/60); end
end

healthy = y == 0; mild = y == 1; ref = y >= 2;
rows = {};
fprintf('\nB. APTOS sealed test (n=%d: %d healthy, %d mild, %d referable)\n', n, nnz(healthy), nnz(mild), nnz(ref));
for v = 1:2
    rr  = rule(:,v) >= 2; esc = dec(:,v) == "ESCALATE";
    fr  = mean(rr(healthy));
    lsens = mean(rr(ref)); lspec = mean(~rr(~ref));
    escRate = mean(esc);
    missed  = ref & ~gRef; silent = nnz(missed & ~esc);
    gErr    = ref ~= gRef; caught = nnz(gErr & esc) / max(nnz(gErr),1);
    anyH    = squeeze(mean(anyLes(healthy,v,:),1))';
    fprintf(['  %s  healthy called referable %5.1f%% | lesion-rule sens %.3f spec %.3f | ' ...
             'D2 escalation %5.1f%% | grader errors caught %5.1f%% | silent misses %d\n'], ...
            names(v), 100*fr, lsens, lspec, 100*escRate, 100*caught, silent);
    fprintf('      healthy eyes with any MA %4.1f%% HE %4.1f%% EX %4.1f%% SE %4.1f%%\n', 100*anyH);
    rows(end+1,:) = {char(names(v)), fr, lsens, lspec, escRate, caught, silent, nnz(missed), ...
                     anyH(1), anyH(2), anyH(3), anyH(4), dice(v,1), dice(v,2), dice(v,3), dice(v,4), dice(v,5)}; %#ok<AGROW>
end
Tt = cell2table(rows, 'VariableNames', {'Model','HealthyFalseReferral','LesionRuleSens','LesionRuleSpec', ...
    'D2EscalationRate','D2GraderErrorsCaught','D2SilentMisses','GraderMissedReferable', ...
    'HealthyAnyMA','HealthyAnyHE','HealthyAnyEX','HealthyAnySE', ...
    'IdridDiceMA','IdridDiceHE','IdridDiceEX','IdridDiceSE','IdridDiceOD'});
writetable(Tt, fullfile(CFG.resultDir,'lesion_v2_eval.csv'));
writetable(table(ids, y, gGrade, gRef, rule(:,1), rule(:,2), dec(:,1), dec(:,2), ...
    'VariableNames',{'Image','Truth','GraderGrade','GraderReferable','RuleV1','RuleV2','D2V1','D2V2'}), ...
    fullfile(CFG.resultDir,'lesion_v2_aptos.csv'));

% ================= pre-registered decision ===============================
c1 = Tt.HealthyFalseReferral(1) - Tt.HealthyFalseReferral(2) >= 0.25;
c2 = all(dice(1,1:4) - dice(2,1:4) <= 0.05);
c3 = Tt.D2SilentMisses(2) == 0;
adopt = c1 && c2 && c3;
fprintf('\nDECISION: false-referral drop >=25pts %d | Dice drop <=0.05 all channels %d | silent misses 0 %d  ->  %s\n', ...
        c1, c2, c3, ternary(adopt, 'ADOPT v2', 'KEEP v1'));

fid = fopen(fullfile(CFG.resultDir,'deck_facts.txt'),'a');
fprintf(fid, '\n[lesion_v2]  # s28-s30: v1 fine-tuned with healthy APTOS negatives; APTOS grader test n=%d, native res\n', n);
for v = 1:2
    s = names(v);
    fprintf(fid, 'lesion_%s.healthy_false_referral = %.4f\n', s, Tt.HealthyFalseReferral(v));
    fprintf(fid, 'lesion_%s.d2_escalation_rate = %.4f\n', s, Tt.D2EscalationRate(v));
    fprintf(fid, 'lesion_%s.d2_silent_misses = %d\n', s, Tt.D2SilentMisses(v));
    fprintf(fid, 'lesion_%s.d2_grader_errors_caught = %.4f\n', s, Tt.D2GraderErrorsCaught(v));
    fprintf(fid, 'lesion_%s.idrid_dice = %s  # MA HE EX SE OD\n', s, num2str(dice(v,:),'%.4f '));
end
fprintf(fid, 'lesion_v2.adopted = %s\n', ternary(adopt,'true','false'));
fclose(fid);
save(fullfile(CFG.resultDir,'lesion_v2_eval.mat'),'Tt','dice','rule','dec','y','ids','gRef','gGrade','adopt');
end

% -------------------------------------------------------------------------
function B = postprocess(P, thr, CFG)
od = imdilate(P(:,:,5) >= thr(5), strel('disk',15));
B = false(size(P));
for c = 1:CFG.nChan
    b = bwareaopen(P(:,:,c) >= thr(c), CFG.minCompSize(c));
    if c == 3 || c == 4, b = b & ~od; end
    B(:,:,c) = b;
end
end

function s = ternary(c, a, b)
if c, s = a; else, s = b; end
end
