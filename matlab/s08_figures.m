function s08_figures(nImages)
%S08_FIGURES  Prediction-vs-ground-truth overlays on held-out test images.
%   s08_figures()     the first 6 test images (quick look)
%   s08_figures(inf)  all 27 - what the appendix and the demo folder want
if nargin < 1 || isempty(nImages), nImages = 6; end
addpath(fullfile(fileparts(mfilename("fullpath")),"lib"));
CFG = s00_config();
S = requireStage(fullfile(CFG.modelDir,'netra_lesion_net.mat'), 's05_train_seg (training)', 's05_train_seg'); net = S.net;
T = requireStage(fullfile(CFG.modelDir,'thresholds.mat'), 's06_tune_thresholds', 's06_tune_thresholds'); thr = T.thr;
out = fullfile(CFG.resultDir,'overlays');
if ~isfolder(out), mkdir(out); end

for id = CFG.testIds(1:min(nImages,end))
    [I,M] = readIdridSample(CFG, id, "test");
    P = slidingWindowPredict(net, I, CFG);
    odMask = imdilate(P(:,:,5) >= thr(5), strel('disk',15));
    Pred = false(size(P));
    for c = 1:CFG.nChan
        B = bwareaopen(P(:,:,c) >= thr(c), CFG.minCompSize(c));
        if c == 3 || c == 4, B = B & ~odMask; end
        Pred(:,:,c) = B;
    end
    sc = 1400/size(I,2);
    gtI = imresize(overlayLesions(I,M),    sc);
    prI = imresize(overlayLesions(I,Pred), sc);
    pad = 255*ones(size(gtI,1), 12, 3, 'uint8');
    imwrite([gtI pad prI], fullfile(out, sprintf('IDRiD_%02d_gt_vs_pred.png',id)));
    fprintf('  IDRiD_%02d overlay written\n', id);
end
fprintf('overlays in %s  (left = ground truth, right = prediction)\n', out);
end
