function M = unpackMasks(P, nChan)
%UNPACKMASKS  HxW uint8 bitfield -> HxWxnChan logical.
if nargin < 2, nChan = 5; end
M = false(size(P,1), size(P,2), nChan);
for c = 1:nChan
    M(:,:,c) = bitand(P, uint8(2^(c-1))) > 0;
end
end
