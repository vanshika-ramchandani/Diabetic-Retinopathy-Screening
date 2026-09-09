function CFG = s00_config()
%S00_CONFIG  Single source of truth for the NETRA-Lesion pipeline.
%   Channel order is fixed everywhere: 1 MA, 2 HE, 3 EX, 4 SE, 5 OD.

root = fileparts(fileparts(mfilename('fullpath')));

CFG.root        = root;
CFG.segRoot     = fullfile(root,'data','aptos','A. Segmentation');
CFG.aptosImgDir = fullfile(root,'data','aptos','Train Images');
CFG.aptosCsv    = fullfile(root,'data','aptos','train.csv');

CFG.cacheDir    = fullfile(root,'data','cache');
CFG.aptosCache  = fullfile(CFG.cacheDir,'aptos512');
CFG.patchCache  = fullfile(CFG.cacheDir,'patches');
CFG.modelDir    = fullfile(root,'models');
CFG.resultDir   = fullfile(root,'results');

% ---- channels -----------------------------------------------------------
CFG.chanSuffix  = ["MA","HE","EX","SE","OD"];
CFG.chanFolder  = ["1. Microaneurysms","2. Haemorrhages","3. Hard Exudates", ...
                   "4. Soft Exudates","5. Optic Disc"];
CFG.chanName    = ["Microaneurysm","Haemorrhage","Hard Exudate","Soft Exudate","Optic Disc"];
CFG.nChan       = 5;
CFG.lesionChan  = 1:4;          % OD is auxiliary, never a headline metric

% ---- data ---------------------------------------------------------------
CFG.trainIds    = 1:54;         % IDRiD_01..54  (official training set)
CFG.testIds     = 55:81;        % IDRiD_55..81  (official test set - SEALED)
CFG.valIds      = [];           % filled by s02 (stratified 10 of the 54)
CFG.patchSize   = 512;
CFG.patchesPerImage = 80;
CFG.lesionCentredFrac = 0.60;

% ---- stage 3: APTOS encoder pretraining ---------------------------------
CFG.encoderWeights   = "imagenet";   % ResNet-18 support package verified installed
CFG.useAptosPretrain = false;        % APTOS was restored from the Recycle Bin 5 Sep ~18:00,
                                     % but this stays FALSE on purpose: the segmentation net
                                     % has already been evaluated once on the sealed 27-image
                                     % test set. Flipping this to true retrains it, which
                                     % would silently invalidate results/metrics.csv.
                                     % The DR grader uses its own track (s10-s12) instead.
CFG.aptosSize   = 512;
CFG.aptosEpochs = 12;
CFG.aptosBatch  = 24;
CFG.aptosLR     = 1e-3;

% ---- stages 10-12: DR grader (ICDR 0-4) ---------------------------------
% Separate from the segmentation net. Trains on the cached APTOS 512px PNGs,
% grades 0-4, and derives the binary referable-DR (grade >= 2) decision that
% the problem statement actually specifies.
CFG.graderSize    = 384;    % resized from the 512 cache; 384 keeps small lesions
                            % legible while training ~1.8x faster than 512.
CFG.graderEpochs  = 10;
CFG.graderBatch   = 16;
CFG.graderLR      = 1e-4;
CFG.graderValFrac = 0.15;   % of the 85% non-test remainder
CFG.graderTestFrac= 0.15;   % sealed until s12
CFG.referableFrom = 2;      % ICDR level 2+ = referable DR, per the problem statement
CFG.sensTarget    = 0.90;   % operating point requirement: sensitivity >= 90%

% ---- stage 5: segmentation ----------------------------------------------
CFG.segEpochs   = 15;   % 3520 patches / batch 8 = 440 iter/epoch ~ 55 min on RTX 4060
CFG.segBatch    = 8;
CFG.lrEncoder   = 1e-4;
CFG.lrDecoder   = 3e-4;
CFG.patchesPerEpoch = 2000;

% loss: focal Tversky (alpha=FP weight, beta=FN weight) + weighted BCE
CFG.tverskyAlpha = 0.3;
CFG.tverskyBeta  = 0.7;
CFG.tverskyGamma = 0.75;
CFG.bceWeight    = 0.5;
CFG.chanWeight   = single([3.0 1.5 1.0 1.5 0.5]);   % MA HE EX SE OD

% ---- inference ----------------------------------------------------------
CFG.stride      = 256;
CFG.minCompSize = [3 10 10 10 50];   % px, per channel
CFG.hemoSensTarget = 0.90;

% ---- normalisation (ImageNet, matches the pretrained encoder) -----------
CFG.imMean = single(reshape([0.485 0.456 0.406],1,1,3));
CFG.imStd  = single(reshape([0.229 0.224 0.225],1,1,3));

CFG.seed = 42;
end
