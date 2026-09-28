%S25_EXPORT_ONNX  Hand the three networks and every constant to the web app (web/).
%
%   After the MATLAB licence lapses (4 Oct 2026) the live prototype runs as
%   Python + ONNX Runtime. This script is the only bridge: it writes
%     web/models/lesion.onnx    512x512 patches, NCHW, no input normalisation
%     web/models/vessel.onnx    256x256 patches, NCHW, no input normalisation
%     web/models/grader.onnx    ResNet-18 grader, 384x384, no input normalisation
%     web/models/config.json    thresholds, strel shapes, FC weights for Grad-CAM
%
%   config.json is written even when the ONNX converter add-on is missing, so
%   the Python image-processing ports can be parity-tested before the export.
here = fileparts(mfilename('fullpath'));
addpath(here, fullfile(here,'lib'));
CFG = s00_config();
out = fullfile(CFG.root,'web','models');
if ~isfolder(out), mkdir(out); end

L  = load(fullfile(CFG.modelDir,CFG.lesionNetFile));
T  = load(fullfile(CFG.modelDir,CFG.lesionThrFile));
V  = load(fullfile(CFG.modelDir,'netra_vessel_net.mat'));
VT = load(fullfile(CFG.modelDir,'vessel_threshold.mat'));
Q  = load(fullfile(CFG.modelDir,'quality_thresholds.mat'));
G  = load(fullfile(CFG.modelDir,'netra_grader.mat'));
GM = load(fullfile(CFG.resultDir,'grader_metrics.mat'));

% ---- grader: find the dense layer and the Grad-CAM feature layer --------
gnet = G.net;
fc  = gnet.Layers(arrayfun(@(l) isa(l,'nnet.cnn.layer.FullyConnectedLayer'), gnet.Layers));
gap = gnet.Layers(arrayfun(@(l) isa(l,'nnet.cnn.layer.GlobalAveragePooling2DLayer'), gnet.Layers));
assert(numel(fc) == 1, 'expected one dense layer in the grader');
gapName = gap(end).Name;
fprintf('grader: dense %s [%s], last GAP %s\n', fc.Name, num2str(size(fc.Weights)), gapName);

% ---- config.json --------------------------------------------------------
C = struct();
C.source         = "matlab/s25_export_onnx.m";
C.generated      = string(datetime('now','Format','yyyy-MM-dd HH:mm'));
C.lesion_model   = CFG.lesionNetFile;
C.im_mean        = squeeze(CFG.imMean)';
C.im_std         = squeeze(CFG.imStd)';
C.patch_size     = CFG.patchSize;
C.stride         = CFG.stride;
C.min_comp_size  = CFG.minCompSize;
C.lesion_thr     = double(T.thr(:))';
C.channel_names  = CFG.chanName;
C.vessel_size    = CFG.vesselSize;
C.vessel_stride  = CFG.vesselStride;
C.vessel_ref_dia = CFG.vesselRefDia;
C.vessel_thr     = double(VT.thr);
C.quality_thr    = Q.thr;
C.grader_size    = CFG.graderSize;
C.grader_cache_size = CFG.aptosSize;             % crop -> CLAHE -> 512 -> 384, as trained
C.grader_referable_thr = GM.R.threshold;         % s12 operating point, fitted on validation
C.referable_from = CFG.referableFrom;
C.grader_fc_weights = double(fc.Weights);          % 5 x K
C.grader_fc_bias    = double(fc.Bias(:))';
C.grader_feature_tensor = gapName;                  % its INPUT is the CAM feature map
% MATLAB's strel('disk',r) is a decomposed approximation, not a true disk;
% ship the exact neighbourhoods so Python morphology matches.
for r = [1 3 5 15]
    C.strel.(sprintf('disk%d',r)) = double(strel('disk',r).Neighborhood);
end
fid = fopen(fullfile(out,'config.json'),'w');
fwrite(fid, jsonencode(C, PrettyPrint=true)); fclose(fid);
fprintf('wrote %s\n', fullfile(out,'config.json'));

% ---- ONNX ---------------------------------------------------------------
if ~exist('exportONNXNetwork','file')
    warning(['ONNX converter not installed - config.json written, ONNX export skipped.\n' ...
             'Install "Deep Learning Toolbox Converter for ONNX Model Format" and rerun.']);
    return
end

exportONNXNetwork(L.net, fullfile(out,'lesion.onnx'), OpsetVersion=14);
exportONNXNetwork(V.net, fullfile(out,'vessel.onnx'), OpsetVersion=14);

exportONNXNetwork(gnet, fullfile(out,'grader.onnx'), OpsetVersion=14);

d = dir(fullfile(out,'*.onnx'));
for k = 1:numel(d), fprintf('  %-12s %6.1f MB\n', d(k).name, d(k).bytes/2^20); end
