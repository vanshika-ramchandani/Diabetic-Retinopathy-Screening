classdef NetraPipelineTests < matlab.unittest.TestCase
%NETRAPIPELINETESTS  Unit tests for the modules added in session 3.
%
%   Deliberately GPU-free and dataset-free: these test decision LOGIC, which
%   is where a screening system does harm when it is wrong. A grader that is
%   two points off is a worse model; a dual-evidence check that fails to
%   escalate a referable disagreement is a missed diagnosis.

    properties
        Root
    end

    methods (TestClassSetup)
        function addPaths(tc)
            here = fileparts(fileparts(mfilename('fullpath')));
            tc.Root = here;
            addpath(here, fullfile(here,'lib'), fullfile(here,'m1_quality'), ...
                    fullfile(here,'m2_enhance'), fullfile(here,'m4_grade'), ...
                    fullfile(here,'m5_simulink'));
        end
    end

    methods (Static)
        function M = blobs(sz, centres, r)
            % A mask with a disc of radius r at each centre.
            M = false(sz);
            [X,Y] = meshgrid(1:sz(2), 1:sz(1));
            for i = 1:size(centres,1)
                M = M | ((X-centres(i,1)).^2 + (Y-centres(i,2)).^2) <= r^2;
            end
        end
        function masks = packChan(sz, varargin)
            masks = false([sz 5]);
            for i = 1:numel(varargin)
                if ~isempty(varargin{i}), masks(:,:,i) = varargin{i}; end
            end
        end
    end

    methods (Test)

        % ---------------- retinalMask ------------------------------------
        function maskFindsDisc(tc)
            I = zeros(400,400,3,'uint8');
            [X,Y] = meshgrid(1:400,1:400);
            disc = (X-200).^2 + (Y-200).^2 <= 150^2;
            for c = 1:3, ch = I(:,:,c); ch(disc) = 180; I(:,:,c) = ch; end
            [M, frac, clipped] = retinalMask(I);
            tc.verifyGreaterThan(nnz(M), 0.9*nnz(disc));
            tc.verifyLessThan(abs(frac - nnz(disc)/numel(disc)), 0.05);
            tc.verifyFalse(clipped, 'a centred disc with margin is not clipped');
        end

        function maskDetectsClipping(tc)
            I = 200*ones(400,400,3,'uint8');   % retina fills the whole frame
            [~, frac, clipped] = retinalMask(I);
            tc.verifyGreaterThan(frac, 0.95);
            tc.verifyTrue(clipped, 'a full-frame retina must report clipped');
        end

        % ---------------- qualityMetrics ---------------------------------
        function metricsAreFiniteAndBounded(tc)
            rng(0);
            I = uint8(128 + 40*randn(500,500,3));
            q = qualityMetrics(I);
            for f = ["focus","illumUniformity","underExposed","overExposed","contrast","fovCoverage"]
                tc.verifyTrue(isfinite(q.(f)), sprintf('%s must be finite', f));
            end
            tc.verifyGreaterThanOrEqual(q.illumUniformity, 0);
            tc.verifyLessThanOrEqual(q.illumUniformity, 1);
            tc.verifyGreaterThanOrEqual(q.underExposed, 0);
            tc.verifyLessThanOrEqual(q.underExposed, 1);
        end

        function blurReducesFocus(tc)
            rng(0);
            I = uint8(128 + 50*randn(400,400,3));
            qSharp = qualityMetrics(I);
            qBlur  = qualityMetrics(imgaussfilt(I, 6));
            tc.verifyLessThan(qBlur.focus, qSharp.focus, ...
                'blurring an image must lower the focus measure');
        end

        function darkImageReadsAsUnderexposed(tc)
            I = uint8(8*ones(400,400,3));
            q = qualityMetrics(I);
            tc.verifyGreaterThan(q.underExposed, 0.5);
        end

        % ---------------- assessQuality ----------------------------------
        function gateRejectsAndInstructs(tc)
            thr = struct('focusMin',1e-3,'focusRef',1e-2, ...
                         'contrastMin',0.2,'contrastRef',0.4, ...
                         'illumMin',0.5,'illumRef',0.8, ...
                         'underMax',0.05,'overMax',0.05);
            I = uint8(8*ones(400,400,3));           % very dark, no texture
            Q = assessQuality(I, thr);
            tc.verifyEqual(Q.decision, "REJECT");
            tc.verifyFalse(Q.gradeable);
            tc.verifyNotEmpty(char(Q.instruction), ...
                'a rejection must carry an operator instruction - that is D1');
            tc.verifyGreaterThanOrEqual(Q.score, 0);
            tc.verifyLessThanOrEqual(Q.score, 100);
        end

        function gatePassesAcceptableImage(tc)
            thr = struct('focusMin',1e-9,'focusRef',1e-3, ...
                         'contrastMin',0.01,'contrastRef',0.4, ...
                         'illumMin',0.0,'illumRef',0.8, ...
                         'underMax',0.99,'overMax',0.99);
            rng(0); I = uint8(128 + 40*randn(400,400,3));
            Q = assessQuality(I, thr);
            tc.verifyEqual(Q.decision, "PASS");
            tc.verifyTrue(Q.gradeable);
        end

        % ---------------- ruleGradeICDR ----------------------------------
        function gradeZeroWhenNoLesions(tc)
            G = ruleGradeICDR(false(200,200,5), true(200,200));
            tc.verifyEqual(G.grade, 0);
            tc.verifyFalse(G.referable);
        end

        function microaneurysmsOnlyIsMild(tc)
            MA = NetraPipelineTests.blobs([200 200], [50 50; 120 140], 3);
            M  = NetraPipelineTests.packChan([200 200], MA);
            G  = ruleGradeICDR(M, true(200,200));
            tc.verifyEqual(G.grade, 1, 'MAs alone are mild NPDR');
            tc.verifyFalse(G.referable, 'grade 1 is not referable');
            tc.verifyEqual(G.counts.MA, 2);
        end

        function exudatesMakeItReferable(tc)
            MA = NetraPipelineTests.blobs([200 200], [50 50], 3);
            EX = NetraPipelineTests.blobs([200 200], [150 60], 6);
            M  = NetraPipelineTests.packChan([200 200], MA, [], EX);
            G  = ruleGradeICDR(M, true(200,200));
            tc.verifyEqual(G.grade, 2, 'anything beyond MAs alone is at least moderate');
            tc.verifyTrue(G.referable);
        end

        function rule421NeedsAllFourQuadrants(tc)
            % >20 haemorrhages in every quadrant -> severe NPDR
            sz = [400 400]; c = [];
            for qx = [1 2]
                for qy = [1 2]
                    ox = (qx-1)*200; oy = (qy-1)*200;
                    for k = 1:25
                        c(end+1,:) = [ox + 20 + mod(k*7,160), oy + 20 + mod(k*11,160)]; %#ok<AGROW>
                    end
                end
            end
            HE = NetraPipelineTests.blobs(sz, c, 2);
            M  = NetraPipelineTests.packChan(sz, [], HE);
            G  = ruleGradeICDR(M, true(sz));
            tc.verifyTrue(G.rule421, '4-2-1 must fire when all quadrants exceed 20');
            tc.verifyEqual(G.grade, 3);
            tc.verifyTrue(G.referable);
        end

        function rule421DoesNotFireOnOneQuadrant(tc)
            sz = [400 400]; c = [];
            for k = 1:25, c(end+1,:) = [20 + mod(k*7,160), 20 + mod(k*11,160)]; end %#ok<AGROW>
            HE = NetraPipelineTests.blobs(sz, c, 2);
            M  = NetraPipelineTests.packChan(sz, [], HE);
            G  = ruleGradeICDR(M, true(sz));
            tc.verifyFalse(G.rule421, 'one loaded quadrant is not the 4-2-1 criterion');
            tc.verifyEqual(G.grade, 2);
        end

        function pdrIsDeclaredUndetectable(tc)
            G = ruleGradeICDR(false(100,100,5), true(100,100));
            tc.verifyFalse(G.pdrDetectable, ...
                'no NV model exists; the rule must say so rather than imply "not PDR"');
        end

        % ---------------- dualEvidence -----------------------------------
        function agreementAutoReports(tc)
            RG = ruleGradeICDR(NetraPipelineTests.packChan([200 200], [], ...
                    NetraPipelineTests.blobs([200 200],[100 100],5)), true(200,200));
            D = dualEvidence(2, [0.02 0.03 0.90 0.03 0.02], RG);
            tc.verifyEqual(D.decision, "AUTO_REPORT");
            tc.verifyTrue(D.agree);
        end

        function referableConflictAlwaysEscalates(tc)
            % rules say referable (exudates), CNN says grade 0
            RG = ruleGradeICDR(NetraPipelineTests.packChan([200 200], [], [], ...
                    NetraPipelineTests.blobs([200 200],[100 100],6)), true(200,200));
            tc.verifyTrue(RG.referable);
            D = dualEvidence(0, [0.95 0.02 0.01 0.01 0.01], RG);
            tc.verifyEqual(D.decision, "ESCALATE");
            tc.verifyFalse(D.agree);
            tc.verifyTrue(D.referable, 'conservative fusion must keep the higher grade');
            tc.verifyEqual(D.finalGrade, 2);
        end

        function lowConfidenceEscalates(tc)
            RG = ruleGradeICDR(NetraPipelineTests.packChan([200 200], [], ...
                    NetraPipelineTests.blobs([200 200],[100 100],5)), true(200,200));
            D = dualEvidence(2, [0.2 0.2 0.25 0.2 0.15], RG);   % max 0.25 < 0.60
            tc.verifyEqual(D.decision, "ESCALATE");
        end

        function oneLevelDisagreementIsTolerated(tc)
            RG = ruleGradeICDR(NetraPipelineTests.packChan([200 200], [], ...
                    NetraPipelineTests.blobs([200 200],[100 100],5)), true(200,200));
            tc.verifyEqual(RG.grade, 2);
            D = dualEvidence(3, [0.01 0.02 0.10 0.85 0.02], RG);
            tc.verifyEqual(D.decision, "AUTO_REPORT", ...
                'one level inside the same referable class is within grader agreement');
        end

        % ---------------- districtSim ------------------------------------
        function districtArithmeticIsConsistent(tc)
            rates = struct('referable',0.20,'escalated',0.05,'rejected',0.05);
            D = districtSim(rates);
            tc.verifyGreaterThan(D.manual.reviewed, D.netra.reviewed);
            tc.verifyGreaterThan(D.manual.experts, D.netra.experts);
            tc.verifyGreaterThan(D.bandwidthCut, 0);
            tc.verifyLessThanOrEqual(D.bandwidthCut, 1);
            tc.verifyEqual(D.manual.reviewed, D.assumptions.patientsPerYear);
        end

        function flaggedFractionIsAUnionNotASum(tc)
            % 20% referable + 5% escalated must not become 25% flagged.
            rates = struct('referable',0.20,'escalated',0.05,'rejected',0);
            D = districtSim(rates);
            frac = D.nFlagged / D.nGraded;
            tc.verifyLessThan(frac, 0.25, ...
                'double-counting cases that are both referable and escalated inflates the saving');
            tc.verifyGreaterThan(frac, 0.20);
        end

        function zeroReferralDegradesGracefully(tc)
            rates = struct('referable',0,'escalated',0,'rejected',0);
            D = districtSim(rates);
            tc.verifyEqual(D.netra.reviewed, 0);
            tc.verifyEqual(D.workloadCut, 1);
        end
    end
end
