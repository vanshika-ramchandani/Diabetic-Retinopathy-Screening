function [M, c] = fieldMask(I)
%FIELDMASK  Retinal field mask and its centroid, computed on a downscaled copy.
%   [M,C] = fieldMask(I)
%     M  logical HxW, the retinal field at full resolution
%     C  [x y] centroid of that field, full-resolution coordinates
%
%   The retinal field is a single huge smooth region, so a quarter-scale mask
%   upsampled back is indistinguishable from the full-resolution one and about
%   16x cheaper. That trade is safe HERE and not in the lesion path: nothing
%   downstream of this mask is a trained model with a resolution regime, and
%   the smallest thing it decides is which half of the image the fovea is in.
small = imresize(I, 0.25);
m = retinalMask(small);

st = regionprops(m, 'Centroid');
if isempty(st)
    c = [size(I,2)/2, size(I,1)/2];
else
    c = st(1).Centroid * 4;
end
M = imresize(m, [size(I,1) size(I,2)], 'nearest');
end
