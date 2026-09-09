function s06_tune_thresholds()
%S06_TUNE_THRESHOLDS  Fit per-channel decision thresholds on the 10 VALIDATION
%   images. The 27 official test images are not opened here.
addpath(fullfile(fileparts(mfilename('fullpath')),'lib'));
CFG = s00_config();
S = requireStage(fullfile(CFG.modelDir,'netra_lesion_net.mat'), 's05_train_seg (training)', 's05_train_seg'); net = S.net;
sp = load(fullfile(CFG.modelDir,'split.mat'));

A = cell(1,CFG.nChan);
fprintf('tuning on %d validation images\n', numel(sp.valIds));
for id = sp.valIds
    t0 = tic;
    [I,M] = readIdridSample(CFG, id, "train");
    P = slidingWindowPredict(net, I, CFG);
    for c = 1:CFG.nChan
        A{c} = prCurveAccum(A{c}, P(:,:,c), M(:,:,c));
    end
    fprintf('  IDRiD_%02d  %.1fs\n', id, toc(t0));
end

thr = zeros(1,CFG.nChan); ap = zeros(1,CFG.nChan); f1 = zeros(1,CFG.nChan);
fprintf('\n%-16s %8s %8s %8s\n','channel','valAP','bestF1','thr');
for c = 1:CFG.nChan
    [ap(c), f1(c), thr(c)] = prCurveFinish(A{c});
    fprintf('%-16s %8.4f %8.4f %8.3f\n', CFG.chanName(c), ap(c), f1(c), thr(c));
end

save(fullfile(CFG.modelDir,'thresholds.mat'),'thr','ap','f1','CFG');
fprintf('\nsaved models/thresholds.mat\n');
end
