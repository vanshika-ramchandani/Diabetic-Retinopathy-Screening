function s07_evaluate_test()
%S07_EVALUATE_TEST  Single pass over the 27 SEALED IDRiD test images.
%   Thresholds come from s06 (validation only). Nothing here is tuned.
%
%   Output follows the agreed metric spec:
%
%     Task                       Output                  Metrics
%     -------------------------  ----------------------  ----------------------------
%     Microaneurysm              Pixel mask              Dice, IoU, Precision, Recall, AUPR
%     Exudates (hard)            Pixel mask              same, reported per channel
%     Exudates (soft)            Pixel mask              same, reported per channel
%     Haemorrhage - mask         Pixel mask              same
%     Haemorrhage - derived flag Binary present/absent   Accuracy, Precision, Recall,
%                                                        Sensitivity/Specificity, ROC-AUC
%     Neovascularisation         -                       not trainable, no labels exist
addpath(fullfile(fileparts(mfilename('fullpath')),'lib'));
CFG = s00_config();
S = requireStage(fullfile(CFG.modelDir,'netra_lesion_net.mat'), 's05_train_seg (training)', 's05_train_seg'); net = S.net;
T = requireStage(fullfile(CFG.modelDir,'thresholds.mat'), 's06_tune_thresholds', 's06_tune_thresholds'); thr = T.thr;

maskChan  = [1 3 4 2];                                   % MA, EXhard, EXsoft, HE
maskLabel = ["Microaneurysm","Exudates (hard)","Exudates (soft)","Haemorrhage - mask"];
nC = CFG.nChan; nI = numel(CFG.testIds);

A  = cell(1,nC);
px = zeros(nC,4);                    % TP FP TN FN pooled over all test pixels
diceImg = nan(nI,nC);

regScore = []; regPred = []; regLabel = [];        % derived HE flag, 512px regions
imgScore = zeros(nI,1); imgPred = false(nI,1); imgLabel = false(nI,1);

if ~isfolder(CFG.resultDir), mkdir(CFG.resultDir); end
fprintf('evaluating %d held-out test images\n', nI);

for k = 1:nI
    id = CFG.testIds(k); t0 = tic;
    [I,M] = readIdridSample(CFG, id, "test");
    P = slidingWindowPredict(net, I, CFG);
    odMask = imdilate(P(:,:,5) >= thr(5), strel('disk',15));

    B = false(size(P));
    for c = 1:nC
        A{c} = prCurveAccum(A{c}, P(:,:,c), M(:,:,c));
        b = bwareaopen(P(:,:,c) >= thr(c), CFG.minCompSize(c));
        if c == 3 || c == 4, b = b & ~odMask; end     % the disc is not an exudate
        B(:,:,c) = b;

        g  = M(:,:,c);
        tp = nnz(b & g);  fp = nnz(b & ~g);
        fn = nnz(~b & g); tn = numel(g) - tp - fp - fn;
        px(c,:) = px(c,:) + [tp fp tn fn];
        if tp+fp+fn > 0, diceImg(k,c) = 2*tp/(2*tp+fp+fn); end
    end

    % ---- derived haemorrhage flag --------------------------------------
    % The flag is DERIVED FROM THE MASK (lesion area passes a minimum), which
    % is what makes it a derived flag rather than a second classifier.
    % ROC-AUC additionally uses the continuous score, so it needs no threshold.
    ps = CFG.patchSize;
    for r = 1:ps:size(I,1)-ps+1
        for c2 = 1:ps:size(I,2)-ps+1
            tile = P(r:r+ps-1, c2:c2+ps-1, 2);
            regScore(end+1,1) = mean(tile(:));                              %#ok<AGROW>
            regPred(end+1,1)  = nnz(B(r:r+ps-1, c2:c2+ps-1, 2)) >= 20;      %#ok<AGROW>
            regLabel(end+1,1) = any(M(r:r+ps-1, c2:c2+ps-1, 2), 'all');     %#ok<AGROW>
        end
    end
    imgScore(k) = mean(P(:,:,2), 'all');
    imgPred(k)  = nnz(B(:,:,2)) >= 50;
    imgLabel(k) = any(M(:,:,2), 'all');

    fprintf('  IDRiD_%02d  %.1fs\n', id, toc(t0));
end

ap = zeros(1,nC);
for c = 1:nC, ap(c) = prCurveFinish(A{c}); end

% =====================================================================
fprintf('\n');
fprintf('=================================================================================\n');
fprintf('  HELD-OUT TEST RESULTS - 27 IDRiD test images, never seen during training\n');
fprintf('=================================================================================\n\n');

% ---- pixel-mask tasks ----------------------------------------------
fprintf('%-22s %-12s %7s %7s %9s %7s %7s\n', ...
        'Task','Output','Dice','IoU','Precision','Recall','AUPR');
fprintf('%s\n', repmat('-',1,78));
rows = {};
for j = 1:numel(maskChan)
    c = maskChan(j);
    m = maskMetrics(px(c,:));
    fprintf('%-22s %-12s %7.4f %7.4f %9.4f %7.4f %7.4f\n', ...
            maskLabel(j),'Pixel mask', m.dice, m.iou, m.prec, m.rec, ap(c));
    rows(end+1,:) = {maskLabel(j),'Pixel mask',m.dice,m.iou,m.prec,m.rec,ap(c), ...
                     NaN,NaN,NaN,mean(diceImg(:,c),'omitnan'), ...
                     px(c,1),px(c,2),px(c,3),px(c,4)}; %#ok<AGROW>
end

% ---- derived binary flag -------------------------------------------
fprintf('\n%-22s %-22s %8s %9s %7s %7s %8s\n', ...
        'Task','Output','Accuracy','Precision','Recall','Spec','ROC-AUC');
fprintf('%s\n', repmat('-',1,86));

fr = flagMetrics(logical(regPred), logical(regLabel), regScore);
fi = flagMetrics(imgPred,          imgLabel,          imgScore);

fprintf('%-22s %-22s %8.4f %9.4f %7.4f %7.4f %8.4f\n', ...
    'Haemorrhage - flag','Binary (512px region)', fr.acc, fr.prec, fr.rec, fr.spec, fr.auc);
fprintf('%-22s %-22s %8.4f %9.4f %7.4f %7s %8s\n', ...
    'Haemorrhage - flag','Binary (whole image)', fi.acc, fi.prec, fi.rec, ...
    fmtNaN(fi.spec), fmtNaN(fi.auc));

rows(end+1,:) = {"Haemorrhage - flag","Binary (512px region)",NaN,NaN,fr.prec,fr.rec,NaN, ...
                 fr.acc,fr.spec,fr.auc,NaN,fr.tp,fr.fp,fr.tn,fr.fn};
rows(end+1,:) = {"Haemorrhage - flag","Binary (whole image)",NaN,NaN,fi.prec,fi.rec,NaN, ...
                 fi.acc,fi.spec,fi.auc,NaN,fi.tp,fi.fp,fi.tn,fi.fn};

% ---- neovascularisation --------------------------------------------
fprintf('\n%-22s %-22s %s\n', 'Neovascularisation','-', ...
        'not trainable - no labels exist in IDRiD or APTOS');
rows(end+1,:) = {"Neovascularisation","-",NaN,NaN,NaN,NaN,NaN,NaN,NaN,NaN,NaN,0,0,0,0};

if all(imgLabel)
    fprintf(['\nNOTE: all %d test images contain haemorrhage, so whole-image\n' ...
             '      SPECIFICITY and ROC-AUC are undefined (no negatives).\n' ...
             '      The 512px region row is the meaningful one.\n'], nI);
end

fprintf('\nAuxiliary (not a headline task) - Optic disc: Dice %.4f, AUPR %.4f\n', ...
        maskMetricsDice(px(5,:)), ap(5));

Tbl = cell2table(rows, VariableNames={'Task','Output','Dice','IoU','Precision','Recall', ...
    'AUPR','Accuracy','Specificity','ROC_AUC','MeanDicePerImage','TP','FP','TN','FN'});
writetable(Tbl, fullfile(CFG.resultDir,'metrics.csv'));
save(fullfile(CFG.resultDir,'test_metrics.mat'),'px','ap','diceImg', ...
     'regScore','regPred','regLabel','imgScore','imgPred','imgLabel','thr');
fprintf('\nwrote results/metrics.csv\n');
end

% =====================================================================
function m = maskMetrics(cm)
tp=cm(1); fp=cm(2); fn=cm(4);
m.prec = tp/max(tp+fp,1);
m.rec  = tp/max(tp+fn,1);
m.dice = 2*tp/max(2*tp+fp+fn,1);
m.iou  = tp/max(tp+fp+fn,1);
end

function d = maskMetricsDice(cm)
m = maskMetrics(cm); d = m.dice;
end

function f = flagMetrics(pred, label, score)
pred = logical(pred(:)); label = logical(label(:));
f.tp = nnz(pred & label);  f.fp = nnz(pred & ~label);
f.tn = nnz(~pred & ~label); f.fn = nnz(~pred & label);
f.acc  = (f.tp+f.tn)/max(numel(label),1);
f.prec = f.tp/max(f.tp+f.fp,1);
f.rec  = f.tp/max(f.tp+f.fn,1);
if f.tn+f.fp == 0, f.spec = NaN; else, f.spec = f.tn/(f.tn+f.fp); end
f.auc  = rocAuc(score, label);
end

function s = fmtNaN(v)
if isnan(v), s = 'undef'; else, s = sprintf('%.4f',v); end
end
