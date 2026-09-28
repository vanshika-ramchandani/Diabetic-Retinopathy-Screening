function CFG = s00_config()
%S00_CONFIG  Single source of truth for the NETRA-Lesion pipeline.
%   Channel order is fixed everywhere: 1 MA, 2 HE, 3 EX, 4 SE, 5 OD.

root = fileparts(fileparts(mfilename('fullpath')));

CFG.root        = root;
CFG.segRoot     = fullfile(root,'data','aptos','A. Segmentation');
CFG.locRoot     = fullfile(root,'data','aptos','C. Localization');
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

% ---- stage 17: optic disc / fovea localisation --------------------------
% The PS asks for "optic disc/fovea localisation" as one requirement. The OD
% half reuses the segmentation net's channel 5; the fovea half has no mask to
% segment (IDRiD marks it with a single coordinate), so it is an anatomical
% prior whose offset and search geometry are FITTED on the localisation
% training split and then applied unchanged to the sealed test split.
CFG.locFitN      = 200;     % training images used to fit the prior (413 available)
CFG.foveaGrid.searchDD = [0.6 0.8 1.0 1.2];   % search radius, OD diameters
CFG.foveaGrid.closeDD  = [0.08 0.12 0.18];    % vessel-removal closing radius
CFG.foveaGrid.smoothDD = [0.08 0.12 0.18];    % smoothing sigma
CFG.foveaGrid.lambda   = [0 1 3 8];           % distance-to-prior penalty
CFG.foveaScale   = 0.25;    % window downscale for the classical fovea search
% Accuracy criteria, in OD diameters. 1 OD RADIUS (0.5 DD) is the criterion
% most IDRiD localisation results are quoted against.
CFG.locCriteriaDD = [0.25 0.5 1.0];

% ---- stages 19-21: vessel segmentation (DRIVE) --------------------------
% Separate track from the lesion net. DRIVE is 40 images at 584x565, so this
% is a SMALL-DATA problem: the split discipline matters more than the model.
%   train 21..40 (official DRIVE training set) -> 16 fit + 4 validation
%   test  01..20 (official DRIVE test set)     -> SEALED until s21
% Opening 01..20 for threshold tuning would leave no held-out set at all, so
% the threshold is tuned on the 4 validation images and then frozen.
CFG.driveRoot     = fullfile(root,'data','drive');
CFG.vesselCache   = fullfile(CFG.cacheDir,'vessels');
CFG.driveTrainIds = 21:40;
CFG.driveTestIds  = 1:20;
CFG.driveValN     = 4;        % held out of the 20 training images

% 256px patches, not the lesion net's 512. A 512 crop from a 584x565 frame has
% almost no translation freedom left; 256 gives real crop diversity out of 16
% images and still spans ~8x the widest vessel, so context is not the limit.
CFG.vesselSize    = 256;
CFG.vesselStride  = 128;
CFG.vesselBatch   = 16;
CFG.vesselEpochs  = 40;
CFG.vesselLR      = 3e-4;
CFG.vesselLrEnc   = 1e-4;
CFG.vesselPatchesPerImage = 128;
CFG.vesselMinFov  = 0.50;     % discard crops that are mostly outside the field

% DRIVE ships no FOV masks in this copy, so they are DERIVED (retinalMask).
% Every vessel metric is computed inside that mask: the circular field covers
% only ~68.5% of the frame, so scoring the whole rectangle would hand the model
% ~34.5% of its true negatives for free and inflate specificity and accuracy.
CFG.vesselFovEval = true;

% DRIVE's retinal field diameter in pixels, sqrt(4*area/pi) over the derived
% FOV masks. segmentVessels rescales any input to this before predicting, so
% the net always sees vessels at the width it was trained on.
CFG.vesselRefDia  = 536;

% ---- live prototype: which lesion net the app ships -----------------------
% v1 = s05 (IDRiD only). v2 = s29 (v1 fine-tuned with healthy APTOS eyes).
% s30 decides by a pre-registered rule; netraAnalyze and s25 read these two.
% The historical scripts (netraScreen, s07, s14, s16) keep using v1 by name.
% 28 Sep 2026: v2 ADOPTED by team decision although s30's pre-registered
% criterion 2 failed by 0.001 (hard-exudate IDRiD Dice 0.7315 -> 0.6805, limit
% 0.05). v2 cuts healthy false referral 96.3% -> 17.0% and D2 escalation 76.0%
% -> 37.5% on the sealed APTOS test, with 0 silent misses. Disclosed in
% results/deck_facts.txt [lesion_v2] and the README.
CFG.lesionNetFile = "netra_lesion_net_v2.mat";
CFG.lesionThrFile = "thresholds_v2.mat";

% ---- inference ----------------------------------------------------------
CFG.stride      = 256;
CFG.minCompSize = [3 10 10 10 50];   % px, per channel
CFG.hemoSensTarget = 0.90;

% ---- normalisation (ImageNet, matches the pretrained encoder) -----------
CFG.imMean = single(reshape([0.485 0.456 0.406],1,1,3));
CFG.imStd  = single(reshape([0.229 0.224 0.225],1,1,3));

CFG.seed = 42;
end
