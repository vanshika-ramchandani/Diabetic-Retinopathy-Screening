function X = normaliseInput(I, CFG)
%NORMALISEINPUT  uint8 HxWx3 -> single, scaled and ImageNet-normalised.
X = single(I)/255;
X = (X - CFG.imMean) ./ CFG.imStd;
end
