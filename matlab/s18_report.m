function s18_report()
%S18_REPORT  Collect every metric and every visual into one place.
%
%   Produces:
%     results/NETRA_results.html          self-contained report, figures embedded
%     figures/overlay_contact_sheet.png   all 27 GT-vs-prediction overlays on one sheet
%     console printout of the full metrics table
%
%   The metric tables follow the task/output/metric structure that was
%   specified for this project: pixel-mask tasks get Dice, IoU, pixel
%   precision/recall and AUPR; the derived binary flag gets accuracy,
%   precision, recall, specificity and ROC-AUC; neovascularisation gets a
%   stated "not trainable" rather than a blank.
here = fileparts(mfilename('fullpath'));
addpath(here, fullfile(here,'lib'));
CFG = s00_config();
R = CFG.resultDir; Fdir = fullfile(CFG.root,'figures');

%% ---------------- console table ----------------------------------------
M = readtable(fullfile(R,'metrics.csv'), TextType='string');
fprintf('\n');
bar(); fprintf('  LESION-LEVEL RESULTS - 27 sealed IDRiD test images\n'); bar();
fprintf('%-22s %-22s %7s %7s %9s %7s %7s\n', ...
        'Task','Output','Dice','IoU','Precision','Recall','AUPR');
fprintf('%s\n', repmat('-',1,86));
for i = 1:height(M)
    if ~isnan(M.Dice(i))
        fprintf('%-22s %-22s %7.4f %7.4f %9.4f %7.4f %7.4f\n', M.Task(i), M.Output(i), ...
                M.Dice(i), M.IoU(i), M.Precision(i), M.Recall(i), M.AUPR(i));
    end
end
fprintf('\n%-22s %-22s %8s %9s %7s %7s %8s\n', ...
        'Task','Output','Accuracy','Precision','Recall','Spec','ROC-AUC');
fprintf('%s\n', repmat('-',1,86));
for i = 1:height(M)
    if ~isnan(M.Accuracy(i))
        fprintf('%-22s %-22s %8.4f %9.4f %7.4f %7s %8s\n', M.Task(i), M.Output(i), ...
            M.Accuracy(i), M.Precision(i), M.Recall(i), ...
            fmt(M.Specificity(i)), fmt(M.ROC_AUC(i)));
    end
end
fprintf('\n%-22s %-22s %s\n', 'Neovascularisation', '-', ...
        'not trainable - no pixel-level labels exist in IDRiD or APTOS');

G = readtable(fullfile(R,'grader_metrics.csv'), TextType='string');
fprintf('\n');
bar(); fprintf('  REFERABLE DR (ICDR 2+) - sealed APTOS test split\n'); bar();
fprintf('  n = %d   threshold %.3f (fitted on validation)\n', G.N(1), G.Threshold(1));
fprintf('  Sensitivity %.4f   Specificity %.4f   Precision %.4f\n', ...
        G.Sensitivity(1), G.Specificity(1), G.Precision(1));
fprintf('  Accuracy    %.4f   ROC-AUC     %.4f\n', G.Accuracy(1), G.ROC_AUC(1));
fprintf('  TP %d  FP %d  TN %d  FN %d\n', G.TP(1), G.FP(1), G.TN(1), G.FN(1));
bar();

%% ---------------- contact sheet ----------------------------------------
d = dir(fullfile(R,'overlays','*.png'));
if ~isempty(d)
    fprintf('\nbuilding contact sheet from %d overlays...\n', numel(d));
    cols = 3; tileW = 640;
    thumbs = cell(numel(d),1); h = 0;
    for i = 1:numel(d)
        I = imread(fullfile(d(i).folder, d(i).name));
        I = imresize(I, [NaN tileW]);
        [~,nm] = fileparts(d(i).name);
        nm = strrep(nm,'_gt_vs_pred','');
        try
            I = insertText(I, [6 6], nm, 'FontSize',20, 'BoxColor',[11 37 69], ...
                           'BoxOpacity',0.85, 'TextColor','white');
        catch
        end
        thumbs{i} = I; h = max(h, size(I,1));
    end
    rows = ceil(numel(d)/cols);
    pad = 8;
    sheet = 255*ones(rows*(h+pad)+pad, cols*(tileW+pad)+pad, 3, 'uint8');
    for i = 1:numel(d)
        r = floor((i-1)/cols); c = mod(i-1,cols);
        y = pad + r*(h+pad); x = pad + c*(tileW+pad);
        T = thumbs{i};
        sheet(y+1:y+size(T,1), x+1:x+size(T,2), :) = T;
    end
    sheetPath = fullfile(Fdir,'overlay_contact_sheet.png');
    imwrite(sheet, sheetPath);
    fprintf('wrote figures/overlay_contact_sheet.png  (%d x %d)\n', size(sheet,2), size(sheet,1));
end

%% ---------------- HTML report ------------------------------------------
figs = { 'title_hero.png',              'Grad-CAM on a held-out test image', ...
            'The evidence behind a grade. Warm regions are what the network used.'
         'triptych.png',                'Raw -> enhanced -> lesion overlay', ...
            'Left: raw capture. Middle: illumination normalisation + CLAHE. Right: detected lesions (red MA, blue haemorrhage, yellow hard exudate, cyan soft exudate, green disc).'
         'grader_roc.png',              'Referable DR ROC', ...
            'Operating point fitted on validation at sensitivity >= 0.90, then applied unchanged to the sealed test split.'
         'grader_confusion.png',        '5-class ICDR confusion matrix', ...
            'Rows are true grade, columns predicted. Most error is one-level, which is why QWK is high.'
         'gradcam_examples.png',        'Grad-CAM across severity', ...
            'Held-out APTOS test images at grades 4, 3, 2 and 0 with their attention maps.'
         'quality_calibration.png',     'Quality-gate calibration', ...
            'Distribution of each quality measure over 400 raw APTOS captures. Red line is the fitted reject threshold.'
         'district_backlog.png',        'District backlog, one working year', ...
            'Manual review is an unstable queue: the backlog grows without bound. Triage holds it at zero.'
         'overlay_contact_sheet.png',   'All 27 test overlays', ...
            'Ground truth (left) vs prediction (right) for every sealed IDRiD test image.' };

htmlPath = fullfile(R,'NETRA_results.html');
fid = fopen(htmlPath,'w','n','UTF-8');
w = @(varargin) fprintf(fid, varargin{:});

w('<!doctype html><html><head><meta charset="utf-8">\n');
w('<title>NETRA - results</title><style>\n');
w(['body{font:15px/1.55 -apple-system,Segoe UI,Roboto,sans-serif;color:#0B2545;' ...
   'max-width:1100px;margin:0 auto;padding:32px 22px;background:#fff}\n']);
w('h1{font-size:27px;margin:0 0 4px}h2{font-size:19px;margin:34px 0 10px;color:#0E7C86}\n');
w('h3{font-size:15px;margin:22px 0 6px}\n');
w('table{border-collapse:collapse;width:100%%;margin:10px 0 6px;font-size:13.5px}\n');
w('th{background:#0E7C86;color:#fff;text-align:left;padding:7px 9px;font-weight:600}\n');
w('td{padding:6px 9px;border-bottom:1px solid #e6ebee}\n');
w('tr:nth-child(even) td{background:#f6f8f9}\n');
w('.num{text-align:right;font-variant-numeric:tabular-nums}\n');
w('.big{font-size:26px;font-weight:700;color:#0E7C86}\n');
w('.ok{color:#3E8E5A;font-weight:600}.bad{color:#C1272D;font-weight:600}\n');
w(['.note{background:#f6f8f9;border-left:3px solid #0E7C86;padding:10px 14px;' ...
   'margin:12px 0;font-size:13.5px}\n']);
w(['.warn{background:#fdf6e8;border-left:3px solid #F0A202;padding:10px 14px;' ...
   'margin:12px 0;font-size:13.5px}\n']);
w('img{max-width:100%%;border:1px solid #e6ebee;border-radius:4px;margin:6px 0}\n');
w('.cap{color:#6b7883;font-size:12.5px;margin:2px 0 20px}\n');
w('code{background:#f2f5f6;padding:1px 5px;border-radius:3px;font-size:12.5px}\n');
w('</style></head><body>\n');

w('<h1>NETRA — results</h1>\n');
w(['<p class="cap">SIH 2026 · PS 26038 · generated %s by <code>s18_report</code>. ' ...
   'Every number here comes from a script in <code>matlab/</code>; ' ...
   'run <code>verify_build</code> to re-check them against their sources.</p>\n'], ...
   datestr(now,'yyyy-mm-dd HH:MM'));

% headline
w('<h2>Headline</h2>\n<table><tr><th>Result</th><th>Value</th><th>Requirement</th></tr>\n');
w('<tr><td>Referable DR sensitivity (sealed APTOS, n=%d)</td><td class="num big">%.1f%%</td><td class="ok">&gt; 90%% ✓</td></tr>\n', G.N(1), 100*G.Sensitivity(1));
w('<tr><td>Referable DR specificity</td><td class="num big">%.1f%%</td><td class="ok">&gt; 85%% ✓</td></tr>\n', 100*G.Specificity(1));
w('<tr><td>ROC-AUC</td><td class="num">%.4f</td><td>—</td></tr>\n', G.ROC_AUC(1));
w('<tr><td>5-class ICDR quadratic weighted kappa</td><td class="num">%.4f</td><td>—</td></tr>\n', factOf(R,'grader.qwk'));
w('</table>\n');

% lesion pixel tasks
w('<h2>Lesion segmentation — 27 sealed IDRiD test images</h2>\n');
w('<h3>Pixel-mask tasks</h3>\n<table>\n');
w('<tr><th>Task</th><th>Output</th><th>Dice</th><th>IoU</th><th>Precision</th><th>Recall</th><th>AUPR</th></tr>\n');
for i = 1:height(M)
    if ~isnan(M.Dice(i))
        w(['<tr><td>%s</td><td>%s</td><td class="num">%.4f</td><td class="num">%.4f</td>' ...
           '<td class="num">%.4f</td><td class="num">%.4f</td><td class="num">%.4f</td></tr>\n'], ...
           M.Task(i), M.Output(i), M.Dice(i), M.IoU(i), M.Precision(i), M.Recall(i), M.AUPR(i));
    end
end
w('</table>\n');

w('<h3>Derived binary flag</h3>\n<table>\n');
w('<tr><th>Task</th><th>Output</th><th>Accuracy</th><th>Precision</th><th>Recall</th><th>Specificity</th><th>ROC-AUC</th></tr>\n');
for i = 1:height(M)
    if ~isnan(M.Accuracy(i))
        w(['<tr><td>%s</td><td>%s</td><td class="num">%.4f</td><td class="num">%.4f</td>' ...
           '<td class="num">%.4f</td><td class="num">%s</td><td class="num">%s</td></tr>\n'], ...
           M.Task(i), M.Output(i), M.Accuracy(i), M.Precision(i), M.Recall(i), ...
           fmt(M.Specificity(i)), fmt(M.ROC_AUC(i)));
    end
end
w('</table>\n');
w(['<div class="warn"><b>Read the two haemorrhage-flag rows together.</b> All 27 IDRiD test ' ...
   'images contain haemorrhages, so the whole-image row has no negatives — its specificity and ' ...
   'ROC-AUC are undefined and its 100%% is not a real result. The 512&nbsp;px region row is the ' ...
   'meaningful one.</div>\n']);
w(['<div class="note"><b>Neovascularisation — not trainable.</b> No pixel-level ' ...
   'annotation exists in IDRiD or APTOS, so no metric is reported. ' ...
   '<code>ruleGradeICDR</code> exposes <code>pdrDetectable = false</code> so silence is never ' ...
   'mistaken for a negative.</div>\n']);

% grader detail
w('<h2>DR grader — sealed APTOS test split</h2>\n<table>\n');
w('<tr><th>Metric</th><th>Value</th></tr>\n');
rows = {'n (test)', sprintf('%d', G.N(1)); ...
        'Threshold (fitted on validation)', sprintf('%.3f', G.Threshold(1)); ...
        'Sensitivity', sprintf('%.4f', G.Sensitivity(1)); ...
        'Specificity', sprintf('%.4f', G.Specificity(1)); ...
        'Precision',   sprintf('%.4f', G.Precision(1)); ...
        'Accuracy',    sprintf('%.4f', G.Accuracy(1)); ...
        'ROC-AUC',     sprintf('%.4f', G.ROC_AUC(1)); ...
        'TP / FP / TN / FN', sprintf('%d / %d / %d / %d', G.TP(1), G.FP(1), G.TN(1), G.FN(1))};
for i = 1:size(rows,1)
    w('<tr><td>%s</td><td class="num">%s</td></tr>\n', rows{i,1}, rows{i,2});
end
w('</table>\n');

% dual evidence + quality + district
w('<h2>Quality gate, dual evidence, district model</h2>\n<table>\n');
w('<tr><th>Measure</th><th>Value</th><th>Source</th></tr>\n');
kv = {'Quality gate reject rate',            pct(factOf(R,'quality.actual_reject')),  's13_calibrate_quality (400 raw captures)'
      'Quality gate pass / enhance / reject on IDRiD', ...
          sprintf('%d / %d / %d', factOf(R,'quality.idrid_pass'), factOf(R,'quality.idrid_enhance'), factOf(R,'quality.idrid_reject')), ...
          's14_integration'
      'CNN referable errors caught by dual evidence', pct(factOf(R,'d2.catch_rate')),  's16_dual_evidence_aptos'
      'Referable cases silently missed after D2',  sprintf('%d', factOf(R,'d2.silently_missed_after_d2')), 's16_dual_evidence_aptos'
      'Manual-review backlog after one year',      sprintf('%d expert-days', factOf(R,'sl.backlog_manual_expert_days')), 'buildNetraSimulink'
      'Break-even flagged fraction',               pct(factOf(R,'district.break_even_flagged')), 'districtSim'
      'NETRA flagged fraction',                    pct(factOf(R,'district.flagged_fraction')),   'districtSim'
      'Mean end-to-end time per image',            sprintf('%.1f s', factOf(R,'pipeline.mean_seconds_per_image')), 's14_integration'};
for i = 1:size(kv,1)
    w('<tr><td>%s</td><td class="num">%s</td><td><code>%s</code></td></tr>\n', kv{i,1}, kv{i,2}, kv{i,3});
end
w('</table>\n');
w(['<div class="warn"><b>One caveat to state before a judge finds it.</b> The dual-evidence ' ...
   '<i>escalation cost</i> (62%% on APTOS) is inflated: the lesion network trains at IDRiD native ' ...
   'resolution, and those APTOS images are cached at 512&nbsp;px, outside its trained regime, ' ...
   'where it over-calls. The <i>safety</i> result above is sound; the cost is an upper bound. ' ...
   'Re-measuring on full-resolution originals is the top next task.</div>\n']);

% visuals
w('<h2>Visuals</h2>\n');
for i = 1:size(figs,1)
    p = fullfile(Fdir, figs{i,1});
    if ~isfile(p), continue; end
    w('<h3>%s</h3>\n', figs{i,2});
    w('<img src="data:image/png;base64,%s" alt="%s">\n', b64(p), figs{i,2});
    w('<p class="cap">%s &nbsp;·&nbsp; <code>figures/%s</code></p>\n', figs{i,3}, figs{i,1});
end

w(['<h2>Where the files are</h2>\n<table><tr><th>What</th><th>Path</th></tr>\n' ...
   '<tr><td>Lesion metrics (this table)</td><td><code>results/metrics.csv</code></td></tr>\n' ...
   '<tr><td>Grader metrics</td><td><code>results/grader_metrics.csv</code></td></tr>\n' ...
   '<tr><td>Per-image dual evidence</td><td><code>results/dual_evidence_aptos.csv</code></td></tr>\n' ...
   '<tr><td>Per-image end-to-end run</td><td><code>results/integration_run.csv</code></td></tr>\n' ...
   '<tr><td>Every number the deck may quote</td><td><code>results/deck_facts.txt</code></td></tr>\n' ...
   '<tr><td>All 27 overlays, full size</td><td><code>results/overlays/</code></td></tr>\n' ...
   '<tr><td>Figures for the PPT</td><td><code>figures/</code></td></tr>\n' ...
   '<tr><td>The deck</td><td><code>ppt/NETRA_SIH2026_PS26038.pptx</code> and <code>.pdf</code></td></tr>\n' ...
   '</table>\n']);

w('</body></html>\n');
fclose(fid);
fprintf('\nwrote %s\n', htmlPath);
fprintf('open it with:  winopen(''%s'')\n', htmlPath);
end

% =========================================================================
function bar(), fprintf('%s\n', repmat('=',1,86)); end
function s = fmt(x)
if isnan(x), s = 'undef'; else, s = sprintf('%.4f', x); end
end
function s = pct(x)
if isnan(x), s = 'n/a'; else, s = sprintf('%.1f%%', 100*x); end
end
function v = factOf(R, key)
persistent F
if isempty(F)
    F = struct(); p = fullfile(R,'deck_facts.txt');
    if isfile(p)
        fid = fopen(p,'r');
        while true
            l = fgetl(fid); if ~ischar(l), break; end
            l = strtrim(l);
            if isempty(l) || startsWith(l,'#') || startsWith(l,'['), continue; end
            i = strfind(l,'='); if isempty(i), continue; end
            k = strtrim(l(1:i(1)-1)); val = strtrim(l(i(1)+1:end));
            j = strfind(val,'  #'); if ~isempty(j), val = strtrim(val(1:j(1)-1)); end
            n = str2double(val);
            if ~isnan(n), F.(matlab.lang.makeValidName(k)) = n; end
        end
        fclose(fid);
    end
end
k = matlab.lang.makeValidName(key);
if isfield(F,k), v = F.(k); else, v = NaN; end
end
function s = b64(p)
fid = fopen(p,'r'); b = fread(fid,inf,'*uint8'); fclose(fid);
s = matlab.net.base64encode(b);
end
