function J = overlayLesions(I, M)
%OVERLAYLESIONS  Colour-code lesion masks onto a fundus image.
%   MA red | HE blue | EX yellow | SE cyan | OD green outline
col = [1 0 0; 0 0.35 1; 1 0.9 0; 0 1 1; 0 1 0];
J = im2single(I);
for c = 1:min(size(M,3),5)
    B = M(:,:,c);
    if c == 5, B = bwperim(imdilate(B,strel('disk',3))); end
    if ~any(B(:)), continue; end
    B = imdilate(B, strel('disk',1));
    for ch = 1:3
        L = J(:,:,ch);
        L(B) = 0.25*L(B) + 0.75*col(c,ch);
        J(:,:,ch) = L;
    end
end
J = im2uint8(J);
end
