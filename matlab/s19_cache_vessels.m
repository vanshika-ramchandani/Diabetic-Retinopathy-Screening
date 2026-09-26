function s19_cache_vessels()
%S19_CACHE_VESSELS  Split DRIVE, derive FOV masks, and cache training patches.
%
%   SPLIT DISCIPLINE - the point of this stage.
%   DRIVE ships 40 images: 21..40 as the official training set and 01..20 as
%   the official test set (the _manual1 suffix is the giveaway). Tuning a
%   threshold on 01..20 would leave this track with no held-out data at all,
%   so those 20 stay SEALED and the 4 validation images are carved out of the
%   20 training images instead. The chosen ids are written to models/
%   vessel_split.mat so s20 and s21 cannot silently disagree about them.
addpath(fullfile(fileparts(mfilename('fullpath')),'lib'));
CFG = s00_config();
rng(CFG.seed);

assert(isfolder(CFG.driveRoot), 'data/drive not found - expected DRIVE at %s', CFG.driveRoot);

ids   = CFG.driveTrainIds;
perm  = ids(randperm(numel(ids)));
valId = sort(perm(1:CFG.driveValN));
fitId = sort(perm(CFG.driveValN+1:end));

fprintf('DRIVE split (seed %d)\n', CFG.seed);
fprintf('  fit   %2d images: %s\n', numel(fitId), mat2str(fitId));
fprintf('  val   %2d images: %s\n', numel(valId), mat2str(valId));
fprintf('  test  %2d images: %s  [SEALED until s21]\n', ...
        numel(CFG.driveTestIds), mat2str(CFG.driveTestIds));

assert(isempty(intersect(fitId, valId)), 'fit/val overlap');
assert(isempty(intersect([fitId valId], CFG.driveTestIds)), 'train/test overlap');

save(fullfile(CFG.modelDir,'vessel_split.mat'), 'fitId','valId','CFG');

nFit = cachePatches(fitId, 'train', CFG);
nVal = cachePatches(valId, 'val',   CFG);
fprintf('\ncached %d train patches, %d val patches -> %s\n', nFit, nVal, CFG.vesselCache);
end

% -------------------------------------------------------------------------
function n = cachePatches(ids, split, CFG)
d = fullfile(CFG.vesselCache, split);
if isfolder(d), rmdir(d,'s'); end
mkdir(d);

ps = CFG.vesselSize;
n  = 0;
fracs = [];

for id = ids
    [I, L, F] = readDriveSample(id, CFG);
    [H, W, ~] = size(I);

    kept = 0; tries = 0;
    while kept < CFG.vesselPatchesPerImage && tries < CFG.vesselPatchesPerImage*20
        tries = tries + 1;
        r = randi(H - ps + 1);
        c = randi(W - ps + 1);
        Fp = F(r:r+ps-1, c:c+ps-1);
        % A crop that is mostly black frame teaches the net almost nothing and
        % skews the prevalence it sees, so it is thrown away.
        if mean(Fp(:)) < CFG.vesselMinFov, continue; end

        n = n + 1; kept = kept + 1;
        Ip = I(r:r+ps-1, c:c+ps-1, :);
        Lp = L(r:r+ps-1, c:c+ps-1);

        imwrite(Ip,            fullfile(d, sprintf('img_%05d.png', n)));
        imwrite(uint8(Lp)*255, fullfile(d, sprintf('lab_%05d.png', n)));
        imwrite(uint8(Fp)*255, fullfile(d, sprintf('fov_%05d.png', n)));
        fracs(end+1) = mean(Lp(Fp)); %#ok<AGROW>
    end
    fprintf('  %s %02d: %d patches\n', split, id, kept);
end

fprintf('%s vessel prevalence inside FOV: %.3f (min %.3f max %.3f)\n', ...
        split, mean(fracs), min(fracs), max(fracs));
end
