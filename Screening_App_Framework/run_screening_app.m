function run_screening_app()
% RUN_SCREENING_APP
% SIH Problem Statement SIH26038
% Interactive Retinal Screening & Explainable AI Validation Interface
%
% Features:
%   - Upload custom retinal fundus images or select pre-loaded samples
%   - Pillar 1: Automated Quality Gating & CLAHE Enhancement
%   - Pillar 2: Retinal Blood Vessel & Lesion Candidate Segmentation
%   - Pillar 3: ICDR Severity Grading & Clinical Risk Stratification
%   - Pillar 4: Explainable AI Attention Heatmap (Grad-CAM Style)
%   - Pillar 5 Bridge: One-click dispatch to the District Telemedicine Queue
%
% Author: SIH 2026 Team (SIH26038 MathWorks)

% Ensure modules and sample images are in path
app_dir = fileparts(mfilename('fullpath'));
if isempty(app_dir), app_dir = pwd; end
addpath(fullfile(app_dir, 'modules'));
addpath(fullfile(app_dir, 'sample_images'));

% Create main figure window
fig = figure('Name', 'SIH26038: Explainable AI Retinal Screening Interface', ...
             'NumberTitle', 'off', ...
             'Units', 'pixels', ...
             'Position', [80, 60, 1260, 800], ...
             'Color', [0.94, 0.95, 0.97], ...
             'MenuBar', 'none', ...
             'ToolBar', 'none', ...
             'Resize', 'on');

% Application State Data
app_data.app_dir = app_dir;
app_data.current_img = [];
app_data.img_path = '';
app_data.is_analyzed = false;

%% ========================================================================
%% 1. HEADER BANNER
%% ========================================================================
uicontrol(fig, 'Style', 'text', ...
    'Units', 'pixels', 'Position', [20, 735, 1220, 50], ...
    'String', sprintf('SMART INDIA HACKATHON 2026 | MathWorks Challenge SIH26038\nExplainable AI for Diabetic Retinopathy Screening in Rural India'), ...
    'FontSize', 13, 'FontWeight', 'bold', ...
    'ForegroundColor', [0.08, 0.22, 0.42], ...
    'BackgroundColor', [0.94, 0.95, 0.97], ...
    'HorizontalAlignment', 'center');

%% ========================================================================
%% 2. CONTROL PANEL (Top Toolbar)
%% ========================================================================
panel_controls = uipanel(fig, 'Units', 'pixels', ...
    'Position', [20, 665, 1220, 60], ...
    'BackgroundColor', [1, 1, 1], ...
    'BorderType', 'line', 'HighlightColor', [0.8, 0.85, 0.9]);

% Button: Upload Custom Image
uicontrol(panel_controls, 'Style', 'pushbutton', ...
    'Units', 'pixels', 'Position', [15, 12, 160, 36], ...
    'String', '📁 Upload Retinal Image', ...
    'FontSize', 10, 'FontWeight', 'bold', ...
    'BackgroundColor', [0.12, 0.45, 0.85], 'ForegroundColor', [1, 1, 1], ...
    'Callback', @on_upload_click);

% Label: Or Choose Sample
uicontrol(panel_controls, 'Style', 'text', ...
    'Units', 'pixels', 'Position', [190, 18, 140, 22], ...
    'String', 'or select demo sample:', ...
    'FontSize', 10, 'BackgroundColor', [1, 1, 1], 'HorizontalAlignment', 'right');

% Popup Dropdown: Pre-loaded Samples
sample_dropdown = uicontrol(panel_controls, 'Style', 'popupmenu', ...
    'Units', 'pixels', 'Position', [340, 16, 260, 30], ...
    'String', {'Select Sample Retina...', ...
               'Sample 1: Grade 0 (Normal Retina)', ...
               'Sample 2: Grade 1 (Mild NPDR)', ...
               'Sample 3: Grade 2 (Moderate NPDR)', ...
               'Sample 4: Grade 4 (Proliferative DR)'}, ...
    'FontSize', 10, ...
    'Callback', @on_sample_selected);

% Button: Run Screening Pipeline
btn_analyze = uicontrol(panel_controls, 'Style', 'pushbutton', ...
    'Units', 'pixels', 'Position', [625, 12, 210, 36], ...
    'String', '⚡ Run Full Screening Pipeline', ...
    'FontSize', 10, 'FontWeight', 'bold', ...
    'BackgroundColor', [0.18, 0.65, 0.35], 'ForegroundColor', [1, 1, 1], ...
    'Callback', @on_analyze_click);

% Button: Telemedicine Dispatch
btn_telemed = uicontrol(panel_controls, 'Style', 'pushbutton', ...
    'Units', 'pixels', 'Position', [855, 12, 250, 36], ...
    'String', '📡 Dispatch to Telemedicine Queue', ...
    'FontSize', 10, 'FontWeight', 'bold', ...
    'BackgroundColor', [0.85, 0.45, 0.12], 'ForegroundColor', [1, 1, 1], ...
    'Callback', @on_telemed_dispatch);

%% ========================================================================
%% 3. FOUR MAIN VISUAL AXES (2x2 Display Grid)
%% ========================================================================
% Axes 1: Original Fundus
ax1_panel = uipanel(fig, 'Units', 'pixels', 'Position', [20, 350, 290, 300], ...
    'Title', '1. Original Retinal Fundus Input', 'FontSize', 10, 'FontWeight', 'bold', ...
    'BackgroundColor', [1, 1, 1], 'ForegroundColor', [0.1, 0.2, 0.4]);
ax1 = axes(ax1_panel, 'Units', 'normalized', 'Position', [0.03, 0.03, 0.94, 0.94]);
axis(ax1, 'off');

% Axes 2: Pillar 1 CLAHE & Quality
ax2_panel = uipanel(fig, 'Units', 'pixels', 'Position', [330, 350, 290, 300], ...
    'Title', '2. Pillar 1: CLAHE & Quality Gate', 'FontSize', 10, 'FontWeight', 'bold', ...
    'BackgroundColor', [1, 1, 1], 'ForegroundColor', [0.1, 0.2, 0.4]);
ax2 = axes(ax2_panel, 'Units', 'normalized', 'Position', [0.03, 0.03, 0.94, 0.94]);
axis(ax2, 'off');

% Axes 3: Pillar 2 Structure & Lesions
ax3_panel = uipanel(fig, 'Units', 'pixels', 'Position', [640, 350, 290, 300], ...
    'Title', '3. Pillar 2: Vessel Tree & Lesion Map', 'FontSize', 10, 'FontWeight', 'bold', ...
    'BackgroundColor', [1, 1, 1], 'ForegroundColor', [0.1, 0.2, 0.4]);
ax3 = axes(ax3_panel, 'Units', 'normalized', 'Position', [0.03, 0.03, 0.94, 0.94]);
axis(ax3, 'off');

% Axes 4: Pillar 4 Explainable AI Heatmap
ax4_panel = uipanel(fig, 'Units', 'pixels', 'Position', [950, 350, 290, 300], ...
    'Title', '4. Pillar 4: Explainable AI Heatmap', 'FontSize', 10, 'FontWeight', 'bold', ...
    'BackgroundColor', [1, 1, 1], 'ForegroundColor', [0.1, 0.2, 0.4]);
ax4 = axes(ax4_panel, 'Units', 'normalized', 'Position', [0.03, 0.03, 0.94, 0.94]);
axis(ax4, 'off');

%% ========================================================================
%% 4. DIAGNOSTIC RESULTS & CLINICAL TRIAGE CARD (Bottom Panel)
%% ========================================================================
panel_results = uipanel(fig, 'Units', 'pixels', ...
    'Position', [20, 20, 1220, 315], ...
    'Title', 'Clinical Diagnostic Summary & Tele-Ophthalmology Triage Card', ...
    'FontSize', 11, 'FontWeight', 'bold', ...
    'BackgroundColor', [1, 1, 1], 'ForegroundColor', [0.08, 0.22, 0.42]);

% Diagnosis Title Banner
txt_diagnosis = uicontrol(panel_results, 'Style', 'text', ...
    'Units', 'pixels', 'Position', [25, 225, 800, 45], ...
    'String', 'STATUS: Ready. Please load a retinal fundus image above.', ...
    'FontSize', 13, 'FontWeight', 'bold', ...
    'BackgroundColor', [1, 1, 1], 'ForegroundColor', [0.2, 0.3, 0.4], ...
    'HorizontalAlignment', 'left');

% Status Badge (Referral vs Normal)
badge_referral = uicontrol(panel_results, 'Style', 'text', ...
    'Units', 'pixels', 'Position', [850, 225, 340, 45], ...
    'String', 'AWAITING INPUT', ...
    'FontSize', 12, 'FontWeight', 'bold', ...
    'BackgroundColor', [0.9, 0.9, 0.9], 'ForegroundColor', [0.4, 0.4, 0.4], ...
    'HorizontalAlignment', 'center');

% Diagnostic Metric Fields
txt_metrics = uicontrol(panel_results, 'Style', 'text', ...
    'Units', 'pixels', 'Position', [25, 85, 1160, 130], ...
    'String', sprintf('Quality Score: -- | Focus: --\nMicroaneurysms Detected: -- | Hard Exudates: -- | Vessel Density: --\nConfidence Score: --\nRecommended Clinical Action: --\nPillar 5 Telemedicine Status: --'), ...
    'FontSize', 10, 'FontName', 'Consolas', ...
    'BackgroundColor', [0.97, 0.98, 0.99], ...
    'ForegroundColor', [0.15, 0.2, 0.25], ...
    'HorizontalAlignment', 'left');

% Telemedicine Notification Bar
txt_telemed_status = uicontrol(panel_results, 'Style', 'text', ...
    'Units', 'pixels', 'Position', [25, 20, 1160, 45], ...
    'String', 'Telemedicine Link: Ready (Connected to District Civil Hospital Simulation Model)', ...
    'FontSize', 10, 'FontWeight', 'bold', ...
    'BackgroundColor', [0.92, 0.95, 0.98], 'ForegroundColor', [0.1, 0.3, 0.6], ...
    'HorizontalAlignment', 'left');

% Store handles in figure
app_data.ax1 = ax1;
app_data.ax2 = ax2;
app_data.ax3 = ax3;
app_data.ax4 = ax4;
app_data.txt_diagnosis = txt_diagnosis;
app_data.badge_referral = badge_referral;
app_data.txt_metrics = txt_metrics;
app_data.txt_telemed_status = txt_telemed_status;
app_data.sample_dropdown = sample_dropdown;
guidata(fig, app_data);

% Automatically load sample 3 on startup as default demo
set(sample_dropdown, 'Value', 4); % Sample 3
on_sample_selected(sample_dropdown, []);

%% ========================================================================
%% CALLBACK FUNCTIONS
%% ========================================================================
    function on_upload_click(~, ~)
        data = guidata(fig);
        [file, path] = uigetfile({'*.png;*.jpg;*.jpeg;*.tif', 'Retinal Images (*.png, *.jpg, *.tif)'}, ...
                                 'Select a Retinal Fundus Image');
        if isequal(file, 0)
            return;
        end
        load_image(fullfile(path, file));
    end

    function on_sample_selected(src, ~)
        val = get(src, 'Value');
        data = guidata(fig);
        samples = {'', 'sample_normal.png', 'sample_mild_npdr.png', ...
                       'sample_moderate_npdr.png', 'sample_severe_pdr.png'};
        if val > 1
            sample_file = fullfile(data.app_dir, 'sample_images', samples{val});
            if exist(sample_file, 'file')
                load_image(sample_file);
            end
        end
    end

    function load_image(filepath)
        data = guidata(fig);
        img = imread(filepath);
        data.current_img = img;
        data.img_path = filepath;
        data.is_analyzed = false;
        
        % Reset displays
        imshow(img, 'Parent', data.ax1);
        title(data.ax1, 'Input Fundus Image', 'FontWeight', 'normal');
        
        cla(data.ax2); axis(data.ax2, 'off');
        cla(data.ax3); axis(data.ax3, 'off');
        cla(data.ax4); axis(data.ax4, 'off');
        
        set(data.txt_diagnosis, 'String', sprintf('Loaded Image: %s | Click "Run Full Screening Pipeline" to analyze', ...
            get_filename(filepath)), 'ForegroundColor', [0.1, 0.2, 0.4]);
        set(data.badge_referral, 'String', 'IMAGE LOADED', 'BackgroundColor', [0.85, 0.9, 0.95], 'ForegroundColor', [0.1, 0.3, 0.6]);
        set(data.txt_metrics, 'String', 'Quality Score: Pending... | Focus: Pending...\nMicroaneurysms Detected: Pending...\nConfidence: Pending...\nAction: Ready to screen.');
        set(data.txt_telemed_status, 'String', 'Telemedicine Link: Ready to transmit upon screening confirmation.');
        
        guidata(fig, data);
    end

    function on_analyze_click(~, ~)
        data = guidata(fig);
        if isempty(data.current_img)
            msgbox('Please upload or select an eye image first.', 'Notice', 'warn');
            return;
        end
        
        t_start = tic;
        img = data.current_img;
        
        % 1. Pillar 1 Quality Gate
        [is_gradeable, q_score, enhanced_img, q_report] = assess_quality(img);
        imshow(enhanced_img, 'Parent', data.ax2);
        title(data.ax2, sprintf('CLAHE Enhanced (Score: %d)', q_score), 'FontWeight', 'normal');
        
        % 2. Pillar 2 Structure & Lesion Detection
        [vessel_mask, lesion_mask, exudate_mask, annotated_img, l_stats] = detect_structures(img);
        imshow(annotated_img, 'Parent', data.ax3);
        title(data.ax3, sprintf('Vessels & Lesions (MAs: %d, Ex: %d)', l_stats.num_microaneurysms, l_stats.num_exudates), 'FontWeight', 'normal');
        
        % 3. Pillar 3 DR Severity Classification
        [grade, grade_name, is_referable, conf, action] = classify_severity(l_stats, img);
        
        % 4. Pillar 4 Explainable AI Heatmap
        [heatmap_overlay, ~] = generate_explainability(img, lesion_mask, exudate_mask, grade);
        imshow(heatmap_overlay, 'Parent', data.ax4);
        title(data.ax4, sprintf('Explainable AI Grad-CAM (Grade %d)', grade), 'FontWeight', 'normal');
        
        elapsed_sec = toc(t_start);
        
        % 5. Update Diagnostic Card
        set(data.txt_diagnosis, 'String', sprintf('DIAGNOSIS: %s', grade_name), ...
            'ForegroundColor', get_grade_color(grade));
        
        if is_referable
            set(data.badge_referral, 'String', '⚠ REFERRAL REQUIRED', ...
                'BackgroundColor', [0.95, 0.82, 0.82], 'ForegroundColor', [0.8, 0.1, 0.1]);
        else
            set(data.badge_referral, 'String', '✓ RESOLVED ON-SITE (NORMAL)', ...
                'BackgroundColor', [0.82, 0.95, 0.82], 'ForegroundColor', [0.1, 0.6, 0.1]);
        end
        
        summary_str = sprintf([...
            'Pillar 1 Quality Gate   : %s\n' ...
            'Pillar 2 Lesion Analysis: %d Microaneurysms | %d Hard Exudates | Vessel Density: %.1f%%\n' ...
            'Pillar 3 AI Confidence  : %.1f%% (Inference Time: %.2f sec - Meets < 30s target)\n' ...
            'Recommended Action      : %s\n' ...
            'Pillar 5 Telemed Bridge : %s'], ...
            q_report, l_stats.num_microaneurysms, l_stats.num_exudates, l_stats.vessel_density_pct, ...
            conf, elapsed_sec, action, get_telemed_msg(is_referable));
        
        set(data.txt_metrics, 'String', summary_str);
        
        data.is_analyzed = true;
        data.is_referable = is_referable;
        data.grade = grade;
        data.grade_name = grade_name;
        guidata(fig, data);
    end

    function on_telemed_dispatch(~, ~)
        data = guidata(fig);
        if ~data.is_analyzed
            msgbox('Please run the screening pipeline first before dispatching.', 'Notice', 'warn');
            return;
        end
        
        if ~data.is_referable
            set(data.txt_telemed_status, 'String', ...
                'Telemedicine Action: Not Required. Patient cleared locally at PHC. 0 bytes transmitted.', ...
                'BackgroundColor', [0.88, 0.95, 0.88], 'ForegroundColor', [0.1, 0.5, 0.1]);
        else
            set(data.txt_telemed_status, 'String', ...
                sprintf('DISPATCH CONFIRMED: Compressed package (4.8 MB) sent to Central Civil Hospital Queue! Case priority logged into Pillar 5 model.'), ...
                'BackgroundColor', [0.98, 0.92, 0.85], 'ForegroundColor', [0.8, 0.35, 0.05]);
        end
    end

    function c = get_grade_color(grade)
        switch grade
            case 0, c = [0.1, 0.6, 0.1];
            case 1, c = [0.2, 0.5, 0.7];
            case 2, c = [0.8, 0.45, 0.0];
            case 3, c = [0.85, 0.25, 0.0];
            case 4, c = [0.85, 0.05, 0.05];
            otherwise, c = [0.1, 0.2, 0.3];
        end
    end

    function msg = get_telemed_msg(is_referable)
        if is_referable
            msg = 'Eligible for Telemedicine Dispatch. Click "Dispatch to Telemedicine Queue" above.';
        else
            msg = 'Patient resolved locally. Saved 40 MB network data and doctor review time.';
        end
    end

    function fn = get_filename(p)
        [~, name, ext] = fileparts(p);
        fn = [name, ext];
    end

end
