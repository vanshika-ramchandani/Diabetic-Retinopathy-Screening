function s20_train_vessels()
%S20_TRAIN_VESSELS  Train the DRIVE vessel net (ResNet-18 U-Net, 1 channel).
%
%   Reuses buildLesionNet through vesselConfig rather than defining a second
%   architecture: same encoder, same decoder, 1 sigmoid output instead of 5.
%   The encoder keeps its ImageNet weights and a reduced learning rate - with
%   only 16 training images, letting it move at the decoder's rate is the
%   fastest way to overfit.
addpath(fullfile(fileparts(mfilename('fullpath')),'lib'));
CFG = s00_config();
V   = vesselConfig(CFG);
rng(CFG.seed);

requireStage(fullfile(CFG.modelDir,'vessel_split.mat'), ...
             's19_cache_vessels', 's19_cache_vessels');

% ---- build --------------------------------------------------------------
base = imagePretrainedNetwork("resnet18");
net  = buildLesionNet(base, V);

x = dlarray(zeros(V.patchSize, V.patchSize, 3, 2, 'single'), 'SSCB');
y = predict(net, x);
assert(isequal(size(y), [V.patchSize V.patchSize 1 2]), 'bad output shape: %s', mat2str(size(y)));
assert(min(y,[],'all') >= 0 && max(y,[],'all') <= 1, 'output not in [0,1]');

enc    = ~startsWith(string(net.Learnables.Layer), ["dec","out"]);
factor = CFG.vesselLrEnc / CFG.vesselLR;
L = net.Learnables;
for i = 1:height(L)
    if enc(i)
        net = setLearnRateFactor(net, L.Layer{i}, L.Parameter{i}, factor);
    end
end
fprintf('net OK | %d layers | encoder LR factor %.3f\n', numel(net.Layers), factor);

% ---- overfit test: prove the label/FOV plumbing before a 30-minute run ---
fprintf('\n--- overfit test ---\n');
small = vesselDatastore("train", CFG, false, 1:4);
opts0 = trainingOptions("adam", MaxEpochs=120, MiniBatchSize=4, ...
    InitialLearnRate=1e-3, Shuffle="never", ExecutionEnvironment="gpu", ...
    Verbose=true, VerboseFrequency=30, Plots="none");
[~, i0] = trainnet(small, net, @vesselLoss, opts0);
fprintf('overfit: start=%.3f end=%.3f\n', i0.TrainingHistory.Loss(1), i0.TrainingHistory.Loss(end));
if i0.TrainingHistory.Loss(end) >= 0.5*i0.TrainingHistory.Loss(1)
    error('FAIL - loss did not fall. Check label/FOV plumbing before training.');
end
fprintf('PASS\n\n');

% ---- train --------------------------------------------------------------
dsTrain = vesselDatastore("train", CFG, true);
dsVal   = vesselDatastore("val",   CFG, false);
nTrain  = numel(dir(fullfile(CFG.vesselCache,'train','img_*.png')));

ckptDir = fullfile(CFG.modelDir,'checkpoints_vessel');
if ~isfolder(ckptDir), mkdir(ckptDir); end

batch = CFG.vesselBatch;
while true
    itersPerEpoch = floor(nTrain/batch);
    fprintf('batch=%d  %d iter/epoch  %d epochs\n', batch, itersPerEpoch, CFG.vesselEpochs);

    opts = trainingOptions("adam", ...
        MaxEpochs           = CFG.vesselEpochs, ...
        MiniBatchSize       = batch, ...
        InitialLearnRate    = CFG.vesselLR, ...
        LearnRateSchedule   = "piecewise", ...
        LearnRateDropPeriod = 15, ...
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
        VerboseFrequency    = 40, ...
        Plots               = "none");

    try
        t0 = tic;
        [net, info] = trainnet(dsTrain, net, @vesselLoss, opts);
        fprintf('trained in %.1f min\n', toc(t0)/60);
        break
    catch ME
        if contains(ME.message,'memory','IgnoreCase',true) && batch > 2
            batch = batch/2;
            fprintf('GPU OOM -> retrying at batch %d (resolution stays %d)\n', batch, V.patchSize);
        else
            rethrow(ME);
        end
    end
end

save(fullfile(CFG.modelDir,'netra_vessel_net.mat'), 'net','info','CFG','-v7.3');
fprintf('saved models/netra_vessel_net.mat\n');
v = info.ValidationHistory.Loss; v = v(~isnan(v));
fprintf('validation loss: %.4f -> %.4f  (best %.4f)\n', v(1), v(end), min(v));
end
