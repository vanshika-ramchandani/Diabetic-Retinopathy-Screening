function [c, dia, ok] = localiseOD(Pod, thr)
%LOCALISEOD  Optic-disc centre and diameter from the OD probability channel.
%   [C,DIA,OK] = localiseOD(POD, THR)
%
%   POD   HxW single, channel 5 of the lesion net's output
%   THR   the channel-5 threshold from s06 (validation-fitted)
%   C     [x y] centroid in POD's frame
%   DIA   equivalent diameter of the detected disc, px (NaN on the fallback)
%   OK    false when no component survived the threshold and the fallback ran
%
%   Localisation reuses the segmentation net's existing OD channel rather than
%   training a second model: the disc is already the one structure that net
%   predicts most reliably (Dice 0.8987), and a centroid is far more forgiving
%   of boundary error than Dice is.
%
%   On failure this still returns a point - the peak of the heavily smoothed
%   map - but flags OK false, so the caller reports how often that path ran
%   instead of quietly scoring a guess as if it were a detection.
B = Pod >= thr;
B = imfill(B, 'holes');
B = bwareaopen(B, 500);

if ~any(B(:))
    Ps = imgaussfilt(single(Pod), 25);
    [~,i] = max(Ps(:));
    [r,cc] = ind2sub(size(Pod), i);
    c = [cc r]; dia = NaN; ok = false;
    return
end

B  = bwareafilt(B, 1);
st = regionprops(B, 'Centroid', 'EquivDiameter');
c   = st(1).Centroid;          % [x y]
dia = st(1).EquivDiameter;
ok  = true;
end
