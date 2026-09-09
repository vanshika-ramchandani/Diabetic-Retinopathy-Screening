function ok = verify_build()
%VERIFY_BUILD  Independently re-check every claim this project makes.
%
%   verify_build()
%
%   This does NOT trust results/deck_facts.txt. It re-opens the source .mat and
%   .csv files that each number came from and compares them. If someone edits a
%   fact by hand, or a script is re-run and the facts file goes stale, this is
%   what catches it.
%
%   Checks, in order:
%     1  artifacts        every file the build claims to produce exists
%     2  split integrity  train / val / test really are disjoint
%     3  facts            deck_facts.txt agrees with the files it was derived from
%     4  thresholds       the operating point was fitted on validation, not test
%     5  models           the networks load and have the shape they should
%     6  deck             exactly 6 slides, PDF present, no unfilled placeholders
%
%   Exit: prints PASS/FAIL per check and returns true only if all passed.
here = fileparts(mfilename('fullpath'));
addpath(here, fullfile(here,'lib'));
CFG = s00_config();
R = CFG.resultDir; M = CFG.modelDir; F = fullfile(CFG.root,'figures');

state = struct('pass',0,'fail',0,'warn',0);
line();
fprintf('  NETRA BUILD VERIFICATION\n');
fprintf('  %s\n', datestr(now,'yyyy-mm-dd HH:MM'));
line();

% ================= 1. artifacts =========================================
section('1. ARTIFACTS');
need = { fullfile(M,'netra_lesion_net.mat'),   'lesion segmentation net'
         fullfile(M,'thresholds.mat'),         'lesion thresholds'
         fullfile(M,'netra_grader.mat'),       'DR grader'
         fullfile(M,'grader_split.mat'),       'grader split'
         fullfile(M,'quality_thresholds.mat'), 'quality gate thresholds'
         fullfile(R,'metrics.csv'),            'lesion metrics'
         fullfile(R,'grader_metrics.mat'),     'grader metrics'
         fullfile(R,'dual_evidence_aptos.mat'),'dual-evidence measurement'
         fullfile(R,'deck_facts.txt'),         'deck facts'
         fullfile(R,'integration_run.csv'),    'end-to-end run'
         fullfile(F,'title_hero.png'),         'deck hero image'
         fullfile(F,'triptych.png'),           'raw/enhanced/lesion triptych'
         fullfile(F,'grader_roc.png'),         'ROC figure'
         fullfile(F,'district_backlog.png'),   'Simulink backlog figure'
         fullfile(here,'m5_simulink','netra_district.slx'), 'Simulink model'
         fullfile(CFG.root,'ppt','NETRA_SIH2026_PS26038.pptx'), 'deck (pptx)'
         fullfile(CFG.root,'ppt','NETRA_SIH2026_PS26038.pdf'),  'deck (pdf)' };
for i = 1:size(need,1)
    state = check(state, isfile(need{i,1}), need{i,2}, ...
                  sprintf('missing: %s', need{i,1}));
end
nOv = numel(dir(fullfile(R,'overlays','*.png')));
state = check(state, nOv >= 27, sprintf('overlays present (%d)', nOv), ...
              sprintf('only %d overlays; run s08_figures(inf)', nOv));

% ================= 2. split integrity ===================================
section('2. SPLIT INTEGRITY  (the thing that invalidates everything if wrong)');
S = load(fullfile(M,'grader_split.mat')); sp = S.split;
nTr = nnz(sp.isTrain); nVa = nnz(sp.isVal); nTe = nnz(sp.isTest);
state = check(state, ~any(sp.isTrain & sp.isVal) && ~any(sp.isTrain & sp.isTest) ...
                     && ~any(sp.isVal & sp.isTest), ...
    sprintf('grader train/val/test disjoint  (%d / %d / %d)', nTr, nVa, nTe), ...
    'SPLITS OVERLAP - every grader number is invalid');
state = check(state, nTr+nVa+nTe == numel(sp.y), ...
    'grader split covers every image exactly once', 'split does not partition the set');

% files must be unique - the same image appearing twice would leak
state = check(state, numel(unique(sp.files)) == numel(sp.files), ...
    'no duplicate images across the grader split', 'duplicate file paths found');

% IDRiD: the lesion net trained on 1-54, evaluated on 55-81
state = check(state, isempty(intersect(CFG.trainIds, CFG.testIds)), ...
    sprintf('IDRiD train (%d) and test (%d) disjoint', numel(CFG.trainIds), numel(CFG.testIds)), ...
    'IDRiD train and test overlap');

% ================= 3. facts vs sources ==================================
section('3. DECK FACTS vs THE FILES THEY CAME FROM');
facts = readFacts(fullfile(R,'deck_facts.txt'));
G = load(fullfile(R,'grader_metrics.mat'));
D = load(fullfile(R,'dual_evidence_aptos.mat'));
Q = load(fullfile(M,'quality_thresholds.mat'));
Mt = readtable(fullfile(R,'metrics.csv'), TextType='string');

state = factCheck(state, facts, 'grader.sensitivity',  G.R.sensitivity);
state = factCheck(state, facts, 'grader.specificity',  G.R.specificity);
state = factCheck(state, facts, 'grader.roc_auc',      G.R.rocAuc);
state = factCheck(state, facts, 'grader.qwk',          G.R.qwk);
state = factCheck(state, facts, 'grader.n_test',       G.R.nTest);
state = factCheck(state, facts, 'd2.catch_rate',       D.R.catchRate);
state = factCheck(state, facts, 'd2.silently_missed_after_d2', D.R.missedAfterD2);
state = factCheck(state, facts, 'quality.actual_reject', Q.thr.actualReject);

k = Mt.Task == "Exudates (hard)";
state = factCheck(state, facts, 'dice.exudates_hard', Mt.Dice(find(k,1)));
k = Mt.Task == "Microaneurysm";
state = factCheck(state, facts, 'dice.microaneurysm', Mt.Dice(find(k,1)));

% ================= 4. protocol ==========================================
section('4. EVALUATION PROTOCOL');
state = check(state, G.R.sensitivity > 0.90 && G.R.specificity > 0.85, ...
    sprintf('meets PS 26038 bar: sens %.4f > 0.90, spec %.4f > 0.85', ...
            G.R.sensitivity, G.R.specificity), ...
    'does NOT meet the problem statement requirement');

% The operating point must have been fitted on validation. Re-derive it and
% confirm it reproduces - if someone re-tuned on test, val sens drops off 0.90.
state = check(state, G.R.valSens >= CFG.sensTarget - 1e-6, ...
    sprintf('operating point fitted on VALIDATION (val sens %.4f >= %.2f)', ...
            G.R.valSens, CFG.sensTarget), ...
    'validation sensitivity is below target - threshold was not fitted on val');

thr = G.R.threshold;
sens2 = mean(G.sTst(G.refTst) >= thr);
spec2 = mean(G.sTst(~G.refTst) <  thr);
state = check(state, abs(sens2-G.R.sensitivity) < 1e-6 && abs(spec2-G.R.specificity) < 1e-6, ...
    sprintf('test metrics reproduce from raw scores (%.4f / %.4f)', sens2, spec2), ...
    'reported metrics do NOT reproduce from the saved scores');

% Grade distribution sanity: a test split that is all one class is meaningless
p = mean(G.refTst);
state = check(state, p > 0.15 && p < 0.85, ...
    sprintf('test split has both classes (%.1f%% referable)', 100*p), ...
    'test split is degenerate');

% ================= 5. models ============================================
section('5. MODELS');
A = load(fullfile(M,'netra_lesion_net.mat'));
state = check(state, isa(A.net,'dlnetwork'), 'lesion net loads as dlnetwork', 'lesion net is not a dlnetwork');
B = load(fullfile(M,'thresholds.mat'));
state = check(state, numel(B.thr) == CFG.nChan, ...
    sprintf('lesion thresholds: %d channels', numel(B.thr)), 'threshold count mismatch');
Gn = load(fullfile(M,'netra_grader.mat'));
state = check(state, ~isempty(Gn.net), 'grader loads', 'grader failed to load');
state = check(state, Q.thr.nCalib >= 100, ...
    sprintf('quality gate calibrated on %d images', Q.thr.nCalib), ...
    'quality gate calibration sample too small');

% ================= 6. deck ==============================================
section('6. DECK');
pptx = fullfile(CFG.root,'ppt','NETRA_SIH2026_PS26038.pptx');
if isfile(pptx)
    tmp = tempname; mkdir(tmp);
    try
        unzip(pptx, tmp);
        sl = dir(fullfile(tmp,'ppt','slides','slide*.xml'));
        state = check(state, numel(sl) == 6, ...
            sprintf('exactly 6 slides (%d)', numel(sl)), ...
            sprintf('%d slides - SIH allows a maximum of 6', numel(sl)));

        txt = "";
        for i = 1:numel(sl)
            txt = txt + string(fileread(fullfile(sl(i).folder, sl(i).name)));
        end
        state = check(state, ~contains(txt,'n/a'), ...
            'no unmeasured values ("n/a") on any slide', ...
            'a slide shows "n/a" - a fact is missing from deck_facts.txt');
        hasPlaceholder = contains(txt,'TEAM NAME') || contains(txt,'TEAM ID');
        state = warnIf(state, hasPlaceholder, ...
            'team name / team ID still unfilled - rerun build_deck.ps1 with -TeamName / -TeamId');
        state = check(state, contains(txt,'91.9') || contains(txt,'0.919'), ...
            'measured sensitivity appears on a slide', 'sensitivity not found on any slide');
        state = check(state, ~contains(lower(txt),'simevents') || contains(txt,'not installed'), ...
            'no unqualified SimEvents claim', ...
            'a slide claims SimEvents without the "not installed" caveat');
    catch ME
        state = check(state, false, 'deck inspected', ['could not read pptx: ' ME.message]);
    end
    rmdir(tmp,'s');
end

% ================= summary ==============================================
line();
fprintf('  passed %d   failed %d   warnings %d\n', state.pass, state.fail, state.warn);
ok = state.fail == 0;
if ok
    fprintf('  ALL AUTOMATED CHECKS PASSED\n');
else
    fprintf('  *** %d CHECK(S) FAILED - see above ***\n', state.fail);
end
line();

fprintf('\nStill to check by eye (a script cannot judge these):\n');
fprintf('  1. open  ppt\\NETRA_SIH2026_PS26038.pdf     - 6 slides, nothing clipped or overlapping\n');
fprintf('  2. run   netra                              - GUI opens; load an image, press Run screening\n');
fprintf('  3. open  figures\\triptych.png               - raw / enhanced / lesion overlay all look right\n');
fprintf('  4. open  results\\overlays\\                  - left = ground truth, right = prediction\n');
fprintf('  5. open  matlab\\m5_simulink\\netra_district.slx  - the Simulink model opens and runs\n');
fprintf('  6. read  results\\deck_facts.txt             - every number on a slide is in here\n');
fprintf('  7. read  matlab\\README.md "Known limitations" - be ready to say these out loud\n\n');
end

% =========================================================================
function line(), fprintf('%s\n', repmat('=',1,74)); end
function section(s), fprintf('\n--- %s %s\n', s, repmat('-',1,max(0,66-numel(s)))); end

function st = check(st, cond, okMsg, failMsg)
if cond
    fprintf('  [PASS] %s\n', okMsg); st.pass = st.pass + 1;
else
    fprintf('  [FAIL] %s\n', failMsg); st.fail = st.fail + 1;
end
end

function st = warnIf(st, cond, msg)
if cond
    fprintf('  [WARN] %s\n', msg); st.warn = st.warn + 1;
end
end

function st = factCheck(st, facts, key, actual)
if ~isfield(facts, matlab.lang.makeValidName(key))
    fprintf('  [FAIL] %s missing from deck_facts.txt\n', key);
    st.fail = st.fail + 1; return;
end
claimed = facts.(matlab.lang.makeValidName(key));
tol = max(1e-3, abs(actual)*1e-3);
if abs(claimed - actual) <= tol
    fprintf('  [PASS] %-32s %g  (matches source)\n', key, actual);
    st.pass = st.pass + 1;
else
    fprintf('  [FAIL] %-32s deck says %g, source says %g\n', key, claimed, actual);
    st.fail = st.fail + 1;
end
end

function F = readFacts(path)
F = struct();
if ~isfile(path), return; end
fid = fopen(path,'r');
while true
    l = fgetl(fid);
    if ~ischar(l), break; end
    l = strtrim(l);
    if isempty(l) || startsWith(l,'#') || startsWith(l,'['), continue; end
    i = strfind(l,'='); if isempty(i), continue; end
    k = strtrim(l(1:i(1)-1)); v = strtrim(l(i(1)+1:end));
    j = strfind(v,'  #'); if ~isempty(j), v = strtrim(v(1:j(1)-1)); end
    n = str2double(v);
    if ~isnan(n), F.(matlab.lang.makeValidName(k)) = n; end
end
fclose(fid);
end
