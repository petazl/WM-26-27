% D-axis inductance parameter characterisation 

clear;
clc;
close all;

% Declare motor parameters

I_SC = 353.8748;
V_OC = 50; % placeholder

statorPhaseResistance = 0.0027;
poles = 5;
RPM_EF = 2000;

% Electrical frequency calculation

elecFreq = (poles*RPM_EF)/60;

% D-axis inductance calculation

%{
    Equation:
    
    Ld = (1/2pi * elecFreq) * sqrt{((V_OC/I_SC)^2) - statorPhaseResistance^2)
%}

Ld = (1/(2*pi*elecFreq))*sqrt((V_OC/I_SC).^2 - statorPhaseResistance.^2);

disp(Ld)

%{
    Just as a note, there are several other ways to calculate the
    d-axis inductance including using flux linkage and the d-axis current
    too.
%}



