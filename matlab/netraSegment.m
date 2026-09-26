function S = netraSegment(imagePath, showFig)
%NETRASEGMENT  Module 2 in one call: lesion evidence + vascular tree.
%
%   S = netraSegment('path\to\fundus.jpg')
%   S = netraSegment(..., true)   draws the combined figure
%
%   Module 2 of the problem statement asks for lesion detection AND retinal
%   structure segmentation. Those are two different jobs, so they are two
%   different networks with their own weights, their own training data and
%   their own sealed test sets:
%
%     lesions   netra_lesion_net.mat   5-channel, IDRiD, 512px patches
%     vessels   netra_vessel_net.mat   1-channel, DRIVE, 256px patches
%
%   This wrapper is PRESENTATION ONLY. It calls both and puts their outputs in
%   one struct and one picture. It does not fuse them, and nothing here feeds
%   the DR grade - netraScreen still grades from the lesion channels alone.
%   Combining them into a severity decision would need artery/vein labels and
%   vessel calibre that neither model produces, and it would silently invalidate
%   the D2 dual-evidence results already measured in results/.
%
%   RESOLUTION / DOMAIN WARNING, and it is not a footnote. The vessel net was
%   trained on DRIVE: 45-degree field, 584x565, one camera, 20 images. The
%   lesion net was trained on IDRiD at 4288x2848. On an IDRiD or APTOS image
%   the vessel half is running outside its training distribution, and S.vessels
%   .inDomain records that. Use the vessel output on DRIVE-like images for
%   measurement; treat it as a qualitative overlay anywhere else.
%
%   S.lesions   struct from netraDetect - masks, counts, areaFrac
%   S.vessels   struct from segmentVessels - mask, prob, fov, areaFrac
%   S.image     the retinal crop both were run on
if nargin < 2, showFig = false; end
here = fileparts(mfilename('fullpath'));
addpath(here, fullfile(here,'lib'), fullfile(here,'m6_vessels'));
CFG = s00_config();

I0 = imread(imagePath);
if size(I0,3) == 1, I0 = repmat(I0,1,1,3); end
I = retinalCrop(I0);

fprintf('netraSegment: %s  [%dx%d]\n', imagePath, size(I,1), size(I,2));

% ---- lesion net ---------------------------------------------------------
t0 = tic;
S.lesions = netraDetect(imagePath);
tLes = toc(t0);

% ---- vessel net ---------------------------------------------------------
t0 = tic;
S.vessels = segmentVessels(I);
tVes = toc(t0);

S.image   = I;
S.timing  = struct('lesionSec',tLes,'vesselSec',tVes);

fprintf('  lesions  %s  (%.1f s)\n', ...
        strjoin(compose("%s=%d", CFG.chanSuffix(:), double(S.lesions.counts(:))), '  '), tLes);
fprintf('  vessels  %.1f%% of field  (%.1f s)%s\n', 100*S.vessels.areaFrac, tVes, ...
        ternaryStr(S.vessels.inDomain, '', '   <-- OUT OF DOMAIN, qualitative only'));

if showFig, drawModule2(S, CFG); end
end

% -------------------------------------------------------------------------
function drawModule2(S, CFG)
I = S.image;

f = lightFigure('Position',[80 80 1500 560]);
t = tiledlayout(f,1,3,'TileSpacing','compact','Padding','compact');

ax = nexttile(t); imshow(I,'Parent',ax);
title(ax,'Fundus','FontWeight','bold','FontSize',15,'Color','k');

ax = nexttile(t); imshow(overlayLesions(I, S.lesions.masks),'Parent',ax);
title(ax,'Lesions  (MA · HE · EX · SE · OD)','FontWeight','bold','FontSize',15,'Color','k');

ax = nexttile(t);
V = I; R = V(:,:,1); G = V(:,:,2); B = V(:,:,3);
m = S.vessels.mask;
R(m) = 0; G(m) = 255; B(m) = 255;          % cyan, distinct from every lesion hue
imshow(cat(3,R,G,B),'Parent',ax);
ttl = sprintf('Vessels  (%.1f%% of field)', 100*S.vessels.areaFrac);
if ~S.vessels.inDomain, ttl = [ttl '  — out of domain']; end
title(ax, ttl, 'FontWeight','bold','FontSize',15,'Color','k');

sgtitle(f, 'NETRA — Module 2: lesion detection + retinal structure', ...
        'FontWeight','bold','FontSize',17,'Color','k');
set(f,'Visible','on');
end

% -------------------------------------------------------------------------
function s = ternaryStr(c,a,b)
if c, s = a; else, s = b; end
end
