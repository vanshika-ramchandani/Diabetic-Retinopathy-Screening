function [I, M] = readIdridSample(CFG, id, split)
%READIDRIDSAMPLE  Load one IDRiD image + its 5 mask channels, retinal-cropped.
%   An ABSENT mask file means the lesion is absent from that image (IDRiD
%   convention), so it is returned as an all-zero plane - not skipped.
if split == "train", sub = "a. Training Set"; else, sub = "b. Testing Set"; end
name = sprintf('IDRiD_%02d', id);

I = imread(fullfile(CFG.segRoot,'1. Original Images',sub,[name '.jpg']));
[I, bbox] = retinalCrop(I);
I = applyClahe(I);

M = false(size(I,1), size(I,2), CFG.nChan);
for c = 1:CFG.nChan
    f = fullfile(CFG.segRoot,'2. All Segmentation Groundtruths',sub, ...
                 CFG.chanFolder(c), sprintf('%s_%s.tif',name,CFG.chanSuffix(c)));
    if isfile(f)
        m = imread(f);
        if ndims(m) == 3, m = m(:,:,1); end
        m = retinalCrop(m > 0, bbox);
        M(:,:,c) = m;
    end
end
end
