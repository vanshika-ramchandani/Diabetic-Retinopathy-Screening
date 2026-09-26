function s23_vessel_figures(nImages, style)
%S23_VESSEL_FIGURES  original | predicted vessels | ground truth, side by side.
%   s23_vessel_figures()            first 4 sealed test images, heat style
%   s23_vessel_figures(inf)         all 20
%   s23_vessel_figures(inf,"binary") white-on-black masks instead
%   s23_vessel_figures(inf,"blend")  mask blended over the fundus underneath
%
%   TWO STYLES, and they show different things:
%
%   "heat" (default) renders the model's raw PROBABILITY map on a colour ramp.
%     This is the more honest picture: it shows where the model is confident
%     and where it is hedging, including the low-probability speckle across the
%     retina that thresholding silently deletes. Ground truth is binary, so it
%     only ever takes the two end colours of the same ramp.
%
%   "binary" renders the thresholded decision - what segmentVessels actually
%     returns, and the form DRIVE results are usually published in.
%
%   "blend" lays the mask over a dimmed grayscale of the fundus, so the retina
%     stays visible behind the vessels. It reads well in a deck, but it is the
%     least honest of the three: a reader cannot tell the model's output from
%     the anatomy underneath it, and faint retinal texture can be mistaken for
%     a weak prediction. Use it to show context, never to show performance.
%
%   COLOUR: a single-hue ramp, dark navy -> bright cyan. Deliberately NOT jet
%   or turbo. A rainbow ramp puts sharp hue boundaries at arbitrary values, so
%   a reader sees edges in the probability map that are not in the data - which
%   matters here, because the whole point of the middle panel is to show a
%   smooth confidence gradient.
if nargin < 1 || isempty(nImages), nImages = 4; end
if nargin < 2 || isempty(style),   style = "heat"; end
style = string(style);
addpath(fullfile(fileparts(mfilename('fullpath')),'lib'));
CFG = s00_config();
V   = vesselConfig(CFG);

S = requireStage(fullfile(CFG.modelDir,'netra_vessel_net.mat'), ...
                 's20_train_vessels', 's20_train_vessels');
T = requireStage(fullfile(CFG.modelDir,'vessel_threshold.mat'), ...
                 's21_eval_vessels', 's21_eval_vessels');
net = S.net; thr = T.thr;

out = fullfile(CFG.resultDir,'overlays','vessels');
if ~isfolder(out), mkdir(out); end

cmap = cyanRamp(256);
ids  = CFG.driveTestIds(1:min(nImages,end));

for id = ids
    [I, L, F] = readDriveSample(id, CFG);
    P = slidingWindowPredict(net, I, V);
    P = P(:,:,1) .* single(F);          % outside the field is not a prediction

    G = single(im2gray(I))/255;         % the retina, for the blend style
    switch style
        case "binary"
            mid = single(bwareaopen(P >= thr, 20));
            gt  = single(L);
            midLabel = sprintf('Predicted Vessels  (thr %.2f)', thr);
        case "blend"
            mid = blendOver(P,         G, F);
            gt  = blendOver(single(L), G, F);
            midLabel = 'Predicted Vessels';
        otherwise
            mid = P;
            gt  = single(L);
            midLabel = 'Predicted Vessels';
    end

    f = lightFigure('Position',[100 100 1560 560]);
    t = tiledlayout(f,1,3,'TileSpacing','compact','Padding','compact');

    ax = nexttile(t); imshow(I, 'Parent', ax);
    title(ax,'Original','FontWeight','bold','FontSize',16,'Color','k');

    ax = nexttile(t); imshow(mid, [0 1], 'Parent', ax); colormap(ax, cmap);
    title(ax, midLabel,'FontWeight','bold','FontSize',16,'Color','k');

    ax = nexttile(t); imshow(gt, [0 1], 'Parent', ax); colormap(ax, cmap);
    title(ax,'Ground Truth','FontWeight','bold','FontSize',16,'Color','k');

    fn = fullfile(out, sprintf('drive_%02d_%s.png', id, style));
    exportgraphics(t, fn, 'Resolution', 150, 'BackgroundColor', 'white');
    close(f);
    fprintf('  wrote %s\n', fn);
end
fprintf('\n%d figures in %s\n', numel(ids), out);
end

% -------------------------------------------------------------------------
function V = blendOver(mask, gray, fov)
%BLENDOVER  Mask over a dimmed retina, both inside the field only.
%   The retina is compressed into the bottom third of the ramp so it can never
%   reach the brightness a confident vessel reaches - otherwise bright anatomy
%   (the optic disc especially) would read as a strong prediction.
V = 0.30*gray + 0.70*mask;
V = min(max(V,0),1) .* single(fov);
end

% -------------------------------------------------------------------------
function c = cyanRamp(n)
%CYANRAMP  Single-hue sequential ramp: near-black navy -> bright cyan.
%   Monotonic in lightness, so a brighter pixel always means a higher
%   probability - the property jet and turbo both break.
t = linspace(0,1,n)';
c = min(max([0.03 + 0.20*t.^1.6, 0.05 + 0.85*t.^0.9, 0.18 + 0.78*t.^0.8], 0), 1);
end
