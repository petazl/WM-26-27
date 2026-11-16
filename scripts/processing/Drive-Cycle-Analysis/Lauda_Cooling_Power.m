fileName = "Drive-Cycle-Unscaled.tdms";

% Check if the file exists before reading to avoid crashing the loop
if isfile(fileName)
    tdmsData = tdmsread(fileName); % Stores data as cell array
else
    warning('File %s not found. Skipping.', fileName);
end

dataTable = tdmsData{1, 1};

inletTemp = dataTable.("CH 1");
outletTemp = dataTable.("CH 0");
p_mech = dataTable.("Mechanical Power");
p_el = dataTable.("Sigma_A_P");

p_losses = p_el - p_mech;

n = length(outletTemp);
time = 0:n-1;
time = 0.001*time';

figure;
plot(time, p_losses);
hold on;
plot(time, power);
ylabel("Power (W)");
xlabel("time (s)")
hold off;
legend('losses','cooling');




% figure;
% plot(inletTemp);
%
% figure;
% plot(outletTemp);

flowRate = 5;
rho = 1000;
cp = 4180;

power = rho * (flowRate/60000) * cp * (outletTemp-inletTemp);


% Time step
dt = 0.001; % in seconds

% Total energy
energy_J = trapz(power) * dt;
energy_kWh = energy_J / 3.6e6;
avg_power = energy_J/((n-1))

fprintf('Total energy = %.2f J\n', energy_J);
fprintf('Total energy = %.6f kWh\n', energy_kWh);
fprintf('Average power = %.6f W', avg_power);



