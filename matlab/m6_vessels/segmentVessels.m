function R = segmentVessels(image, showFig)
%SEGMENTVESSELS  Vascular tree from one fundus image - the D-vessel module.
%
%   R = segmentVessels('path\to\fundus.jpg')
%   R = segmentVessels(I)          I is an HxWx3 uint8 image already in memory
%   R = segmentVessels(..., true)  also draws the overlay
%
%   R.mask        HxW logical  vessel tree at the frozen threshold
%   R.prob        HxW single   raw probability map
%   R.fov         HxW logical  field of view used for every measurement
%   R.areaFrac    vessel area as a fraction of the FIELD, not of the frame
%   R.threshold   the threshold from s21, unchanged
%
%   SCOPE - read before quoting this anywhere.
%   This returns the vascular TREE only: a binary vessel / not-vessel map. It
%   does not classify arteries against veins and it does not measure calibre,
%   so on its own it does not deliver the venous-beading or IRMA arms of the
%   4-2-1 rule that ruleGradeICDR still leaves open. Those need A/V labels
%   (DRIVE has none - RITE or HRF do) on top of this tree.
%
%   SCALE NORMALISATION - why this is not optional. The model is trained on
%   DRIVE, whose retinal field is ~536 px across. A vessel is 1-5 px wide
%   there. On an IDRiD image the same vessel is ~5x wider in pixels, and a
%   convolutional net has no way to know that - fed IDRiD at native size it
%   returns 0.8% vessel where the truth is ~13%, i.e. it fails almost
%   completely. So the image is rescaled so its FIELD DIAMETER matches DRIVE's
%   before prediction, and the resulting mask is scaled back. R.scale records
%   the factor used. This fixes the resolution regime; it does not fix camera
%   colour or optics, so a non-DRIVE camera is still outside the training
%   distribution and R.inDomain stays the honest flag to check.
if nargin < 2, showFig = false; end
here = fileparts(fileparts(mfilename('fullpath')));
addpath(here, fullfile(here,'lib'));
CFG = s00_config();
V   = vesselConfig(CFG);

persistent net thr
if isempty(net)
    S = requireStage(fullfile(CFG.modelDir,'netra_vessel_net.mat'), ...
                     's20_train_vessels', 's20_train_vessels');
    T = requireStage(fullfile(CFG.modelDir,'vessel_threshold.mat'), ...
                     's21_eval_vessels', 's21_eval_vessels');
    net = S.net; thr = T.thr;
end

if ischar(image) || isstring(image), I = imread(image); else, I = image; end
if size(I,3) == 1, I = repmat(I,1,1,3); end

F = retinalMask(I);

% Rescale so the retinal field is DRIVE-sized, predict there, then map back.
dia   = sqrt(4*nnz(F)/pi);
scale = CFG.vesselRefDia / max(dia, 1);
if abs(log(scale)) > 0.05
    Is = imresize(I, scale);
    Ps = slidingWindowPredict(net, Is, V);
    P  = imresize(Ps(:,:,1), [size(I,1) size(I,2)]);
else
    scale = 1;
    P = slidingWindowPredict(net, I, V);
    P = P(:,:,1);
end
P = min(max(P,0),1);

% Outside the field the input is black frame the net never trained on, so its
% output there is meaningless rather than merely wrong. Masking is not cosmetic.
M = (P >= thr) & F;
M = bwareaopen(M, 20);          % drop speckle below any plausible vessel size

R.mask      = M;
R.prob      = P;
R.fov       = F;
R.areaFrac  = nnz(M) / max(nnz(F),1);
R.threshold = thr;
R.scale     = scale;
R.fieldDia  = dia;
% DRIVE-like optics, not merely DRIVE-like size. Scale is corrected above;
% this flag is about the camera the net has never seen.
R.inDomain  = abs(log(scale)) < 0.35;

if showFig
    f = figure('Name','NETRA vessels'); lightFigure(f);
    ax = subplot(1,2,1); imshow(I);  title(ax,'input');   lightAxes(ax);
    ax = subplot(1,2,2);
    O = I; Rc = O(:,:,1); Gc = O(:,:,2); Bc = O(:,:,3);
    Rc(M) = 0; Gc(M) = 255; Bc(M) = 0;
    imshow(cat(3,Rc,Gc,Bc));
    title(ax, sprintf('vessels - %.1f%% of field', 100*R.areaFrac)); lightAxes(ax);
end
end
