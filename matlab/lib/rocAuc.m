function a = rocAuc(scores, labels)
%ROCAUC  Area under the ROC curve via the Mann-Whitney U statistic.
%   Returns NaN when only one class is present - which is the honest answer,
%   not 0.5. IDRiD's image-level haemorrhage label is exactly this case.
labels = logical(labels(:));
scores = double(scores(:));
np = nnz(labels); nn = numel(labels) - np;
if np == 0 || nn == 0, a = NaN; return; end
% Rank across the COMBINED set, then sum the ranks of the positives.
% Ranking scores(labels) alone is wrong: that sum is always np*(np+1)/2,
% which drives the statistic to exactly 0 regardless of the model.
r = tiedrank(scores);
a = (sum(r(labels)) - np*(np+1)/2) / (np*nn);
end
