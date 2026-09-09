function [M, frac, clipped] = retinalMask(I)
%RETINALMASK  Binary mask of the illuminated retinal disc inside a fundus frame.
%   [M,FRAC,CLIPPED] = retinalMask(I)
%     M       logical HxW  - the retinal field
%     FRAC    retinal area as a fraction of the whole frame
%     CLIPPED true when the retina touches a frame edge (field cut off)
%
%   Uses the same >10 grey threshold as retinalCrop so the mask and the crop
%   never disagree about where the retina is.
g = im2gray(I);
M = g > 10;
M = imfill(M,'holes');
if ~any(M(:))
    M = true(size(g)); frac = 1; clipped = true; return;
end
M = bwareafilt(M,1);
M = imopen(M, strel('disk',5));
if ~any(M(:)), M = imfill(g>10,'holes'); end
frac = nnz(M) / numel(M);

% A properly framed fundus disc sits clear of the border. Touching an edge
% along a long run means the field of view is cut, not merely tight.
b = false(1,4);
b(1) = mean(M(1,:))   > 0.20;
b(2) = mean(M(end,:)) > 0.20;
b(3) = mean(M(:,1))   > 0.20;
b(4) = mean(M(:,end)) > 0.20;
clipped = any(b);
end
