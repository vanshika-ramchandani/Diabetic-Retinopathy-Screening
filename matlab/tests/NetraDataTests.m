classdef NetraDataTests < matlab.unittest.TestCase
%NETRADATATESTS  Data integrity, helper correctness and leakage checks.
%   These run without a trained model.

    properties
        CFG
    end

    methods (TestClassSetup)
        function setup(t)
            here = fileparts(fileparts(mfilename('fullpath')));
            addpath(here, fullfile(here,'lib'));
            t.CFG = s00_config();
        end
    end

    methods (Test)

        % ---------- data integrity -------------------------------------
        function allTrainImagesLoad(t)
            for id = t.CFG.trainIds
                [I,M] = readIdridSample(t.CFG, id, "train");
                t.verifyEqual(size(I,3), 3, sprintf('IDRiD_%02d not RGB',id));
                t.verifyEqual(size(M,3), t.CFG.nChan);
                t.verifyEqual(size(I,1), size(M,1), sprintf('IDRiD_%02d h mismatch',id));
                t.verifyEqual(size(I,2), size(M,2), sprintf('IDRiD_%02d w mismatch',id));
            end
        end

        function allTestImagesLoad(t)
            for id = t.CFG.testIds
                [I,M] = readIdridSample(t.CFG, id, "test");
                t.verifyEqual(size(I,1), size(M,1));
                t.verifyEqual(size(I,2), size(M,2));
            end
        end

        function absentMaskBecomesZeroPlane(t)
            % IDRiD omits the .tif when a lesion is absent. Reading it as an
            % all-zero plane (not skipping the image) is what makes all 54
            % images usable for all 5 channels.
            [~,M] = readIdridSample(t.CFG, 43, "train");   % IDRiD_43 has no HE file
            t.verifyFalse(any(M(:,:,2),'all'), 'IDRiD_43 HE should be empty, not missing');
            t.verifyTrue(any(M(:,:,1),'all'),  'IDRiD_43 should still have MA');

            [~,M1] = readIdridSample(t.CFG, 1, "train");   % IDRiD_01 has no SE file
            t.verifyFalse(any(M1(:,:,4),'all'), 'IDRiD_01 SE should be empty');
            t.verifyTrue(any(M1(:,:,3),'all'),  'IDRiD_01 should still have EX');
        end

        function everyImageHasSomeLesion(t)
            for id = [1 20 43 54]
                [~,M] = readIdridSample(t.CFG, id, "train");
                t.verifyTrue(any(M(:,:,t.CFG.lesionChan),'all'), ...
                    sprintf('IDRiD_%02d has no lesion at all',id));
            end
        end

        function opticDiscPresentEverywhere(t)
            for id = [1 25 54]
                [~,M] = readIdridSample(t.CFG, id, "train");
                t.verifyTrue(any(M(:,:,5),'all'), 'optic disc missing');
            end
        end

        % ---------- leakage ---------------------------------------------
        function noSplitLeakage(t)
            sp = load(fullfile(t.CFG.modelDir,'split.mat'));
            t.verifyEmpty(intersect(sp.trainIds, sp.valIds),  'train/val overlap');
            t.verifyEmpty(intersect(sp.trainIds, sp.testIds), 'train/test overlap');
            t.verifyEmpty(intersect(sp.valIds,   sp.testIds), 'val/test overlap');
            t.verifyEqual(numel(sp.trainIds)+numel(sp.valIds), 54);
            t.verifyEqual(numel(sp.testIds), 27);
        end

        function testSetOnlyOpenedByS07(t)
            % Static leakage check. Merely naming CFG.testIds is fine (s02
            % records the split); what must not happen is a script other than
            % s07/s08 actually READING the test images.
            d = fileparts(fileparts(mfilename('fullpath')));
            f = dir(fullfile(d,'s0*.m'));
            allowed = {'s07_evaluate_test.m','s08_figures.m'};
            for k = 1:numel(f)
                src = fileread(fullfile(f(k).folder, f(k).name));
                readsTest = contains(src, '"test"') || contains(src, 'b. Testing Set');
                if readsTest
                    t.verifyTrue(any(strcmp(f(k).name, allowed)), ...
                        sprintf('%s reads the sealed test set', f(k).name));
                end
            end
            % and s06 (threshold fitting) must never read it
            src6 = fileread(fullfile(d,'s06_tune_thresholds.m'));
            t.verifyFalse(contains(src6,'"test"'), 'thresholds fitted on test data');
            t.verifyFalse(contains(src6,'testIds'), 'thresholds fitted on test data');
        end

        % ---------- helper unit tests -----------------------------------
        function maskPackRoundTrip(t)
            M = rand(64,64,5) > 0.5;
            t.verifyEqual(unpackMasks(packMasks(M), 5), M, 'bit-pack round trip lost data');
        end

        function maskPackHandlesEmptyAndFull(t)
            t.verifyEqual(unpackMasks(packMasks(false(8,8,5)),5), false(8,8,5));
            t.verifyEqual(unpackMasks(packMasks(true(8,8,5)),5),  true(8,8,5));
        end

        function retinalCropReusesBbox(t)
            I = zeros(200,300,3,'uint8'); I(50:150, 80:220, :) = 200;
            [J, bb] = retinalCrop(I);
            M = false(200,300); M(60:70, 90:100) = true;
            Mc = retinalCrop(M, bb);
            t.verifyEqual(size(Mc,1), size(J,1), 'mask/image crop height mismatch');
            t.verifyEqual(size(Mc,2), size(J,2), 'mask/image crop width mismatch');
        end

        function normaliseInputRange(t)
            X = normaliseInput(uint8(128*ones(16,16,3)), t.CFG);
            t.verifyClass(X,'single');
            t.verifyEqual(size(X), [16 16 3]);
            t.verifyTrue(all(isfinite(X),'all'));
        end

        % ---------- loss behaviour --------------------------------------
        function lossRewardsCorrectPrediction(t)
            T = single(zeros(32,32,5,2)); T(10:20,10:20,1,:) = 1;
            good = dlarray(T*0.98 + 0.01, 'SSCB');
            bad  = dlarray((1-T)*0.98 + 0.01, 'SSCB');
            Lg = extractdata(netraLoss(good, dlarray(T,'SSCB')));
            Lb = extractdata(netraLoss(bad,  dlarray(T,'SSCB')));
            t.verifyLessThan(Lg, Lb, 'loss does not prefer the correct prediction');
            t.verifyTrue(isfinite(Lg) && isfinite(Lb), 'loss is not finite');
        end

        function lossPenalisesAllZeroOnRareClass(t)
            % The failure mode this loss exists to prevent: predicting all-zero
            % against a 0.06% target must NOT be cheap.
            T = single(zeros(64,64,5,1)); T(30:32,30:32,1) = 1;   % ~0.05% of pixels
            allZero = dlarray(single(0.001*ones(64,64,5,1)),'SSCB');
            L = extractdata(netraLoss(allZero, dlarray(T,'SSCB')));
            t.verifyGreaterThan(L, 1, 'all-zero prediction is too cheap - MA will collapse');
        end

        function lossDecreasesMonotonically(t)
            T = single(zeros(32,32,5,1)); T(8:24,8:24,2) = 1;
            prev = inf;
            for a = [0.1 0.3 0.5 0.7 0.9]
                Y = dlarray(single(T*a + (1-T)*(1-a)*0.5 + 0.01),'SSCB');
                L = extractdata(netraLoss(Y, dlarray(T,'SSCB')));
                t.verifyLessThan(L, prev, 'loss not monotonic as prediction improves');
                prev = L;
            end
        end

        % ---------- patch cache -----------------------------------------
        function patchCacheIsPaired(t)
            for s = ["train","val"]
                d = fullfile(t.CFG.patchCache, s);
                ni = numel(dir(fullfile(d,'img_*.png')));
                nl = numel(dir(fullfile(d,'lab_*.png')));
                t.verifyEqual(ni, nl, sprintf('%s: img/lab count mismatch',s));
                t.verifyGreaterThan(ni, 0);
            end
        end

        function patchesHaveCorrectSizeAndChannels(t)
            ds = patchDatastore("train", t.CFG, false, 1:5);
            while hasdata(ds)
                o = read(ds);
                t.verifyEqual(size(o{1}), [t.CFG.patchSize t.CFG.patchSize 3]);
                t.verifyEqual(size(o{2}), [t.CFG.patchSize t.CFG.patchSize t.CFG.nChan]);
                t.verifyTrue(all(ismember(unique(o{2}), [0 1])), 'targets not binary');
            end
        end

        function lesionSamplingEnrichedRareClasses(t)
            % 60/40 lesion-biased sampling must lift MA well above its 0.057%
            % natural rate, or the model has almost nothing to learn from.
            ds = patchDatastore("train", t.CFG, false, 1:120);
            tot = 0; pos = zeros(1,t.CFG.nChan);
            while hasdata(ds)
                o = read(ds);
                pos = pos + reshape(sum(o{2},[1 2]),1,[]);
                tot = tot + numel(o{2}(:,:,1));
            end
            frac = pos/tot;
            t.verifyGreaterThan(frac(1), 0.001, 'MA not enriched by sampling');
            t.verifyGreaterThan(frac(2), 0.005, 'HE not enriched by sampling');
        end

        function augmentationPreservesAlignment(t)
            % A flip applied to the image but not the mask would silently destroy
            % training. Total lesion area must be invariant under augmentation.
            ds0 = patchDatastore("train", t.CFG, false, 7);
            o0  = read(ds0);
            base = reshape(sum(o0{2},[1 2]),1,[]);
            for k = 1:8
                ds = patchDatastore("train", t.CFG, true, 7);
                o  = read(ds);
                a  = reshape(sum(o{2},[1 2]),1,[]);
                t.verifyEqual(a, base, 'augmentation changed mask area');
            end
        end
    end
end
