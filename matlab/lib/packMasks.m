function P = packMasks(M)
%PACKMASKS  HxWxC logical -> HxW uint8 with channel c in bit c.
P = zeros(size(M,1),size(M,2),'uint8');
for c = 1:size(M,3)
    P = bitor(P, uint8(M(:,:,c)) * uint8(2^(c-1)));
end
end
