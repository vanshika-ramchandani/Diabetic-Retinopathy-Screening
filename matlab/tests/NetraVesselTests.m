classdef NetraVesselTests < matlab.unittest.TestCase
%NETRAVESSELTESTS  DRIVE data integrity, FOV derivation and split leakage.
%   The data tests run without a trained model. The model tests skip
%   themselves if s20 has not been run yet rather than failing.

    properties
        CFG
    end

    methods (TestClassSetup)
        function setup(t)
            here = fileparts(fileparts(mfilename('fullpath')));
            addpath(here, fullfile(here,'lib'), fullfile(here,'m6_vessels'));
            t.CFG = s00_config();
            t.assumeTrue(isfolder(t.CFG.driveRoot), 'DRIVE not present');
        end
    end

    methods (Test)

        % ---------- data integrity -------------------------------------
        function allDriveImagesLoad(t)
            for id = [t.CFG.driveTrainIds t.CFG.driveTestIds]
                [I,L,F] = readDriveSample(id, t.CFG);
                t.verifyEqual(size(I,3), 3, sprintf('DRIVE %02d not RGB', id));
                t.verifyEqual(size(L), size(I,[1 2]), sprintf('DRIVE %02d label size', id));
                t.verifyEqual(size(F), size(I,[1 2]), sprintf('DRIVE %02d fov size', id));
                t.verifyTrue(islogical(L) && islogical(F));
            end
        end

        function labelsAreBinaryAndPlausible(t)
            for id = [t.CFG.driveTrainIds t.CFG.driveTestIds]
                [~,L,F] = readDriveSample(id, t.CFG);
                frac = mean(L(F));
                % Published DRIVE vessel density inside the field is ~12-13%.
                % Anything far outside that band means the label was misread.
                t.verifyGreaterThan(frac, 0.04, sprintf('DRIVE %02d too few vessels', id));
                t.verifyLessThan(frac,    0.30, sprintf('DRIVE %02d too many vessels', id));
            end
        end

        function derivedFovContainsTheLabels(t)
            % The FOV masks are DERIVED, not shipped. If the derivation were
            % wrong it would crop real vessel away and quietly inflate every
            % metric computed inside it, so the containment is asserted.
            for id = t.CFG.driveTestIds
                [~,L,F] = readDriveSample(id, t.CFG);
                outside = nnz(L & ~F);
                t.verifyLessThan(outside, 200, ...
                    sprintf('DRIVE %02d: %d vessel px outside derived FOV', id, outside));
                t.verifyGreaterThan(mean(F(:)), 0.60, sprintf('DRIVE %02d FOV too small', id));
                t.verifyLessThan(mean(F(:)),    0.80, sprintf('DRIVE %02d FOV too large', id));
            end
        end

        % ---------- leakage ---------------------------------------------
        function splitsAreDisjoint(t)
            f = fullfile(t.CFG.modelDir,'vessel_split.mat');
            t.assumeTrue(isfile(f), 's19 not run');
            S = load(f);
            t.verifyEmpty(intersect(S.fitId, S.valId), 'fit/val overlap');
            t.verifyEmpty(intersect(S.fitId, t.CFG.driveTestIds), 'fit/test overlap');
            t.verifyEmpty(intersect(S.valId, t.CFG.driveTestIds), 'val/test overlap');
            t.verifyEqual(sort([S.fitId S.valId]), t.CFG.driveTrainIds, ...
                'fit+val must exactly reconstitute the DRIVE training set');
        end

        function testSetIsTheOfficialDriveTestSet(t)
            % 01..20 are DRIVE's official test images. If this ever changes,
            % the numbers stop being comparable to published DRIVE results.
            t.verifyEqual(t.CFG.driveTestIds, 1:20);
            t.verifyEqual(t.CFG.driveTrainIds, 21:40);
        end

        % ---------- loss -------------------------------------------------
        function lossIgnoresPixelsOutsideTheFov(t)
            % Two targets identical inside the field and opposite outside it
            % must score the same, or the FOV masking is not actually working.
            rng(0);
            Y = rand(32,32,1,2,'single')*0.8 + 0.1;
            lab = single(rand(32,32,1,2) > 0.7);
            fov = zeros(32,32,1,2,'single'); fov(5:28,5:28,:,:) = 1;

            a = vesselLoss(Y, cat(3, lab, fov));
            lab2 = lab; lab2(fov == 0) = 1 - lab2(fov == 0);
            b = vesselLoss(Y, cat(3, lab2, fov));
            t.verifyEqual(extractdata(dlarray(a)), extractdata(dlarray(b)), 'AbsTol', 1e-5);
        end

        % ---------- trained model ---------------------------------------
        function vesselNetProducesSaneOutput(t)
            f = fullfile(t.CFG.modelDir,'netra_vessel_net.mat');
            t.assumeTrue(isfile(f), 's20 not run');
            t.assumeTrue(isfile(fullfile(t.CFG.modelDir,'vessel_threshold.mat')), 's21 not run');

            R = segmentVessels(fullfile(t.CFG.driveRoot,'val','input','01.tif'));
            t.verifyTrue(islogical(R.mask));
            t.verifyGreaterThanOrEqual(min(R.prob(:)), 0);
            t.verifyLessThanOrEqual(max(R.prob(:)), 1);
            t.verifyFalse(any(R.mask & ~R.fov, 'all'), 'vessels reported outside the FOV');
            t.verifyGreaterThan(R.areaFrac, 0.04);
            t.verifyLessThan(R.areaFrac,    0.30);
        end
    end
end
