function [ap, bestF1, bestThr, prec, rec] = prCurveFinish(A)
%PRCURVEFINISH  Average precision + best-F1 threshold from accumulated bins.
tp = flipud(cumsum(flipud(A.pos)));      % predicted positive at thr >= bin
fp = flipud(cumsum(flipud(A.neg)));
P  = sum(A.pos);
prec = tp ./ max(tp+fp, 1);
rec  = tp ./ max(P, 1);
prec(tp+fp == 0) = 1;

[rec, o] = sort(rec); prec = prec(o);
ap = trapz(rec, prec);
if isnan(ap), ap = 0; end

f1 = 2*prec.*rec ./ max(prec+rec, eps);
[bestF1, i] = max(f1);
thr = ((1:A.nBins)'-1)/A.nBins;
thr = thr(o);
bestThr = thr(i);
end
