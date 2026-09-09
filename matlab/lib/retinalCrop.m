function [J, bbox] = retinalCrop(I, bbox)
%RETINALCROP  Crop the black surround off a fundus image.
%   [J,BBOX] = retinalCrop(I)        computes the retinal bounding box.
%   J        = retinalCrop(I,BBOX)   applies a bounding box (for masks).
if nargin < 2 || isempty(bbox)
    g = im2gray(I);
    m = g > 10;
    m = imfill(m,'holes');
    if any(m(:))
        m = bwareafilt(m,1);
        st = regionprops(m,'BoundingBox');
        bbox = round(st(1).BoundingBox);
        bbox(1:2) = max(bbox(1:2),1);
        bbox(3) = min(bbox(3), size(I,2)-bbox(1));
        bbox(4) = min(bbox(4), size(I,1)-bbox(2));
    else
        bbox = [1 1 size(I,2)-1 size(I,1)-1];
    end
end
J = I(bbox(2):bbox(2)+bbox(4), bbox(1):bbox(1)+bbox(3), :);
end
