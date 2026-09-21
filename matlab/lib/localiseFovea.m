function [c, info] = localiseFovea(I, odCentre, odDia, prm, retMask)
%LOCALISEFOVEA  Fovea centre as the darkest macular point near an anatomical prior.
%   [C,INFO] = localiseFovea(I, ODCENTRE, ODDIA, PRM, RETMASK)
%
%   I         HxWx3 fundus image, in whatever frame ODCENTRE is given in
%   ODCENTRE  [x y] optic-disc centre
%   ODDIA     reference optic-disc diameter, px
%   PRM       fitted prior: .dxDD .dyDD .searchDD .closeDD .smoothDD .lambda .scale
%   RETMASK   logical retinal field mask, or [] to compute it here
%   C         [x y] fovea centre
%   INFO      .side (+1/-1 temporal direction), .prior (the prior point), .fallback
%
%   Why this is not a trained model: IDRiD marks the fovea with a single
%   coordinate, not a mask, so there is nothing to segment, and 413 points is
%   thin for regressing two numbers off a 4288x2848 image. The anatomy is
%   strong enough to exploit directly - the fovea is the darkest broad patch of
%   retina at a near-fixed offset from the disc - so the only things fitted are
%   that offset and the search geometry, measured on the training split.
%
%   Laterality needs no classifier. The disc sits nasally in both eyes, so the
%   fovea is always on the side of the disc facing the centre of the retinal
%   field, whichever eye this is.
%
%   The search runs on a downscaled copy of the window (PRM.scale). That is
%   safe here in a way it is NOT safe in the lesion path: this is a classical
%   operator with no trained resolution regime, and the fovea is a feature
%   hundreds of pixels wide, so 4x downscaling costs a few pixels of precision
%   against a tolerance measured in optic-disc diameters.
if nargin < 5 || isempty(retMask), retMask = retinalMask(I); end
[H,W,~] = size(I);

% ---- which way is temporal ---------------------------------------------
% PRM.fieldC lets a caller hoist this out of a grid search; recomputing the
% field centroid 144 times for the same image is pure waste.
if isfield(prm,'fieldC') && ~isempty(prm.fieldC)
    fieldC = prm.fieldC;
else
    st = regionprops(retMask, 'Centroid');
    if isempty(st), fieldC = [W/2 H/2]; else, fieldC = st(1).Centroid; end
end
side = sign(fieldC(1) - odCentre(1));
if side == 0, side = 1; end

% ---- anatomical prior ---------------------------------------------------
p = [odCentre(1) + side*prm.dxDD*odDia, odCentre(2) + prm.dyDD*odDia];
info = struct('side', side, 'prior', p, 'fallback', true);

% ---- search window ------------------------------------------------------
r  = prm.searchDD * odDia;
x0 = max(1, floor(p(1)-r)); x1 = min(W, ceil(p(1)+r));
y0 = max(1, floor(p(2)-r)); y1 = min(H, ceil(p(2)+r));
if x1-x0 < 8 || y1-y0 < 8
    % The prior landed off the frame - a clipped field, or a disc detected
    % near an edge. Return the nearest point that is actually on the retina
    % rather than a coordinate outside the image.
    c = clampToField(p, retMask); return
end

s  = prm.scale;
g  = imresize(I(y0:y1, x0:x1, 2), s);              % green: best retinal contrast
m  = imresize(retMask(y0:y1, x0:x1), s, 'nearest');
dd = max(odDia*s, 4);

% The dark rim outside the retina would otherwise always win.
m = imerode(m, strel('disk', max(1, round(0.5*dd))));
if ~any(m(:))
    c = clampToField(p, retMask); return
end

% Vessels are dark and thin; the fovea is dark and broad. Closing removes the
% former and leaves the latter, so the minimum lands on the macula and not on
% an arcade crossing.
g = imclose(g, strel('disk', max(1, round(prm.closeDD*dd))));
g = imgaussfilt(single(g), max(0.5, prm.smoothDD*dd));

% A distance penalty stops a dark artefact at the window edge outvoting a
% slightly less dark point exactly where the fovea belongs.
[xx,yy] = meshgrid(1:size(g,2), 1:size(g,1));
px = (p(1)-x0)*s + 0.5;  py = (p(2)-y0)*s + 0.5;
d2 = ((xx-px).^2 + (yy-py).^2) / (dd^2);

score = g + prm.lambda*d2;
score(~m) = inf;
if all(isinf(score(:)))
    c = clampToField(p, retMask); return
end

[~,i]   = min(score(:));
[ry,rx] = ind2sub(size(score), i);
c = [x0 + (rx-0.5)/s - 0.5, y0 + (ry-0.5)/s - 0.5];
info.fallback = false;
end

% =========================================================================
function q = clampToField(p, retMask)
%CLAMPTOFIELD  Nearest point on the retina to P.
%   Every fallback in this file goes through here. A prior that lands off the
%   frame - a clipped field, or a disc detected near an edge - must still
%   produce a coordinate someone can draw on the image, not one outside it.
[H,W] = size(retMask);
q = [min(max(p(1),1), W), min(max(p(2),1), H)];
if retMask(round(q(2)), round(q(1))), return; end

small = imresize(retMask, 0.25, 'nearest');
if ~any(small(:)), return; end
[~, idx] = bwdist(small);
r = min(max(round(q(2)*0.25), 1), size(small,1));
c = min(max(round(q(1)*0.25), 1), size(small,2));
[sy, sx] = ind2sub(size(small), idx(r,c));
q = [min(sx*4, W), min(sy*4, H)];
end
