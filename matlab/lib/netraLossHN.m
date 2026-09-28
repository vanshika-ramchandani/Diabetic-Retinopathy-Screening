function L = netraLossHN(Y, T)
%NETRALOSSHN  netraLoss with an "unlabelled optic disc" mask - for s29.
%   Y : HxWx5xB sigmoid predictions.
%   T : HxWx6xB. Channels 1-5 are the targets exactly as in netraLoss;
%       channel 6 is 1 where the optic-disc label is UNKNOWN (healthy APTOS
%       patches, which have no disc masks) and 0 where it is real (IDRiD).
%   Channels 1-4 are fully supervised on every patch: an all-empty lesion
%   target on a healthy eye is the whole point. Channel 5 is supervised only
%   where its label exists, so the disc channel is not taught "no disc here".
%   With channel 6 all zero this is numerically identical to netraLoss.
alpha = 0.3; beta = 0.7; gamma = 0.75; bceW = 0.5; eps0 = 1;
w = single([3.0 1.5 1.0 1.5 0.5]);
Y = max(min(Y, 1-1e-6), 1e-6);
valid = 1 - T(:,:,6,:);
L = 0;
for c = 1:5
    yc = Y(:,:,c,:);  tc = T(:,:,c,:);
    if c == 5, v = valid; else, v = ones(size(tc), 'like', tc); end
    nv = max(sum(v,[1 2 4]), 1);
    tp = sum(v.*yc.*tc,       [1 2 4]);
    fp = sum(v.*yc.*(1-tc),   [1 2 4]);
    fn = sum(v.*(1-yc).*tc,   [1 2 4]);
    tv = (tp + eps0) ./ (tp + alpha*fp + beta*fn + eps0);
    focalTversky = (1 - tv).^gamma;
    posFrac = sum(v.*tc,[1 2 4]) ./ nv;
    posW    = min(1./max(posFrac,1e-6), 200);
    bce = -sum(v.*(posW.*tc.*log(yc) + (1-tc).*log(1-yc)), [1 2 4]) ./ nv;
    L = L + w(c) * (focalTversky + bceW*bce);
end
end
