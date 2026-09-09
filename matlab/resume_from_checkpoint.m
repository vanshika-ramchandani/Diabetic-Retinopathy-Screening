function net = resume_from_checkpoint()
%RESUME_FROM_CHECKPOINT  Recover the latest s05 checkpoint after a crash.
%   Promotes the newest epoch checkpoint to models/netra_lesion_net.mat so the
%   rest of the pipeline (s06 onward) can run without retraining.
addpath(fileparts(mfilename('fullpath')), fullfile(fileparts(mfilename('fullpath')),'lib'));
CFG = s00_config();
d = dir(fullfile(CFG.modelDir,'checkpoints','*.mat'));
if isempty(d), error('no checkpoints in models\checkpoints - nothing to resume'); end
[~,i] = max([d.datenum]);
f = fullfile(d(i).folder, d(i).name);
fprintf('recovering %s (%s)\n', d(i).name, datestr(d(i).datenum));
S = load(f);
fn = fieldnames(S);
net = S.(fn{find(cellfun(@(k) isa(S.(k),'dlnetwork'), fn),1)});
info = struct('note','recovered from checkpoint; ValidationHistory unavailable');
save(fullfile(CFG.modelDir,'netra_lesion_net.mat'),'net','info','CFG','-v7.3');
fprintf('wrote models/netra_lesion_net.mat - you can now run s06_tune_thresholds\n');
end
