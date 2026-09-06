function [is_gradeable, quality_score, enhanced_img, quality_report] = assess_quality(img)
% ASSESS_QUALITY (Pillar 1 Quality Gate Module)
% Evaluates retinal fundus image for focus, illumination, and field-of-view.
% Applies adaptive enhancement (CLAHE on Green channel) for borderline images.
%
% Inputs:
%   img - RGB retinal fundus image (uint8)
% Outputs:
%   is_gradeable   - Boolean (true = gradeable, false = reject for recapture)
%   quality_score  - Quality metric (0 - 100)
%   enhanced_img   - Contrast-enhanced RGB image using CLAHE
%   quality_report - Text diagnostic summary for clinician/operator

if size(img, 3) < 3
    img = cat(3, img, img, img);
end

% Extract green channel (maximum retinal vessel contrast)
G = double(img(:,:,2));

% 1. Sharpness / Focus Assessment via Tenengrad gradient energy
[Gx, Gy] = imgradientxy(G, 'Sobel');
grad_mag = sqrt(Gx.^2 + Gy.^2);
sharpness_val = mean(grad_mag(G > 20)); % ignore black border

% 2. Illumination & Contrast Assessment
mean_intensity = mean(G(G > 20));
contrast_val = std(G(G > 20));

% Compute overall Quality Score (0 to 100)
% Baseline threshold calibration
sharpness_score = min(50, (sharpness_val / 8.0) * 50);
contrast_score  = min(50, (contrast_val / 30.0) * 50);
quality_score   = round(sharpness_score + contrast_score);

% Quality Gating Threshold (Score >= 45 is gradeable)
if quality_score >= 45 && mean_intensity >= 25
    is_gradeable = true;
    quality_report = sprintf('Gradeable (Score: %d/100) | Focus: Sharp | Contrast: Adequate', quality_score);
else
    is_gradeable = false;
    quality_report = sprintf('Ungradeable (Score: %d/100) | Recapture Required: Low Contrast/Blur', quality_score);
end

% 3. Adaptive Enhancement: CLAHE (Contrast-Limited Adaptive Histogram Equalization)
% Applied specifically to the green channel, then merged back with RGB
G_norm = mat2gray(img(:,:,2));
G_clahe = adapthisteq(G_norm, 'ClipLimit', 0.02, 'Distribution', 'rayleigh');

enhanced_img = img;
enhanced_img(:,:,2) = uint8(G_clahe * 255);

end
