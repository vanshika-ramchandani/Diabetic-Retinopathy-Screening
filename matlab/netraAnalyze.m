function S = netraAnalyze(image, opts)
%NETRAANALYZE  The live-prototype contract: one photo, our two models.
%
%   S = netraAnalyze('path\to\fundus.jpg')
%   S = netraAnalyze(I)                     I is HxWx3 uint8 already in memory
%   S = netraAnalyze(..., struct('gradcam',false))
%
%   Model 1 - DR assessment
%     lesions   netra_lesion_net.mat   IDRiD, 5 channels  -> masks, counts, rule grade
%     grader    netra_grader.mat       ResNet-18, APTOS   -> ICDR grade, confidence, Grad-CAM
%   Model 2 - retinal structure
%     vessels   netra_vessel_net.mat   DRIVE, 1 channel   -> vessel tree
%
%   Each network reads the photo itself, never another network's output.
%   The lesion net and the grader share one PREPROCESSING step (retinal crop +
%   CLAHE, the distribution both were trained on) - that is input
%   normalisation, not one model reading another's answer.
%
%   Two checks sit outside the networks:
%     before  quality gate  - REJECT short-circuits; nothing is graded   (D1)
%     after   dual evidence - grader vs lesion-rule grade               (D2)
%
%   Grader input is the exact path it was trained and measured on
%   (s01_cache_aptos -> s11/s12): crop -> CLAHE -> 512x512 -> 384x384 ->
%   ImageNet normalisation. Referable = P(grade >= 2) >= the operating point
%   s12 fitted on validation (results/grader_metrics.mat), NOT the argmax,
%   because that threshold is what the quoted sens/spec were measured at.
%
%   This is also the reference the Python web app (web/) is parity-tested
%   against: s26_golden_refs saves its intermediates.
if nargin < 2, opts = struct; end
if ~isfield(opts,'gradcam'), opts.gradcam = true; end

here = fileparts(mfilename('fullpath'));
addpath(here, fullfile(here,'lib'), fullfile(here,'m1_quality'), ...
        fullfile(here,'m4_grade'), fullfile(here,'m6_vessels'));
CFG = s00_config();

persistent segNet thr qthr grader gThr
if isempty(segNet)
    A = requireStage(fullfile(CFG.modelDir,CFG.lesionNetFile),'s05_train_seg / s29_finetune_lesion','run_all');
    B = requireStage(fullfile(CFG.modelDir,CFG.lesionThrFile),'s06_tune_thresholds / s29_finetune_lesion','run_all(6)');
    Q = requireStage(fullfile(CFG.modelDir,'quality_thresholds.mat'),'s13_calibrate_quality','s13_calibrate_quality');
    G = requireStage(fullfile(CFG.modelDir,'netra_grader.mat'),'s11_train_grader','s11_train_grader');
    M = requireStage(fullfile(CFG.resultDir,'grader_metrics.mat'),'s12_eval_grader','s12_eval_grader');
    segNet = A.net; thr = B.thr; qthr = Q.thr; grader = G.net; gThr = M.R.threshold;
end

tAll = tic;
if ischar(image) || isstring(image)
    S.imagePath = string(image); Iraw = imread(image);
else
    S.imagePath = ""; Iraw = image;
end
if size(Iraw,3) == 1, Iraw = repmat(Iraw,1,1,3); end
[I0, bbox] = retinalCrop(Iraw);
S.image = I0; S.bbox = bbox;
S.timing = struct();

% ================= quality gate (before the models) ======================
t = tic;
S.quality = assessQuality(I0, qthr);
S.timing.quality = toc(t);
if S.quality.decision == "REJECT"
    S.decisionPath = "REJECTED_AT_QUALITY_GATE";
    S.lesions = []; S.vessels = []; S.grader = []; S.ruleGrade = []; S.dual = [];
    S.referable = NaN; S.finalGrade = NaN;
    S.reportLine = "NOT GRADED - " + S.quality.instruction;
    S.elapsed = toc(tAll);
    return
end

% shared input normalisation for the lesion net and the grader
t = tic;
Inet = applyClahe(I0);
S.timing.clahe = toc(t);

% ================= model 1a: lesions =====================================
t = tic;
P = slidingWindowPredict(segNet, Inet, CFG);
odMask = imdilate(P(:,:,5) >= thr(5), strel('disk',15));
M = false(size(P));
for c = 1:CFG.nChan
    Bc = bwareaopen(P(:,:,c) >= thr(c), CFG.minCompSize(c));
    if c == 3 || c == 4, Bc = Bc & ~odMask; end
    M(:,:,c) = Bc;
end
RG = ruleGradeICDR(M, retinalMask(I0));
S.lesions = struct('clahe',Inet, 'prob',P, 'masks',M, 'counts',RG.counts, ...
                   'overlay',overlayLesions(I0, M));
S.ruleGrade = RG;
S.timing.lesions = toc(t);

% ================= model 1b: ResNet-18 grader + Grad-CAM =================
t = tic;
x  = imresize(imresize(Inet, [CFG.aptosSize CFG.aptosSize]), [CFG.graderSize CFG.graderSize]);
X  = dlarray(single(normaliseInput(x, CFG)), 'SSCB');
p  = double(gather(extractdata(predict(grader, X))));  p = p(:)';
[conf, gi] = max(p);
refProb = sum(p(CFG.referableFrom+1:end));
Gr = struct('grade',gi-1, 'prob',p, 'confidence',conf, 'referableProb',refProb, ...
            'referable',refProb >= gThr, 'threshold',gThr, 'input',x, 'cam',[]);
if opts.gradcam
    cam = gradCAM(grader, X, gi);
    if isa(cam,'dlarray'), cam = extractdata(cam); end
    Gr.cam = double(gather(cam));
end
S.grader = Gr;
S.timing.grader = toc(t);

% ================= model 2: vessels ======================================
t = tic;
S.vessels = segmentVessels(I0);
S.timing.vessels = toc(t);

% ================= dual evidence (after the models) ======================
D = dualEvidence(Gr.grade, p, RG, struct('referableFrom',CFG.referableFrom, ...
                                          'cnnReferable',Gr.referable));
S.dual = D;
S.decisionPath = D.decision;
S.finalGrade = D.finalGrade;
S.referable  = D.referable || (D.decision == "ESCALATE" && (Gr.referable || RG.referable));
names = ["No DR","Mild NPDR","Moderate NPDR","Severe NPDR","PDR"];
S.finalGradeName = names(S.finalGrade + 1);
if D.decision == "ESCALATE"
    S.reportLine = sprintf('ESCALATE - ophthalmologist review (grader %d, lesion rules %d)', ...
                           Gr.grade, RG.grade);
elseif S.referable
    S.reportLine = sprintf('REFERABLE - %s (ICDR %d)', S.finalGradeName, S.finalGrade);
else
    S.reportLine = sprintf('not referable - %s (ICDR %d)', S.finalGradeName, S.finalGrade);
end
S.elapsed = toc(tAll);
end
