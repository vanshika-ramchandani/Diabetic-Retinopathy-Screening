function Q = assessQuality(I, thr)
%ASSESSQUALITY  Decide whether a fundus image is gradeable - differentiator D1.
%
%   Q = assessQuality(I)      uses the calibrated thresholds from
%                             models/quality_thresholds.mat
%   Q = assessQuality(I, thr) uses supplied thresholds
%
%   Q.decision     "PASS" | "ENHANCE" | "REJECT"
%   Q.score        0-100 overall gradeability score
%   Q.instruction  operator-facing recapture instruction (REJECT only)
%   Q.reasons      cellstr of every criterion that failed
%   Q.metrics      the raw measurements from qualityMetrics
%
%   The point of this module is that NETRA declines to produce a grade it
%   cannot justify. A classifier forced to answer on an ungradeable image
%   returns a confident number with nothing behind it; that is the failure
%   mode this gate exists to prevent.
if nargin < 2 || isempty(thr)
    here = fileparts(fileparts(mfilename('fullpath')));
    f = fullfile(here,'models','quality_thresholds.mat');
    if ~isfile(f)
        error('NETRA:noQualityThresholds', ...
            ['\n  Missing: models/quality_thresholds.mat\n' ...
             '  This comes from: s13_calibrate_quality\n' ...
             '  Do this first:   s13_calibrate_quality\n']);
    end
    S = load(f); thr = S.thr;
end

q = qualityMetrics(I);
reasons = {}; instr = {};

% --- hard failures: no enhancement recovers these ------------------------
if q.focus < thr.focusMin
    reasons{end+1} = sprintf('out of focus (%.2e < %.2e)', q.focus, thr.focusMin);
    instr{end+1}   = 'image is blurred - hold the camera steady and refocus';
end
if q.underExposed > thr.underMax
    reasons{end+1} = sprintf('underexposed (%.1f%% of retina below 0.10)', 100*q.underExposed);
    instr{end+1}   = 'image is too dark - increase flash intensity and recapture';
end
if q.overExposed > thr.overMax
    reasons{end+1} = sprintf('overexposed (%.1f%% of retina above 0.95)', 100*q.overExposed);
    instr{end+1}   = 'image is washed out - reduce flash intensity and recapture';
end
if q.contrast < thr.contrastMin
    reasons{end+1} = sprintf('insufficient contrast (%.3f < %.3f)', q.contrast, thr.contrastMin);
    instr{end+1}   = 'retinal detail is not visible - clean the lens and recapture';
end

% --- soft failure: recoverable by M2 enhancement -------------------------
softFail = q.illumUniformity < thr.illumMin;

if ~isempty(reasons)
    Q.decision    = "REJECT";
    Q.instruction = strjoin(instr, '; ');
elseif softFail
    Q.decision    = "ENHANCE";
    Q.instruction = "";
    reasons{end+1} = sprintf('uneven illumination (%.2f < %.2f) - correctable', ...
                             q.illumUniformity, thr.illumMin);
else
    Q.decision    = "PASS";
    Q.instruction = "";
end

% --- 0-100 score ---------------------------------------------------------
% Each term is the metric's position between the reject threshold and the
% median of the calibration set, clamped to [0,1]. Equal weights: no term
% has evidence entitling it to a larger one.
t = [ ramp(q.focus,           thr.focusMin,    thr.focusRef)
      ramp(q.contrast,        thr.contrastMin, thr.contrastRef)
      ramp(q.illumUniformity, thr.illumMin,    thr.illumRef)
      ramp(thr.underMax - q.underExposed, 0, thr.underMax)
      ramp(thr.overMax  - q.overExposed,  0, thr.overMax ) ];
Q.score   = round(100 * mean(t));
Q.reasons = reasons;
Q.metrics = q;
Q.gradeable = Q.decision ~= "REJECT";
end

function y = ramp(x, lo, hi)
if hi <= lo, y = double(x >= hi); return; end
y = min(max((x - lo) / (hi - lo), 0), 1);
end
