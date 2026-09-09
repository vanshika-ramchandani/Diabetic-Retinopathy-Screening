function s12_eval_grader()
%S12_EVAL_GRADER  Open the sealed grader test split, once.
%
%   Produces the numbers the problem statement actually asks for: sensitivity
%   and specificity for REFERABLE DR (ICDR level 2+), at an operating point
%   chosen on VALIDATION to meet sensitivity >= 0.90 - the protocol Gulshan
%   2016 and the IDx-DR pivotal trial both use.
%
%   The threshold is fitted on validation and then applied unchanged to test.
%   Choosing it on test would report the best number the test set can give,
%   which is not a held-out result at all.
here = fileparts(mfilename('fullpath'));
addpath(here, fullfile(here,'lib'));
CFG = s00_config(); rng(CFG.seed);

S  = requireStage(fullfile(CFG.modelDir,'netra_grader.mat'), ...
        's11_train_grader', 's11_train_grader');
Sp = requireStage(fullfile(CFG.modelDir,'grader_split.mat'), ...
        's11_train_grader', 's11_train_grader');
net = S.net; split = Sp.split;

yAll = double(split.y) - 1;

fprintf('scoring validation (%d) and sealed test (%d)\n', nnz(split.isVal), nnz(split.isTest));
pVal = scoreSet(net, split.files(split.isVal),  CFG);
pTst = scoreSet(net, split.files(split.isTest), CFG);
yVal = yAll(split.isVal);
yTst = yAll(split.isTest);

% ================= 5-class grading =======================================
[~,ix] = max(pTst,[],2); predTst = ix - 1;
acc  = mean(predTst == yTst);
kap  = qwk(yTst, predTst, 5);
fprintf('\n5-class ICDR grading  |  accuracy %.4f  QWK %.4f\n', acc, kap);

C = accumarray([yTst+1, predTst+1], 1, [5 5]);
fprintf('\nconfusion (rows = true 0-4, cols = predicted)\n');
disp(C);

% ================= referable DR (level 2+) ===============================
refVal = yVal >= CFG.referableFrom;
refTst = yTst >= CFG.referableFrom;
sVal = sum(pVal(:, CFG.referableFrom+1:end), 2);   % P(grade >= 2)
sTst = sum(pTst(:, CFG.referableFrom+1:end), 2);

% --- operating point: on VAL, the threshold meeting the sensitivity bar ---
ths = linspace(0,1,1001);
bestTh = 0; bestSpec = -1;
for t = ths
    d = sVal >= t;
    se = mean(d(refVal)); sp = mean(~d(~refVal));
    if se >= CFG.sensTarget && sp > bestSpec, bestSpec = sp; bestTh = t; end
end
seVal = mean(sVal(refVal) >= bestTh); spVal = mean(sVal(~refVal) < bestTh);
fprintf('\noperating point from VALIDATION: threshold %.3f -> sens %.4f spec %.4f\n', ...
        bestTh, seVal, spVal);

d   = sTst >= bestTh;
TP  = nnz(d & refTst);   FP = nnz(d & ~refTst);
TN  = nnz(~d & ~refTst); FN = nnz(~d & refTst);
sens = TP/max(TP+FN,1);  spec = TN/max(TN+FP,1);
prec = TP/max(TP+FP,1);  accR = (TP+TN)/numel(refTst);
auc  = rocAuc(sTst, refTst);

fprintf('\n=====================================================================\n');
fprintf('  REFERABLE DR (ICDR 2+) - SEALED TEST, n = %d\n', numel(refTst));
fprintf('=====================================================================\n');
fprintf('  Sensitivity  %.4f      (requirement > 0.90)\n', sens);
fprintf('  Specificity  %.4f      (requirement > 0.85)\n', spec);
fprintf('  Precision    %.4f\n', prec);
fprintf('  Accuracy     %.4f\n', accR);
fprintf('  ROC-AUC      %.4f\n', auc);
fprintf('  TP %d  FP %d  TN %d  FN %d\n', TP, FP, TN, FN);
fprintf('  positives %d / %d (%.1f%%)\n', nnz(refTst), numel(refTst), 100*mean(refTst));
meets = sens > 0.90 && spec > 0.85;
fprintf('  PS 26038 requirement met: %s\n', string(meets));
fprintf('=====================================================================\n');

R = struct('nTest',numel(refTst),'threshold',bestTh, ...
   'sensitivity',sens,'specificity',spec,'precision',prec,'accuracy',accR, ...
   'rocAuc',auc,'TP',TP,'FP',FP,'TN',TN,'FN',FN, ...
   'valSens',seVal,'valSpec',spVal,'grade5Acc',acc,'qwk',kap, ...
   'confusion',C,'meetsRequirement',meets);
if ~isfolder(CFG.resultDir), mkdir(CFG.resultDir); end
save(fullfile(CFG.resultDir,'grader_metrics.mat'),'R','sTst','refTst','sVal','refVal','-v7');

t = table("Referable DR (ICDR 2+)", numel(refTst), bestTh, sens, spec, prec, accR, auc, TP, FP, TN, FN, ...
    'VariableNames', {'Task','N','Threshold','Sensitivity','Specificity', ...
                      'Precision','Accuracy','ROC_AUC','TP','FP','TN','FN'});
writetable(t, fullfile(CFG.resultDir,'grader_metrics.csv'));
fprintf('wrote results/grader_metrics.csv\n');

makeFigures(sTst, refTst, C, acc, kap, sens, spec, auc, CFG);
gradCamFigure(net, split, yAll, CFG);
end

% =========================================================================
function P = scoreSet(net, files, CFG)
imds = imageDatastore(files);
ds   = transform(imds, @(I) {normaliseInput(imresize(I,[CFG.graderSize CFG.graderSize]), CFG)}, ...
                 IncludeInfo=false);
P = double(minibatchpredict(net, ds, MiniBatchSize=CFG.graderBatch, ExecutionEnvironment="gpu"));
end

function k = qwk(a, b, nc)
%QWK  Quadratic weighted kappa - the metric APTOS is actually scored on.
O = accumarray([a(:)+1, b(:)+1], 1, [nc nc]);
W = (repmat(0:nc-1,nc,1) - repmat((0:nc-1)',1,nc)).^2 / (nc-1)^2;
E = accumarray(a(:)+1,1,[nc 1]) * accumarray(b(:)+1,1,[nc 1])';
E = E / sum(E(:)) * sum(O(:));
k = 1 - sum(W(:).*O(:)) / max(sum(W(:).*E(:)), eps);
end

function makeFigures(s, ref, C, acc, kap, sens, spec, auc, CFG)
figDir = fullfile(CFG.root,'figures');
if ~isfolder(figDir), mkdir(figDir); end
teal = [0.055 0.486 0.525]; crim = [0.757 0.153 0.176];

ths = linspace(1,0,500); tpr = zeros(size(ths)); fpr = zeros(size(ths));
for i = 1:numel(ths)
    d = s >= ths(i);
    tpr(i) = mean(d(ref)); fpr(i) = mean(d(~ref));
end
f = lightFigure('Position',[100 100 560 520]);
plot(fpr,tpr,'-','Color',teal,'LineWidth',2.5); hold on;
plot([0 1],[0 1],'--','Color',[0.6 0.6 0.6]);
plot(1-spec, sens, 'o', 'MarkerSize',11, 'MarkerFaceColor',crim, ...
     'MarkerEdgeColor','w','LineWidth',1.5);
text(min(1-spec+0.04,0.55), max(sens-0.08,0.1), ...
     sprintf('operating point\nsens %.3f / spec %.3f', sens, spec), ...
     'FontSize',10, 'Color',crim);
xlabel('1 - specificity'); ylabel('sensitivity');
title(sprintf('Referable DR (ICDR 2+) - held-out test\nROC-AUC = %.4f', auc));
grid on; axis square; xlim([0 1]); ylim([0 1]);
lightAxes(f); exportgraphics(f, fullfile(figDir,'grader_roc.png'), 'Resolution',150); close(f);

f = lightFigure('Position',[100 100 560 520]);
imagesc(C); colormap(flipud(gray)); axis square; hold on;
mx = max(C(:));
for i = 1:5
    for j = 1:5
        if C(i,j) > 0
            if C(i,j) > mx/2, col = 'w'; else, col = 'k'; end
            text(j,i,sprintf('%d',C(i,j)),'HorizontalAlignment','center', ...
                 'Color',col,'FontWeight','bold');
        end
    end
end
set(gca,'XTick',1:5,'XTickLabel',0:4,'YTick',1:5,'YTickLabel',0:4);
xlabel('predicted ICDR grade'); ylabel('true ICDR grade');
title(sprintf('5-class grading - accuracy %.3f, QWK %.3f', acc, kap));
lightAxes(f); exportgraphics(f, fullfile(figDir,'grader_confusion.png'), 'Resolution',150); close(f);
fprintf('wrote figures/grader_roc.png and figures/grader_confusion.png\n');
end

function gradCamFigure(net, split, yAll, CFG)
%GRADCAMFIGURE  Explainability panel on real held-out test images.
figDir = fullfile(CFG.root,'figures');
idx = find(split.isTest);
yT  = yAll(idx);
pick = [];
for g = [4 3 2 0]                      % the severe end, plus a normal
    k = find(yT == g, 1);
    if ~isempty(k), pick(end+1) = idx(k); end %#ok<AGROW>
end
pick = pick(1:min(4,numel(pick)));
if isempty(pick), fprintf('no test images available for Grad-CAM\n'); return; end

f = lightFigure('Position',[100 100 300*numel(pick) 620]);
for i = 1:numel(pick)
    I  = imread(split.files(pick(i)));
    Ir = imresize(I,[CFG.graderSize CFG.graderSize]);
    X  = dlarray(single(normaliseInput(Ir,CFG)),'SSCB');
    sc = double(extractdata(predict(net,X)));
    [~,pg] = max(sc); pg = pg-1;
    try
        M = rescale(extractdata(gradCAM(net, X, pg+1)));
    catch ME
        fprintf('gradCAM failed: %s\n', ME.message);
        M = zeros(CFG.graderSize);
    end
    subplot(2,numel(pick),i); imshow(Ir);
    title(sprintf('true %d / pred %d', yAll(pick(i)), pg), 'FontSize',10);
    subplot(2,numel(pick),numel(pick)+i);
    imshow(Ir); hold on;
    h = imagesc(imresize(M,[CFG.graderSize CFG.graderSize]));
    colormap(jet); set(h,'AlphaData',0.45); axis off;
    title(sprintf('Grad-CAM  p=%.2f', sc(pg+1)), 'FontSize',10);
end
sgtitle('NETRA explainability - Grad-CAM on held-out APTOS test images');
lightAxes(f); exportgraphics(f, fullfile(figDir,'gradcam_examples.png'), 'Resolution',150); close(f);
fprintf('wrote figures/gradcam_examples.png\n');
end
