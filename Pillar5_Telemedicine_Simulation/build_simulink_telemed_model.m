function build_simulink_telemed_model()
% BUILD_SIMULINK_TELEMED_MODEL
% SIH Problem Statement SIH26038 - Pillar 5
% Programmatically constructs and simulates the District Telemedicine
% Screening Workflow & Capacity Model in Simulink.
%
% Generates:
%   1. telemedicine_screening_model.slx (Interactive visual Simulink model)
%   2. simulink_model_diagram.png       (High-resolution diagram snapshot)
%
% Architecture Modeled:
%   - Lane 1: Main Telemedicine Pipeline (Intake -> Edge Triage -> Cellular Delay -> Cloud XAI -> Doctor Queue)
%   - Lane 2: Doctor Service & Capacity Pool (Service Rate -> Queue Subtract -> Completed Reviews)
%   - Lane 3: Local PHC Resolution Stream (Non-referable filter -> Local Reassurance Integrator)
%
% Author: SIH 2026 Team (SIH26038 MathWorks)

model_name = 'telemedicine_screening_model';

fprintf('========================================================================\n');
fprintf('  BUILDING SIMULINK TELEMEDICINE CAPACITY MODEL: %s.slx\n', model_name);
fprintf('  Formatting: Spacious multi-lane layout with non-overlapping labels\n');
fprintf('========================================================================\n');

% Close and discard if already open in memory
if bdIsLoaded(model_name)
    close_system(model_name, 0);
end

% Create new empty Simulink system
new_system(model_name);
open_system(model_name);

% Configure simulation parameters
set_param(model_name, 'Solver', 'ode45', ...
                      'StopTime', '28800', ... % 8 hours (28,800 seconds)
                      'SaveOutput', 'on', ...
                      'OutputSaveName', 'simout');

%% ========================================================================
%% LANE 1: MAIN TELEMEDICINE SCREENING PIPELINE (Y: 120 - 180)
%% ========================================================================
% 1. Patient Intake (50 PHCs across District)
name_intake = sprintf('District Intake\n(50 Rural PHCs)');
add_block('simulink/Sources/Pulse Generator', [model_name, '/', name_intake], ...
    'Position', [80, 120, 160, 175], ...
    'Period', '54', ...           % 1 patient every 54 seconds district-wide
    'PulseWidth', '50', ...
    'Amplitude', '1');

% 2. Edge AI Triage Filter (Referable DR cases: 25%)
name_triage = sprintf('Edge AI Triage\n(Referral Filter: 25%%)');
add_block('simulink/Math Operations/Gain', [model_name, '/', name_triage], ...
    'Position', [360, 120, 440, 175], ...
    'Gain', '0.25');

% 3. Rural Network Bandwidth Channel (Transmission Delay)
name_net = sprintf('Rural Network Link\n(Transmission Delay: 32s)');
add_block('simulink/Continuous/Transport Delay', [model_name, '/', name_net], ...
    'Position', [640, 120, 720, 175], ...
    'DelayTime', '32.0');

% 4. Central Cloud XAI Processing Server
name_cloud = sprintf('Central Cloud Server\n(XAI Grad-CAM Delay: 4.5s)');
add_block('simulink/Continuous/Transport Delay', [model_name, '/', name_cloud], ...
    'Position', [920, 120, 1000, 175], ...
    'DelayTime', '4.5');

% 5. Doctor Review Queue Sum Node
name_sum = sprintf('Doctor Queue Sum');
add_block('simulink/Math Operations/Sum', [model_name, '/', name_sum], ...
    'Position', [1180, 130, 1220, 170], ...
    'Inputs', '+-');

% 6. Doctor Review Queue Length (Integrator Q >= 0)
name_queue = sprintf('Doctor Review Queue\n(Cases Awaiting Doctor)');
add_block('simulink/Continuous/Integrator', [model_name, '/', name_queue], ...
    'Position', [1320, 120, 1390, 175], ...
    'LimitOutput', 'on', ...
    'LowerSaturationLimit', '0');

% 7. Scope for Doctor Queue Length
name_scope_q = sprintf('Scope: Doctor Queue');
add_block('simulink/Sinks/Scope', [model_name, '/', name_scope_q], ...
    'Position', [1570, 95, 1630, 145]);

% 8. To Workspace: Doctor Queue Length
name_log_q = sprintf('Log: Doctor Queue');
add_block('simulink/Sinks/To Workspace', [model_name, '/', name_log_q], ...
    'Position', [1570, 170, 1660, 205], ...
    'VariableName', 'sim_queue_len', ...
    'SaveFormat', 'Array');

%% ========================================================================
%% LANE 2: DOCTOR REVIEW SERVICE & CAPACITY POOL (Y: 270 - 340)
%% ========================================================================
% Doctor Service Rate (With XAI <30s: 2 doctors / 25s = 0.08 cases/s)
name_doc_rate = sprintf('Doctor Service Rate\n(With XAI: 0.08 cases per sec)');
add_block('simulink/Sources/Constant', [model_name, '/', name_doc_rate], ...
    'Position', [920, 270, 1000, 315], ...
    'Value', '0.08');

% Cumulative Completed Reviews Integrator
name_cum_rev = sprintf('Cumulative Completed\nDoctor Reviews');
add_block('simulink/Continuous/Integrator', [model_name, '/', name_cum_rev], ...
    'Position', [1320, 270, 1390, 325]);

% To Workspace: Completed Reviews
name_log_rev = sprintf('Log: Completed Reviews');
add_block('simulink/Sinks/To Workspace', [model_name, '/', name_log_rev], ...
    'Position', [1570, 280, 1660, 315], ...
    'VariableName', 'sim_completed_reviews', ...
    'SaveFormat', 'Array');

%% ========================================================================
%% LANE 3: LOCAL PHC RESOLUTION STREAM (Y: 420 - 480)
%% ========================================================================
% Local Resolution Filter (Non-Referable cases: 75%)
name_local_filter = sprintf('Local Resolution Filter\n(Non-Referable: 75%%)');
add_block('simulink/Math Operations/Gain', [model_name, '/', name_local_filter], ...
    'Position', [360, 420, 440, 475], ...
    'Gain', '0.75');

% Cumulative Locally Resolved Cases Integrator
name_cum_local = sprintf('Cumulative Locally\nResolved Patients');
add_block('simulink/Continuous/Integrator', [model_name, '/', name_cum_local], ...
    'Position', [640, 420, 720, 475]);

% To Workspace: Locally Resolved Patients
name_log_local = sprintf('Log: Locally Resolved');
add_block('simulink/Sinks/To Workspace', [model_name, '/', name_log_local], ...
    'Position', [920, 430, 1010, 465], ...
    'VariableName', 'sim_locally_resolved', ...
    'SaveFormat', 'Array');

%% ========================================================================
%% WIRING SIGNALS
%% ========================================================================
fprintf('      Wiring pipeline components with orthogonal routing...\n');
% Main Lane
add_line(model_name, [name_intake, '/1'], [name_triage, '/1']);
add_line(model_name, [name_triage, '/1'], [name_net, '/1']);
add_line(model_name, [name_net, '/1'], [name_cloud, '/1']);
add_line(model_name, [name_cloud, '/1'], [name_sum, '/1']);
add_line(model_name, [name_sum, '/1'], [name_queue, '/1']);
add_line(model_name, [name_queue, '/1'], [name_scope_q, '/1']);
add_line(model_name, [name_queue, '/1'], [name_log_q, '/1']);

% Doctor Service Lane
add_line(model_name, [name_doc_rate, '/1'], [name_sum, '/2']);
add_line(model_name, [name_doc_rate, '/1'], [name_cum_rev, '/1']);
add_line(model_name, [name_cum_rev, '/1'], [name_log_rev, '/1']);

% Local Resolution Lane
add_line(model_name, [name_intake, '/1'], [name_local_filter, '/1']);
add_line(model_name, [name_local_filter, '/1'], [name_cum_local, '/1']);
add_line(model_name, [name_cum_local, '/1'], [name_log_local, '/1']);

%% ========================================================================
%% SAVE & SIMULATE
%% ========================================================================
fprintf('      Saving spacious Simulink model file: %s.slx...\n', model_name);
save_system(model_name, [model_name, '.slx']);

fprintf('      Exporting visual diagram snapshot to simulink_model_diagram.png...\n');
print(['-s', model_name], '-dpng', '-r300', 'simulink_model_diagram.png');

fprintf('      Running Simulink simulation engine for 8-hour shift (28,800 sec)...\n');
sim(model_name);

fprintf('\n>>> Simulink model generated, spaced, and simulated successfully!\n');
fprintf('    Model file: %s.slx\n', fullfile(pwd, model_name));
fprintf('    Visual diagram: simulink_model_diagram.png\n\n');

close_system(model_name, 0);

end
