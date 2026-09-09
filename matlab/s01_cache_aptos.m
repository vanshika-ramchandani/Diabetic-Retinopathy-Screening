function s01_cache_aptos()
%S01_CACHE_APTOS  Crop + CLAHE + resize the 3,662 APTOS images to 512^2 PNGs.
%   Resumable: already-cached files are skipped, so a crash costs nothing.
addpath(fullfile(fileparts(mfilename('fullpath')),'lib'));
CFG = s00_config();
if ~isfolder(CFG.aptosCache), mkdir(CFG.aptosCache); end

T = readtable(CFG.aptosCsv, TextType='string');
n = height(T);
fprintf('APTOS cache -> %s\n', CFG.aptosCache);

todo = true(n,1);
for i = 1:n
    todo(i) = ~isfile(fullfile(CFG.aptosCache, T.id_code(i) + ".png"));
end
idx = find(todo);
fprintf('%d of %d still to cache\n', numel(idx), n);
if isempty(idx), fprintf('nothing to do\n'); return; end

% 4 workers, not 16: only ~3 GB RAM is free and each worker is a full MATLAB.
p = gcp('nocreate');
if isempty(p), parpool('Processes', 4); end

src = CFG.aptosImgDir; dst = CFG.aptosCache; sz = CFG.aptosSize;
ids = T.id_code;
t0 = tic;
parfor k = 1:numel(idx)
    i = idx(k);
    try
        I = imread(fullfile(src, ids(i) + ".png"));
        if size(I,3) == 1, I = repmat(I,1,1,3); end
        I = retinalCrop(I);
        I = applyClahe(I);
        I = imresize(I, [sz sz]);
        imwrite(I, fullfile(dst, ids(i) + ".png"));
    catch ME
        fprintf('FAIL %s : %s\n', ids(i), ME.message);
    end
end
fprintf('done in %.1f min\n', toc(t0)/60);

d = dir(fullfile(dst,'*.png'));
fprintf('cached %d / %d images\n', numel(d), n);
end
