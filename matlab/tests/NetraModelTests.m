classdef NetraModelTests < matlab.unittest.TestCase
%NETRAMODELTESTS  Behaviour of the trained model: correctness, invariances,
%   robustness, and whether it actually beats trivial baselines.

    properties
        CFG; net; thr; hasModel = false; hasThr = false;
    end

    methods (TestClassSetup)
        function setup(t)
            here = fileparts(fileparts(mfilename('fullpath')));
            addpath(here, fullfile(here,'lib'));
            t.CFG = s00_config();
            f = fullfile(t.CFG.modelDir,'netra_lesion_net.mat');
            if isfile(f)
                S = load(f); t.net = S.net; t.hasModel = true;
            end
            g = fullfile(t.CFG.modelDir,'thresholds.mat');
            if isfile(g)
                T = load(g); t.thr = T.thr; t.hasThr = true;
            end
        end
    end

    methods
        function needModel(t)
            t.assumeTrue(t.hasModel, 'trained model not found - run s05 first');
        end
        function needThr(t)
            t.assumeTrue(t.hasThr, 'thresholds not found - run s06 first');
        end
    end

    methods (Test)

        % ---------- shape and range -------------------------------------
        function forwardShapeAndRange(t)
            t.needModel();
            x = dlarray(zeros(t.CFG.patchSize,t.CFG.patchSize,3,2,'single'),'SSCB');
            y = extractdata(predict(t.net, x));
            t.verifyEqual(size(y), [t.CFG.patchSize t.CFG.patchSize t.CFG.nChan 2]);
            t.verifyGreaterThanOrEqual(min(y(:)), 0);
            t.verifyLessThanOrEqual(max(y(:)), 1);
            t.verifyTrue(all(isfinite(y(:))), 'non-finite output');
        end

        function outputIsDeterministic(t)
            t.needModel();
            ds = patchDatastore("val", t.CFG, false, 1);
            o = read(ds);
            x = dlarray(o{1},'SSCB');
            y1 = extractdata(predict(t.net,x));
            y2 = extractdata(predict(t.net,x));
            t.verifyEqual(y1, y2, 'inference is not deterministic');
        end

        function batchInvariance(t)
            % Predicting an image alone must equal predicting it inside a batch.
            % A failure here means batch-norm is still in training mode.
            t.needModel();
            ds = patchDatastore("val", t.CFG, false, 1:3);
            X = zeros(t.CFG.patchSize,t.CFG.patchSize,3,3,'single');
            for k = 1:3, o = read(ds); X(:,:,:,k) = o{1}; end
            solo  = extractdata(predict(t.net, dlarray(X(:,:,:,2),'SSCB')));
            batch = extractdata(predict(t.net, dlarray(X,'SSCB')));
            t.verifyLessThan(max(abs(solo - batch(:,:,:,2)),[],'all'), 1e-4, ...
                'batch size changes the prediction');
        end

        function channelsAreIndependentNotSoftmax(t)
            % Multi-label sigmoid: channels must NOT sum to 1 across a pixel.
            t.needModel();
            ds = patchDatastore("val", t.CFG, false, 5);
            o = read(ds);
            y = extractdata(predict(t.net, dlarray(o{1},'SSCB')));
            s = sum(y,3);
            t.verifyGreaterThan(max(abs(s(:)-1)), 0.05, ...
                'channels behave like a softmax - lesions cannot co-occur');
        end

        % ---------- inference plumbing ----------------------------------
        function slidingWindowMatchesDirectPredict(t)
            % On an image exactly one patch wide, tiled inference must reproduce
            % a plain forward pass. Catches blending and indexing bugs.
            t.needModel();
            ps = t.CFG.patchSize;
            I = uint8(128 + 40*randn(ps,ps,3));
            P = slidingWindowPredict(t.net, I, t.CFG);
            y = extractdata(predict(t.net, dlarray(normaliseInput(I,t.CFG),'SSCB')));
            t.verifyEqual(size(P), [ps ps t.CFG.nChan]);
            % Tolerance 5e-3, not 1e-3: the Hann taper falls to its 1e-3 floor at
            % the tile edge, and the accumulate-then-divide amplifies single
            % precision rounding there. Measured worst case is ~1.1e-3 on 9 of
            % 1.3M pixels (mean 1.9e-5), which is numerically irrelevant against
            % a decision threshold of ~0.98.
            d = abs(P - y);
            t.verifyLessThan(max(d,[],'all'), 5e-3, ...
                'sliding window disagrees with direct prediction');
            t.verifyLessThan(mean(d,'all'), 1e-4, ...
                'sliding window differs systematically, not just at tile edges');
        end

        function slidingWindowHandlesOddSizes(t)
            t.needModel();
            for sz = {[700 900], [513 512], [512 1200]}
                I = uint8(120*ones(sz{1}(1), sz{1}(2), 3));
                P = slidingWindowPredict(t.net, I, t.CFG);
                t.verifyEqual(size(P), [sz{1}(1) sz{1}(2) t.CFG.nChan], ...
                    sprintf('bad output size for %dx%d', sz{1}(1), sz{1}(2)));
                t.verifyTrue(all(isfinite(P(:))));
            end
        end

        function smallerThanPatchIsPadded(t)
            t.needModel();
            I = uint8(120*ones(300,400,3));
            P = slidingWindowPredict(t.net, I, t.CFG);
            t.verifyEqual(size(P), [300 400 t.CFG.nChan]);
        end

        % ---------- robustness ------------------------------------------
        function handlesDegenerateInputs(t)
            t.needModel();
            cases = {zeros(600,600,3,'uint8'), 255*ones(600,600,3,'uint8'), ...
                     uint8(randi([0 255],600,600,3))};
            names = {'all black','all white','pure noise'};
            for k = 1:numel(cases)
                P = slidingWindowPredict(t.net, cases{k}, t.CFG);
                t.verifyTrue(all(isfinite(P(:))), sprintf('%s produced NaN/Inf', names{k}));
            end
        end

        function blackImageProducesFewLesions(t)
            % A black frame is not a retina. It must not light up with lesions.
            t.needModel(); t.needThr();
            P = slidingWindowPredict(t.net, zeros(1024,1024,3,'uint8'), t.CFG);
            for c = t.CFG.lesionChan
                frac = mean(P(:,:,c) >= t.thr(c), 'all');
                t.verifyLessThan(frac, 0.05, ...
                    sprintf('%s fires on a black image (%.1f%%)', t.CFG.chanName(c), 100*frac));
            end
        end

        function grayscaleInputIsAccepted(t)
            t.needModel(); t.needThr();
            f = fullfile(t.CFG.segRoot,'1. Original Images','b. Testing Set','IDRiD_55.jpg');
            t.assumeTrue(isfile(f));
            I = imread(f);
            tmp = [tempname '.png'];
            imwrite(repmat(im2gray(I),1,1,3), tmp);
            R = netraDetect(tmp);
            t.verifyEqual(size(R.masks,3), t.CFG.nChan);
            delete(tmp);
        end

        % ---------- end-to-end API --------------------------------------
        function netraDetectReturnsCompleteStruct(t)
            t.needModel(); t.needThr();
            f = fullfile(t.CFG.segRoot,'1. Original Images','b. Testing Set','IDRiD_55.jpg');
            t.assumeTrue(isfile(f));
            R = netraDetect(f);
            for fld = ["image","prob","masks","counts","areaFrac","haemorrhageDetected"]
                t.verifyTrue(isfield(R, fld), sprintf('netraDetect missing %s', fld));
            end
            t.verifyEqual(numel(R.counts), t.CFG.nChan);
            t.verifyClass(R.haemorrhageDetected, 'logical');
            t.verifyEqual(size(R.masks,3), t.CFG.nChan);
            t.verifyTrue(islogical(R.masks));
        end

        function opticDiscSuppressionRemovesExudatesOnDisc(t)
            % Channel 5 exists to stop the bright disc being called an exudate.
            t.needModel(); t.needThr();
            f = fullfile(t.CFG.segRoot,'1. Original Images','b. Testing Set','IDRiD_55.jpg');
            t.assumeTrue(isfile(f));
            R = netraDetect(f);
            od = imdilate(R.prob(:,:,5) >= t.thr(5), strel('disk',15));
            t.verifyEqual(nnz(R.masks(:,:,3) & od), 0, 'hard exudate survives on the disc');
            t.verifyEqual(nnz(R.masks(:,:,4) & od), 0, 'soft exudate survives on the disc');
        end

        % ---------- does it actually beat doing nothing? -----------------
        function beatsTrivialBaselines(t)
            % The decisive test. AUPR on a 0.06% class looks low in absolute
            % terms, so it is only meaningful against chance.
            t.needModel();
            sp = load(fullfile(t.CFG.modelDir,'split.mat'));
            ids = sp.valIds(1:min(3,end));
            Am = cell(1,t.CFG.nChan); Ar = cell(1,t.CFG.nChan);
            prev = zeros(1,t.CFG.nChan);
            for id = ids
                [I,M] = readIdridSample(t.CFG, id, "train");
                P = slidingWindowPredict(t.net, I, t.CFG);
                for c = 1:t.CFG.nChan
                    Am{c} = prCurveAccum(Am{c}, P(:,:,c), M(:,:,c));
                    Ar{c} = prCurveAccum(Ar{c}, rand(size(M,1),size(M,2),'single'), M(:,:,c));
                    prev(c) = prev(c) + mean(M(:,:,c),'all')/numel(ids);
                end
            end
            fprintf('\n  %-16s %10s %10s %10s\n','channel','modelAP','randomAP','prevalence');
            for c = 1:t.CFG.nChan
                apM = prCurveFinish(Am{c});
                apR = prCurveFinish(Ar{c});
                fprintf('  %-16s %10.4f %10.4f %10.5f\n', t.CFG.chanName(c), apM, apR, prev(c));
                t.verifyGreaterThan(apM, 3*max(apR,1e-6), ...
                    sprintf('%s is not meaningfully better than random', t.CFG.chanName(c)));
            end
        end

        function reloadsFromDiskInFreshSession(t)
            % The saved model must be usable without any pipeline state.
            t.needModel();
            S = load(fullfile(t.CFG.modelDir,'netra_lesion_net.mat'));
            t.verifyClass(S.net, 'dlnetwork');
            t.verifyTrue(S.net.Initialized);
            y = extractdata(predict(S.net, ...
                dlarray(zeros(t.CFG.patchSize,t.CFG.patchSize,3,1,'single'),'SSCB')));
            t.verifyEqual(size(y,3), t.CFG.nChan);
        end
    end
end
