function q = qualityMetrics(I)
%QUALITYMETRICS  Five scale-free image-quality measurements on a fundus photo.
%   q = qualityMetrics(I) returns a struct of raw measurements. It applies no
%   thresholds and makes no decision - s13_calibrate_quality fits the
%   thresholds to the real APTOS distribution, and assessQuality applies them.
%
%   Every measurement is taken INSIDE the retinal mask. Including the black
%   surround would let a large border inflate "uniformity" and deflate
%   "exposure" on exactly the images that need rejecting.
if size(I,3) == 1, I = repmat(I,1,1,3); end
[M, frac, clipped] = retinalMask(I);

% Work on the green channel: highest lesion/vessel contrast in fundus imaging.
g = im2single(I(:,:,2));

% Scale invariance: every measurement below is taken on a 1024px-wide version,
% so a 4288px IDRiD frame and a 512px phone capture score comparably.
target = 1024;
if size(g,2) ~= target
    s = target / size(g,2);
    g = imresize(g, s);
    M = imresize(M, s, 'nearest');
end
if ~any(M(:)), M = true(size(g)); end

% --- 1. focus: energy of the Laplacian response inside the retina ---------
L = imfilter(g, fspecial('laplacian', 0.2), 'replicate');
q.focus = var(L(M));

% --- 2. illumination uniformity ------------------------------------------
% Large-sigma blur strips lesions and vessels and leaves only the lighting
% field. A uniformly lit retina has low spread in that field.
bg = imgaussfilt(g, 40);
v  = bg(M);
q.illumUniformity = 1 - min(std(v) / max(mean(v), eps), 1);

% --- 3/4. exposure -------------------------------------------------------
r = g(M);
q.underExposed = mean(r < 0.10);
q.overExposed  = mean(r > 0.95);

% --- 5. contrast: robust dynamic range, immune to specular outliers -------
p = prctile(double(r), [2 98]);
q.contrast = p(2) - p(1);

% --- geometry ------------------------------------------------------------
q.fovCoverage = frac;
q.clipped     = clipped;
q.meanLum     = mean(r);
end
