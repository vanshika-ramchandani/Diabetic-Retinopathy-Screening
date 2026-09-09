function s13_calibrate_quality(nSample, targetReject)
%S13_CALIBRATE_QUALITY  Fit the D1 quality-gate thresholds to real data.
%
%   The thresholds are NOT hand-picked. Each is a percentile of the measured
%   distribution over a random sample of raw APTOS captures, so "reject" means
%   "worse than the bottom 5% of real screening images" - a statement that can
%   be defended with the histogram in figures/quality_calibration.png.
%
%   Calibration deliberately runs on the RAW originals, not the CLAHE cache:
%   the gate sits in front of enhancement, so it must see what the camera saw.
if nargin < 1 || isempty(nSample), nSample = 400; end
if nargin < 2 || isempty(targetReject), targetReject = 0.05; end
here = fileparts(mfilename('fullpath'));
addpath(here, fullfile(here,'lib'), fullfile(here,'m1_quality'));
CFG = s00_config(); rng(CFG.seed);

T = readtable(CFG.aptosCsv, TextType='string');
files = fullfile(CFG.aptosImgDir, T.id_code + ".png");
files = files(isfile(files));
if isempty(files), error('no APTOS originals found in %s', CFG.aptosImgDir); end
idx = randperm(numel(files), min(nSample, numel(files)));
files = files(idx);
fprintf('calibrating quality gate on %d raw APTOS captures\n', numel(files));

names = {'focus','illumUniformity','underExposed','overExposed','contrast','fovCoverage'};
V = nan(numel(files), numel(names));
t0 = tic;
for i = 1:numel(files)
    try
        q = qualityMetrics(imread(files(i)));
        for k = 1:numel(names), V(i,k) = q.(names{k}); end
    catch ME
        fprintf('  skip %s : %s\n', files(i), ME.message);
    end
    if mod(i,50) == 0, fprintf('  %d/%d  (%.1f min)\n', i, numel(files), toc(t0)/60); end
end
V = V(all(isfinite(V),2), :);
fprintf('%d images measured in %.1f min\n', size(V,1), toc(t0)/60);

g = @(n) V(:, strcmp(names,n));

% ---- fit to a TARGET OVERALL REJECT RATE, not per-axis percentiles ------
% Setting each of the four reject criteria at its own 5th percentile does not
% reject 5% of images - it rejects the UNION, which measured 16% here. That
% is an operationally different (and much more expensive) gate than intended.
% So the free parameter is a single percentile p shared by all four axes,
% chosen so the union lands on the rate the programme can actually absorb.
ps = linspace(0.1, 10, 200);
best = struct('p',5,'err',inf,'rate',NaN);
for p = ps
    c = axisThresholds(V, names, p);
    r = mean(rejectMask(V, names, c));
    e = abs(r - targetReject);
    if e < best.err, best = struct('p',p,'err',e,'rate',r); end
end
cut = axisThresholds(V, names, best.p);
fprintf('\nshared percentile p=%.2f -> overall reject rate %.1f%% (target %.1f%%)\n', ...
        best.p, 100*best.rate, 100*targetReject);

thr.focusMin     = cut.focusMin;
thr.focusRef     = median(g('focus'));
thr.contrastMin  = cut.contrastMin;
thr.contrastRef  = median(g('contrast'));
thr.illumMin     = prctile(g('illumUniformity'), 10);   % ENHANCE only, not a reject
thr.illumRef     = median(g('illumUniformity'));
thr.underMax     = cut.underMax;
thr.overMax      = cut.overMax;
thr.nCalib       = size(V,1);
thr.targetReject = targetReject;
thr.sharedPct    = best.p;
thr.actualReject = best.rate;
thr.source       = "APTOS 2019 raw training captures, random sample";
thr.percentiles  = sprintf(['four reject axes share percentile p=%.2f, fitted so the ' ...
    'overall reject rate is %.1f%%; illumination p10 triggers ENHANCE only'], ...
    best.p, 100*best.rate);

if ~isfolder(CFG.modelDir), mkdir(CFG.modelDir); end
save(fullfile(CFG.modelDir,'quality_thresholds.mat'),'thr','V','names','-v7');
fprintf('\nfitted thresholds (n=%d)\n', thr.nCalib);
disp(thr);

% ---- what the gate does to its own calibration set ----------------------
dec = strings(size(V,1),1);
for i = 1:size(V,1)
    q = cell2struct(num2cell(V(i,:))', names', 1); q.clipped = false; q.meanLum = NaN;
    dec(i) = decideFrom(q, thr);
end
fprintf('\ngate applied to the calibration sample:\n');
for d = ["PASS","ENHANCE","REJECT"]
    fprintf('  %-8s %4d  (%.1f%%)\n', d, nnz(dec==d), 100*mean(dec==d));
end

figDir = fullfile(CFG.root,'figures');
if ~isfolder(figDir), mkdir(figDir); end
f = lightFigure('Position',[100 100 1100 650]);
plotNames = {'focus','contrast','illumUniformity','underExposed','overExposed','fovCoverage'};
cut = {thr.focusMin, thr.contrastMin, thr.illumMin, thr.underMax, thr.overMax, []};
for k = 1:6
    subplot(2,3,k);
    histogram(g(plotNames{k}), 40, 'FaceColor',[0.055 0.486 0.525], 'EdgeColor','none');
    hold on;
    if ~isempty(cut{k})
        xline(cut{k}, '-', 'Color',[0.757 0.153 0.176], 'LineWidth',2, 'Label','gate');
    end
    title(plotNames{k}, 'Interpreter','none'); grid on;
end
sgtitle(sprintf('NETRA quality-gate calibration - %d raw APTOS captures', thr.nCalib));
lightAxes(f);
exportgraphics(f, fullfile(figDir,'quality_calibration.png'), 'Resolution',150);
close(f);
fprintf('\nwrote figures/quality_calibration.png\n');
end

function c = axisThresholds(V, names, p)
%AXISTHRESHOLDS  The four reject cut-offs at a shared percentile p.
g = @(n) V(:, strcmp(names,n));
c.focusMin    = prctile(g('focus'),        p);
c.contrastMin = prctile(g('contrast'),     p);
c.underMax    = prctile(g('underExposed'), 100-p);
c.overMax     = prctile(g('overExposed'),  100-p);
end

function m = rejectMask(V, names, c)
g = @(n) V(:, strcmp(names,n));
m = g('focus') < c.focusMin | g('contrast') < c.contrastMin | ...
    g('underExposed') > c.underMax | g('overExposed') > c.overMax;
end

function d = decideFrom(q, thr)
if q.focus < thr.focusMin || q.underExposed > thr.underMax || ...
   q.overExposed > thr.overMax || q.contrast < thr.contrastMin
    d = "REJECT";
elseif q.illumUniformity < thr.illumMin
    d = "ENHANCE";
else
    d = "PASS";
end
end
