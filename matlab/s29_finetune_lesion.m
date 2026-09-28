function s29_finetune_lesion()
%S29_FINETUNE_LESION  Lesion net v2: fine-tune v1 with healthy-eye negatives (s28).
%
%   Starts FROM the s05 weights (netra_lesion_net.mat) and continues training
%   on the IDRiD patches plus the healthy APTOS patches, so it keeps what it
%   learned about real lesions while learning what a normal fovea, disc rim
%   and light reflex look like. Loss: netraLossHN (netraLoss + unlabelled-disc
%   mask). Validation = IDRiD val patches + healthy val patches; the best
%   validation epoch is kept.
%
%   Then re-tunes the per-channel thresholds with the SAME rule s06 used
%   (best pixel F1 on the 10 IDRiD validation images), so any change in
%   behaviour is attributable to the training, not to a new threshold rule.
%
%   Writes models/netra_lesion_net_v2.mat and models/thresholds_v2.mat.
%   v1 is left untouched; s30 decides which one the app uses.
addpath(fullfile(fileparts(mfilename('fullpath')),'lib'));
CFG = s00_config(); rng(CFG.seed);

S = load(fullfile(CFG.modelDir,'netra_lesion_net.mat')); net = S.net;

dsTrain = mixedDatastore(CFG, ["train","neg_train"], true);
dsVal   = mixedDatastore(CFG, ["val","neg_val"], false);
nTrain  = numel(dsTrain.UnderlyingDatastores{1}.UnderlyingDatastores{1}.Files);
fprintf('train patches %d | val patches %d\n', nTrain, ...
        numel(dsVal.UnderlyingDatastores{1}.UnderlyingDatastores{1}.Files));

% sanity: on IDRiD-only data the new loss must equal the one v1 was trained with
d = read(patchDatastore("val", CFG, false)); reset(patchDatastore("val", CFG, false));
X = dlarray(d{1},'SSCB'); Y = predict(net, X); T5 = dlarray(d{2},'SSCB');
T6 = cat(3, d{2}, zeros(size(d{2},1), size(d{2},2), 1, 'single'));
l1 = extractdata(netraLoss(Y, T5)); l2 = extractdata(netraLossHN(Y, dlarray(T6,'SSCB')));
fprintf('loss check on an IDRiD patch: netraLoss %.6f | netraLossHN %.6f\n', l1, l2);
assert(abs(l1-l2) < 1e-4*max(abs(l1),1), 'netraLossHN does not reduce to netraLoss');

ckptDir = fullfile(CFG.modelDir,'checkpoints_lesion_v2');
if ~isfolder(ckptDir), mkdir(ckptDir); end
batch = CFG.segBatch;
itersPerEpoch = floor(nTrain/batch);
opts = trainingOptions("adam", ...
    MaxEpochs           = 6, ...
    MiniBatchSize       = batch, ...
    InitialLearnRate    = 1e-4, ...                 % v1 ended at 3e-4*0.35^2; stay gentle
    LearnRateSchedule   = "piecewise", ...
    LearnRateDropPeriod = 4, ...
    LearnRateDropFactor = 0.3, ...
    GradientThreshold   = 1, ...
    Shuffle             = "every-epoch", ...
    ValidationData      = dsVal, ...
    ValidationFrequency = itersPerEpoch, ...
    ValidationPatience  = Inf, ...
    OutputNetwork       = "best-validation", ...
    CheckpointPath      = ckptDir, ...
    CheckpointFrequency = 1, ...
    CheckpointFrequencyUnit = "epoch", ...
    ExecutionEnvironment= "gpu", ...
    Verbose             = true, ...
    VerboseFrequency    = 100, ...
    Plots               = "none");
t0 = tic;
[net, info] = trainnet(dsTrain, net, @netraLossHN, opts);
fprintf('fine-tuned in %.1f min\n', toc(t0)/60);
v = info.ValidationHistory.Loss; v = v(~isnan(v));
fprintf('validation loss per epoch: %s\n', strjoin(compose('%.3f', v), ' '));
save(fullfile(CFG.modelDir,'netra_lesion_net_v2.mat'),'net','info','CFG','-v7.3');
fprintf('saved models/netra_lesion_net_v2.mat\n');

% ---- thresholds: the s06 rule, unchanged --------------------------------
sp = load(fullfile(CFG.modelDir,'split.mat'));
A = cell(1,CFG.nChan);
for id = sp.valIds
    [I,M] = readIdridSample(CFG, id, "train");
    P = slidingWindowPredict(net, I, CFG);
    for c = 1:CFG.nChan, A{c} = prCurveAccum(A{c}, P(:,:,c), M(:,:,c)); end
end
thr = zeros(1,CFG.nChan); ap = thr; f1 = thr;
fprintf('\n%-16s %8s %8s %8s\n','channel','valAP','bestF1','thr');
for c = 1:CFG.nChan
    [ap(c), f1(c), thr(c)] = prCurveFinish(A{c});
    fprintf('%-16s %8.4f %8.4f %8.3f\n', CFG.chanName(c), ap(c), f1(c), thr(c));
end
save(fullfile(CFG.modelDir,'thresholds_v2.mat'),'thr','ap','f1','CFG');
fprintf('saved models/thresholds_v2.mat\n');
end

% -------------------------------------------------------------------------
function ds = mixedDatastore(CFG, splits, doAug)
fi = strings(0,1); fl = strings(0,1);
for s = splits
    d = fullfile(CFG.patchCache, s);
    n = numel(dir(fullfile(d,'img_*.png')));
    assert(n > 0, 'no patches in %s', d);
    fi = [fi; arrayfun(@(k) string(fullfile(d,sprintf('img_%05d.png',k))), (1:n)')]; %#ok<AGROW>
    fl = [fl; arrayfun(@(k) string(fullfile(d,sprintf('lab_%05d.png',k))), (1:n)')]; %#ok<AGROW>
end
cds = combine(imageDatastore(fi), imageDatastore(fl));
ds  = transform(cds, @(data) augmentPair(data, CFG, doAug));
end

function out = augmentPair(data, CFG, doAug)
% identical to patchDatastore's augmentation, with the 6th (ignore-disc) plane carried along
I = data{1};
M = unpackMasks(data{2}, 6);
if doAug
    if rand > 0.5, I = fliplr(I); M = fliplr(M); end
    if rand > 0.5, I = flipud(I); M = flipud(M); end
    k = randi(4)-1;
    if k > 0, I = rot90(I,k); M = rot90(M,k); end
    if rand > 0.5
        I = im2uint8(min(max(single(I)/255 * (0.85+0.3*rand) + (rand-0.5)*0.08, 0), 1));
    end
end
out = {normaliseInput(I, CFG), single(M)};
end
