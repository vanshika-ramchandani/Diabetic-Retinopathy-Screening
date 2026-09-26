function s22_vessel_semantic_metrics()
%S22_VESSEL_SEMANTIC_METRICS  MATLAB semantic-segmentation metrics for the
%   vessel net, on the sealed DRIVE test set.
%
%   s21 reports binary vessel-class metrics. This stage reports the standard
%   evaluateSemanticSegmentation set - global accuracy, mean accuracy, mean and
%   weighted IoU, mean BF score - which are computed over BOTH classes
%   (background and vessel) and are therefore NOT interchangeable with s21's
%   numbers. Two traps worth naming, because both flatter the result:
%
%     * MeanIoU averages the vessel IoU with the background IoU. Background is
%       ~87% of the field and trivially easy, so its IoU is ~0.95 and it drags
%       the mean far above the vessel IoU that actually matters. WeightedIoU is
%       worse still - it weights by class frequency, so it is almost entirely a
%       report on the background class.
%     * MeanBFScore depends completely on its distance tolerance, which
%       defaults to 0.75% of the image diagonal. On 584x565 that is ~6 px -
%       wider than most vessels in the image, so a boundary can be off by more
%       than a vessel width and still score as a hit. The tolerance is printed
%       with the score, and a strict 2 px figure is reported alongside it.
%
%   Pixels outside the derived FOV are written as <undefined> so
%   evaluateSemanticSegmentation excludes them, matching s21's FOV discipline.
addpath(fullfile(fileparts(mfilename('fullpath')),'lib'));
CFG = s00_config();
V   = vesselConfig(CFG);

S = requireStage(fullfile(CFG.modelDir,'netra_vessel_net.mat'), ...
                 's20_train_vessels', 's20_train_vessels');
T = requireStage(fullfile(CFG.modelDir,'vessel_threshold.mat'), ...
                 's21_eval_vessels', 's21_eval_vessels');
net = S.net; thr = T.thr;

classes  = ["background" "vessel"];
labelIDs = [1 2];                       % 0 stays unmapped -> <undefined>

work = fullfile(tempdir,'netra_vessel_sem');
if isfolder(work), rmdir(work,'s'); end
mkdir(fullfile(work,'pred')); mkdir(fullfile(work,'truth'));

ids = CFG.driveTestIds;
bf2 = zeros(numel(ids),1);
diagPx = 0;

fprintf('predicting %d sealed test images at threshold %.2f...\n', numel(ids), thr);
for i = 1:numel(ids)
    [I, L, F] = readDriveSample(ids(i), CFG);
    P = slidingWindowPredict(net, I, V);
    D = (P(:,:,1) >= thr);

    % 1 background, 2 vessel, 0 outside the field (-> <undefined>)
    pl = uint8(F) .* uint8(D + 1);
    tl = uint8(F) .* uint8(L + 1);

    imwrite(pl, fullfile(work,'pred',  sprintf('%02d.png', ids(i))));
    imwrite(tl, fullfile(work,'truth', sprintf('%02d.png', ids(i))));

    % Strict boundary score: 2 px tolerance, evaluated inside the FOV only.
    b = bfscore(D & F, L & F, 2);
    bf2(i) = b(1);
    diagPx = hypot(size(I,1), size(I,2));
end

pxdsPred  = pixelLabelDatastore(fullfile(work,'pred'),  classes, labelIDs);
pxdsTruth = pixelLabelDatastore(fullfile(work,'truth'), classes, labelIDs);

m = evaluateSemanticSegmentation(pxdsPred, pxdsTruth, 'Verbose', false);

% ---- vessel-class precision from the raw confusion matrix ---------------
C  = m.ConfusionMatrix{:,:};       % rows = true class, cols = predicted
tp = C(2,2); fn = C(2,1); fp = C(1,2); tn = C(1,1);
precision = tp / max(tp+fp,1);
recall    = tp / max(tp+fn,1);
iouVessel = tp / max(tp+fp+fn,1);

% ---- report -------------------------------------------------------------
d = m.DataSetMetrics; c = m.ClassMetrics;
fprintf('\n================ DATASET METRICS (both classes) ================\n');
fprintf('  Threshold          %.2f   (frozen on validation in s21)\n', thr);
fprintf('  GlobalAccuracy     %.4f\n', d.GlobalAccuracy);
fprintf('  MeanAccuracy       %.4f\n', d.MeanAccuracy);
fprintf('  MeanIoU            %.4f\n', d.MeanIoU);
fprintf('  WeightedIoU        %.4f\n', d.WeightedIoU);
fprintf('  MeanBFScore        %.4f   (tolerance %.1f px = 0.75%% of the %.0f px diagonal)\n', ...
        d.MeanBFScore, 0.0075*diagPx, diagPx);
fprintf('  MeanBFScore@2px    %.4f   (strict, vessel class, mean over images)\n', mean(bf2));

fprintf('\n================ PER-CLASS ====================================\n');
fprintf('  %-12s %10s %10s %12s\n', 'class', 'Accuracy', 'IoU', 'MeanBFScore');
for k = 1:height(c)
    fprintf('  %-12s %10.4f %10.4f %12.4f\n', string(c.Properties.RowNames{k}), ...
            c.Accuracy(k), c.IoU(k), c.MeanBFScore(k));
end

fprintf('\n================ VESSEL CLASS (the one that matters) ==========\n');
fprintf('  Recall (sensitivity)  %.4f\n', recall);
fprintf('  Precision             %.4f\n', precision);
fprintf('  IoU (Jaccard)         %.4f\n', iouVessel);
fprintf('  Dice (F1)             %.4f\n', 2*tp/max(2*tp+fp+fn,1));
fprintf('  Specificity           %.4f\n', tn/max(tn+fp,1));

% ---- persist ------------------------------------------------------------
Sum = table(thr, d.GlobalAccuracy, d.MeanAccuracy, d.MeanIoU, d.WeightedIoU, ...
            d.MeanBFScore, mean(bf2), recall, precision, iouVessel, ...
    'VariableNames', {'Threshold','GlobalAccuracy','MeanAccuracy','MeanIoU', ...
                      'WeightedIoU','MeanBFScore','MeanBFScore_2px', ...
                      'Recall','Precision','IoU'});
writetable(Sum, fullfile(CFG.resultDir,'vessel_semantic_metrics.csv'));
writetable(m.ImageMetrics, fullfile(CFG.resultDir,'vessel_semantic_per_image.csv'));
save(fullfile(CFG.resultDir,'vessel_semantic_metrics.mat'), 'm','Sum','bf2','thr');

fprintf('\nwrote results/vessel_semantic_metrics.csv\n');
fprintf('wrote results/vessel_semantic_per_image.csv\n');
rmdir(work,'s');
end
