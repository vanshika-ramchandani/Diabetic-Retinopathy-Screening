function A = prCurveAccum(A, prob, gt, nBins)
%PRCURVEACCUM  Accumulate a histogram-based PR curve across many images.
%   Storing 12M pixels x 27 images is not viable, so scores are binned once
%   per image and the curve is computed from cumulative counts at the end.
if nargin < 4, nBins = 1000; end
if isempty(A), A = struct('pos',zeros(nBins,1),'neg',zeros(nBins,1),'nBins',nBins); end
b = min(max(floor(double(prob(:))*A.nBins)+1, 1), A.nBins);
g = gt(:);
A.pos = A.pos + accumarray(b(g),  1, [A.nBins 1]);
A.neg = A.neg + accumarray(b(~g), 1, [A.nBins 1]);
end
