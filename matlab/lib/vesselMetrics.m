function M = vesselMetrics(prob, L, F, thr)
%VESSELMETRICS  Vessel scores computed strictly inside the field of view.
%   M = vesselMetrics(PROB, L, F, THR)
%     PROB  HxW single, sigmoid probability of vessel
%     L     HxW logical ground truth
%     F     HxW logical field of view
%     THR   scalar decision threshold
%
%   Only pixels with F true are counted. Outside the field the frame is black
%   and labelled 0, so including it would add ~34.5% of the frame as free true
%   negatives - which is why DRIVE results are conventionally quoted inside the
%   FOV, and why a number scored over the whole rectangle is not comparable to
%   anything in the literature.
p = prob(F);
t = L(F);
d = p >= thr;

tp = sum( d &  t);  fp = sum( d & ~t);
fn = sum(~d &  t);  tn = sum(~d & ~t);

M.tp = tp; M.fp = fp; M.fn = fn; M.tn = tn;
M.sensitivity = tp / max(tp+fn, 1);
M.specificity = tn / max(tn+fp, 1);
M.precision   = tp / max(tp+fp, 1);
M.accuracy    = (tp+tn) / max(tp+tn+fp+fn, 1);
M.dice        = 2*tp / max(2*tp+fp+fn, 1);
M.iou         = tp / max(tp+fp+fn, 1);
% Balanced over the two classes - the honest headline when 91% of the field
% is background even after the frame is excluded.
M.gmean       = sqrt(M.sensitivity * M.specificity);
M.auc         = rocAuc(double(p), double(t));   % rocAuc(scores, labels)
end
