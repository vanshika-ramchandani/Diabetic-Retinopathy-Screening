function [vessel_mask, lesion_mask, exudate_mask, annotated_img, lesion_stats] = detect_structures(img)
% DETECT_STRUCTURES (Pillar 2 Retinal Structure & Lesion Segmentation Module)
% Uses shape-morphology and spectral absorption to cleanly separate:
%   - Elongated Blood Vessels (eccentricity > 0.85 or area > 45)
%   - Compact Microaneurysms (round dots: area 3-40, eccentricity <= 0.85)
%   - Hemorrhages (larger dark blots: area > 40, eccentricity <= 0.85)
%   - Hard Exudates (bright yellowish lipid deposits outside the optic disc)

R = double(img(:,:,1));
G = double(img(:,:,2));
B = double(img(:,:,3));

sz = size(img, 1);
cx = sz/2; cy = sz/2;

% 1. Retinal Aperture Mask (circular field of view)
[X, Y] = meshgrid(1:sz, 1:sz);
retina_mask = sqrt((X - cx).^2 + (Y - cy).^2) <= 230;

% 2. Optic Disc Localization & Exclusion Zone (Radius 55px to exclude disc halo)
disc_search_mask = retina_mask & (X < cx - 40) & (abs(Y - cy) < 80);
disc_metric = (R + G) .* double(disc_search_mask);
[~, max_idx] = max(disc_metric(:));
[disc_row, disc_col] = ind2sub([sz, sz], max_idx);
disc_mask = sqrt((X - disc_col).^2 + (Y - disc_row).^2) <= 55;

% 3. Bottom-Hat Transform on Green Channel (Detects all dark structures: vessels + lesions)
se = strel('disk', 6);
v_enh = imbothat(G, se);
v_raw = (v_enh > 15.0) & retina_mask & ~disc_mask;

% 4. Morphological Separation: Line Structures (Vessels) vs Round Dots (Lesions)
rp = regionprops(v_raw, 'Area', 'Eccentricity', 'PixelIdxList');

vessel_mask = false(sz, sz);
lesion_mask = false(sz, sz);
num_ma = 0;
num_hem = 0;

for k = 1:length(rp)
    a = rp(k).Area;
    e = rp(k).Eccentricity;
    
    % Vessels: Elongated lines (eccentricity > 0.85) OR large continuous branches (area > 45)
    if a > 45 || e > 0.85
        vessel_mask(rp(k).PixelIdxList) = true;
    % Microaneurysms: Compact, round dark dots (area 3 to 40, low eccentricity)
    elseif a >= 3 && a <= 40 && e <= 0.85
        lesion_mask(rp(k).PixelIdxList) = true;
        num_ma = num_ma + 1;
    % Hemorrhages: Larger, irregular dark red blotches
    elseif a > 40 && a <= 600 && e <= 0.85
        lesion_mask(rp(k).PixelIdxList) = true;
        num_hem = num_hem + 1;
    end
end

% Smooth vessels
vessel_mask = bwareaopen(vessel_mask, 25);

% 5. Bright Lesion Detection (Hard Exudates)
% Bright yellowish-white specks outside optic disc
is_ex = (G > 150) & (R > 180) & (B < 160) & retina_mask & ~disc_mask;
exp = regionprops(is_ex, 'Area', 'PixelIdxList');

exudate_mask = false(sz, sz);
num_ex = 0;

for k = 1:length(exp)
    if exp(k).Area >= 3 && exp(k).Area <= 450
        exudate_mask(exp(k).PixelIdxList) = true;
        num_ex = num_ex + 1;
    end
end

% 6. Compile Lesion Statistics
lesion_stats.num_microaneurysms = num_ma;
lesion_stats.num_hemorrhages    = num_hem;
lesion_stats.num_exudates       = num_ex;
lesion_stats.total_lesion_area  = sum(lesion_mask(:)) + sum(exudate_mask(:));
lesion_stats.vessel_density_pct = (sum(vessel_mask(:)) / sum(retina_mask(:))) * 100;

% 7. Construct Annotated Overlay Image
annotated_img = img;

% Overlay vessels in vivid medical green
annotated_img(:,:,2) = uint8(double(annotated_img(:,:,2)) + 90 * double(vessel_mask));

% Highlight red lesions (MAs/Hemorrhages) with Cyan rings
lesion_dilated = imdilate(lesion_mask, strel('disk', 3)) & ~lesion_mask;
annotated_img(:,:,1) = uint8(double(annotated_img(:,:,1)) .* (1 - double(lesion_dilated)));
annotated_img(:,:,2) = uint8(double(annotated_img(:,:,2)) + 245 * double(lesion_dilated));
annotated_img(:,:,3) = uint8(double(annotated_img(:,:,3)) + 245 * double(lesion_dilated));

% Highlight exudates with Bright Magenta rings
exudate_dilated = imdilate(exudate_mask, strel('disk', 3)) & ~exudate_mask;
annotated_img(:,:,1) = uint8(double(annotated_img(:,:,1)) + 245 * double(exudate_dilated));
annotated_img(:,:,2) = uint8(double(annotated_img(:,:,2)) .* (1 - double(exudate_dilated)));
annotated_img(:,:,3) = uint8(double(annotated_img(:,:,3)) + 245 * double(exudate_dilated));

end
