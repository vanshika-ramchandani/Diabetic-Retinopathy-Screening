function vesselSanityCheck(id)
%VESSELSANITYCHECK  One-image look at the vessel net - original, prediction,
%   ground truth. The quick "is it working" check, not an evaluation.
%
%   vesselSanityCheck()     DRIVE test image 1
%   vesselSanityCheck(7)    DRIVE test image 7
%
%   For the real numbers use s21_eval_vessels (vessel metrics) or
%   s22_vessel_semantic_metrics (MATLAB's semantic-segmentation set). One
%   image is a smoke test; it cannot tell you the model is good.
%
%   NOTE on resolution. This predicts at NATIVE resolution via a sliding
%   window - it never resizes the image down to the network input. DRIVE
%   vessels are 1-5 px wide, so downscaling a 584x565 fundus to the patch size
%   would delete the thinnest ones before the model ever saw them, and
%   downscaling the ground truth with them hides that in the metrics too.
if nargin < 1 || isempty(id), id = 1; end
here = fileparts(fileparts(mfilename('fullpath')));
addpath(here, fullfile(here,'lib'));
CFG = s00_config();
V   = vesselConfig(CFG);

S = requireStage(fullfile(CFG.modelDir,'netra_vessel_net.mat'), ...
                 's20_train_vessels','s20_train_vessels');
T = requireStage(fullfile(CFG.modelDir,'vessel_threshold.mat'), ...
                 's21_eval_vessels','s21_eval_vessels');

[I, L, F] = readDriveSample(id, CFG);
P    = slidingWindowPredict(S.net, I, V);
pred = bwareaopen((P(:,:,1) >= T.thr) & F, 20);

f = lightFigure('Position',[100 100 1500 540]);
t = tiledlayout(f,1,3,'TileSpacing','compact','Padding','compact');

ax = nexttile(t); imshow(I,'Parent',ax);
title(ax,'Original','FontWeight','bold','FontSize',16,'Color','k');

ax = nexttile(t); imshow(labeloverlay(I, pred, 'Colormap',[0 1 1], 'Transparency',0.35),'Parent',ax);
title(ax,'Predicted Vessels','FontWeight','bold','FontSize',16,'Color','k');

ax = nexttile(t); imshow(labeloverlay(I, L,    'Colormap',[0 1 1], 'Transparency',0.35),'Parent',ax);
title(ax,'Ground Truth','FontWeight','bold','FontSize',16,'Color','k');

set(f,'Visible','on');

m = vesselMetrics(P(:,:,1), L, F, T.thr);
fprintf('DRIVE %02d @ thr %.2f | Dice %.4f  IoU %.4f  sens %.4f  spec %.4f  AUC %.4f\n', ...
        id, T.thr, m.dice, m.iou, m.sensitivity, m.specificity, m.auc);
end
