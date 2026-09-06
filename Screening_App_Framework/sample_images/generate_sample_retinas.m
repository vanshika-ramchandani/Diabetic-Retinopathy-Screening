function generate_sample_retinas()
% GENERATE_SAMPLE_RETINAS
% Synthesizes realistic 512x512 retinal fundus images for demonstration:
%   1. sample_normal.png        (ICDR Grade 0: Normal Retina - 0 lesions)
%   2. sample_mild_npdr.png     (ICDR Grade 1: Mild NPDR - 5 Microaneurysms)
%   3. sample_moderate_npdr.png (ICDR Grade 2: Moderate NPDR - 18 MAs + 12 Hard Exudates)
%   4. sample_severe_pdr.png    (ICDR Grade 4: Proliferative DR - 45+ Lesions + Hemorrhages)

target_dir = fileparts(mfilename('fullpath'));
if isempty(target_dir), target_dir = pwd; end

fprintf('Generating distinct demonstration retinal fundus images in: %s\n', target_dir);

% Seed for reproducible lesion locations
rng(42);

% 1. Normal Retina (Clean)
img_normal = create_base_fundus();
imwrite(img_normal, fullfile(target_dir, 'sample_normal.png'));
fprintf('  [+] sample_normal.png created (Grade 0: Normal - 0 lesions)\n');

% 2. Mild NPDR (5 isolated microaneurysms)
img_mild = add_microaneurysms(img_normal, 6);
imwrite(img_mild, fullfile(target_dir, 'sample_mild_npdr.png'));
fprintf('  [+] sample_mild_npdr.png created (Grade 1: Mild NPDR - isolated MAs)\n');

% 3. Moderate NPDR (18 microaneurysms + 12 hard exudates + 4 dot hemorrhages)
img_mod = add_microaneurysms(img_normal, 18);
img_mod = add_hard_exudates(img_mod, 12);
img_mod = add_hemorrhages(img_mod, 5);
imwrite(img_mod, fullfile(target_dir, 'sample_moderate_npdr.png'));
fprintf('  [+] sample_moderate_npdr.png created (Grade 2: Moderate NPDR - MAs & Exudates)\n');

% 4. Severe / Proliferative DR (45 MAs/blots + 25 exudates + cotton wool spots)
img_severe = add_microaneurysms(img_normal, 45);
img_severe = add_hard_exudates(img_severe, 26);
img_severe = add_hemorrhages(img_severe, 20);
img_severe = add_cotton_wool_spots(img_severe, 5);
imwrite(img_severe, fullfile(target_dir, 'sample_severe_pdr.png'));
fprintf('  [+] sample_severe_pdr.png created (Grade 4: Proliferative DR - Extensive Pathologies)\n');

fprintf('Sample retinal images generation complete!\n');

end

%% ========================================================================
%  BASE RETINAL FUNDUS SYNTHESIZER
%  ========================================================================
function img = create_base_fundus()
    sz = 512;
    [X, Y] = meshgrid(1:sz, 1:sz);
    cx = sz/2; cy = sz/2;
    dist_center = sqrt((X - cx).^2 + (Y - cy).^2);
    
    % Circular Aperture Mask (radius 235)
    aperture_radius = 235;
    mask = dist_center <= aperture_radius;
    
    % Radial falloff for realistic lens vignette
    vignette = cos(min(pi/2, (dist_center / aperture_radius) * (pi/2.5)));
    
    % Retinal background color: Orange-Red hue (R: ~180-205, G: ~65-80, B: ~15-25)
    R = 185 + 20 * (dist_center/aperture_radius) - 15 * vignette;
    G = 70 + 15 * vignette;
    B = 20 + 8 * vignette;
    
    % Macula / Fovea (Darker circular region at center-right)
    mac_x = cx + 55; mac_y = cy + 10;
    dist_mac = sqrt((X - mac_x).^2 + (Y - mac_y).^2);
    mac_falloff = exp(-(dist_mac.^2) / (2 * 45^2));
    R = R - 35 * mac_falloff;
    G = G - 18 * mac_falloff;
    B = B - 8 * mac_falloff;
    
    % Optic Disc (Bright circular region at center-left: cx-85, cy-10)
    disc_x = cx - 85; disc_y = cy - 10;
    dist_disc = sqrt((X - disc_x).^2 + (Y - disc_y).^2);
    disc_mask = dist_disc <= 28;
    disc_falloff = exp(-(dist_disc.^2) / (2 * 26^2));
    R(disc_mask) = 245;
    G(disc_mask) = 215;
    B(disc_mask) = 140;
    R = R + 35 * disc_falloff;
    G = G + 30 * disc_falloff;
    B = B + 15 * disc_falloff;
    
    % Retinal Blood Vessel Tree radiating from Optic Disc
    vessels = zeros(sz, sz);
    angles = [-1.3, -1.0, -0.6, -0.2, 0.2, 0.6, 1.0, 1.3, 2.5, 3.1, -2.8];
    for a = angles
        t = 0:1:220;
        curvature = 0.0018 * t.^1.8;
        vx = disc_x + t .* cos(a) - curvature .* sin(a);
        vy = disc_y + t .* sin(a) + curvature .* cos(a);
        for k = 1:length(t)
            px = round(vx(k)); py = round(vy(k));
            if px >= 3 && px <= sz-2 && py >= 3 && py <= sz-2
                w = max(1, round(3.5 - 0.012 * t(k)));
                vessels(py-w:py+w, px-w:px+w) = 1;
            end
        end
    end
    
    vessels = imgaussfilt(double(vessels), 1.0);
    
    % Vessels absorb green strongly
    v_factor = 1 - 0.50 * vessels;
    R = R .* v_factor;
    G = G .* (1 - 0.65 * vessels);
    B = B .* (1 - 0.70 * vessels);
    
    % Black background outside aperture
    R(~mask) = 0; G(~mask) = 0; B(~mask) = 0;
    
    img = cat(3, uint8(max(0, min(255, R))), ...
                 uint8(max(0, min(255, G))), ...
                 uint8(max(0, min(255, B))));
end

%% ========================================================================
%  LESION INSERTERS (Calibrated to realistic optical absorption)
%  ========================================================================
function img = add_microaneurysms(img, count)
    sz = size(img, 1);
    cx = sz/2; cy = sz/2;
    disc_x = cx - 85; disc_y = cy - 10;
    
    R = double(img(:,:,1)); G = double(img(:,:,2)); B = double(img(:,:,3));
    
    k = 0;
    while k < count
        rx = round(cx + (rand() - 0.3) * 220);
        ry = round(cy + (rand() - 0.5) * 220);
        % Avoid optic disc and outside aperture
        if sqrt((rx-cx)^2 + (ry-cy)^2) < 200 && sqrt((rx-disc_x)^2 + (ry-disc_y)^2) > 40
            w = 2;
            % Microaneurysms: Strong hemoglobin absorption (G drops drastically to ~12)
            R(ry-w:ry+w, rx-w:rx+w) = 135;
            G(ry-w:ry+w, rx-w:rx+w) = 12;
            B(ry-w:ry+w, rx-w:rx+w) = 8;
            k = k + 1;
        end
    end
    img = cat(3, uint8(R), uint8(G), uint8(B));
end

function img = add_hard_exudates(img, count)
    sz = size(img, 1);
    cx = sz/2; cy = sz/2;
    disc_x = cx - 85; disc_y = cy - 10;
    
    R = double(img(:,:,1)); G = double(img(:,:,2)); B = double(img(:,:,3));
    
    k = 0;
    while k < count
        rx = round(cx + 40 + randn() * 55);
        ry = round(cy + randn() * 65);
        if sqrt((rx-cx)^2 + (ry-cy)^2) < 200 && sqrt((rx-disc_x)^2 + (ry-disc_y)^2) > 45
            w = randi([2, 3]);
            % Hard Exudates: Bright yellowish lipid reflections (High R and high G)
            R(ry-w:ry+w, rx-w:rx+w) = 250;
            G(ry-w:ry+w, rx-w:rx+w) = 235;
            B(ry-w:ry+w, rx-w:rx+w) = 110;
            k = k + 1;
        end
    end
    img = cat(3, uint8(R), uint8(G), uint8(B));
end

function img = add_hemorrhages(img, count)
    sz = size(img, 1);
    cx = sz/2; cy = sz/2;
    disc_x = cx - 85; disc_y = cy - 10;
    
    R = double(img(:,:,1)); G = double(img(:,:,2)); B = double(img(:,:,3));
    
    k = 0;
    while k < count
        rx = round(cx + (rand() - 0.4) * 210);
        ry = round(cy + (rand() - 0.5) * 210);
        if sqrt((rx-cx)^2 + (ry-cy)^2) < 200 && sqrt((rx-disc_x)^2 + (ry-disc_y)^2) > 40
            r_blob = randi([3, 5]);
            [Xb, Yb] = meshgrid(-r_blob:r_blob, -r_blob:r_blob);
            blob = (Xb.^2 + Yb.^2) <= r_blob^2;
            
            y_idx = ry-r_blob:ry+r_blob;
            x_idx = rx-r_blob:rx+r_blob;
            
            subR = R(y_idx, x_idx); subG = G(y_idx, x_idx); subB = B(y_idx, x_idx);
            subR(blob) = 110;
            subG(blob) = 10;
            subB(blob) = 8;
            R(y_idx, x_idx) = subR; G(y_idx, x_idx) = subG; B(y_idx, x_idx) = subB;
            k = k + 1;
        end
    end
    img = cat(3, uint8(R), uint8(G), uint8(B));
end

function img = add_cotton_wool_spots(img, count)
    sz = size(img, 1);
    cx = sz/2; cy = sz/2;
    disc_x = cx - 85; disc_y = cy - 10;
    
    R = double(img(:,:,1)); G = double(img(:,:,2)); B = double(img(:,:,3));
    
    k = 0;
    while k < count
        rx = round(cx + (rand() - 0.5) * 160);
        ry = round(cy + (rand() - 0.5) * 160);
        if sqrt((rx-cx)^2 + (ry-cy)^2) < 190 && sqrt((rx-disc_x)^2 + (ry-disc_y)^2) > 40
            r_spot = randi([5, 8]);
            [Xs, Ys] = meshgrid(-r_spot:r_spot, -r_spot:r_spot);
            spot_weight = exp(-(Xs.^2 + Ys.^2) / (2 * (r_spot/1.8)^2));
            
            y_idx = ry-r_spot:ry+r_spot;
            x_idx = rx-r_spot:rx+r_spot;
            
            R(y_idx, x_idx) = min(255, R(y_idx, x_idx) + 85 * spot_weight);
            G(y_idx, x_idx) = min(255, G(y_idx, x_idx) + 85 * spot_weight);
            B(y_idx, x_idx) = min(255, B(y_idx, x_idx) + 80 * spot_weight);
            k = k + 1;
        end
    end
    img = cat(3, uint8(R), uint8(G), uint8(B));
end
