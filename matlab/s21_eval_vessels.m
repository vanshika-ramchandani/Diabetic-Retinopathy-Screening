function s21_eval_vessels()
%S21_EVAL_VESSELS  Tune the threshold on validation, then open the sealed test.
%
%   Order matters and is enforced here: the threshold is chosen on the 4
%   validation images ONLY, frozen, and then applied unchanged to DRIVE 01..20.
%   Every metric is computed inside the derived FOV (see vesselMetrics) so the
%   numbers are comparable to published DRIVE results instead of being inflated
%   by the black frame.
addpath(fullfile(fileparts(mfilename('fullpath')),'lib'));
CFG = s00_config();
V   = vesselConfig(CFG);

S  = requireStage(fullfile(CFG.modelDir,'netra_vessel_net.mat'), ...
                  's20_train_vessels', 's20_train_vessels');
SP = requireStage(fullfile(CFG.modelDir,'vessel_split.mat'), ...
                  's19_cache_vessels', 's19_cache_vessels');
net = S.net;

% ---- threshold selection on validation ----------------------------------
fprintf('--- threshold tuning on validation images %s ---\n', mat2str(SP.valId));
[pv, lv, fv] = predictSet(net, SP.valId, V, CFG);

grid = 0.05:0.01:0.95;
dice = zeros(size(grid));
for k = 1:numel(grid)
    d = 0;
    for i = 1:numel(pv)
        m = vesselMetrics(pv{i}, lv{i}, fv{i}, grid(k));
        d = d + m.dice;
    end
    dice(k) = d / numel(pv);
end
[bestDice, bi] = max(dice);
thr = grid(bi);
fprintf('best validation Dice %.4f at threshold %.2f\n', bestDice, thr);
fprintf('THRESHOLD FROZEN at %.2f - the test set is opened below.\n\n', thr);

% ---- sealed test --------------------------------------------------------
fprintf('--- sealed test: DRIVE %s ---\n', mat2str(CFG.driveTestIds));
[pt, lt, ft] = predictSet(net, CFG.driveTestIds, V, CFG);

rows = [];
fn = {'sensitivity','specificity','precision','accuracy','dice','iou','gmean','auc'};
fprintf('%-6s %7s %7s %7s %7s %7s %7s %7s %7s\n', 'id', 'sens','spec','prec','acc','dice','iou','gmean','auc');
for i = 1:numel(pt)
    m = vesselMetrics(pt{i}, lt{i}, ft{i}, thr);
    vals = cellfun(@(f) m.(f), fn);
    rows(end+1,:) = vals; %#ok<AGROW>
    fprintf('%-6d %7.4f %7.4f %7.4f %7.4f %7.4f %7.4f %7.4f %7.4f\n', ...
            CFG.driveTestIds(i), vals);
end
mu = mean(rows,1); sd = std(rows,0,1);
fprintf('%-6s %7.4f %7.4f %7.4f %7.4f %7.4f %7.4f %7.4f %7.4f\n', 'MEAN', mu);
fprintf('%-6s %7.4f %7.4f %7.4f %7.4f %7.4f %7.4f %7.4f %7.4f\n', 'SD',   sd);

% ---- persist ------------------------------------------------------------
T = array2table(rows, 'VariableNames', fn);
T = addvars(T, CFG.driveTestIds(:), 'Before', 1, 'NewVariableNames', 'image');
writetable(T, fullfile(CFG.resultDir,'vessel_metrics.csv'));
save(fullfile(CFG.resultDir,'vessel_metrics.mat'), 'T','thr','bestDice','mu','sd','CFG');
fprintf('\nwrote results/vessel_metrics.csv\n');

save(fullfile(CFG.modelDir,'vessel_threshold.mat'), 'thr','bestDice');
fprintf('wrote models/vessel_threshold.mat (thr = %.2f)\n', thr);

% ---- one overlay per test image for the deck ----------------------------
od = fullfile(CFG.resultDir,'overlays','vessels');
if ~isfolder(od), mkdir(od); end
for i = 1:min(4, numel(pt))
    id = CFG.driveTestIds(i);
    I  = readDriveSample(id, CFG);
    imwrite(vesselOverlay(I, pt{i} >= thr, lt{i}, ft{i}), ...
            fullfile(od, sprintf('drive_%02d.png', id)));
end
fprintf('wrote %d overlays to results/overlays/vessels\n', min(4,numel(pt)));
end

% -------------------------------------------------------------------------
function [P, L, F] = predictSet(net, ids, V, CFG)
P = cell(numel(ids),1); L = P; F = P;
for i = 1:numel(ids)
    [I, Li, Fi] = readDriveSample(ids(i), CFG);
    P{i} = slidingWindowPredict(net, I, V);
    L{i} = Li; F{i} = Fi;
end
end

% -------------------------------------------------------------------------
function O = vesselOverlay(I, pred, truth, fov)
%VESSELOVERLAY  green = hit, red = false positive, blue = missed vessel.
%   FOV is not optional. Outside the field the input is black frame the net
%   never trained on, so it fires there freely - and an unmasked overlay paints
%   that whole ring red, which reads as a catastrophic false-positive rate that
%   the metrics (correctly FOV-restricted) do not show. The picture has to be
%   masked the same way the numbers are or the two tell different stories.
O = I;
pred  = pred  & fov;
truth = truth & fov;
tp = pred & truth; fp = pred & ~truth; fn = ~pred & truth;
R = O(:,:,1); G = O(:,:,2); B = O(:,:,3);
R(tp) = 0;   G(tp) = 255; B(tp) = 0;
R(fp) = 255; G(fp) = 0;   B(fp) = 0;
R(fn) = 0;   G(fn) = 0;   B(fn) = 255;
O = cat(3,R,G,B);
end
