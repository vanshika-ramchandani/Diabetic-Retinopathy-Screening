function ds = vesselDatastore(split, CFG, doAug, idx)
%VESSELDATASTORE  Paired image / (label,FOV) datastore over the vessel patches.
%   Mirrors patchDatastore, but the target is HxWx2 - vessel label in channel 1
%   and FOV in channel 2 - because vesselLoss has to know which pixels are
%   actually retina. Explicit index-matched file lists guarantee img_k pairs
%   with lab_k and fov_k.
if nargin < 3, doAug = false; end
d = fullfile(CFG.vesselCache, split);
n = numel(dir(fullfile(d,'img_*.png')));
assert(n > 0, 'no vessel patches in %s - run s19_cache_vessels first', d);
if nargin < 4 || isempty(idx), idx = 1:n; end

fi = arrayfun(@(k) string(fullfile(d,sprintf('img_%05d.png',k))), idx);
fl = arrayfun(@(k) string(fullfile(d,sprintf('lab_%05d.png',k))), idx);
ff = arrayfun(@(k) string(fullfile(d,sprintf('fov_%05d.png',k))), idx);
assert(all(isfile(fi)) && all(isfile(fl)) && all(isfile(ff)), ...
       'vessel patch cache is incomplete');

cds = combine(imageDatastore(fi), imageDatastore(fl), imageDatastore(ff));
ds  = transform(cds, @(data) augmentVesselPair(data, CFG, doAug));
end

% -------------------------------------------------------------------------
function out = augmentVesselPair(data, CFG, doAug)
I = data{1};
L = data{2} > 0;
F = data{3} > 0;

if doAug
    % Geometric ops must hit image, label and FOV identically or the mask
    % stops describing the image it is masking.
    if rand > 0.5, I = fliplr(I); L = fliplr(L); F = fliplr(F); end
    if rand > 0.5, I = flipud(I); L = flipud(L); F = flipud(F); end
    k = randi(4)-1;
    if k > 0, I = rot90(I,k); L = rot90(L,k); F = rot90(F,k); end
    if rand > 0.5   % photometric jitter on the image only
        I = im2uint8(min(max(single(I)/255 * (0.85+0.3*rand) + (rand-0.5)*0.08, 0), 1));
    end
end

out = {normaliseInput(I, CFG), single(cat(3, L, F))};
end
