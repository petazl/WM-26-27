
%% CREATE 2D TORQUE-VOLTAGE LOOKUP AND CALCULATE DRIVE CYCLE VOLTAGE

% clear;
% clc;
% close all;

%% 1. Load saved torque matrix

load('MeanTorqueMatrix.mat', ...
     'rpm', 'voltage', 'torqueMatrix');

%% 2. Check lookup matrix dimensions

rpm = rpm(:);
voltage = voltage(:)';

if size(torqueMatrix,1) ~= numel(rpm)
    error('Number of matrix rows must match number of RPM values.');
end

if size(torqueMatrix,2) ~= numel(voltage)
    error('Number of matrix columns must match number of voltage values.');
end

%% 3. Display torque lookup matrix

disp('Rows correspond to RPM:');
disp(rpm);

disp('Columns correspond to voltage:');
disp(voltage);

disp('Torque lookup matrix (Nm):');
disp(torqueMatrix);

%% 4. Display lookup table

voltageNames = "V_" + replace(string(voltage), ".", "_");

lookupTable = array2table(torqueMatrix, ...
    'VariableNames', cellstr(voltageNames));

lookupTable = addvars(lookupTable, rpm, ...
    'Before', 1, ...
    'NewVariableNames', 'RPM');

disp('Torque lookup table:');
disp(lookupTable);

%% 5. Save lookup table as CSV

writetable(lookupTable, 'TorqueVoltageLookup.csv');

%% 6. Plot 3D torque lookup surface

% % X = RPM
% % Y = voltage
% % Z = mean torque
% 
% [RPM_GRID, VOLTAGE_GRID] = meshgrid(rpm, voltage);
% 
% TORQUE_GRID = torqueMatrix';
% 
% fig3D = figure('Color','w', ...
%                'Name','3D Torque Voltage Lookup');
% 
% surf(RPM_GRID, VOLTAGE_GRID, TORQUE_GRID, ...
%     'EdgeColor', 'none');
% 
% xlabel('RPM');
% ylabel('Voltage command (V)');
% zlabel('Mean torque (Nm)');
% title('3D Torque Lookup');
% 
% colorbar;
% grid on;
% box on;
% view(45, 30);
% 
% exportgraphics(fig3D, 'TorqueVoltageLookup_3D.png', ...
%     'Resolution', 300);

%% 7. Load drive cycle

drivecycle = DriveCycleOL;

driveRPM = drivecycle.EVO1UserMotorRPMDriveCycle;
driveTorque = drivecycle.EVO1UserTorqueDriveCycle;
driveTime = drivecycle.timestamp;

% Convert signals to column vectors

driveRPM = driveRPM(:);
driveTorque = driveTorque(:);
driveTime = driveTime(:);

%% 8. Check drive cycle dimensions

if numel(driveRPM) ~= numel(driveTorque)
    error('Drive RPM and torque signals must have equal lengths.');
end

if numel(driveRPM) ~= numel(driveTime)
    error('Drive RPM and time signals must have equal lengths.');
end

%% 9. Calculate required voltage

requiredVoltage = NaN(size(driveRPM));

% Store achievable torque at each drive cycle point

minAvailableTorque = NaN(size(driveRPM));
maxAvailableTorque = NaN(size(driveRPM));

% Store clamped torque request

clampedTorque = NaN(size(driveRPM));

for i = 1:length(driveRPM)

    % Skip invalid drive cycle points

    if ~isfinite(driveRPM(i)) || ...
       ~isfinite(driveTorque(i))

        continue;

    end

    % Torque available at this RPM for each voltage

    torqueCurve = NaN(size(voltage));

    for j = 1:length(voltage)

        % Interpolate lookup torque at current RPM

        torqueCurve(j) = interp1(...
            rpm, ...
            torqueMatrix(:,j), ...
            driveRPM(i), ...
            'linear', ...
            'extrap');

    end

    % Remove invalid torque values

    valid = isfinite(torqueCurve) & isfinite(voltage);

    torqueCurve = torqueCurve(valid);
    voltageAvailable = voltage(valid);

    if isempty(torqueCurve)
        continue;
    end

    %% Find achievable torque range

    minAvailableTorque(i) = min(torqueCurve);
    maxAvailableTorque(i) = max(torqueCurve);

    %% Clamp requested torque

    reqTorque = driveTorque(i);

    reqTorque = min(max(reqTorque, ...
        minAvailableTorque(i)), ...
        maxAvailableTorque(i));

    clampedTorque(i) = reqTorque;

    %% Inverse interpolation

    % Sort torque values into ascending order

    [torqueSorted, sortIdx] = sort(torqueCurve);
    voltageSorted = voltageAvailable(sortIdx);

    % Remove duplicate torque values

    [torqueUnique, uniqueIdx] = unique(torqueSorted);
    voltageUnique = voltageSorted(uniqueIdx);

    % Interpolate required voltage

    if numel(torqueUnique) == 1

        % All available voltages produce the same torque

        requiredVoltage(i) = voltageUnique(1);

    else

        requiredVoltage(i) = interp1(...
            torqueUnique, ...
            voltageUnique, ...
            reqTorque, ...
            'linear');

    end

end

%% 10. Plot drive cycle RPM

figure('Color','w');

plot(driveTime, driveRPM, 'LineWidth', 1.2);

xlabel('Time');
ylabel('RPM');
title('Drive Cycle Motor Speed');

grid on;

%% 11. Plot drive cycle torque

figure('Color','w');

plot(driveTime, driveTorque, 'LineWidth', 1.2);

xlabel('Time');
ylabel('Torque (Nm)');
title('Drive Cycle Requested Torque');

grid on;

%% 12. Plot required voltage

figure('Color','w');

plot(driveTime, requiredVoltage, 'LineWidth', 1.2);

xlabel('Time');
ylabel('Voltage command (V)');
title('Required Voltage for Drive Cycle');

grid on;

%% 13. Plot requested versus achievable torque

figure('Color','w');

plot(driveTime, driveTorque, ...
    'LineWidth', 1.2);

hold on;

plot(driveTime, clampedTorque, ...
    '--', 'LineWidth', 1.2);

hold on;

xlabel('Time');
ylabel('Torque (Nm)');
title('Requested vs Achievable Torque');

legend('Requested Torque', ...
       'Clamped Torque', ...
       'Location', 'best');

grid on;

%% 14. Calculate RPM gradient

rpmGradient = 1000 * gradient(driveRPM) ./ gradient(driveTime);

figure('Color','w');

plot(driveTime, rpmGradient, ...
    'LineWidth', 1.2);

xlabel('Time');
ylabel('RPM/s');
title('Motor Acceleration');

grid on;

%% 15. Create output table

T = table(...
    driveTime, ...
    driveRPM, ...
    driveTorque, ...
    clampedTorque, ...
    minAvailableTorque, ...
    maxAvailableTorque, ...
    requiredVoltage, ...
    rpmGradient, ...
    'VariableNames', {...
        'Time', ...
        'RPM', ...
        'RequestedTorque_Nm', ...
        'ClampedTorque_Nm', ...
        'MinAvailableTorque_Nm', ...
        'MaxAvailableTorque_Nm', ...
        'RequiredVoltage_V', ...
        'RPMGradient_RPM_per_s'});

%% 16. Export drive cycle results

writetable(T, 'DriveCycleVoltageResults.csv');

disp('Drive cycle voltage calculation complete.');
disp('Results saved to DriveCycleVoltageResults.csv');