function s28_cache_negatives()
%S28_CACHE_NEGATIVES  Healthy-eye patches that teach the lesion net what is NOT a lesion.
%
%   Why. The lesion net (s05) was trained only on IDRiD's 81 segmentation
%   images, and every one of them has DR. On healthy APTOS eyes it marks the
%   fovea as a haemorrhage and bright nerve-fibre / vessel reflections as
%   exudates, so the lesion-rule grade calls 97% of healthy eyes referable
%   (diagnosed 28 Sep 2026). It has simply never seen a normal retina.
%
%   What. APTOS grade-0 eyes from the grader's TRAIN split only (the grader's
%   val split supplies validation negatives; its TEST split stays sealed for
%   s30). Each image is prepared exactly as at inference - native resolution,
%   retinalCrop, applyClahe - and cut into 512px patches whose lesion masks
%   are all empty:
%     up to 3  hard negatives, centred on the CURRENT net's false detections
%     1        the fovea (darkest macular point)
%     1        the optic disc region (its bright rim is where exudates leak)
%     1        random, inside the retinal field
%
%   The optic-disc channel. APTOS has no disc masks, so a healthy patch must
%   not teach "there is no disc here". Bit 6 of the packed label (unused by
%   the 5 real channels) marks the disc as UNLABELLED; netraLossHN ignores
%   channel 5 wherever that bit is set. IDRiD labels never set it.
%
%   Writes data/cache/patches/neg_train and neg_val (img_/lab_ pairs, same
%   format as s02) and models/negatives_split.mat.
addpath(fullfile(fileparts(mfilename('fullpath')),'lib'));
CFG = s00_config(); rng(CFG.seed);

S  = load(fullfile(CFG.modelDir,'grader_split.mat')); sp = S.split;
y  = double(sp.y(:)) - 1;
[~, ids] = cellfun(@fileparts, cellstr(sp.files(:)), 'UniformOutput', false);
ids = string(ids);

trainPool = find(sp.isTrain(:) & y == 0);
valPool   = find(sp.isVal(:)   & y == 0);
nTrain = 400; nVal = 60;
trainIdx = trainPool(randperm(numel(trainPool), nTrain));
valIdx   = valPool(randperm(numel(valPool), nVal));
save(fullfile(CFG.modelDir,'negatives_split.mat'), 'trainIdx','valIdx','ids');
fprintf('healthy eyes: %d train (of %d) | %d val (of %d) - grader TEST split untouched\n', ...
        nTrain, numel(trainPool), nVal, numel(valPool));

L  = load(fullfile(CFG.modelDir,'netra_lesion_net.mat')); net = L.net;
T  = load(fullfile(CFG.modelDir,'thresholds.mat'));       thr = T.thr;

emit(CFG, net, thr, ids(trainIdx), fullfile(CFG.patchCache,'neg_train'));
emit(CFG, net, thr, ids(valIdx),   fullfile(CFG.patchCache,'neg_val'));
end

% -------------------------------------------------------------------------
function emit(CFG, net, thr, ids, out)
if isfolder(out), rmdir(out,'s'); end
mkdir(out);
ps = CFG.patchSize; k = 0; t0 = tic; kinds = zeros(1,4);
ignoreOD = uint8(2^5);                            % bit 6: disc unlabelled
for i = 1:numel(ids)
    I0 = retinalCrop(imread(fullfile(CFG.aptosImgDir, ids(i) + ".png")));
    if size(I0,3) == 1, I0 = repmat(I0,1,1,3); end
    I  = applyClahe(I0);
    [H,W,~] = size(I);
    F  = retinalMask(I0);
    P  = slidingWindowPredict(net, I, CFG);
    od = P(:,:,5) >= thr(5);

    centres = zeros(0,3);                         % [row col kind]
    % 1) hard negatives: the current net's false lesions, largest first
    fp = false(H,W);
    for c = 1:4
        b = bwareaopen(P(:,:,c) >= thr(c), CFG.minCompSize(c));
        if c == 3 || c == 4, b = b & ~imdilate(od, strel('disk',15)); end
        fp = fp | b;
    end
    st = regionprops(fp, 'Centroid', 'Area');
    if ~isempty(st)
        [~, o] = sort([st.Area], 'descend');
        for j = o(1:min(3,end))
            centres(end+1,:) = [round(st(j).Centroid([2 1])) 1]; %#ok<AGROW>
        end
    end
    % 2) fovea: darkest smoothed-green point near the field centre, away from the disc
    dia = sqrt(4*nnz(F)/pi);
    sf = regionprops(F,'Centroid'); c0 = sf(1).Centroid;
    g  = imgaussfilt(im2single(I0(:,:,2)), max(dia/40,1));
    [yy,xx] = ndgrid(1:H,1:W);
    cand = F & hypot(xx-c0(1), yy-c0(2)) < 0.35*dia/2 & ~imdilate(od, strel('disk',max(round(dia/12),1)));
    if any(cand(:))
        g(~cand) = Inf; [~,m] = min(g(:)); [fy,fx] = ind2sub([H W], m);
        centres(end+1,:) = [fy fx 2];
    end
    % 3) optic disc region
    so = regionprops(od, 'Centroid', 'Area');
    if ~isempty(so)
        [~,m] = max([so.Area]); centres(end+1,:) = [round(so(m).Centroid([2 1])) 3];
    end
    % 4) random, inside the field
    [fr, fc] = find(F);
    if ~isempty(fr), m = randi(numel(fr)); centres(end+1,:) = [fr(m) fc(m) 4]; end

    for j = 1:size(centres,1)
        r  = centres(j,1) - ps/2 + randi([-ps/8 ps/8]);
        c1 = centres(j,2) - ps/2 + randi([-ps/8 ps/8]);
        r  = min(max(r,1),  max(H-ps+1,1));
        c1 = min(max(c1,1), max(W-ps+1,1));
        ip = I(r:min(r+ps-1,H), c1:min(c1+ps-1,W), :);
        if size(ip,1) ~= ps || size(ip,2) ~= ps, ip(ps,ps,3) = 0; end
        k = k + 1;
        imwrite(ip, fullfile(out, sprintf('img_%05d.png',k)));
        imwrite(repmat(ignoreOD, ps, ps), fullfile(out, sprintf('lab_%05d.png',k)));
        kinds(centres(j,3)) = kinds(centres(j,3)) + 1;
    end
    if mod(i,50) == 0, fprintf('  %d/%d images  %d patches  %.1f min\n', i, numel(ids), k, toc(t0)/60); end
end
fprintf('%s: %d patches from %d eyes  [false-detection %d | fovea %d | disc %d | random %d]  %.1f min\n', ...
        out, k, numel(ids), kinds, toc(t0)/60);
end
