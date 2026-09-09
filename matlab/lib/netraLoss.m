function L = netraLoss(Y, T)
%NETRALOSS  Focal Tversky + weighted BCE, summed over channels.
%   Y : HxWxCxB sigmoid predictions.  T : HxWxCxB targets in {0,1}.
%   beta>alpha penalises false negatives harder - required when the target
%   class occupies 0.057% of pixels (microaneurysms).
alpha = 0.3; beta = 0.7; gamma = 0.75; bceW = 0.5; eps0 = 1;
w = single([3.0 1.5 1.0 1.5 0.5]);

Y = max(min(Y, 1-1e-6), 1e-6);
C = size(Y,3);
L = 0;

for c = 1:C
    yc = Y(:,:,c,:);  tc = T(:,:,c,:);

    tp = sum(yc.*tc,       [1 2 4]);
    fp = sum(yc.*(1-tc),   [1 2 4]);
    fn = sum((1-yc).*tc,   [1 2 4]);
    tv = (tp + eps0) ./ (tp + alpha*fp + beta*fn + eps0);
    focalTversky = (1 - tv).^gamma;

    % positive-weighted BCE: rare class up-weighted by its own scarcity
    posFrac = sum(tc,[1 2 4]) ./ numel(tc);
    posW    = min(1./max(posFrac,1e-6), 200);
    bce = -mean(posW.*tc.*log(yc) + (1-tc).*log(1-yc), [1 2 4]);

    L = L + w(c) * (focalTversky + bceW*bce);
end
end
