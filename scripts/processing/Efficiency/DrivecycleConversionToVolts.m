% Import the drive cycle here
rpm = [500 1000 1500 2000 2500 3000 3500 4000 4500 5000 5500];

voltage = [0.5 1 1.5 2 2.5 3 3.5 4 4.5 4.94];

torque = [
    14    30    46    61    76    89    101    112    121    130;
    14    30    46    61    76    89    101    112    121    129;
    13    28    45    61    76    89.75 101    111.5  120.8  128.5;
    12.5  28    44.5  60.5  75    88.5  100    111    119    128;
    11.5  26    42.5  57    71    84    95     106    115    121;
    9.3   23.75 38.7  52    63    75    85.35  95     104.5  111;
    8.5   21    33    46    57.74 68.5  78.75  88.5   97     104;
    8     19.5  31.5  42    54    63.5  73     82.5   92      97;
    0.5   18.5  30.5  41    51.5  60    68.75  77     81      85;
    6.5   18    27.5  38    47.5  55    63     68.5   71      73;
    5     16.5  26    36    45    52    56     60     62      63.5
];

driveRPM = drivecycle.RPM; % change the name 'drivecycle' to whatever your imported csv is called
driveTorque = drivecycle.Torque;
driveTime = drivecycle.Time;

requiredVoltage = zeros(size(driveRPM));

for i = 1:length(driveRPM)

    % Torque available at this RPM for each throttle voltage
    torqueCurve = zeros(size(voltage));

    for j = 1:length(voltage)

        torqueCurve(j) = interp1(...
            rpm,...
            torque(:,j),...
            driveRPM(i),...
            'linear',...
            'extrap');

    end

    % Clamp torque so it stays within the achievable range
    reqTorque = min(max(driveTorque(i), min(torqueCurve)), max(torqueCurve));

    % Find the voltage corresponding to the required torque
    requiredVoltage(i) = interp1(...
        torqueCurve,...
        voltage,...
        reqTorque,...
        'linear');

end
figure;
plot(driveTime, driveRPM);
title("RPM");

figure;
plot(driveTime, driveTorque);
title("Torque");

figure;
plot(driveTime, requiredVoltage);
title("Voltage")

figure;
plot(driveTime, driveRPM)
title("RPM")


figure;
dvdx = gradient(driveRPM) ./ gradient(driveTime);
plot(dvdx);


T = table(driveTime, driveRPM, driveTorque, requiredVoltage);
writetable(T, "name.csv")