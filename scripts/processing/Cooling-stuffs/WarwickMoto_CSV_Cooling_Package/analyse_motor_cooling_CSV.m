%% Warwick Moto | Motor thermal characterisation from drive-cycle CSVs
% MATLAB R2020b+ (readtable VariableNamingRule); no toolboxes required.
% INPUT: CSV columns Time,Torque,AC,DC,Mech,Inlet,Outlet,MotorTemp,RPM.
% UNITS: s, Nm, W, W, W, degC, degC, degC, rpm.
%
% The rule requested by the user is strict:
%   EXCLUDE a complete row if ANY of AC, DC or Mech is NEGATIVE.
%   Zero power is valid. Other negative values (e.g. torque) do NOT
%   themselves cause exclusion. Non-finite required values also excluded.
%   Calculated negative LOSSES (AC - Mech, DC - AC) are NOT deleted/clipped.
%
% Energy is integrated only across ORIGINAL adjacent rows where BOTH rows
% are valid. This deliberately avoids bridging gaps caused by exclusions.
% The coolant calculation assumes motor-only water circuit, constant 5 L/min,
% rho=1 kg/L and cp=4180 J/(kg*K).

clear; clc; close all;
folder = fileparts(mfilename('fullpath'));
inputDir = fullfile(folder,'Input_CSVs');
outputDir = fullfile(folder,'Results_MATLAB');
if ~exist(outputDir,'dir'); mkdir(outputDir); end

% Add a fourth CSV filename below if one becomes available.
csvFiles = {'MS2025-1.csv', 'MS2025-2.csv', ...
            'Optimum-Lap-Single-Lap.csv'};
flow_L_min = 5;
rho_kg_L = 1.0;         % Approximate density of water
cp_J_kgK = 4180;        % Approximate specific heat capacity
heatFactor_W_K = (flow_L_min/60) * rho_kg_L * cp_J_kgK;

needCols = {'Time','Torque','AC','DC','Mech','Inlet','Outlet','MotorTemp','RPM'};
nFiles = numel(csvFiles);
summary = table('Size',[nFiles,21], ...
    'VariableTypes',{'string','double','double','double','double','double', ...
                     'double','double','double','double','double','double', ...
                     'double','double','double','double','double','double', ...
                     'double','double','double'}, ...
    'VariableNames',{'Cycle','RowsTotal','RowsKept','RowsExcluded', ...
    'ExcludedNegativePower','RawDuration_s','AnalysedDuration_s', ...
    'MeanAC_kW','MeanDC_kW','MeanMech_kW','MeanMotorLoss_kW', ...
    'PeakMotorLoss_kW','MotorLossEnergy_MJ','MeanInverterLoss_kW', ...
    'MeanCoolantHeat_kW','CoolantEnergy_MJ','MeanDeltaT_degC', ...
    'MaxMotorTemp_degC','MaxOutletTemp_degC','NegativeMotorLossRows', ...
    'NegativeInverterLossRows'});

for k = 1:nFiles
    filename = csvFiles{k};
    filePath = fullfile(inputDir,filename);
    if ~isfile(filePath), error('Cannot find %s',filePath); end
    T = readtable(filePath,'VariableNamingRule','preserve');
    assert(all(ismember(needCols,T.Properties.VariableNames)), ...
        'Missing required columns in %s. Expected: %s',filename,strjoin(needCols,', '));
    for c = 1:numel(needCols)
        assert(isnumeric(T.(needCols{c})), ...
               '%s must be numeric in %s',needCols{c},filename);
    end
    time = double(T.Time(:));
    tq = double(T.Torque(:));
    pac = double(T.AC(:));
    pdc = double(T.DC(:));
    pmech = double(T.Mech(:));
    tin = double(T.Inlet(:));
    tout = double(T.Outlet(:));
    tmotor = double(T.MotorTemp(:));
    rpm = double(T.RPM(:));

    if any(diff(time)<=0)
        error('%s: Time must be strictly increasing; review CSV time column.',filename);
    end
    numericData = [time,tq,pac,pdc,pmech,tin,tout,tmotor,rpm];
    nonFinite = ~all(isfinite(numericData),2);
    negativePower = (pac<0) | (pdc<0) | (pmech<0);
    valid = ~nonFinite & ~negativePower;
    assert(sum(valid)>=2,'%s: Fewer than two valid rows.',filename);

    % These are SIGNED balances; a negative value flags an inconsistency
    % rather than permission to discard or to convert it into zero.
    motorLoss_W = pac - pmech;
    inverterLoss_W = pdc - pac;
    dT_degC = tout-tin;
    coolantHeat_W = heatFactor_W_K .* dT_degC;
    calcMech_W = tq .* (rpm*2*pi/60);  % Cross-check only

    dt = diff(time);
    pairOK = valid(1:end-1) & valid(2:end);
    analysed_s = sum(dt(pairOK));
    if analysed_s<=0, error('%s: No adjacent valid samples to integrate.',filename); end

    E_motor_J = integrateValidPairs(time,motorLoss_W,pairOK);
    E_coolant_J = integrateValidPairs(time,coolantHeat_W,pairOK);
    E_inverter_J = integrateValidPairs(time,inverterLoss_W,pairOK);
    E_ac_J = integrateValidPairs(time,pac,pairOK);
    E_dc_J = integrateValidPairs(time,pdc,pairOK);
    E_mech_J = integrateValidPairs(time,pmech,pairOK);
    E_dT_sC = integrateValidPairs(time,dT_degC,pairOK);

    % Keep ONLY valid original rows in exported output.
    out = table(time(valid),tq(valid),rpm(valid),pac(valid),pdc(valid), ...
        pmech(valid),tin(valid),tout(valid),tmotor(valid),dT_degC(valid), ...
        motorLoss_W(valid),inverterLoss_W(valid),coolantHeat_W(valid), ...
        calcMech_W(valid),E_motor_J(valid),E_coolant_J(valid),E_inverter_J(valid), ...
        'VariableNames',{'Time_s','Torque_Nm','RPM','AC_W','DC_W', ...
        'Mech_W','Inlet_degC','Outlet_degC','MotorTemp_degC', ...
        'CoolantDeltaT_degC','MotorLoss_signed_W','InverterLoss_signed_W', ...
        'CoolantHeat_W','MechCheck_TorqueRPM_W', ...
        'CumulativeMotorLoss_J','CumulativeCoolantEnergy_J', ...
        'CumulativeInverterLoss_J'});
    [~,stem] = fileparts(filename);
    writetable(out,fullfile(outputDir,[stem '_processed.csv']));

    summary.Cycle(k) = string(stem);
    summary.RowsTotal(k) = height(T);
    summary.RowsKept(k) = sum(valid);
    summary.RowsExcluded(k) = sum(~valid);
    summary.ExcludedNegativePower(k) = sum(negativePower);
    summary.RawDuration_s(k) = time(end)-time(1);
    summary.AnalysedDuration_s(k) = analysed_s;
    summary.MeanAC_kW(k) = E_ac_J(end)/analysed_s/1000;
    summary.MeanDC_kW(k) = E_dc_J(end)/analysed_s/1000;
    summary.MeanMech_kW(k) = E_mech_J(end)/analysed_s/1000;
    summary.MeanMotorLoss_kW(k) = E_motor_J(end)/analysed_s/1000;
    summary.PeakMotorLoss_kW(k) = max(motorLoss_W(valid))/1000;
    summary.MotorLossEnergy_MJ(k) = E_motor_J(end)/1e6;
    summary.MeanInverterLoss_kW(k) = E_inverter_J(end)/analysed_s/1000;
    summary.MeanCoolantHeat_kW(k) = E_coolant_J(end)/analysed_s/1000;
    summary.CoolantEnergy_MJ(k) = E_coolant_J(end)/1e6;
    summary.MeanDeltaT_degC(k) = E_dT_sC(end)/analysed_s;
    summary.MaxMotorTemp_degC(k) = max(tmotor(valid));
    summary.MaxOutletTemp_degC(k) = max(tout(valid));
    summary.NegativeMotorLossRows(k) = sum(valid & motorLoss_W<0);
    summary.NegativeInverterLossRows(k) = sum(valid & inverterLoss_W<0);

    ind = find(valid);
    ind = ind(1:max(1,floor(numel(ind)/4000)):end);
    % FIGURE 1 | signed motor loss versus coolant heat uptake
    fig = figure('Visible','off','Color','w','Position',[100 100 1150 550]);
    plot(time(ind),motorLoss_W(ind)/1000,'LineWidth',0.7); hold on;
    plot(time(ind),coolantHeat_W(ind)/1000,'LineWidth',1.3);
    yline(0,'--','LineWidth',0.8);
    xlabel('Time (s)'); ylabel('Thermal power (kW)');
    legend('Motor losses (AC - Mech)','Coolant uptake','Zero','Location','best');
    title([stem ' | motor losses vs coolant heat uptake']); grid on;
    exportgraphics(fig,fullfile(outputDir,[stem '_01_power.png']),'Resolution',180); close(fig);

    % FIGURE 2 | temperatures
    fig = figure('Visible','off','Color','w','Position',[100 100 1150 550]);
    plot(time(ind),tmotor(ind),'LineWidth',1.5);hold on;
    plot(time(ind),tin(ind),'LineWidth',1.1);
    plot(time(ind),tout(ind),'LineWidth',1.1);
    xlabel('Time (s)'); ylabel('Temperature (degC)');
    title([stem ' | temperature response']);
    legend('Motor','Coolant inlet','Coolant outlet','Location','best'); grid on;
    exportgraphics(fig,fullfile(outputDir,[stem '_02_temperatures.png']),'Resolution',180); close(fig);

    % FIGURE 3 | energy from only adjacent valid original samples
    fig = figure('Visible','off','Color','w','Position',[100 100 1150 550]);
    plot(time(ind),E_motor_J(ind)/1e6,'LineWidth',1.5);hold on;
    plot(time(ind),E_coolant_J(ind)/1e6,'LineWidth',1.5);
    xlabel('Time (s)'); ylabel('Cumulative energy (MJ)');
    title([stem ' | valid-interval energy']);
    legend('Signed motor loss energy','Coolant heat energy','Location','best'); grid on;
    exportgraphics(fig,fullfile(outputDir,[stem '_03_energy.png']),'Resolution',180); close(fig);

    % FIGURE 4 | average signed motor losses in torque/RPM bins
    rEdges = linspace(min(rpm(valid)),max(rpm(valid)),16);
    tEdges = linspace(min(tq(valid)),max(tq(valid)),13);
    [~,~,rB] = histcounts(rpm(valid),rEdges);
    [~,~,tB] = histcounts(tq(valid),tEdges);
    binOK = rB>0 & tB>0;
    zValid = motorLoss_W(valid)/1000;
    binned = accumarray([tB(binOK),rB(binOK)],zValid(binOK), ...
        [numel(tEdges)-1,numel(rEdges)-1],@mean,NaN);
    fig = figure('Visible','off','Color','w','Position',[100 100 1100 650]);
    imagesc((rEdges(1:end-1)+rEdges(2:end))/2, ...
            (tEdges(1:end-1)+tEdges(2:end))/2,binned);
    set(gca,'YDir','normal'); colorbar; xlabel('RPM');ylabel('Torque (Nm)');
    title([stem ' | mean signed motor losses per bin (kW)']);
    exportgraphics(fig,fullfile(outputDir,[stem '_04_torque_rpm_map.png']),'Resolution',180);close(fig);

    % FIGURE 5 | motor temperature vs cumulative signed motor loss energy
    fig = figure('Visible','off','Color','w','Position',[100 100 1100 550]);
    plot(E_motor_J(ind)/1e6,tmotor(ind),'.','MarkerSize',4);
    xlabel('Cumulative signed motor loss energy (MJ)'); ylabel('Motor temperature (degC)');
    title([stem ' | motor temperature vs integrated loss energy']); grid on;
    exportgraphics(fig,fullfile(outputDir,[stem '_05_temperature_energy.png']),'Resolution',180); close(fig);

    fprintf('\n%s: retained %d/%d rows; motor loss %.3f kW; coolant uptake %.3f kW; motor max %.1f C\n', ...
        stem,sum(valid),height(T),summary.MeanMotorLoss_kW(k), ...
        summary.MeanCoolantHeat_kW(k),summary.MaxMotorTemp_degC(k));
end

writetable(summary,fullfile(outputDir,'DriveCycle_Comparison.csv'));
fig = figure('Visible','off','Color','w','Position',[100 100 1150 650]);
bar(categorical(cellstr(summary.Cycle)),[summary.MeanMotorLoss_kW, summary.MeanCoolantHeat_kW]);
ylabel('Average thermal power over valid intervals (kW)');
legend('Signed motor losses','Heat taken up by motor coolant','Location','northwest');
title('Warwick Moto | Drive cycle thermal comparison'); grid on;
exportgraphics(fig,fullfile(outputDir,'DriveCycle_Comparison.png'),'Resolution',180); close(fig);

disp('');disp(summary);
fprintf('\nResults saved in: %s\n',outputDir);
fprintf('CAUTION: Negative derived losses are retained and indicate measurement/temporal consistency issues.\n');

function E = integrateValidPairs(t,p,pairOK)
% A trapezoidal interval is accepted only when BOTH original rows are valid.
% Gaps due to excluded rows contribute zero, NOT an interpolated value.
    increments = zeros(numel(t)-1,1);
    dt = diff(t);
    idx = find(pairOK);
    increments(idx) = dt(idx) .* (p(idx)+p(idx+1))/2;
    E = [0;cumsum(increments)];
end
