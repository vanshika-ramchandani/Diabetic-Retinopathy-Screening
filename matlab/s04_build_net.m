function s04_build_net()
%S04_BUILD_NET  Assemble the model, assert it is wired correctly, and prove it
%   can learn before committing to a 45-minute run.
addpath(fullfile(fileparts(mfilename('fullpath')),'lib'));
CFG = s00_config();

% ---- encoder source ------------------------------------------------------
f = fullfile(CFG.modelDir,'encoder_aptos.mat');
if CFG.useAptosPretrain && isfile(f)
    S = load(f); base = S.net;  fprintf('encoder: APTOS-pretrained\n');
else
    base = imagePretrainedNetwork("resnet18");  fprintf('encoder: ImageNet\n');
end

net = buildLesionNet(base, CFG);

% ---- assertions ----------------------------------------------------------
x = dlarray(zeros(CFG.patchSize,CFG.patchSize,3,2,'single'),'SSCB');
y = predict(net, x);
assert(isequal(size(y),[CFG.patchSize CFG.patchSize CFG.nChan 2]), 'bad output shape');
assert(min(y,[],'all') >= 0 && max(y,[],'all') <= 1, 'output not in [0,1]');
enc = ~startsWith(string(net.Learnables.Layer), ["dec","out"]);
fprintf('OK  %d layers | %d encoder params | %d decoder params\n', ...
        numel(net.Layers), sum(enc), sum(~enc));

% ---- differential learning rate: protect the pretrained encoder ----------
factor = CFG.lrEncoder / CFG.lrDecoder;
L = net.Learnables;
for i = 1:height(L)
    if enc(i)
        net = setLearnRateFactor(net, L.Layer{i}, L.Parameter{i}, factor);
    end
end
fprintf('encoder LR factor = %.3f\n', factor);

save(fullfile(CFG.modelDir,'net_init.mat'),'net','-v7.3');

% ---- OVERFIT TEST: 4 patches, 150 iterations, loss must collapse ---------
% If this fails, the labels or the loss are miswired and the real run would
% waste 45 minutes producing nothing.
fprintf('\n--- overfit test ---\n');
small = patchDatastore("train", CFG, false, 1:4);

opts = trainingOptions("adam", ...
    MaxEpochs=150, MiniBatchSize=4, InitialLearnRate=1e-3, ...
    Shuffle="never", ExecutionEnvironment="gpu", ...
    Verbose=true, VerboseFrequency=25, Plots="none");

t0 = tic;
[~, info] = trainnet(small, net, @netraLoss, opts);
fprintf('overfit test: start=%.3f  end=%.3f  (%.1f s)\n', ...
        info.TrainingHistory.Loss(1), info.TrainingHistory.Loss(end), toc(t0));

if info.TrainingHistory.Loss(end) < 0.5*info.TrainingHistory.Loss(1)
    fprintf('PASS - the model can fit the data. Safe to run s05.\n');
else
    error('FAIL - loss did not fall. Check label plumbing before training.');
end
end

