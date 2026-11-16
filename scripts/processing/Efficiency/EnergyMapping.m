%% ============================================================
% MECHANICAL POWER DIRECTLY FROM TORQUE LOOKUP
% ============================================================
% 
% clear;
% clc;
% close all;

%% Load torque lookup

load('MeanTorqueMatrix.mat', ...
    'rpm', 'voltage', 'torqueMatrix');

%% RPM -> angular velocity

omega = rpm(:) * 2*pi/60;

%% Calculate mechanical power

% torqueMatrix:
% rows    = RPM
% columns = voltage

mechanicalPowerMatrix = ...
    torqueMatrix .* omega;

%% Display

disp('Mechanical power matrix (W):');
disp(mechanicalPowerMatrix);

% %% ============================================================
% % 3D PLOT
% % ============================================================
% 
% [RPM_GRID, VOLTAGE_GRID] = meshgrid(rpm, voltage);
% 
% fig = figure( ...
%     'Color','w', ...
%     'Name','Mechanical Power Lookup');
% 
% surf( ...
%     RPM_GRID, ...
%     VOLTAGE_GRID, ...
%     mechanicalPowerMatrix', ...
%     'EdgeColor','none');
% 
% xlabel('RPM');
% ylabel('Voltage command (V)');
% zlabel('Mechanical Power (W)');
% 
% title('Mechanical Power Lookup');
% 
% colorbar;
% grid on;
% box on;
% 
% view(45,30);
% 
% %% Save
% 
% save('MechanicalPowerMatrix.mat', ...
%     'rpm', ...
%     'voltage', ...
%     'mechanicalPowerMatrix');
% 
% exportgraphics(fig, ...
%     'MechanicalPowerLookup_3D.png', ...
%     'Resolution',300);

%% ============================================================
%  2D POWER HEAT MAP
%  X = RPM
%  Y = Torque
%  Colour = Power
%  ============================================================

clear;
clc;
close all;

%% Load processed results
% If results is already in your workspace, comment this out

% load('ProcessedResults.mat');

%% Select which power to plot

powerColumn = 'MeanMechanicalPower';

% Other possibilities, depending on your results table:
%
% powerColumn = 'MeanMechanicalPower';
% powerColumn = 'MeanACPower';
% powerColumn = 'MeanDCPower';

torqueColumn = 'MeanTorque';

%% Check columns
% 
% if ~ismember(powerColumn, results.Properties.VariableNames)
%     error('Power column "%s" not found in results.', powerColumn);
% end
% 
% if ~ismember(torqueColumn, results.Properties.VariableNames)
%     error('Torque column "%s" not found in results.', torqueColumn);
% end

%% ============================================================
% Extract data
% ============================================================

valid = isfinite(results.RPM) & ...
        isfinite(results.(torqueColumn)) & ...
        isfinite(results.(powerColumn));

rpmData = results.RPM(valid);
torqueData = results.(torqueColumn)(valid);
powerData = results.(powerColumn)(valid);

%% ============================================================
% Average duplicate operating points
% ============================================================

[operatingPoints, ~, groupID] = unique( ...
    [rpmData torqueData], 'rows');

powerMean = accumarray( ...
    groupID, ...
    powerData, ...
    [], ...
    @(x) mean(x,'omitnan'));

rpmData = operatingPoints(:,1);
torqueData = operatingPoints(:,2);
powerData = powerMean;

%% ============================================================
% Create interpolation grid
% ============================================================

rpmGrid = linspace( ...
    min(rpmData), ...
    max(rpmData), ...
    400);

torqueGrid = linspace( ...
    min(torqueData), ...
    max(torqueData), ...
    400);

[RPM_GRID, TORQUE_GRID] = meshgrid( ...
    rpmGrid, torqueGrid);

%% ============================================================
% Interpolate power
% ============================================================

F = scatteredInterpolant( ...
    rpmData, ...
    torqueData, ...
    powerData, ...
    'linear', ...
    'none');

POWER_GRID = F( ...
    RPM_GRID, ...
    TORQUE_GRID);

%% ============================================================
% Mask outside measured operating region
% ============================================================

hull = convhull( ...
    rpmData, ...
    torqueData);

insideHull = inpolygon( ...
    RPM_GRID, ...
    TORQUE_GRID, ...
    rpmData(hull), ...
    torqueData(hull));

POWER_GRID(~insideHull) = NaN;

%% ============================================================
% Smooth for visualisation
% ============================================================

POWER_FILLED = POWER_GRID;

% Temporarily fill NaNs using nearest-neighbour interpolation
Fnearest = scatteredInterpolant( ...
    rpmData, ...
    torqueData, ...
    powerData, ...
    'nearest', ...
    'nearest');

missing = isnan(POWER_FILLED);

POWER_FILLED(missing) = Fnearest( ...
    RPM_GRID(missing), ...
    TORQUE_GRID(missing));

% Gaussian smoothing
smoothingWindow = 7;

POWER_SMOOTH = smoothdata( ...
    POWER_FILLED, ...
    1, ...
    'gaussian', ...
    smoothingWindow);

POWER_SMOOTH = smoothdata( ...
    POWER_SMOOTH, ...
    2, ...
    'gaussian', ...
    smoothingWindow);

% Restore measured operating boundary
POWER_SMOOTH(~insideHull) = NaN;

%% ============================================================
% Plot
% ============================================================

fig = figure( ...
    'Color','w', ...
    'Name','Power Map');

contourf( ...
    RPM_GRID, ...
    TORQUE_GRID, ...
    POWER_SMOOTH, ...
    100, ...
    'LineColor','none');

hold on;

% Plot actual measured points
scatter( ...
    rpmData, ...
    torqueData, ...
    20, ...
    powerData, ...
    'filled', ...
    'MarkerEdgeColor','k');

hold off;

xlabel('RPM');
ylabel('Torque (Nm)');

title(strrep( ...
    powerColumn, ...
    'Mean', ''));

cb = colorbar;
cb.Label.String = 'Power (W)';

colormap(turbo);

grid on;
box on;

%% ============================================================
% Save
% ============================================================

exportgraphics( ...
    fig, ...
    'PowerMap.png', ...
    'Resolution',300);