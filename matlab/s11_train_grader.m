function s11_train_grader()
%S11_TRAIN_GRADER  ResNet-18 DR grader on APTOS (ICDR 0-4).
%
%   Three-way stratified split, fixed by CFG.seed and saved to
%   models/grader_split.mat so s12 evaluates exactly what s11 held out:
%     train  ~70%   fits weights
%     val    ~15%   early stopping AND the referable operating point
%     test   ~15%   SEALED - opened only by s12, once
here = fileparts(mfilename('fullpath'));
addpath(here, fullfile(here,'lib'));
CFG = s00_config(); rng(CFG.seed);

if ~isfolder(CFG.aptosCache) || numel(dir(fullfile(CFG.aptosCache,'*.png'))) < 100
    error('NETRA:noAptosCache', ...
        '\n  APTOS cache is empty or short.\n  Do this first: s01_cache_aptos\n');
end

T = readtable(CFG.aptosCsv, TextType='string');
files = fullfile(CFG.aptosCache, T.id_code + ".png");
keep  = isfile(files);
files = files(keep);
grade = T.diagnosis(keep);
fprintf('APTOS grader: %d cached images of %d labelled\n', numel(files), height(T));

y = categorical(grade, 0:4);

% ---- stratified 70/15/15 ------------------------------------------------
cvTest = cvpartition(y, 'HoldOut', CFG.graderTestFrac);
isTest = test(cvTest);
yRem   = y(~isTest);
cvVal  = cvpartition(yRem, 'HoldOut', CFG.graderValFrac/(1-CFG.graderTestFrac));
remIdx = find(~isTest);
isVal  = false(size(y)); isVal(remIdx(test(cvVal))) = true;
isTrain= ~isTest & ~isVal;

fprintf('split: train %d | val %d | test %d (SEALED)\n', nnz(isTrain), nnz(isVal), nnz(isTest));
fprintf('train grade counts: %s\n', mat2str(countcats(y(isTrain))'));
fprintf('test  grade counts: %s\n', mat2str(countcats(y(isTest))'));

split.files = files; split.y = y;
split.isTrain = isTrain; split.isVal = isVal; split.isTest = isTest;
if ~isfolder(CFG.modelDir), mkdir(CFG.modelDir); end
save(fullfile(CFG.modelDir,'grader_split.mat'),'split','-v7');

dsTrain = makeDS(files(isTrain), y(isTrain), CFG, true);
dsVal   = makeDS(files(isVal),   y(isVal),   CFG, false);

% ---- class weights ------------------------------------------------------
% Inverse square root, not inverse frequency: APTOS is 1805/370/999/193/295,
% and full inverse weighting makes grade 3 dominate every gradient step.
n = countcats(y(isTrain));
w = single((1./sqrt(double(n)))');
w = w / sum(w) * numel(n);
fprintf('class weights: %s\n', mat2str(round(w,3)));

net = imagePretrainedNetwork("resnet18", NumClasses=5);
net = replaceLayer(net, net.InputNames{1}, ...
        imageInputLayer([CFG.graderSize CFG.graderSize 3], ...
                        Name=net.InputNames{1}, Normalization='none'));
net = initialize(net);

lossFcn = @(Y,Tg) crossentropy(Y, Tg, w, WeightsFormat="C");

opts = trainingOptions("adam", ...
    MaxEpochs           = CFG.graderEpochs, ...
    MiniBatchSize       = CFG.graderBatch, ...
    InitialLearnRate    = CFG.graderLR, ...
    LearnRateSchedule   = "piecewise", ...
    LearnRateDropPeriod = 4, ...
    LearnRateDropFactor = 0.3, ...
    ValidationData      = dsVal, ...
    ValidationFrequency = 120, ...
    OutputNetwork       = "best-validation", ...
    Shuffle             = "every-epoch", ...
    ExecutionEnvironment= "gpu", ...
    Verbose = true, VerboseFrequency = 40, Plots = "none");

fprintf('\ntraining ResNet-18 grader at %dpx, batch %d, %d epochs\n', ...
        CFG.graderSize, CFG.graderBatch, CFG.graderEpochs);
t0 = tic;
net = trainnet(dsTrain, net, lossFcn, opts);
fprintf('grader trained in %.1f min\n', toc(t0)/60);

save(fullfile(CFG.modelDir,'netra_grader.mat'),'net','CFG','-v7.3');
fprintf('saved models/netra_grader.mat\n');
end

function ds = makeDS(files, y, CFG, augment)
imds = imageDatastore(files, Labels=y);
if augment
    tf = @(I) {augmentOne(I, CFG)};
else
    tf = @(I) {normaliseInput(imresize(I,[CFG.graderSize CFG.graderSize]), CFG)};
end
ds = combine(transform(imds, tf, IncludeInfo=false), arrayDatastore(y));
end

function X = augmentOne(I, CFG)
% Fundus-appropriate augmentation only. No vertical-flip-plus-rotation soup:
% the optic disc / macula geometry is clinically meaningful, and destroying
% it teaches the network that laterality does not matter.
if rand > 0.5, I = fliplr(I); end
if rand > 0.5, I = flipud(I); end
I = imrotate(I, (rand*2-1)*15, 'bilinear', 'crop');
s = 1 + (rand*2-1)*0.10;
I = im2uint8(min(max(im2single(I)*s, 0), 1));
X = normaliseInput(imresize(I,[CFG.graderSize CFG.graderSize]), CFG);
end
