function [J, info] = enhanceFundus(I)
%ENHANCEFUNDUS  Illumination normalisation + CLAHE + edge-preserving denoise.
%
%   IMPORTANT - read before wiring this into the model path.
%   The segmentation network was trained on applyClahe(retinalCrop(I)) and
%   nothing else. Inserting this richer enhancement in front of the network
%   would shift its input distribution away from training, which degrades
%   accuracy silently - no error, just worse masks. So:
%
%     * the NETWORK input path stays applyClahe (see netraDetect / netraScreen)
%     * this function produces the OPERATOR-FACING image and the recovery
%       path for captures the quality gate marked ENHANCE
%
%   [J,INFO] = enhanceFundus(I) also returns the illumination field removed.
if size(I,3) == 1, I = repmat(I,1,1,3); end
M = retinalMask(I);
J = I;

% --- 1. illumination normalisation ---------------------------------------
% Divide out the large-scale lighting field, which is multiplicative in
% fundus photography (flash falloff), then restore the original mean level.
sigma = max(size(I,1), size(I,2)) / 30;
for c = 1:3
    ch = im2single(I(:,:,c));
    bg = imgaussfilt(ch, sigma);
    mu = mean(ch(M));
    corrected = ch ./ max(bg, 1e-3) * max(mu, 1e-3);
    J(:,:,c) = im2uint8(min(max(corrected, 0), 1));
end
info.illumSigma = sigma;

% --- 2. local contrast ---------------------------------------------------
J = applyClahe(J);

% --- 3. denoise ----------------------------------------------------------
% Non-local means preserves microaneurysms - a 10px lesion survives this
% where a Gaussian blur of equivalent strength erases it.
try
    J = imnlmfilt(J, 'DegreeOfSmoothing', 3, 'SearchWindowSize', 11, 'ComparisonWindowSize', 5);
    info.denoise = "imnlmfilt";
catch
    info.denoise = "skipped";
end

% Keep the surround black: enhancement must not invent signal outside the retina.
for c = 1:3
    ch = J(:,:,c); ch(~M) = 0; J(:,:,c) = ch;
end
info.retinaFrac = nnz(M)/numel(M);
end
