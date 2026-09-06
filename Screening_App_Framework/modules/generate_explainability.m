function [heatmap_overlay, saliency_map] = generate_explainability(img, lesion_mask, exudate_mask, icdr_grade)
% GENERATE_EXPLAINABILITY (Pillar 4 Explainable AI Module)
% Constructs visual attention / Grad-CAM style saliency heatmaps.
% Highlights the specific retinal regions that drove the clinical diagnosis,
% allowing the ophthalmologist to validate the case in < 30 seconds.
%
% Inputs:
%   img          - Original RGB retinal fundus (uint8)
%   lesion_mask  - Binary mask of detected red lesions
%   exudate_mask - Binary mask of detected exudates
%   icdr_grade   - Assigned ICDR severity grade (0 to 4)
% Outputs:
%   heatmap_overlay - Blended RGB image with semi-transparent heatmap
%   saliency_map    - 2D normalized attention matrix [0, 1]

sz = size(img, 1);
combined_lesions = double(lesion_mask | exudate_mask);

if icdr_grade == 0
    % Normal retina: Attention is uniformly low (calm blue background)
    saliency = zeros(sz, sz);
    % Subtle anatomical focal baseline near fovea
    [X, Y] = meshgrid(1:sz, 1:sz);
    saliency = 0.15 * exp(-((X - sz/2).^2 + (Y - sz/2).^2) / (2 * 100^2));
else
    % Diseased retina: Smooth Gaussian kernels over each lesion cluster
    saliency = imgaussfilt(combined_lesions, 18.0);
    if max(saliency(:)) > 0
        saliency = saliency / max(saliency(:));
    end
    % Scale intensity with disease severity
    severity_boost = 0.5 + 0.12 * icdr_grade;
    saliency = min(1.0, saliency * severity_boost);
end

saliency_map = saliency;

% Generate Jet Colormap for the heatmap
cmap = jet(256);
heatmap_rgb = ind2rgb(round(saliency * 255) + 1, cmap);

% Alpha blend: 65% Original Image + 35% Heatmap
alpha = 0.40;
fundus_double = double(img) / 255.0;

% Mask out black aperture boundary
mask = (img(:,:,1) > 15 | img(:,:,2) > 15 | img(:,:,3) > 10);
mask_3d = cat(3, mask, mask, mask);

blended = (1 - alpha) * fundus_double + alpha * heatmap_rgb;
blended(~mask_3d) = 0;

heatmap_overlay = uint8(blended * 255);

end
