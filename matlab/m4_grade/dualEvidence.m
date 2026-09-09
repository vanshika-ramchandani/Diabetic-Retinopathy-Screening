function D = dualEvidence(cnnGrade, cnnProb, ruleG, opts)
%DUALEVIDENCE  Cross-check the CNN grade against lesion evidence - D2.
%
%   D = dualEvidence(CNNGRADE, CNNPROB, RULEG)
%     CNNGRADE  0-4 integer from the ResNet-18 grader
%     CNNPROB   1x5 posterior over grades 0-4
%     RULEG     struct from ruleGradeICDR
%
%   Why this exists. A Grad-CAM heatmap is not a safety mechanism - it is a
%   picture that a clinician cannot falsify. Two independent estimators that
%   must agree IS a safety mechanism: when a CNN trained on image-level labels
%   and a rule reading counted lesions disagree, something is wrong with one
%   of them, and that is precisely the case a human should see.
%
%   The escalation is deliberately asymmetric. Disagreement about WHETHER a
%   patient is referable escalates always; disagreement about severity within
%   the same referable class is tolerated by one level, because the scale's
%   own inter-grader agreement is not better than that.
if nargin < 4, opts = struct; end
if ~isfield(opts,'confMin'),    opts.confMin    = 0.60; end
if ~isfield(opts,'gradeTol'),   opts.gradeTol   = 1;    end
if ~isfield(opts,'referableFrom'), opts.referableFrom = 2; end

cnnProb   = cnnProb(:)';
cnnConf   = max(cnnProb);
cnnRefer  = cnnGrade >= opts.referableFrom;
ruleRefer = ruleG.referable;
delta     = abs(double(cnnGrade) - double(ruleG.grade));

reasons = strings(0);
escalate = false;

if cnnRefer ~= ruleRefer
    escalate = true;
    reasons(end+1) = sprintf(['referable-status conflict: CNN says %s, lesion rules say %s ' ...
        '- this is the disagreement that changes patient management'], ...
        tf(cnnRefer), tf(ruleRefer));
end
if delta > opts.gradeTol
    escalate = true;
    reasons(end+1) = sprintf('grade gap of %d levels (CNN %d vs rules %d), tolerance is %d', ...
        delta, cnnGrade, ruleG.grade, opts.gradeTol);
end
if cnnConf < opts.confMin
    escalate = true;
    reasons(end+1) = sprintf('CNN confidence %.2f below %.2f', cnnConf, opts.confMin);
end
if ruleG.rule421
    reasons(end+1) = "4-2-1 severe-NPDR criterion met on lesion counts";
end

% Conservative fusion: when the two disagree, the higher grade carries.
% Under-calling referable DR costs sight; over-calling costs one review.
if escalate
    D.decision   = "ESCALATE";
    D.finalGrade = max(double(cnnGrade), double(ruleG.grade));
    D.action     = "route to ophthalmologist for manual review";
else
    D.decision   = "AUTO_REPORT";
    D.finalGrade = double(cnnGrade);
    D.action     = "auto-generate report";
    reasons(end+1) = sprintf('CNN and lesion rules agree (%d vs %d), confidence %.2f', ...
        cnnGrade, ruleG.grade, cnnConf);
end

D.agree        = ~escalate;
D.cnnGrade     = double(cnnGrade);
D.ruleGrade    = double(ruleG.grade);
D.cnnConf      = cnnConf;
D.cnnReferable = cnnRefer;
D.ruleReferable= ruleRefer;
D.referable    = D.finalGrade >= opts.referableFrom;
D.reasons      = reasons;
D.pdrCaveat    = ~ruleG.pdrDetectable;
end

function s = tf(b)
if b, s = "REFERABLE"; else, s = "not referable"; end
end
