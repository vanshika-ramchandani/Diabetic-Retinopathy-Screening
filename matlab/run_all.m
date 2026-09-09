function run_all(fromStage)
%RUN_ALL  Execute the NETRA-Lesion pipeline end to end.
%   run_all()   runs everything from patch extraction
%   run_all(4)  resumes from stage 4 (build) - each stage checkpoints to models/
%
%   Stage 1 (s01_cache_aptos) is OPTIONAL and only needed if CFG.useAptosPretrain
%   is true and the APTOS images are present.
if nargin < 1, fromStage = 2; end
addpath(fileparts(mfilename('fullpath')), fullfile(fileparts(mfilename('fullpath')),'lib'));
CFG = s00_config();

stages = { 2, 's02_cache_patches',   'extract IDRiD patches'
           4, 's04_build_net',       'build model + overfit test'
           5, 's05_train_seg',       'train'
           6, 's06_tune_thresholds', 'tune thresholds on validation'
           7, 's07_evaluate_test',   'evaluate on sealed test set'
           8, 's08_figures',         'write overlays' };

if CFG.useAptosPretrain
    stages = [{1,'s01_cache_aptos','cache APTOS'; 3,'s03_pretrain_encoder','pretrain encoder'}; stages];
    stages = sortrows(stages, 1);
end

for i = 1:size(stages,1)
    if stages{i,1} < fromStage, continue; end
    fprintf('\n========== STAGE %d : %s ==========\n', stages{i,1}, stages{i,3});
    t0 = tic; feval(stages{i,2}); fprintf('stage %d done in %.1f min\n', stages{i,1}, toc(t0)/60);
end
fprintf('\nPipeline complete. Metrics: results/metrics.csv\n');
end
