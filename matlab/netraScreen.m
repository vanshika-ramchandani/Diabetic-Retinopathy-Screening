function S = netraScreen(imagePath, opts)
%NETRASCREEN  The complete NETRA triage pipeline on one fundus image.
%
%   S = netraScreen(PATH)
%   S = netraScreen(PATH, struct('verbose',true,'gradcam',true))
%
%   Runs, in order:
%     M1  quality gate      - may REJECT with a recapture instruction  (D1)
%     M2  enhancement       - operator-facing view; ENHANCE recovery path
%     M3  lesion evidence   - 5-channel segmentation, native resolution
%     M4a CNN grade         - ResNet-18, ICDR 0-4, with confidence
%     M4b rule grade        - ICDR from counted lesions
%     M4c dual evidence     - agree -> auto-report, disagree -> escalate (D2)
%     M4d Grad-CAM          - attention map for the predicted grade
%
%   The pipeline SHORT-CIRCUITS at M1. That is the whole point of D1: an
%   ungradeable image produces a recapture instruction, not a grade. Every
%   downstream field is left empty so a caller cannot accidentally read a
%   number that was never computed.
%
%   Model input path note: the segmentation net sees applyClahe(retinalCrop(I)),
%   exactly as trained. The richer enhanceFundus output is used for display
%   only - see m2_enhance/enhanceFundus.m.
if nargin < 2, opts = struct; end
if ~isfield(opts,'verbose'), opts.verbose = false; end
if ~isfield(opts,'gradcam'), opts.gradcam = true;  end

here = fileparts(mfilename('fullpath'));
addpath(here, fullfile(here,'lib'), fullfile(here,'m1_quality'), ...
        fullfile(here,'m2_enhance'), fullfile(here,'m4_grade'));
CFG = s00_config();

persistent segNet thr grader qthr
if isempty(segNet)
    A = requireStage(fullfile(CFG.modelDir,'netra_lesion_net.mat'), ...
            's05_train_seg', 'run_all');
    segNet = A.net;
    B = requireStage(fullfile(CFG.modelDir,'thresholds.mat'), ...
            's06_tune_thresholds', 'run_all(6)');
    thr = B.thr;
end
if isempty(qthr)
    f = fullfile(CFG.modelDir,'quality_thresholds.mat');
    if isfile(f), Q = load(f); qthr = Q.thr; else, qthr = []; end
end
if isempty(grader)
    f = fullfile(CFG.modelDir,'netra_grader.mat');
    if isfile(f), G = load(f); grader = G.net; else, grader = []; end
end

tAll = tic;
I0 = imread(imagePath);
if size(I0,3) == 1, I0 = repmat(I0,1,1,3); end
I0 = retinalCrop(I0);

S = struct();
S.imagePath = string(imagePath);
S.image     = I0;

% ================= M1  quality gate ======================================
if isempty(qthr)
    S.quality = struct('decision',"UNCHECKED", 'score',NaN, 'instruction',"", ...
                       'reasons',{{'quality thresholds not calibrated - run s13_calibrate_quality'}}, ...
                       'gradeable',true);
else
    S.quality = assessQuality(I0, qthr);
end
S.decisionPath = "";

if S.quality.decision == "REJECT"
    S.decisionPath   = "REJECTED_AT_QUALITY_GATE";
    S.enhanced       = I0;
    S.masks          = [];
    S.lesionCounts   = [];
    S.ruleGrade      = [];
    S.cnnGrade       = [];
    S.dual           = [];
    S.gradcam        = [];
    S.finalGrade     = NaN;
    S.referable      = NaN;
    S.reportLine     = "NOT GRADED - " + S.quality.instruction;
    S.elapsed        = toc(tAll);
    if opts.verbose, printSummary(S); end
    return;
end

% ================= M2  enhancement =======================================
if S.quality.decision == "ENHANCE"
    S.enhanced = enhanceFundus(I0);
else
    S.enhanced = applyClahe(I0);
end

% ================= M3  lesion evidence ===================================
Inet = applyClahe(I0);                       % the distribution the net was trained on
P = slidingWindowPredict(segNet, Inet, CFG);
odMask = imdilate(P(:,:,5) >= thr(5), strel('disk',15));
M = false(size(P));
for c = 1:CFG.nChan
    B = bwareaopen(P(:,:,c) >= thr(c), CFG.minCompSize(c));
    if c == 3 || c == 4, B = B & ~odMask; end   % the disc is not an exudate
    M(:,:,c) = B;
end
S.masks   = M;
S.prob    = P;
S.overlay = overlayLesions(Inet, M);

retina = retinalMask(I0);
RG = ruleGradeICDR(M, retina);
S.ruleGrade    = RG;
S.lesionCounts = RG.counts;

% ================= M4a  CNN grade ========================================
if isempty(grader)
    S.cnnGrade = struct('grade',NaN,'prob',nan(1,5),'confidence',NaN, ...
                        'available',false, ...
                        'note',"grader not trained - run s11_train_grader");
    S.dual = [];
    S.finalGrade = RG.grade;
    S.referable  = RG.referable;
    S.decisionPath = "LESION_RULES_ONLY";
else
    X  = dlarray(single(normaliseInput(imresize(Inet,[CFG.graderSize CFG.graderSize]),CFG)),'SSCB');
    sc = double(extractdata(predict(grader, X)));
    sc = sc(:)';
    [conf, gi] = max(sc);
    S.cnnGrade = struct('grade',gi-1,'prob',sc,'confidence',conf,'available',true, ...
                        'referableProb',sum(sc(CFG.referableFrom+1:end)),'note',"");

    % ============= M4c  dual evidence ====================================
    D = dualEvidence(gi-1, sc, RG, struct('referableFrom',CFG.referableFrom));
    S.dual         = D;
    S.finalGrade   = D.finalGrade;
    S.referable    = D.referable;
    S.decisionPath = D.decision;

    % ============= M4d  Grad-CAM =========================================
    if opts.gradcam
        try
            cam = rescale(extractdata(gradCAM(grader, X, gi)));
            S.gradcam = imresize(cam, [size(I0,1) size(I0,2)]);
        catch ME
            S.gradcam = [];
            S.gradcamError = string(ME.message);
        end
    else
        S.gradcam = [];
    end
end

names = ["No DR","Mild NPDR","Moderate NPDR","Severe NPDR","PDR"];
S.finalGradeName = names(min(max(S.finalGrade,0),4) + 1);
if S.referable
    S.reportLine = sprintf('REFERABLE - %s (ICDR %d)', S.finalGradeName, S.finalGrade);
else
    S.reportLine = sprintf('not referable - %s (ICDR %d)', S.finalGradeName, S.finalGrade);
end
S.elapsed = toc(tAll);
if opts.verbose, printSummary(S); end
end

% =========================================================================
function printSummary(S)
fprintf('\n---------------------------------------------------------------\n');
fprintf(' NETRA screening report\n');
fprintf('---------------------------------------------------------------\n');
fprintf(' image        : %s\n', S.imagePath);
fprintf(' quality      : %s (score %d/100)\n', S.quality.decision, S.quality.score);
if ~isempty(S.quality.reasons)
    for i = 1:numel(S.quality.reasons)
        fprintf('                - %s\n', string(S.quality.reasons{i}));
    end
end
if S.decisionPath == "REJECTED_AT_QUALITY_GATE"
    fprintf(' ACTION       : %s\n', S.quality.instruction);
    fprintf(' no grade was produced - by design\n');
    fprintf('---------------------------------------------------------------\n');
    return;
end
c = S.lesionCounts;
fprintf(' lesions      : MA %d | HE %d | EX %d | SE %d\n', c.MA, c.HE, c.EX, c.SE);
fprintf(' rule grade   : %d (%s)\n', S.ruleGrade.grade, S.ruleGrade.gradeName);
fprintf('                %s\n', S.ruleGrade.rationale);
if S.cnnGrade.available
    fprintf(' CNN grade    : %d (confidence %.2f)\n', S.cnnGrade.grade, S.cnnGrade.confidence);
    fprintf(' dual check   : %s\n', S.dual.decision);
    for i = 1:numel(S.dual.reasons)
        fprintf('                - %s\n', S.dual.reasons(i));
    end
else
    fprintf(' CNN grade    : unavailable (%s)\n', S.cnnGrade.note);
end
fprintf(' RESULT       : %s\n', S.reportLine);
fprintf(' elapsed      : %.1f s\n', S.elapsed);
fprintf('---------------------------------------------------------------\n');
end
