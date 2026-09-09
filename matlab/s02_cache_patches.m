function s02_cache_patches()
%S02_CACHE_PATCHES  Build the IDRiD training patches.
%   Patches are cut at NATIVE resolution - downscaling destroys microaneurysms
%   (~10 px wide). 60% are centred on a lesion, 40% uniform random; keeping the
%   random negatives is what preserves specificity.
%   Masks are bit-packed into one uint8 plane (channel c -> bit c).
addpath(fullfile(fileparts(mfilename('fullpath')),'lib'));
CFG = s00_config();
rng(CFG.seed);

% ---- stratified 44/10 split: val must contain soft-exudate positives -----
hasSE = false(1,54);
for id = CFG.trainIds
    hasSE(id) = isfile(fullfile(CFG.segRoot,'2. All Segmentation Groundtruths', ...
        'a. Training Set','4. Soft Exudates',sprintf('IDRiD_%02d_SE.tif',id)));
end
withSE = find(hasSE); withoutSE = find(~hasSE);
valIds = sort([withSE(randperm(numel(withSE),5)), withoutSE(randperm(numel(withoutSE),5))]);
trainIds = setdiff(CFG.trainIds, valIds);
fprintf('split: %d train / %d val   (val = %s)\n', numel(trainIds), numel(valIds), ...
        strjoin(string(valIds),','));

split = struct('trainIds',trainIds,'valIds',valIds,'testIds',CFG.testIds);
if ~isfolder(CFG.modelDir), mkdir(CFG.modelDir); end
save(fullfile(CFG.modelDir,'split.mat'),'-struct','split');

for s = ["train","val"]
    d = fullfile(CFG.patchCache, s);
    if isfolder(d), rmdir(d,'s'); end
    mkdir(d);
end

emit(CFG, trainIds, 'train', CFG.patchesPerImage);
emit(CFG, valIds,   'val',   30);

fprintf('\ntrain patches: %d\n', numel(dir(fullfile(CFG.patchCache,'train','img_*.png'))));
fprintf('val   patches: %d\n', numel(dir(fullfile(CFG.patchCache,'val','img_*.png'))));
end

% =========================================================================
function emit(CFG, ids, split, nPer)
ps = CFG.patchSize; out = fullfile(CFG.patchCache, split);
counts = zeros(1,CFG.nChan); k = 0; t0 = tic;

for id = ids
    [I, M] = readIdridSample(CFG, id, "train");
    [H,W,~] = size(I);
    nLes = round(nPer * CFG.lesionCentredFrac);

    % which lesion channels actually have pixels in this image
    present = [];
    for c = CFG.lesionChan
        if any(M(:,:,c),'all'), present(end+1) = c; end %#ok<AGROW>
    end

    for j = 1:nPer
        if j <= nLes && ~isempty(present)
            c = present(randi(numel(present)));
            idxp = find(M(:,:,c));
            [r0,c0] = ind2sub([H W], idxp(randi(numel(idxp))));
            r = r0 - round(ps/2) + randi([-ps/4 ps/4]);
            c1 = c0 - round(ps/2) + randi([-ps/4 ps/4]);
        else
            r = randi(max(H-ps,1)); c1 = randi(max(W-ps,1));
        end
        r  = min(max(r,1),  max(H-ps+1,1));
        c1 = min(max(c1,1), max(W-ps+1,1));
        rr = r:min(r+ps-1,H); cc = c1:min(c1+ps-1,W);

        ip = I(rr,cc,:); mp = M(rr,cc,:);
        if size(ip,1) ~= ps || size(ip,2) ~= ps
            ip(ps,ps,3) = 0; mp(ps,ps,CFG.nChan) = false;
        end

        k = k + 1;
        imwrite(ip,             fullfile(out, sprintf('img_%05d.png',k)));
        imwrite(packMasks(mp),  fullfile(out, sprintf('lab_%05d.png',k)));
        counts = counts + squeeze(sum(mp,[1 2]))';
    end
    fprintf('  IDRiD_%02d done (%d patches)\n', id, nPer);
end

fprintf('%s: %d patches in %.1f min\n', split, k, toc(t0)/60);
tot = k*ps*ps;
for c = 1:CFG.nChan
    fprintf('   %-14s %7.4f%% of patch pixels\n', CFG.chanName(c), 100*counts(c)/tot);
end
end
