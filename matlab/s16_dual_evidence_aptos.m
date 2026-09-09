function s16_dual_evidence_aptos(limit)
%S16_DUAL_EVIDENCE_APTOS  Measure D2 in-domain, on the sealed APTOS test split.
%
%   WHY THIS EXISTS.
%   s14 measures the escalation rate on the 27 IDRiD test images, and gets
%   48%. That number is real but it is not a screening population: IDRiD is
%   100% diseased and comes from a different camera, so it measures the
%   dual-evidence check under domain shift. Driving a district-scale model
%   with it would be wrong in both directions - unrepresentative class mix
%   AND unrepresentative image statistics.
%
%   This script measures the same check on the sealed APTOS test split, which
%   is the population the grader was actually trained for, and reports the one
%   number that says whether D2 earns its place:
%
%       of the CNN's referable-status ERRORS, what fraction did the
%       dual-evidence check escalate instead of auto-reporting?
%
%   A safety mechanism that does not catch the model's mistakes is decoration.
%
%   PREPROCESSING NOTE. The cached APTOS PNGs are already retinalCrop + CLAHE
%   at 512px (s01_cache_aptos), which is exactly the distribution both networks
%   were trained on. They are therefore fed to the nets AS-IS. Re-applying
%   applyClahe here would double-enhance and silently shift the input.
here = fileparts(mfilename('fullpath'));
addpath(here, fullfile(here,'lib'), fullfile(here,'m1_quality'), ...
        fullfile(here,'m4_grade'));
CFG = s00_config(); rng(CFG.seed);

A = requireStage(fullfile(CFG.modelDir,'netra_lesion_net.mat'),'s05_train_seg','run_all');
B = requireStage(fullfile(CFG.modelDir,'thresholds.mat'),'s06_tune_thresholds','run_all(6)');
G = requireStage(fullfile(CFG.modelDir,'netra_grader.mat'),'s11_train_grader','s11_train_grader');
S = requireStage(fullfile(CFG.modelDir,'grader_split.mat'),'s11_train_grader','s11_train_grader');
segNet = A.net; thr = B.thr; grader = G.net; split = S.split;

files = split.files(split.isTest);
y     = double(split.y(split.isTest)) - 1;
if nargin >= 1 && ~isempty(limit) && limit < numel(files)
    files = files(1:limit); y = y(1:limit);
end
n = numel(files);
fprintf('dual-evidence on %d sealed APTOS test images\n', n);

cnnG = zeros(n,1); ruleG = zeros(n,1); conf = zeros(n,1);
esc  = false(n,1); finalG = zeros(n,1);
t0 = tic;
for i = 1:n
    I = imread(files(i));                       % already cropped + CLAHE at 512
    if size(I,3)==1, I = repmat(I,1,1,3); end

    % ---- lesion evidence -------------------------------------------------
    P = slidingWindowPredict(segNet, I, CFG);
    od = imdilate(P(:,:,5) >= thr(5), strel('disk',15));
    M = false(size(P));
    for c = 1:CFG.nChan
        Bc = bwareaopen(P(:,:,c) >= thr(c), CFG.minCompSize(c));
        if c == 3 || c == 4, Bc = Bc & ~od; end
        M(:,:,c) = Bc;
    end
    RG = ruleGradeICDR(M, retinalMask(I));

    % ---- CNN grade -------------------------------------------------------
    X  = dlarray(single(normaliseInput(imresize(I,[CFG.graderSize CFG.graderSize]),CFG)),'SSCB');
    sc = double(extractdata(predict(grader,X))); sc = sc(:)';
    [c1, gi] = max(sc);

    D = dualEvidence(gi-1, sc, RG, struct('referableFrom',CFG.referableFrom));
    cnnG(i) = gi-1; ruleG(i) = RG.grade; conf(i) = c1;
    esc(i) = ~D.agree; finalG(i) = D.finalGrade;

    if mod(i,50)==0, fprintf('  %d/%d  (%.1f min)\n', i, n, toc(t0)/60); end
end
fprintf('done in %.1f min\n\n', toc(t0)/60);

ref      = y      >= CFG.referableFrom;      % ground truth
cnnRef   = cnnG   >= CFG.referableFrom;      % CNN alone
finalRef = finalG >= CFG.referableFrom;      % after conservative fusion

cnnWrong = cnnRef ~= ref;
caught   = cnnWrong & esc;

fprintf('=====================================================================\n');
fprintf('  DUAL-EVIDENCE (D2) ON THE SEALED APTOS TEST SPLIT, n = %d\n', n);
fprintf('=====================================================================\n');
fprintf('  escalation rate            %.4f  (%d of %d)\n', mean(esc), nnz(esc), n);
fprintf('  agreement rate             %.4f\n', 1-mean(esc));
fprintf('\n  CNN referable errors       %d\n', nnz(cnnWrong));
fprintf('  ...of which escalated      %d  (%.1f%%)   <- D2 catches these\n', ...
        nnz(caught), 100*nnz(caught)/max(nnz(cnnWrong),1));
fprintf('  ...auto-reported wrong     %d  (%.1f%%)\n', ...
        nnz(cnnWrong & ~esc), 100*nnz(cnnWrong & ~esc)/max(nnz(cnnWrong),1));

% Missed referable cases are the ones that cost sight.
cnnMiss   = ref & ~cnnRef;
finalMiss = ref & ~finalRef & ~esc;
fprintf('\n  referable cases missed by CNN alone        %d\n', nnz(cnnMiss));
fprintf('  still missed AND auto-reported after D2    %d\n', nnz(finalMiss));
fprintf('=====================================================================\n');

R = struct('n',n,'escalationRate',mean(esc),'agreementRate',1-mean(esc), ...
   'cnnErrors',nnz(cnnWrong),'errorsCaught',nnz(caught), ...
   'catchRate',nnz(caught)/max(nnz(cnnWrong),1), ...
   'cnnMissed',nnz(cnnMiss),'missedAfterD2',nnz(finalMiss), ...
   'meanConfidence',mean(conf));
save(fullfile(CFG.resultDir,'dual_evidence_aptos.mat'),'R','cnnG','ruleG','y','esc','conf','-v7');

T = table(files(:), y(:), cnnG, ruleG, conf, esc, finalG, ...
    'VariableNames',{'File','TrueGrade','CnnGrade','RuleGrade','Confidence','Escalated','FinalGrade'});
writetable(T, fullfile(CFG.resultDir,'dual_evidence_aptos.csv'));
fprintf('wrote results/dual_evidence_aptos.csv\n');
end
