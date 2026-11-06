# WM-26-27

Repository for 2026–2027 electric-vehicle powertrain development and motor characterization. It currently contains development placeholders for the BMS, VCU, and Motor-CAD work, dyno test data, and scripts for organizing and processing motor-test measurements.

> **Status:** Work in progress. Some directories are placeholders, and the scripts may need project-specific configuration before use.

## Repository layout

| Path | Contents |
| --- | --- |
| `bms_dev/` | BMS development areas: GUI, firmware, and hardware information. |
| `vcu_dev/` | VCU development files. |
| `motorcad_dev/` | Motor-CAD development files. |
| `data/can_id_matrix/` | Location for CAN ID matrix data. |
| `data/dyno_data/` | Dyno data, including archived raw drive-cycle, efficiency, open-circuit, short-circuit, and torque-speed-envelope test files. |
| `MDD/` | Master data sheet workbook and a MATLAB script for organizing TDMS measurements. |
| `scripts/automation/` | Python dyno efficiency-map sweep script. |
| `scripts/processing/` | MATLAB scripts for back-EMF, d-axis inductance, flux linkage, and short-circuit-current analysis. |

## Requirements

Requirements depend on which files you use:

- **MATLAB:** The processing scripts use MATLAB. TDMS workflows require MATLAB's `tdmsread` support; some analysis scripts may also use functions from MATLAB toolboxes.
- **Python:** `scripts/automation/EfficiencyMap.py` uses Python and the project-specific `ev_support` module. This module and its hardware interfaces are not included in this repository; use the team's configured test environment.
- **Data:** Place the required TDMS test files in the working directory expected by the script, or update the script's file paths. The raw dyno archives are `.7z` files and need to be extracted with a compatible archive utility before their contents can be analyzed.

No dependency lockfile or automated setup procedure is currently provided.

## Working with the scripts

1. Review the script and confirm its input filenames, channel names, units, and output paths match the measurement setup.
2. Run offline analysis only with the appropriate data and MATLAB/Python environment.
3. Keep generated or proprietary measurement data in the appropriate project data location and follow team data-handling practices.

The efficiency-map script interfaces with dyno and motor-control equipment and can issue operating commands. **Do not run it on connected hardware without qualified supervision, a verified test setup, and an independent review of the configured limits and emergency procedures.** Software checks are not a substitute for the equipment's safeguards or the team's approved test protocol.

## Contributing

Keep work in the appropriate development directory, use descriptive filenames, and document required input data and environment-specific configuration when adding scripts. Avoid committing credentials, machine-specific secrets, or data that should not be shared.
