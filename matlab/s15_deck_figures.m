function s15_deck_figures()
%S15_DECK_FIGURES  Render the images the deck places on slides 1 and 3.
%
%   figures/title_hero.png  one fundus image with its Grad-CAM overlay
%   figures/triptych.png    raw -> enhanced -> lesion overlay, side by side
%
%   Both come from real held-out images. No synthetic or stock retinal
%   imagery goes anywhere near this deck: a judge who asks "where did that
%   picture come from" must get a file path, not a shrug.
here = fileparts(mfilename('fullpath'));
addpath(here, fullfile(here,'lib'), fullfile(here,'m1_quality'), ...
        fullfile(here,'m2_enhance'), fullfile(here,'m4_grade'));
CFG = s00_config();
figDir = fullfile(CFG.root,'figures');
if ~isfolder(figDir), mkdir(figDir); end

testDir = fullfile(CFG.segRoot,'1. Original Images','b. Testing Set');

% ================= triptych: raw -> enhanced -> lesions ==================
src = fullfile(testDir,'IDRiD_60.jpg');
if ~isfile(src)
    d = dir(fullfile(testDir,'IDRiD_*.jpg'));
    src = fullfile(d(1).folder, d(1).name);
end
fprintf('triptych from %s\n', src);
R = netraScreen(src, struct('verbose',false,'gradcam',false));

raw = imresize(R.image,    [420 420]);
enh = imresize(R.enhanced, [420 420]);
if isempty(R.masks)
    ov = raw;
else
    ov = imresize(R.overlay, [420 420]);
end
gap = 255*ones(420, 14, 3, 'uint8');
strip = [raw gap enh gap ov];
imwrite(strip, fullfile(figDir,'triptych.png'));
fprintf('wrote figures/triptych.png\n');

% ================= title hero: fundus + Grad-CAM =========================
gf = fullfile(CFG.modelDir,'netra_grader.mat');
made = false;
if isfile(gf)
    S = load(gf); net = S.net;
    sp = fullfile(CFG.modelDir,'grader_split.mat');
    pick = "";
    if isfile(sp)
        P = load(sp); split = P.split;
        y = double(split.y) - 1;
        idx = find(split.isTest & (y(:) >= 3), 1);   % a visibly diseased eye
        if ~isempty(idx), pick = split.files(idx); end
    end
    if pick == "" , pick = string(src); end
    fprintf('title hero from %s\n', pick);

    I  = imread(pick);
    if size(I,3)==1, I = repmat(I,1,1,3); end
    I  = retinalCrop(I);
    Ir = imresize(applyClahe(I), [CFG.graderSize CFG.graderSize]);
    X  = dlarray(single(normaliseInput(Ir,CFG)),'SSCB');
    sc = double(extractdata(predict(net,X)));
    [conf, gi] = max(sc);
    try
        cam = rescale(extractdata(gradCAM(net, X, gi)));
        cam = imresize(cam, [CFG.graderSize CFG.graderSize]);

        % A flat 42% jet wash over the whole frame buries the retina - the
        % title image stops reading as a fundus photograph at all. Ramp the
        % alpha with the activation so cold regions stay clear and only the
        % evidence the network actually used is tinted.
        alpha = 0.72 * max(0, (cam - 0.45) / 0.55).^0.8;

        % Base image = the cached 512px file, which is already retinalCrop +
        % CLAHE. That is the same picture the network saw, which is the honest
        % thing to put a Grad-CAM on.
        base = imread(pick);
        if size(base,3)==1, base = repmat(base,1,1,3); end
        base = imresize(retinalCrop(base), [CFG.graderSize CFG.graderSize]);

        f = lightFigure('Position',[100 100 620 620]);
        ax = axes(f,'Position',[0 0 1 1]);
        imshow(base,'Parent',ax); hold(ax,'on');
        h = imagesc(ax, cam);
        set(h,'AlphaData',alpha); colormap(ax,'jet'); axis(ax,'off');
        exportgraphics(ax, fullfile(figDir,'title_hero.png'), 'Resolution',150);
        close(f);
        fprintf('wrote figures/title_hero.png  (predicted grade %d, p=%.2f)\n', gi-1, conf);
        made = true;
    catch ME
        fprintf('gradCAM failed for hero: %s\n', ME.message);
    end
end

if ~made
    % Grader unavailable - fall back to the lesion overlay, which is still a
    % real result from this build rather than a placeholder.
    imwrite(imresize(R.overlay,[620 620]), fullfile(figDir,'title_hero.png'));
    fprintf('wrote figures/title_hero.png (lesion overlay fallback)\n');
end
end
