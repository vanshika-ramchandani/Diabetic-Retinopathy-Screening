function Lval = vesselLoss(Y, T)
%VESSELLOSS  Tversky + BCE for vessels, evaluated INSIDE the field of view.
%   Y : HxWx1xB sigmoid predictions.
%   T : HxWx2xB, channel 1 = vessel label, channel 2 = FOV mask.
%
%   Two things make this different from netraLoss:
%
%   1) Vessels occupy ~8.6% of the field - two orders of magnitude commoner
%      than microaneurysms (0.057%). netraLoss up-weights the positive BCE
%      term by 1/prevalence, which would put a weight of ~12 on vessels and
%      buy recall at a precision cost the class imbalance does not justify.
%      Tversky alone carries the imbalance here; BCE goes in unweighted.
%
%   2) Everything outside the FOV is black frame labelled 0. Scoring it would
%      let the model bank a huge, trivial true-negative mass and flatter the
%      loss without learning anything, so it is masked out of BOTH terms.
alpha = 0.4; beta = 0.6; bceW = 0.5; eps0 = 1;

Y = max(min(Y, 1-1e-6), 1e-6);
t = T(:,:,1,:);
m = T(:,:,2,:);           % 1 inside the field, 0 outside

tp = sum(m.*Y.*t,       [1 2 4]);
fp = sum(m.*Y.*(1-t),   [1 2 4]);
fn = sum(m.*(1-Y).*t,   [1 2 4]);
tversky = (tp + eps0) ./ (tp + alpha*fp + beta*fn + eps0);

bce = -sum(m .* (t.*log(Y) + (1-t).*log(1-Y)), [1 2 4]) ./ max(sum(m,[1 2 4]), 1);

Lval = (1 - tversky) + bceW*bce;
end
