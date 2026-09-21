function T = readLocGroundTruth(CFG, split)
%READLOCGROUNDTRUTH  IDRiD optic-disc and fovea centre markups for one split.
%   T = readLocGroundTruth(CFG, "train" | "test")
%
%   Returns a table with one row per image that has BOTH centres marked:
%     name   IDRiD_001 ...
%     file   full path to the original .jpg
%     odX odY     optic disc centre, ORIGINAL image pixels
%     fvX fvY     fovea centre,      ORIGINAL image pixels
%
%   The markup CSVs are padded out with dozens of empty trailing columns and a
%   run of blank rows, so readtable guesses the width wrong. They are parsed
%   line by line instead: anything that is not IDRiD_<n>,<x>,<y> is dropped.
%
%   Coordinates are in the frame of the ORIGINAL file, not of retinalCrop's
%   output. Callers that predict on a cropped image must add the crop origin
%   back before comparing - see s17_localise.
if split == "train"
    sub   = 'a. Training Set';
    odCsv = fullfile('1. Optic Disc Center Location','a. IDRiD_OD_Center_Training Set_Markups.csv');
    fvCsv = fullfile('2. Fovea Center Location','IDRiD_Fovea_Center_Training Set_Markups.csv');
else
    sub   = 'b. Testing Set';
    odCsv = fullfile('1. Optic Disc Center Location','b. IDRiD_OD_Center_Testing Set_Markups.csv');
    fvCsv = fullfile('2. Fovea Center Location','IDRiD_Fovea_Center_Testing Set_Markups.csv');
end

gtDir = fullfile(CFG.locRoot,'2. Groundtruths');
OD = readCentres(fullfile(gtDir, odCsv));
FV = readCentres(fullfile(gtDir, fvCsv));

T = innerjoin(OD, FV, 'Keys','name', ...
        'LeftVariables',{'name','x','y'}, 'RightVariables',{'x','y'});
T.Properties.VariableNames = {'name','odX','odY','fvX','fvY'};

T.file = fullfile(CFG.locRoot, '1. Original Images', sub, T.name + ".jpg");
keep = isfile(T.file);
if ~all(keep)
    fprintf('  %d markup rows have no image file and were dropped\n', nnz(~keep));
end
T = T(keep,:);
T = movevars(T,'file','After','name');
end

% -------------------------------------------------------------------------
function C = readCentres(f)
if ~isfile(f)
    error('NETRA:missingMarkup', ...
        ['\n  Missing markup file: %s\n' ...
         '  This is part of the IDRiD "C. Localization" download.\n'], f);
end
fid = fopen(f,'r');
raw = textscan(fid,'%s','Delimiter','\n','Whitespace','');
fclose(fid);

lines = string(raw{1});
name = strings(0,1); x = zeros(0,1); y = zeros(0,1);
for i = 1:numel(lines)
    p = strsplit(lines(i), ',');
    if numel(p) < 3, continue; end
    nm = strtrim(p(1));
    if ~startsWith(nm, "IDRiD_"), continue; end     % skips the header too
    xv = str2double(p(2)); yv = str2double(p(3));
    if ~isfinite(xv) || ~isfinite(yv), continue; end
    name(end+1,1) = nm;  x(end+1,1) = xv;  y(end+1,1) = yv;   %#ok<AGROW>
end
if isempty(name)
    error('NETRA:emptyMarkup','no IDRiD rows parsed from %s', f);
end
C = table(name, x, y);
end
