function R = netraDetect(imagePath, showFig)
%NETRADETECT  Run the NETRA multi-task lesion model on one fundus image.
%
%   R = netraDetect('path\to\fundus.jpg')
%   R = netraDetect(..., true)   also draws the overlay
%
%   ONE model, ONE forward pass, all three tasks:
%     R.masks      HxWx5 logical  (MA, HE, EX, SE, OD)
%     R.prob       HxWx5 single   raw probabilities
%     R.counts     1x5  connected-component counts per lesion
%     R.areaFrac   1x5  lesion area as a fraction of retina
%     R.haemorrhageDetected  logical  - the image-level classification output
if nargin < 2, showFig = false; end
here = fileparts(mfilename('fullpath'));
addpath(here, fullfile(here,'lib'));
CFG = s00_config();

persistent net thr
if isempty(net)
    S = load(fullfile(CFG.modelDir,'netra_lesion_net.mat')); net = S.net;
    T = load(fullfile(CFG.modelDir,'thresholds.mat'));       thr = T.thr;
end

I0 = imread(imagePath);
if size(I0,3) == 1, I0 = repmat(I0,1,1,3); end
I = applyClahe(retinalCrop(I0));

P = slidingWindowPredict(net, I, CFG);
odMask = imdilate(P(:,:,5) >= thr(5), strel('disk',15));

M = false(size(P));
for c = 1:CFG.nChan
    B = bwareaopen(P(:,:,c) >= thr(c), CFG.minCompSize(c));
    if c == 3 || c == 4, B = B & ~odMask; end
    M(:,:,c) = B;
end

R.image  = I;
R.prob   = P;
R.masks  = M;
R.counts   = arrayfun(@(c) max(0,numel(regionprops(M(:,:,c),'Area'))), 1:CFG.nChan);
R.areaFrac = squeeze(sum(M,[1 2]))' / (size(I,1)*size(I,2));
R.haemorrhageDetected = nnz(M(:,:,2)) >= 50;
R.channelNames = CFG.chanName;

if showFig
    figure; imshow(overlayLesions(I,M)); title('NETRA lesion detection');
end
end
