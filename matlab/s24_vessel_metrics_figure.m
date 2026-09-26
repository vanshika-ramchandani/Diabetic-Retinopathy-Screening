function s24_vessel_metrics_figure()
%S24_VESSEL_METRICS_FIGURE  The vessel numbers as a figure, with the trap
%   drawn rather than only written down.
%
%   Left panel. Every headline metric, colour-split by what it is actually
%   measuring: BLUE bars score the vessel class alone, GREY bars average the
%   vessel in with the background. Background is ~87% of the field and trivially
%   easy, so the grey bars sit high for a reason that has nothing to do with how
%   well vessels are segmented. A reader who takes MeanIoU 0.81 as "the score"
%   has read a background metric. Colour is never the only cue - every bar
%   carries its value and the grey ones are labelled in the legend.
%
%   Right panel. Per-image Dice across the 20 sealed test images. One bar in
%   the left panel is a mean; this shows the spread it came from, which is the
%   thing a mean hides.
addpath(fullfile(fileparts(mfilename('fullpath')),'lib'));
CFG = s00_config();
R = CFG.resultDir;

S = requireStage(fullfile(R,'vessel_semantic_metrics.mat'), ...
                 's22_vessel_semantic_metrics','s22_vessel_semantic_metrics');
V = requireStage(fullfile(R,'vessel_metrics.mat'), ...
                 's21_eval_vessels','s21_eval_vessels');

name = ["IoU (vessel)"    "Precision"  "Recall"     "Dice"       "Specificity" ...
        "MeanBFScore@2px" "ROC-AUC"    "MeanIoU"    "MeanAccuracy" ...
        "GlobalAccuracy"  "WeightedIoU" "MeanBFScore"];
val  = [S.Sum.IoU         S.Sum.Precision S.Sum.Recall V.mu(5)   V.mu(2) ...
        S.Sum.MeanBFScore_2px  V.mu(8)   S.Sum.MeanIoU S.Sum.MeanAccuracy ...
        S.Sum.GlobalAccuracy   S.Sum.WeightedIoU  S.Sum.MeanBFScore];
% true  = scores the vessel class alone
% false = averaged or pooled with the background class
vesselOnly = [true true true true true true true false false false false false];

[val, ord] = sort(val, 'ascend');
name = name(ord); vesselOnly = vesselOnly(ord);

blue = [0.16 0.44 0.73];     % vessel class
grey = [0.68 0.70 0.73];     % includes background

f = lightFigure('Position',[80 80 1440 620]);
t = tiledlayout(f,1,2,'TileSpacing','compact','Padding','compact');

% ---- left: the metrics ---------------------------------------------------
ax = nexttile(t); hold(ax,'on');
for k = 1:numel(val)
    c = grey; if vesselOnly(k), c = blue; end
    barh(ax, k, val(k), 0.62, 'FaceColor', c, 'EdgeColor','none');
    text(ax, val(k)+0.012, k, sprintf('%.4f', val(k)), ...
         'FontSize',11, 'VerticalAlignment','middle', 'Color',[0.15 0.15 0.15]);
end
set(ax,'YTick',1:numel(val),'YTickLabel',name,'FontSize',11);
xlim(ax,[0 1.12]); ylim(ax,[0.4 numel(val)+0.6]);
xlabel(ax,'score','FontSize',11);
title(ax,'Vessel segmentation — 20 sealed DRIVE test images', ...
      'FontWeight','bold','FontSize',14,'Color','k');
ax.XGrid='on'; ax.YGrid='off'; ax.GridAlpha=0.12; ax.Box='off';
h1 = patch(ax,NaN,NaN,blue,'EdgeColor','none');
h2 = patch(ax,NaN,NaN,grey,'EdgeColor','none');
legend(ax,[h1 h2], {'vessel class only','averaged with background'}, ...
       'Location','southoutside','Orientation','horizontal','FontSize',10,'Box','off');
lightAxes(ax);

% ---- right: per-image spread --------------------------------------------
ax = nexttile(t); hold(ax,'on');
d = V.T.dice; ids = V.T.image;
bar(ax, ids, d, 0.62, 'FaceColor', blue, 'EdgeColor','none');
yline(ax, mean(d), '-', sprintf('mean %.4f', mean(d)), ...
      'Color',[0.15 0.15 0.15], 'LineWidth',1.6, 'FontSize',11, ...
      'LabelHorizontalAlignment','left');
set(ax,'XTick',ids(1:2:end),'FontSize',11);
ylim(ax,[0.70 0.88]); xlim(ax,[0.3 20.7]);
xlabel(ax,'DRIVE test image','FontSize',11);
ylabel(ax,'Dice','FontSize',11);
title(ax, sprintf('Per-image Dice — spread %.4f to %.4f', min(d), max(d)), ...
      'FontWeight','bold','FontSize',14,'Color','k');
ax.YGrid='on'; ax.XGrid='off'; ax.GridAlpha=0.12; ax.Box='off';
lightAxes(ax);

out = fullfile(CFG.root,'figures','vessel_metrics.png');
exportgraphics(t, out, 'Resolution', 150, 'BackgroundColor','white');
close(f);
fprintf('wrote %s\n', out);
end
