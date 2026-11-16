
%% Warwick Moto - Full Efficiency Map Analysis
% RPM: 500-5500 in 500 RPM increments
% 10 files per RPM
%
% Calculates:
% 1. Total DC to mechanical efficiency
% 2. DC to AC inverter efficiency
% 3. AC to mechanical motor efficiency
%
% Generates smoothed efficiency maps using:
% - Linear interpolation
% - Light Gaussian smoothing
% - Measured points overlaid
%
% Smoothing is for visualisation only.  

% clear;
% clc;
% close all;

%% 1. Parameters

rpms = 500:500:5500;
files = 1:10;

nRPM = length(rpms);
nFiles = length(files);
nRows = nRPM * nFiles;

% Plateau detection parameters
window = 15;
slope_fraction = 0.01;
amplitude_fraction = 0.7;
min_plateau_length = 20;

% Plot individual torque traces?
plot_results = false;

% Parent folder containing all RPM folders
root_folder = pwd;

% Efficiency map settings
grid_resolution = 400;

% Gaussian smoothing window
smoothing_window = 9;

% Colour limits for all efficiency maps
efficiency_limits = [60 100];

%% 2. Preallocate results

rpm_results = NaN(nRows,1);
file_results = NaN(nRows,1);

plateau_start = NaN(nRows,1);
plateau_end = NaN(nRows,1);

plateau_start_raw = NaN(nRows,1);
plateau_end_raw = NaN(nRows,1);

plateau_mean = NaN(nRows,1);

mean_dc_power = NaN(nRows,1);
mean_ac_power = NaN(nRows,1);
mean_mech_power = NaN(nRows,1);

efficiency_total = NaN(nRows,1);
efficiency_dc_ac = NaN(nRows,1);
efficiency_ac_mech = NaN(nRows,1);

%% 3. Read files and detect plateaus

for r = 1:nRPM

    rpm = rpms(r);

    % Folder for this RPM
    rpm_folder = sprintf('efficiency-map-%dRPM', rpm);

    folder_path = fullfile(root_folder, rpm_folder);

    fprintf('\n====================================\n');
    fprintf('Processing %d RPM\n', rpm);
    fprintf('====================================\n');

    for f = 1:nFiles

        fileNum = files(f);

        % Unique row for this RPM and file
        row = (r-1)*nFiles + f;

        rpm_results(row) = rpm;
        file_results(row) = fileNum;

        %% Read TDMS file

        fileName = sprintf( ...
            'efficiency-map-%dRPM-%d.tdms', ...
            rpm, fileNum);

        full_file_path = fullfile(folder_path, fileName);

        if ~isfile(full_file_path)

            warning('File not found: %s', full_file_path);
            continue;

        end

        fprintf('\nRPM: %d, File: %d\n', rpm, fileNum);

        tdms_data = tdmsread(full_file_path);

        % Extract first group
        raw_data = tdms_data{1,1};

        %% Extract signals

        torque_raw = raw_data.("FMI 1");

        mech_power = raw_data.("Mechanical Power");

        dc_power = raw_data.("EV_Phase7_True_Power");

        ac_power = raw_data.("Sigma_A_P");

        % Convert to column vectors
        torque_raw = torque_raw(:);
        mech_power = mech_power(:);
        dc_power = dc_power(:);
        ac_power = ac_power(:);

        %% Check signal lengths

        if length(torque_raw) ~= length(mech_power) || ...
           length(torque_raw) ~= length(dc_power) || ...
           length(torque_raw) ~= length(ac_power)

            warning(['Signal lengths do not match in ' ...
                'RPM %d, file %d. Skipping.'], rpm, fileNum);

            continue;

        end

        %% Filter torque values below 5 Nm

        % Keep original TDMS indices
        original_indices = find(torque_raw >= 3);

        % Filtered torque signal
        y = torque_raw(original_indices);

        if isempty(y)

            warning(['No torque samples >= 5 Nm in ' ...
                'RPM %d, file %d.'], rpm, fileNum);

            continue;

        end

        %% Smooth torque signal

        y_smooth = smoothdata(y, 'movmean', window);

        %% Calculate gradient

        dy = gradient(y_smooth);

        %% Calculate thresholds

        signal_range = max(y) - min(y);

        slope_threshold = slope_fraction * signal_range;

        amplitude_threshold = min(y) + ...
            amplitude_fraction * signal_range;

        %% Identify plateau samples

        is_flat = abs(dy) < slope_threshold & ...
                  y_smooth > amplitude_threshold;

        %% Find consecutive flat regions

        edges = diff([false; is_flat; false]);

        starts = find(edges == 1);
        ends = find(edges == -1) - 1;

        %% Remove plateaus that are too short

        valid_plateaus = ...
            (ends - starts + 1) >= min_plateau_length;

        starts = starts(valid_plateaus);
        ends = ends(valid_plateaus);

        %% Check if plateau was found

        if isempty(starts)

            warning(['No plateau found in RPM %d, ' ...
                'file %d.'], rpm, fileNum);

            continue;

        end

        %% Find longest plateau

        [~, best_idx] = max(ends - starts + 1);

        plateau_start(row) = starts(best_idx);
        plateau_end(row) = ends(best_idx);

        %% Convert filtered indices to original TDMS indices

        plateau_start_raw(row) = ...
            original_indices(plateau_start(row));

        plateau_end_raw(row) = ...
            original_indices(plateau_end(row));

        %% Calculate mean plateau torque

        plateau_mean(row) = mean( ...
            y(plateau_start(row):plateau_end(row)));

        %% Get original TDMS indices of plateau samples

        plateau_indices = original_indices( ...
            plateau_start(row):plateau_end(row));

        %% Extract power signals over plateau

        dc_plateau = dc_power(plateau_indices);

        ac_plateau = ac_power(plateau_indices);

        mech_plateau = mech_power(plateau_indices);

        %% Calculate mean powers

        mean_dc_power(row) = mean(dc_plateau);

        mean_ac_power(row) = mean(ac_plateau);

        mean_mech_power(row) = mean(mech_plateau);

        %% Calculate efficiencies

        if mean_dc_power(row) ~= 0 && ...
           mean_ac_power(row) ~= 0

            % Total DC to mechanical efficiency
            efficiency_total(row) = ...
                mean_mech_power(row) / ...
                mean_dc_power(row) * 100;

            % Inverter DC to AC efficiency
            efficiency_dc_ac(row) = ...
                mean_ac_power(row) / ...
                mean_dc_power(row) * 100;

            % Motor AC to mechanical efficiency
            efficiency_ac_mech(row) = ...
                mean_mech_power(row) / ...
                mean_ac_power(row) * 100;

        else

            warning(['Zero mean DC or AC power in ' ...
                'RPM %d, file %d.'], rpm, fileNum);

        end

        %% Display results

        fprintf('Mean plateau torque: %.3f Nm\n', ...
            plateau_mean(row));

        fprintf('Mean DC power: %.3f W\n', ...
            mean_dc_power(row));

        fprintf('Mean AC power: %.3f W\n', ...
            mean_ac_power(row));

        fprintf('Mean mechanical power: %.3f W\n', ...
            mean_mech_power(row));

        fprintf('Total efficiency: %.2f %%\n', ...
            efficiency_total(row));

        fprintf('DC-AC efficiency: %.2f %%\n', ...
            efficiency_dc_ac(row));

        fprintf('AC-mechanical efficiency: %.2f %%\n', ...
            efficiency_ac_mech(row));

        %% Optional torque plot for debugging

        if plot_results

            figure('Name', sprintf( ...
                '%d RPM - File %d', rpm, fileNum));

            plot(y, 'DisplayName', 'Filtered torque');
            hold on;

            plot(y_smooth, ...
                'DisplayName', 'Smoothed torque');

            xline(plateau_start(row), '--g', ...
                'Plateau start');

            xline(plateau_end(row), '--r', ...
                'Plateau end');

            yline(amplitude_threshold, '--k', ...
                'Amplitude threshold');

            legend;
            grid on;

            xlabel('Filtered sample index');
            ylabel('Torque (Nm)');

            title(sprintf('%d RPM - File %d', ...
                rpm, fileNum));

        end

    end
end

%% 4. Create combined results table

results = table( ...
    rpm_results, ...
    file_results, ...
    plateau_start, ...
    plateau_end, ...
    plateau_start_raw, ...
    plateau_end_raw, ...
    plateau_mean, ...
    mean_dc_power, ...
    mean_ac_power, ...
    mean_mech_power, ...
    efficiency_total, ...
    efficiency_dc_ac, ...
    efficiency_ac_mech, ...
    'VariableNames', { ...
        'RPM', ...
        'FileNumber', ...
        'FilteredStartIndex', ...
        'FilteredEndIndex', ...
        'OriginalStartIndex', ...
        'OriginalEndIndex', ...
        'MeanPlateauTorque', ...
        'MeanDCPower', ...
        'MeanACPower', ...
        'MeanMechanicalPower', ...
        'TotalEfficiency', ...
        'DCAEfficency', ...
        'ACMechanicalEfficiency'});

disp(results);

%% 5. Save results table

writetable(results, ...
    fullfile(root_folder, 'Efficiency_Map_Results.csv'));

fprintf('\nResults saved to Efficiency_Map_Results.csv\n');

%% 6. Prepare valid measurements

% Use separate valid masks for each efficiency map

valid_total = isfinite(rpm_results) & ...
              isfinite(plateau_mean) & ...
              isfinite(efficiency_total);

valid_dc_ac = isfinite(rpm_results) & ...
              isfinite(plateau_mean) & ...
              isfinite(efficiency_dc_ac);

valid_ac_mech = isfinite(rpm_results) & ...
                isfinite(plateau_mean) & ...
                isfinite(efficiency_ac_mech);

%% 7. Combine repeated operating points

% Round torque to 0.1 Nm to identify repeated points

% Total efficiency
rpm_total = rpm_results(valid_total);
torque_total = round(plateau_mean(valid_total),1);
eta_total = efficiency_total(valid_total);

[G_total, rpm_unique_total, torque_unique_total] = ...
    findgroups(rpm_total, torque_total);

total_mean = splitapply(@mean, eta_total, G_total);

% Inverter efficiency
rpm_dc_ac = rpm_results(valid_dc_ac);
torque_dc_ac = round(plateau_mean(valid_dc_ac),1);
eta_dc_ac = efficiency_dc_ac(valid_dc_ac);

[G_dc_ac, rpm_unique_dc_ac, torque_unique_dc_ac] = ...
    findgroups(rpm_dc_ac, torque_dc_ac);

dc_ac_mean = splitapply(@mean, eta_dc_ac, G_dc_ac);

% Motor efficiency
rpm_ac_mech = rpm_results(valid_ac_mech);
torque_ac_mech = round(plateau_mean(valid_ac_mech),1);
eta_ac_mech = efficiency_ac_mech(valid_ac_mech);

[G_ac_mech, rpm_unique_ac_mech, torque_unique_ac_mech] = ...
    findgroups(rpm_ac_mech, torque_ac_mech);

ac_mech_mean = splitapply(@mean, eta_ac_mech, G_ac_mech);

%% 8. Plot total efficiency map

plotEfficiencyMap( ...
    rpm_unique_total, ...
    torque_unique_total, ...
    total_mean, ...
    'Total DC to Mechanical Efficiency (%)', ...
    'Total Efficiency Map', ...
    efficiency_limits, ...
    grid_resolution, ...
    smoothing_window, ...
    root_folder, ...
    'Total_Efficiency_Map.png');

%% 9. Plot inverter efficiency map

% plotEfficiencyMap( ...
%     rpm_unique_dc_ac, ...
%     torque_unique_dc_ac, ...
%     dc_ac_mean, ...
%     'DC to AC Inverter Efficiency (%)', ...
%     'Inverter Efficiency Map', ...
%     efficiency_limits, ...
%     grid_resolution, ...
%     smoothing_window, ...
%     root_folder, ...
%     'DC_AC_Efficiency_Map.png');

%% 10. Plot motor efficiency map

plotEfficiencyMap( ...
    rpm_unique_ac_mech, ...
    torque_unique_ac_mech, ...
    ac_mech_mean, ...
    'AC to Mechanical Motor Efficiency (%)', ...
    'Motor Efficiency Map', ...
    efficiency_limits, ...
    grid_resolution, ...
    smoothing_window, ...
    root_folder, ...
    'AC_Mechanical_Efficiency_Map.png');

fprintf('\nAll efficiency maps generated.\n');

%% 11. Local plotting function

function plotEfficiencyMap( ...
    rpm_data, torque_data, efficiency_data, ...
    plot_title, figure_name, ...
    efficiency_limits, grid_resolution, ...
    smoothing_window, root_folder, output_filename)

    %% Check sufficient unique operating points

    if length(rpm_data) < 3 || ...
       length(unique([rpm_data, torque_data], 'rows')) < 3

        warning('Not enough unique points for %s.', plot_title);
        return;

    end

    %% Create interpolation grid

    rpm_grid = linspace( ...
        min(rpm_data), max(rpm_data), grid_resolution);

    torque_grid = linspace( ...
        min(torque_data), max(torque_data), grid_resolution);

    [RPM_GRID, TORQUE_GRID] = ...
        meshgrid(rpm_grid, torque_grid);

    %% Linear interpolation

    F_linear = scatteredInterpolant( ...
        rpm_data, ...
        torque_data, ...
        efficiency_data, ...
        'linear', ...
        'none');

    EFF_GRID = F_linear(RPM_GRID, TORQUE_GRID);

    %% Find measured operating region

    hull_indices = convhull(rpm_data, torque_data);

    inside_hull = inpolygon( ...
        RPM_GRID, ...
        TORQUE_GRID, ...
        rpm_data(hull_indices), ...
        torque_data(hull_indices));

    %% Fill missing grid values for smoothing only

    % Nearest-neighbour extrapolation is used only to
    % prevent NaNs contaminating the smoothing filter.

    F_nearest = scatteredInterpolant( ...
        rpm_data, ...
        torque_data, ...
        efficiency_data, ...
        'nearest', ...
        'nearest');

    EFF_FILLED = EFF_GRID;

    missing = ~isfinite(EFF_FILLED);

    EFF_FILLED(missing) = ...
        F_nearest(RPM_GRID(missing), TORQUE_GRID(missing));

    %% Light Gaussian smoothing

    % Smooth across torque direction
    EFF_SMOOTH = smoothdata( ...
        EFF_FILLED, 1, 'gaussian', smoothing_window);

    % Smooth across RPM direction
    EFF_SMOOTH = smoothdata( ...
        EFF_SMOOTH, 2, 'gaussian', smoothing_window);

    %% Mask outside measured operating region

    EFF_SMOOTH(~inside_hull) = NaN;

    %% Plot efficiency map

    figure('Name', figure_name);

    contourf( ...
        RPM_GRID, ...
        TORQUE_GRID, ...
        EFF_SMOOTH, ...
        100, ...
        'LineColor', 'none');

    hold on;

    %% Overlay actual measured points

    scatter( ...
        rpm_data, ...
        torque_data, ...
        35, ...
        efficiency_data, ...
        'filled', ...
        'MarkerEdgeColor', 'k');

    %% Formatting

    colormap(turbo(256));

    clim(efficiency_limits);

    colorbar;

    xlabel('Speed (RPM)');
    ylabel('Mean Plateau Torque (Nm)');

    title(plot_title);

    grid on;
    box on;
    axis tight;

    set(gca, 'FontSize', 12);

    %% Save figure

    exportgraphics(gcf, ...
        fullfile(root_folder, output_filename), ...
        'Resolution', 300);

end

%% SAVE MEAN TORQUE MATRIX

% Fixed voltage commands for the 10 test points
voltage = [0.5 1 1.5 2 2.5 3 3.5 4 4.5 4.94];

% Get all RPMs represented in the processed results
rpm = sort(unique(results.RPM));

% Initialise matrix:
% Rows    = RPM
% Columns = test point / voltage command
% Values  = mean torque in Nm
torqueMatrix = NaN(numel(rpm), numel(voltage));

%% Fill matrix using processed results

for i = 1:numel(rpm)
    for j = 1:numel(voltage)

        % File number is assumed to match voltage column
        idx = results.RPM == rpm(i) & ...
              results.FileNumber == j;

        if any(idx)
            torqueMatrix(i,j) = mean( ...
                results.MeanPlateauTorque(idx), 'omitnan');
        end
    end
end

%% Display matrix

disp('RPM values:');
disp(rpm);

disp('Voltage commands:');
disp(voltage);

disp('Mean torque matrix (Nm):');
disp(torqueMatrix);

%% Save matrix and axes for the lookup script

save('MeanTorqueMatrix.mat', ...
     'rpm', 'voltage', 'torqueMatrix');

%% Also save a readable CSV file

voltageNames = "V_" + replace(string(voltage), ".", "_");

torqueTable = array2table(torqueMatrix, ...
    'VariableNames', cellstr(voltageNames));

torqueTable = addvars(torqueTable, rpm, ...
    'Before', 1, ...
    'NewVariableNames', 'RPM');

writetable(torqueTable, 'MeanTorqueMatrix.csv');

disp('Saved MeanTorqueMatrix.mat and MeanTorqueMatrix.csv');


