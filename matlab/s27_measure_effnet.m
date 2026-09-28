%S27_MEASURE_EFFNET  Measure the EfficientNet-B0 grader and D2 on ITS OWN held-out split.
%
%   The live prototype grades with the teammate's EfficientNet-B0
%   (trainedNet_v3.mat, branch dr-grading-model). Its README quotes
%   sens 95.07% / spec 90.15% / AUC 0.972. The deck may only quote what a
%   script here measured (D13/D21), so this script re-derives them.
%
%   SPLIT. Our sealed ResNet split (grader_split.mat) cannot be used: the
%   EfficientNet was trained on a different 70% of APTOS, which overlaps it.
%   Instead the teammate's split is reproduced exactly - same csv order, same
%   rng(42), same two splitEachLabel calls - so the test set is the one the
%   EfficientNet has never seen. Their copy of the images was JPEG, ours is
%   the original PNG; the pixel content differs only by their compression.
%
%   Both evaluation paths are run on every test image:
%     ads    augmentedImageDatastore at 160, exactly as the teammate evaluated
%     live   imresize(raw,[160 160]), exactly as netraAnalyze / the web app do
%   so any gap between the quoted numbers and the live app is visible.
%
%   D2 on this split runs the lesion net at the images' NATIVE resolution
%   (the originals, not the 512 cache) - the open caveat from s16.
%
%   Writes results/effnet_metrics.csv, results/effnet_dual_evidence.csv,
%   and appends to results/deck_facts.txt.
here = fileparts(mfilename('fullpath'));
addpath(here, fullfile(here,'lib'), fullfile(here,'m1_quality'), ...
        fullfile(here,'m4_grade'), fullfile(here,'m6_vessels'));
CFG = s00_config();
logf = fullfile(CFG.resultDir,'s27_log.txt');
diary(logf); diary on; cleanupDiary = onCleanup(@() diary('off'));

E = load(fullfile(CFG.modelDir,'trainedNet_v3.mat'));
net = E.trainedNet;

% ---- reproduce the teammate's split exactly -----------------------------
labels = readtable(CFG.aptosCsv, 'TextType','char');
files  = fullfile(CFG.aptosImgDir, strcat(labels.id_code, '.png'));
imds   = imageDatastore(files, 'Labels', categorical(labels.diagnosis));
rng(42);
[imdsTrain, imdsRest] = splitEachLabel(imds, 0.7, 'randomized');
[imdsVal,   imdsTest] = splitEachLabel(imdsRest, 0.5, 'randomized');
fprintf('split: train %d | val %d | test %d\n', numel(imdsTrain.Files), ...
        numel(imdsVal.Files), numel(imdsTest.Files));
tc = countEachLabel(imdsTrain); disp(tc.Count');   % must read 1264 259 699 135 207

y = double(imdsTest.Labels) - 1;             % grades 0-4
n = numel(y);

% ---- path 1: the teammate's evaluation ----------------------------------
augTest = augmentedImageDatastore([160 160 3], imdsTest, 'ColorPreprocessing','gray2rgb');
Pads = minibatchpredict(net, augTest);

% ---- path 2: live path + lesion arm + D2 --------------------------------
S = load(fullfile(CFG.modelDir,'netra_lesion_net.mat')); segNet = S.net;
T = load(fullfile(CFG.modelDir,'thresholds.mat'));       thr = T.thr;

Plive = zeros(n,5); ruleG = zeros(n,1); dec = strings(n,1); nativeW = zeros(n,1);
t0 = tic;
for i = 1:n
    Iraw = imread(imdsTest.Files{i});
    if size(Iraw,3) == 1, Iraw = repmat(Iraw,1,1,3); end
    nativeW(i) = size(Iraw,2);
    p = double(gather(extractdata(predict(net, dlarray(single(imresize(Iraw,[160 160])),'SSCB')))));
    Plive(i,:) = p(:)';

    I0 = retinalCrop(Iraw);
    P  = slidingWindowPredict(segNet, applyClahe(I0), CFG);
    odMask = imdilate(P(:,:,5) >= thr(5), strel('disk',15));
    M = false(size(P));
    for c = 1:CFG.nChan
        Bc = bwareaopen(P(:,:,c) >= thr(c), CFG.minCompSize(c));
        if c == 3 || c == 4, Bc = Bc & ~odMask; end
        M(:,:,c) = Bc;
    end
    RG = ruleGradeICDR(M, retinalMask(I0));
    ruleG(i) = RG.grade;
    [~, gi] = max(Plive(i,:));
    D = dualEvidence(gi-1, Plive(i,:), RG, struct('referableFrom',2, ...
            'cnnReferable', sum(Plive(i,3:5)) >= 0.40));
    dec(i) = D.decision;
    if mod(i,25) == 0
        fprintf('  %d/%d  %.0f s\n', i, n, toc(t0));
    end
end

% ---- metrics -------------------------------------------------------------
refTrue = y >= 2;
rows = {};
for pathName = ["ads","live"]
    if pathName == "ads", Pm = Pads; else, Pm = Plive; end
    [~, gi] = max(Pm, [], 2); g = gi - 1;
    rp = sum(Pm(:,3:5), 2);
    ref = rp >= 0.40;
    TP = sum(ref & refTrue); FN = sum(~ref & refTrue);
    TN = sum(~ref & ~refTrue); FP = sum(ref & ~refTrue);
    sens = TP/(TP+FN); spec = TN/(TN+FP);
    auc = rocAuc(rp, refTrue);
    acc = mean(g == y);
    qwk = quadKappa(y, g);
    fprintf('[%s] n=%d  acc %.4f  QWK %.4f  referable@0.40 sens %.4f spec %.4f AUC %.4f\n', ...
            pathName, n, acc, qwk, sens, spec, auc);
    rows(end+1,:) = {char(pathName), n, acc, qwk, sens, spec, auc, TP, FN, TN, FP}; %#ok<AGROW>
end
Tm = cell2table(rows, 'VariableNames', ...
     {'Path','N','Accuracy','QWK','Sensitivity','Specificity','AUC','TP','FN','TN','FP'});
writetable(Tm, fullfile(CFG.resultDir,'effnet_metrics.csv'));

% ---- D2 on this split ----------------------------------------------------
refLive = sum(Plive(:,3:5),2) >= 0.40;
esc  = dec == "ESCALATE";
cnnMiss = refTrue & ~refLive;                       % referable, EfficientNet says not
missCaught = sum(cnnMiss & esc);
missAuto   = sum(cnnMiss & ~esc);                  % auto-reported as not referable
cnnErr = refTrue ~= refLive;
fprintf('D2: escalation rate %.1f%% | EfficientNet referable errors escalated %d/%d (%.1f%%)\n', ...
        100*mean(esc), sum(cnnErr & esc), sum(cnnErr), 100*sum(cnnErr & esc)/max(sum(cnnErr),1));
fprintf('D2: referable cases EfficientNet missed: %d | escalated %d | auto-cleared %d\n', ...
        sum(cnnMiss), missCaught, missAuto);
fprintf('native width: median %d px (min %d, max %d)\n', median(nativeW), min(nativeW), max(nativeW));

[~,nm,~] = cellfun(@fileparts, imdsTest.Files, 'UniformOutput', false);
writetable(table(string(nm), y, Plive, sum(Plive(:,3:5),2), ruleG, dec, nativeW, ...
    'VariableNames',{'Image','Truth','Prob','ReferableProb','RuleGrade','DualEvidence','NativeWidth'}), ...
    fullfile(CFG.resultDir,'effnet_dual_evidence.csv'));

% ---- deck facts (append; s14 owns the rest of the file) -----------------
L = Tm(Tm.Path=="live",:);
fid = fopen(fullfile(CFG.resultDir,'deck_facts.txt'),'a');
fprintf(fid, '\n# s27 - EfficientNet-B0 (trainedNet_v3), teammate split rng(42), n=%d, live preprocessing\n', n);
fprintf(fid, 'effnet_sensitivity = %.4f\n', L.Sensitivity);
fprintf(fid, 'effnet_specificity = %.4f\n', L.Specificity);
fprintf(fid, 'effnet_auc = %.4f\n', L.AUC);
fprintf(fid, 'effnet_accuracy_5class = %.4f\n', L.Accuracy);
fprintf(fid, 'effnet_qwk = %.4f\n', L.QWK);
fprintf(fid, 'effnet_d2_escalation_rate = %.4f\n', mean(esc));
fprintf(fid, 'effnet_d2_missed_referable = %d\n', sum(cnnMiss));
fprintf(fid, 'effnet_d2_missed_referable_auto_cleared = %d\n', missAuto);
fclose(fid);
fprintf('done in %.0f min\n', toc(t0)/60);

% -------------------------------------------------------------------------
function k = quadKappa(a, b)
K = 5; O = accumarray([a b]+1, 1, [K K]);
W = ((0:K-1)' - (0:K-1)).^2 / (K-1)^2;
E = sum(O,2) * sum(O,1) / sum(O(:));
k = 1 - sum(W(:).*O(:)) / sum(W(:).*E(:));
end
