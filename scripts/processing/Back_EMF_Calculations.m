% Define the specific RPM
rpmValues = [1000, 2000, 3000, 4000, 5000, 6000];
numFiles = length(rpmValues);

% motor information
poles = 5;

% Preallocate a cell array to store the structure returned by tdmsread
tdmsData = cell(1, numFiles);

for k = 1:numFiles
    % Construct filename using string interpolation or sprintf
    fileName = sprintf('open-circuit-test-%d-RPM.tdms', rpmValues(k));

    % Check if the file exists before reading to avoid crashing the loop
    if isfile(fileName)
        tdmsData{k} = tdmsread(fileName); % Stores data as cell array
    else
        warning('File %s not found. Skipping.', fileName);
    end
end
%% 1000 RPM 
phase_data_1000RPM= tdmsData{1, 1}{1, 2}; % returns table
phase1_voltage_1000 = phase_data_1000RPM.("Phase 1 Voltage ");
Phase2_voltage_1000 = phase_data_1000RPM.("Phase 2 Voltage ");
Phase3_voltage_1000 = phase_data_1000RPM.("Phase 3 Voltage ");

%% 2000 RPM
phase_data_2000RPM= tdmsData{1,2}{1,2}; % returns table
phase1_voltage_2000 = phase_data_2000RPM.("Phase 1 Voltage ");
phase2_voltage_2000 = phase_data_2000RPM.("Phase 2 Voltage ");
phase3_voltage_2000 = phase_data_2000RPM.("Phase 3 Voltage ");

%% 3000 RPM
phase_data_3000RPM= tdmsData{1,3}{1,2}; % returns table
phase1_voltage_3000 = phase_data_3000RPM.("Phase 1 Voltage ");
phase2_voltage_3000 = phase_data_3000RPM.("Phase 2 Voltage ");
phase3_voltage_3000 = phase_data_3000RPM.("Phase 3 Voltage ");

%% 4000 RPM
phase_data_4000RPM= tdmsData{1,4}{1,2}; % returns table
phase1_voltage_4000 = phase_data_4000RPM.("Phase 1 Voltage ");
phase2_voltage_4000 = phase_data_4000RPM.("Phase 2 Voltage ");
phase3_voltage_4000 = phase_data_4000RPM.("Phase 3 Voltage ");

%% 5000 RPM 
phase_data_5000RPM= tdmsData{1,5}{1,2}; % returns table
phase1_voltage_5000 = phase_data_5000RPM.("Phase 1 Voltage ");
phase2_voltage_5000 = phase_data_5000RPM.("Phase 2 Voltage ");
phase3_voltage_5000 = phase_data_5000RPM.("Phase 3 Voltage ");

%% 6000 RPM
phase_data_6000RPM= tdmsData{1,6}{1,2}; % returns table
phase1_voltage_6000 = phase_data_6000RPM.("Phase 1 Voltage ");
phase2_voltage_6000 = phase_data_6000RPM.("Phase 2 Voltage ");
phase3_voltage_6000 = phase_data_6000RPM.("Phase 3 Voltage ");

% Phase 1 peaks for all RPMs
[pks1, locs1] = findpeaks(phase1_voltage_1000, 'MinPeakHeight', 13);
[pks2, locs2] = findpeaks(phase1_voltage_2000, 'MinPeakHeight', 26);
[pks3, locs3] = findpeaks(phase1_voltage_3000, 'MinPeakHeight', 39);
[pks4, locs4] = findpeaks(phase1_voltage_4000, 'MinPeakHeight', 48);
[pks5, locs5] = findpeaks(phase1_voltage_5000, 'MinPeakHeight', 65);
[pks6, locs6] = findpeaks(phase1_voltage_6000, 'MinPeakHeight', 80);

% Calculate the average of those peak values
V_rms_1000 = mean(pks1);
V_rms_2000 = mean(pks2);
V_rms_3000 = mean(pks3);
V_rms_4000 = mean(pks4);
V_rms_5000 = mean(pks5);
V_rms_6000 = mean(pks6);

back_emf_1000 = V_rms_1000/1000;
back_emf_2000 = V_rms_2000/2000;
back_emf_3000 = V_rms_3000/3000;
back_emf_4000 = V_rms_4000/4000;
back_emf_5000 = V_rms_5000/5000;
back_emf_6000 = V_rms_6000/6000;

back_emf_values = [back_emf_1000, back_emf_2000, back_emf_3000, ...
                   back_emf_4000, back_emf_5000, back_emf_6000];

% V per RPM
back_emf_constant = mean(back_emf_values);

back_emf_constant_rms = back_emf_constant/sqrt(2);
% 
% figure
% plot(phase1_voltage_1000);
% 
% figure
% plot(phase1_voltage_2000);
% 
% figure
% plot(phase1_voltage_3000);
% figure
% plot(phase1_voltage_4000);
% figure
% plot(phase1_voltage_5000);
% figure
% plot(phase1_voltage_6000);
% 
