WARWICK MOTO | CSV-BASED MOTOR COOLING ANALYSIS
==============================================

FILES
- analyse_motor_cooling_CSV.m      Main MATLAB processing and plotting script
- check_input_CSVs.m              Data-quality check and exclusion counts
- Input_CSVs/                     Three original user-supplied CSV files
- Results/                        Already computed results from your actual files
- Figures/                        Already generated PNG plots from your actual files
- Motor_Cooling_Short_Report.docx  Short report containing actual calculations

RUNNING MATLAB
1. Unzip the full package, leaving the Input_CSVs folder beside the scripts.
2. From MATLAB, open and Run analyse_motor_cooling_CSV.m.
3. The script creates a new Results_MATLAB folder next to the script.
4. Optionally run check_input_CSVs.m to inspect exclusions.
5. To add a fourth file, put it in Input_CSVs and append its name to csvFiles.

CSV FIELDS AND UNITS
Time seconds; Torque Nm; AC W; DC W; Mech W; Inlet degC;
Outlet degC; MotorTemp degC; RPM revolutions/minute.

EXCLUSION RULE
Remove a complete row if AC<0 OR DC<0 OR Mech<0.
Also remove non-finite required values. Zero powers are allowed.
Signed calculated losses (AC-Mech or DC-AC) are NOT an additional exclusion.

ENERGY AND AVERAGING METHOD
Trapezoidal integration ONLY over adjacent valid ORIGINAL rows.
Intervals touching excluded original rows are not integrated, and no gaps
are interpolated. Means are total valid-interval energy / valid-interval
elapsed time, not a simple average of discontinuous retained rows.

ASSUMPTIONS
- AC is motor electrical input, DC is inverter electrical input,
  Mech is shaft mechanical output.
- Coolant is WATER only, at constant 5 litres/min, rho=1 kg/L,
  cp=4180 J/(kg K), and inlet/outlet measurements bracket ONLY the motor.
- Heat taken up by coolant = (5/60 kg/s) * 4180 * (Tout-Tin).
- Motor losses = AC-Mech; inverter losses = DC-AC (both signed).
- Coolant uptake is not equal to instantaneous loss generation due to
  thermal storage and other heat paths; sensor response and offsets matter.

DATA CAUTION
13%-22% of retained rows give AC < Mech, hence negative derived motor
loss. Treat high-frequency loss traces and inferred thermal load as
provisional pending power-channel alignment/calibration checks.

OUTPUTS
- Results/<cycle>_processed.csv: filtered original rows + derived values
- Results/DriveCycle_Comparison.csv: one-row-per-cycle key metrics
- Figures/<cycle>_01 ... _05 .png and Figures/DriveCycle_Comparison.png
