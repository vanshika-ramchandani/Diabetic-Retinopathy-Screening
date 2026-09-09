function s03_pretrain_encoder()
%S03_PRETRAIN_ENCODER  Pretrain the ResNet-18 encoder on APTOS DR grading.
%
%   OPTIONAL STAGE. Only runs when CFG.useAptosPretrain is true and the cached
%   APTOS images exist (s01_cache_aptos). It gives the encoder 3,662 retinal
%   images before it has to segment lesions from only 54 - and produces a
%   quadratic-weighted-kappa figure for the DR grading task as a by-product.
%
%   The saved network is resnet18-shaped, so s04_build_net consumes it exactly
%   like a fresh ImageNet network - no weight transplant step to get wrong.
addpath(fullfile(fileparts(mfilename('fullpath')),'lib'));
CFG = s00_config();
rng(CFG.seed);

if ~isfolder(CFG.aptosCache) || numel(dir(fullfile(CFG.aptosCache,'*.png'))) == 0
    error(['APTOS cache is empty. Run s01_cache_aptos first, and make sure ' ...
           'data\\aptos\\Train Images and train.csv exist.']);
end

T = readtable(CFG.aptosCsv, TextType='string');
files = fullfile(CFG.aptosCache, T.id_code + ".png");
keep  = isfile(files);
files = files(keep);
grade = categorical(T.diagnosis(keep));
fprintf('APTOS: %d cached images of %d labelled\n', numel(files), height(T));

% ---- stratified 85/15 split ---------------------------------------------
cv = cvpartition(grade, 'HoldOut', 0.15);
imdsTrain = imageDatastore(files(training(cv)), Labels=grade(training(cv)));
imdsVal   = imageDatastore(files(test(cv)),     Labels=grade(test(cv)));

dsTrain = transform(imdsTrain, @(I) {normaliseInput(I,CFG)}, IncludeInfo=false);
dsTrain = combine(dsTrain, arrayDatastore(imdsTrain.Labels));
dsVal   = transform(imdsVal,   @(I) {normaliseInput(I,CFG)}, IncludeInfo=false);
dsVal   = combine(dsVal,   arrayDatastore(imdsVal.Labels));

% ---- class weights: APTOS is 1805/370/999/193/295 -----------------------
cls = categories(grade);
n   = countcats(grade);
w   = single((1./sqrt(double(n)))');
w   = w / sum(w) * numel(cls);
fprintf('class counts: %s\n', mat2str(n'));

net = imagePretrainedNetwork("resnet18", NumClasses=numel(cls));
net = replaceLayer(net, net.InputNames{1}, ...
        imageInputLayer([CFG.aptosSize CFG.aptosSize 3], ...
                        Name=net.InputNames{1}, Normalization='none'));
net = initialize(net);

lossFcn = @(Y,T2) crossentropy(Y, T2, w, WeightsFormat="C");

opts = trainingOptions("adam", ...
    MaxEpochs           = CFG.aptosEpochs, ...
    MiniBatchSize       = CFG.aptosBatch, ...
    InitialLearnRate    = CFG.aptosLR, ...
    LearnRateSchedule   = "piecewise", ...
    LearnRateDropPeriod = 5, ...
    LearnRateDropFactor = 0.3, ...
    ValidationData      = dsVal, ...
    ValidationFrequency = 100, ...
    OutputNetwork       = "best-validation", ...
    Shuffle             = "every-epoch", ...
    ExecutionEnvironment= "gpu", ...
    Verbose = true, VerboseFrequency = 50, Plots = "none");

t0 = tic;
net = trainnet(dsTrain, net, lossFcn, opts);
fprintf('pretraining done in %.1f min\n', toc(t0)/60);

% ---- report QWK, the metric APTOS is actually scored on -----------------
scores = minibatchpredict(net, dsVal, ExecutionEnvironment="gpu");
[~,pi] = max(scores,[],2);
pred   = double(pi) - 1;
truth  = double(imdsVal.Labels) - 1;
fprintf('DR grading accuracy %.4f | QWK %.4f\n', mean(pred==truth), qwk(truth,pred,numel(cls)));

if ~isfolder(CFG.modelDir), mkdir(CFG.modelDir); end
save(fullfile(CFG.modelDir,'encoder_aptos.mat'),'net','-v7.3');
fprintf('saved models/encoder_aptos.mat\n');
end

% =========================================================================
function k = qwk(a, b, nc)
%QWK  Quadratic weighted kappa - the APTOS 2019 competition metric.
O = accumarray([a(:)+1, b(:)+1], 1, [nc nc]);
W = (repmat(0:nc-1,nc,1) - repmat((0:nc-1)',1,nc)).^2 / (nc-1)^2;
E = accumarray(a(:)+1,1,[nc 1]) * accumarray(b(:)+1,1,[nc 1])';
E = E / sum(E(:)) * sum(O(:));
k = 1 - sum(W(:).*O(:)) / max(sum(W(:).*E(:)), eps);
end
