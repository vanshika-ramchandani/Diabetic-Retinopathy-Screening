function P = slidingWindowPredict(net, I, CFG)
%SLIDINGWINDOWPREDICT  Full-resolution probability map by tiled inference.
%   Windows overlap by CFG.stride and are blended with a Hann taper so tile
%   seams do not appear as edges in the probability map.
ps = CFG.patchSize; st = CFG.stride;
[H,W,~] = size(I);
Hp = max(H,ps); Wp = max(W,ps);
if Hp > H || Wp > W, I(Hp,Wp,3) = 0; end

rs = unique([1:st:max(Hp-ps+1,1), max(Hp-ps+1,1)]);
cs = unique([1:st:max(Wp-ps+1,1), max(Wp-ps+1,1)]);

% Hann taper, written out rather than calling hann() - that needs the Signal
% Processing Toolbox, which is not installed here.
w1  = 0.5*(1 - cos(2*pi*(0:ps-1)'/(ps-1)));
w2d = single(w1*w1') + 1e-3;

acc  = zeros(Hp,Wp,CFG.nChan,'single');
wacc = zeros(Hp,Wp,'single');

[RR,CC] = meshgrid(rs,cs);
starts  = [RR(:) CC(:)];
B = 8;

for k = 1:B:size(starts,1)
    idx = k:min(k+B-1, size(starts,1));
    X = zeros(ps,ps,3,numel(idx),'single');
    for j = 1:numel(idx)
        r = starts(idx(j),1); c = starts(idx(j),2);
        X(:,:,:,j) = normaliseInput(I(r:r+ps-1, c:c+ps-1, :), CFG);
    end
    Y = extractdata(predict(net, dlarray(gpuArray(X),'SSCB')));
    Y = gather(Y);
    for j = 1:numel(idx)
        r = starts(idx(j),1); c = starts(idx(j),2);
        acc(r:r+ps-1, c:c+ps-1, :) = acc(r:r+ps-1, c:c+ps-1, :) + Y(:,:,:,j).*w2d;
        wacc(r:r+ps-1, c:c+ps-1)   = wacc(r:r+ps-1, c:c+ps-1) + w2d;
    end
end

P = acc ./ max(wacc, 1e-6);
P = P(1:H, 1:W, :);
end
