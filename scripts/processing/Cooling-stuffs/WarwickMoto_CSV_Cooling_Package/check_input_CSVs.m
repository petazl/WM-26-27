%% Quick quality-control check for Warwick Moto supplied CSV files
% Prints row exclusions and negative derived loss counts BEFORE analysis.
clear; clc;
root = fileparts(mfilename('fullpath'));
files = {'MS2025-1.csv','MS2025-2.csv','Optimum-Lap-Single-Lap.csv'};
for i=1:numel(files)
  f = fullfile(root,'Input_CSVs',files{i});
  T = readtable(f,'VariableNamingRule','preserve');
  required = {'Time','Torque','AC','DC','Mech','Inlet','Outlet','MotorTemp','RPM'};
  assert(all(ismember(required,T.Properties.VariableNames)), 'Missing columns in %s',f);
  data = T{:,required};
  finiteRows = all(isfinite(data),2);
  negativeRawPower = T.AC < 0 | T.DC < 0 | T.Mech < 0;
  valid = finiteRows & ~negativeRawPower;
  fprintf('\n%s\n',files{i});
  fprintf('  Total rows: %d\n',height(T));
  fprintf('  Kept rows: %d | excluded: %d\n',sum(valid),sum(~valid));
  fprintf('  Negative AC: %d | negative DC: %d | negative Mech: %d\n', ...
    sum(T.AC<0),sum(T.DC<0),sum(T.Mech<0));
  fprintf('  Derived AC-Mech < 0 among kept rows: %d (%.1f%%)\n', ...
    sum(valid & (T.AC-T.Mech)<0),100*sum(valid & (T.AC-T.Mech)<0)/sum(valid));
  fprintf('  Derived DC-AC < 0 among kept rows: %d\n',sum(valid & (T.DC-T.AC)<0));
end
