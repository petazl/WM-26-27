% Short circuit current parameter data acquisition     

clear;
clc;
close all;

% Load TDMS data

filename = "short-circuit-test-1500-RPM.tdms";

data = tdmsread(filename);

%% RPM threshold

lowerBound = 500;

%% Read data

tbl = data{1};

current = tbl.EV_Phase2_RMS_Current;
rpm = tbl.EV_Measured_Speed;

%% Find samples within RPM threshold

indices = find(rpm >= lowerBound);

%% Calculate mean RMS current

mean_RMS_current = mean(current(indices));

disp(mean_RMS_current);

% Moving average

movingavg = [];

filtlen = 25;
for q = 1:(10437-filtlen)
    movingavg(q) = sum( current(q:q+filtlen)) / (filtlen+1);
end

% plots 

figure;

plot(current);
hold on;
plot(movingavg, 'r');

xlabel("Index");
ylabel("RMS Current (A)");
title("Short Circuit Test - Phase 2 RMS Current");
legend("Raw current", "Moving average", "Location", "best");
grid on;









