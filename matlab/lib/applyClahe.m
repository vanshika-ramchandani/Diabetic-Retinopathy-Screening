function J = applyClahe(I)
%APPLYCLAHE  Mild per-channel CLAHE. Identical in pretraining and segmentation
%   stages - a mismatch here silently destroys encoder transfer.
J = I;
for c = 1:size(I,3)
    J(:,:,c) = adapthisteq(I(:,:,c),'ClipLimit',0.01,'NumTiles',[8 8]);
end
end
