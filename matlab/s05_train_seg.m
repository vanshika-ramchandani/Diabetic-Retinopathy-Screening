function s05_train_seg()
%S05_TRAIN_SEG  Train the multi-task lesion network on the IDRiD patches.
addpath(fullfile(fileparts(mfilename('fullpath')),'lib'));
CFG = s00_config();
rng(CFG.seed);

S = load(fullfile(CFG.modelDir,'net_init.mat'));
net = S.net;

dsTrain = patchDatastore("train", CFG, true);
dsVal   = patchDatastore("val",   CFG, false);
nTrain  = numel(dir(fullfile(CFG.patchCache,'train','img_*.png')));

% Checkpoint every epoch. trainnet otherwise writes the model ONLY on success,
% so a crash 50 minutes in loses everything. Resume with resume_from_checkpoint.
ckptDir = fullfile(CFG.modelDir,'checkpoints');
if ~isfolder(ckptDir), mkdir(ckptDir); end

batch = CFG.segBatch;
while true
    itersPerEpoch = floor(nTrain/batch);
    fprintf('batch=%d  %d iter/epoch  %d epochs\n', batch, itersPerEpoch, CFG.segEpochs);

    opts = trainingOptions("adam", ...
        MaxEpochs           = CFG.segEpochs, ...
        MiniBatchSize       = batch, ...
        InitialLearnRate    = CFG.lrDecoder, ...
        LearnRateSchedule   = "piecewise", ...
        LearnRateDropPeriod = 6, ...
        LearnRateDropFactor = 0.35, ...
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
        VerboseFrequency    = 50, ...
        Plots               = "none");

    try
        t0 = tic;
        [net, info] = trainnet(dsTrain, net, @netraLoss, opts);
        fprintf('trained in %.1f min\n', toc(t0)/60);
        break
    catch ME
        if contains(ME.message,'memory','IgnoreCase',true) && batch > 2
            batch = batch/2;
            fprintf('GPU OOM -> retrying at batch %d (resolution stays 512)\n', batch);
        else
            rethrow(ME);
        end
    end
end

save(fullfile(CFG.modelDir,'netra_lesion_net.mat'),'net','info','CFG','-v7.3');
fprintf('saved models/netra_lesion_net.mat\n');
v = info.ValidationHistory.Loss; v = v(~isnan(v));
fprintf('validation loss: %.3f -> %.3f  (best %.3f)\n', v(1), v(end), min(v));
end
