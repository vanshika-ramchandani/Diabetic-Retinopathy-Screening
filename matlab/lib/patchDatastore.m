function ds = patchDatastore(split, CFG, doAug, idx)
%PATCHDATASTORE  Paired image/mask datastore over the cached patches.
%   Explicit index-matched file lists guarantee img_k pairs with lab_k.
%   IDX optionally restricts to a subset (used by the overfit test).
if nargin < 3, doAug = false; end
d = fullfile(CFG.patchCache, split);
n = numel(dir(fullfile(d,'img_*.png')));
assert(n > 0, 'no patches in %s - run s02_cache_patches first', d);
if nargin < 4 || isempty(idx), idx = 1:n; end

fi = arrayfun(@(k) string(fullfile(d,sprintf('img_%05d.png',k))), idx);
fl = arrayfun(@(k) string(fullfile(d,sprintf('lab_%05d.png',k))), idx);
assert(all(isfile(fi)) && all(isfile(fl)), 'patch cache is incomplete');

cds = combine(imageDatastore(fi), imageDatastore(fl));
ds  = transform(cds, @(data) augmentPair(data, CFG, doAug));
end

% -------------------------------------------------------------------------
function out = augmentPair(data, CFG, doAug)
I = data{1};
M = unpackMasks(data{2}, CFG.nChan);

if doAug
    if rand > 0.5, I = fliplr(I); M = fliplr(M); end
    if rand > 0.5, I = flipud(I); M = flipud(M); end
    k = randi(4)-1;
    if k > 0, I = rot90(I,k); M = rot90(M,k); end
    if rand > 0.5   % photometric jitter on the image only
        I = im2uint8(min(max(single(I)/255 * (0.85+0.3*rand) + (rand-0.5)*0.08, 0), 1));
    end
end

out = {normaliseInput(I, CFG), single(M)};
end
