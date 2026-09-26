function [I, L, F] = readDriveSample(id, CFG)
%READDRIVESAMPLE  One DRIVE image, its vessel ground truth, and its FOV mask.
%   [I,L,F] = readDriveSample(ID, CFG)
%     I  uint8   HxWx3 fundus image
%     L  logical HxW   manual vessel tracing (observer 1)
%     F  logical HxW   field of view, DERIVED - see below
%
%   The label files are named differently in the two splits (21.png in train,
%   01_manual1.png in test) so the lookup is by stem-prefix, not by a format
%   string that would silently miss one of them.
%
%   FOV: this copy of DRIVE has no mask/ folder, so F comes from retinalMask -
%   the same >10 grey threshold the rest of the pipeline uses to find a retina.
%   Measured against the ground truth it leaves at most 44 labelled vessel
%   pixels outside the mask (mean 11), which is edge antialiasing rather than
%   real vessel, so nothing of substance is being cropped away.
if nargin < 2, CFG = s00_config(); end

if ismember(id, CFG.driveTestIds), split = 'val'; else, split = 'train'; end
stem = sprintf('%02d', id);

fi = fullfile(CFG.driveRoot, split, 'input', [stem '.tif']);
assert(isfile(fi), 'DRIVE image not found: %s', fi);
I = imread(fi);

d = dir(fullfile(CFG.driveRoot, split, 'label', [stem '*.png']));
assert(numel(d) == 1, 'expected exactly 1 label for DRIVE %s, found %d', stem, numel(d));
L = imread(fullfile(d(1).folder, d(1).name)) > 0;

F = retinalMask(I);
end
