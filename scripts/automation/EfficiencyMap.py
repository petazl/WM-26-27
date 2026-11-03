import time
import os
import math
import ev_support as ev


# ============================================================
# Torque-voltage sweep test for efficiency mapping
#
# Tests:
#   RPM:         500 to 5500 RPM in 500 RPM steps
#   Temperature: 25 to 65 degC in 10 degC steps
#   Voltage:     0 to 4.94 V
#
# Output:
#   500RPM_20degC.csv
#   1000RPM_20degC.csv
#   ...
#   5500RPM_60degC.csv
#
# Safety:
#   - Dyno dynamic speed limit: 6000 RPM
#   - Dyno dynamic torque limit: +/-500 Nm
#   - Software overspeed trip: 5900 RPM
#   - Software over-temperature trip: 100 degC
#   - Software torque trip: +/-450 Nm
#   - Any invalid safety-critical measurement aborts the test
#   - Any failed command aborts the test
#   - Voltage and heating torque are zeroed on faults
#   - Dyno is commanded to 0 RPM and disabled during cleanup
# ============================================================


# -----------------------------
# Test settings
# -----------------------------

RPM_SETPOINTS = range(500, 5501, 500)
TEMP_SETPOINTS = range(25, 66, 10)

VOLTAGE_START = 0.00
VOLTAGE_END = 4.94
VOLTAGE_STEP = 0.10

TEMP_TOLERANCE = 1.0
SPEED_TOLERANCE = 100.0
SPEED_SETTLE_TIME = 5.0
SPEED_TIMEOUT = 120.0

VOLTAGE_SETTLE_TIME = 1.0
SAMPLES_PER_VOLTAGE = 5
SAMPLE_INTERVAL = 0.1

HEATING_TORQUE_REQUEST = 2.0
HEATING_CHECK_INTERVAL = 5.0
HEATING_TIMEOUT = 900.0

# -----------------------------
# Safety limits
# -----------------------------

# Nominal motor speed 6000RPM. We will operate in the 500-5500RPM range.
MAX_DYNO_SPEED = 6000.0
SOFTWARE_OVERSPEED_LIMIT = 5900.0

# Keep the software torque trip below the +/-500 Nm dyno limit.
MAX_DYNO_TORQUE = 500.0
SOFTWARE_TORQUE_LIMIT = 450.0

# Highest requested temperature is 65 degC. Nominal motor temperature is 130 degC.
# Trip at 100 degC to avoid any damage during testing.
MAX_MOTOR_TEMP = 100.0

# Minimum speed expected before applying a voltage request.
# This is deliberately separate from the +/-100 RPM operating tolerance.
MIN_TEST_SPEED = 400.0

# -----------------------------
# Channel names
# -----------------------------

MOTOR_TEMP_CHANNEL = "MotorTemp"

# Voltage command/request channel.
VOLTAGE_REQUEST_CHANNEL = "A_OUT_0A"

# Torque command channel used only for motor heating.
HEATING_TORQUE_CHANNEL = "TorqueRequest"

# These are retained for CSV/logging compatibility where useful.
# Safety-critical speed and torque checks use ev.dyno directly.
DYNO_SPEED_CHANNEL = "Controller/Fixed/Dyno/Outputs/Dyno_Measured_Speed"
MEASURED_TORQUE_CHANNEL = "FMI 1"


# ============================================================
# Safety helpers
# ============================================================

def checked_command(name, function, *args):
    """Run an ev_support command and abort if it reports an error."""
    try:
        error = function(*args)
    except Exception as exc:
        raise RuntimeError(
            "{} failed with exception: {}".format(name, exc)
        ) from exc

    if error not in (None, 0):
        raise RuntimeError(
            "{} returned error code {}".format(name, error)
        )

    return error


def read_required_channel(channel, description=None):
    """Read a channel; never silently convert a failed safety read to None."""
    label = description or channel

    try:
        value = ev.get_channel(channel)
    except Exception as exc:
        raise RuntimeError(
            "Failed to read {}: {}".format(label, exc)
        ) from exc

    if value is None:
        raise RuntimeError("Invalid None reading from {}".format(label))

    try:
        value = float(value)
    except (TypeError, ValueError) as exc:
        raise RuntimeError(
            "Invalid non-numeric reading from {}: {!r}".format(label, value)
        ) from exc

    if not math.isfinite(value):
        raise RuntimeError(
            "Invalid non-finite reading from {}: {!r}".format(label, value)
        )

    return value


def get_dyno_speed():
    """Use the documented dyno API for the safety-critical speed reading."""
    try:
        value = float(ev.dyno.get_measured_speed())
    except Exception as exc:
        raise RuntimeError(
            "Failed to read dyno measured speed: {}".format(exc)
        ) from exc

    if not math.isfinite(value):
        raise RuntimeError(
            "Invalid dyno measured speed: {!r}".format(value)
        )

    return value


def get_dyno_torque():
    """Read measured torque from the configured dyno torque channel."""
    try:
        value = ev.get_channel(MEASURED_TORQUE_CHANNEL)
    except Exception as exc:
        raise RuntimeError(
            "Failed to read measured torque: {}".format(exc)
        ) from exc

    if value is None:
        raise RuntimeError(
            "Measured torque channel returned None"
        )

    try:
        value = float(value)
    except (TypeError, ValueError) as exc:
        raise RuntimeError(
            "Invalid measured torque value: {!r}".format(value)
        ) from exc

    if not math.isfinite(value):
        raise RuntimeError(
            "Invalid measured torque: {!r}".format(value)
        )

    return value


def check_safety_limits(rpm_target=None, require_test_speed=False):
    """
    Check all safety-critical measurements.

    Returns:
        (measured_rpm, motor_temp, measured_torque)
    """
    measured_rpm = get_dyno_speed()
    motor_temp = read_required_channel(
        MOTOR_TEMP_CHANNEL, "MotorTemp"
    )
    measured_torque = get_dyno_torque()

    if abs(measured_rpm) > SOFTWARE_OVERSPEED_LIMIT:
        raise RuntimeError(
            "OVERSPEED: measured {} RPM exceeds software limit of {} RPM".format(
                measured_rpm, SOFTWARE_OVERSPEED_LIMIT
            )
        )

    if motor_temp > MAX_MOTOR_TEMP:
        raise RuntimeError(
            "OVER-TEMPERATURE: MotorTemp = {:.2f} degC exceeds "
            "software limit of {:.2f} degC".format(
                motor_temp, MAX_MOTOR_TEMP
            )
        )

    if abs(measured_torque) > SOFTWARE_TORQUE_LIMIT:
        raise RuntimeError(
            "OVER-TORQUE: measured dyno torque = {:.2f} Nm exceeds "
            "software limit of +/-{:.2f} Nm".format(
                measured_torque, SOFTWARE_TORQUE_LIMIT
            )
        )

    if rpm_target is not None:
        if abs(measured_rpm - rpm_target) > SPEED_TOLERANCE:
            raise RuntimeError(
                "SPEED OUT OF TOLERANCE: measured {:.1f} RPM, "
                "target {:.1f} RPM, tolerance +/-{:.1f} RPM".format(
                    measured_rpm,
                    rpm_target,
                    SPEED_TOLERANCE
                )
            )

    if require_test_speed and abs(measured_rpm) < MIN_TEST_SPEED:
        raise RuntimeError(
            "TEST SPEED TOO LOW: measured {:.1f} RPM".format(measured_rpm)
        )

    return measured_rpm, motor_temp, measured_torque


def zero_test_commands():
    """Immediately remove the inverter-side commands used by this script."""
    errors = []

    try:
        error = ev.set_channel(VOLTAGE_REQUEST_CHANNEL, 0.0)
        if error not in (None, 0):
            errors.append(
                "Voltage zero returned error code {}".format(error)
            )
    except Exception as exc:
        errors.append("Voltage zero failed: {}".format(exc))

    try:
        error = ev.set_channel(HEATING_TORQUE_CHANNEL, 0.0)
        if error not in (None, 0):
            errors.append(
                "Heating torque zero returned error code {}".format(error)
            )
    except Exception as exc:
        errors.append("Heating torque zero failed: {}".format(exc))

    if errors:
        print("WARNING: command zeroing encountered problems:")
        for error in errors:
            print("  - {}".format(error))

    return errors


# ============================================================
# Main function
# ============================================================

def run_test():
    print("Starting dyno voltage sweep test...")

    try:
        setup_dyno()

        for temp_target in TEMP_SETPOINTS:

            print("\n====================================")
            print("Temperature target: {} degC".format(temp_target))
            print("====================================")

            for rpm_target in RPM_SETPOINTS:

                print("\n------------------------------------")
                print(
                    "Testing {} RPM at {} degC".format(
                        rpm_target, temp_target
                    )
                )
                print("------------------------------------")

                # Heat/cool motor until correct temperature.
                wait_for_temperature_at_rpm(
                    temp_target, rpm_target
                )

                # Make sure speed is settled before test.
                set_speed_and_wait(rpm_target)

                # Final safety check immediately before applying voltage.
                check_safety_limits(
                    rpm_target=rpm_target,
                    require_test_speed=True
                )

                filename = "{}RPM_{}degC.csv".format(
                    rpm_target, temp_target
                )

                run_voltage_sweep(
                    rpm_target=rpm_target,
                    temp_target=temp_target,
                    filename=filename
                )

                # Reset commands after each run.
                zero_test_commands()

        print("\nAll tests complete.")

    except Exception as exc:
        print("\n*** TEST ABORTED ***")
        print("Reason: {}".format(exc))
        raise

    finally:
        cleanup()


# ============================================================
# Dyno setup
# ============================================================

def setup_dyno():
    print("Setting up dyno...")

    # Ensure the script controls the manual/script setpoints.
    checked_command(
        "Dyno setpoint source",
        
    )

    checked_command(
        "Dyno speed mode",
        ev.dyno.set_speed_mode
    )

    # Establish the dyno's dynamic safety envelope.
    # The script test itself only reaches 5500 RPM.
    checked_command(
        "Dyno limits",
        ev.dyno.set_limits,
        MAX_DYNO_SPEED,
        -MAX_DYNO_SPEED,
        MAX_DYNO_TORQUE,
        -MAX_DYNO_TORQUE,
        1000.0,
        10.0
    )

    checked_command(
        "Dyno speed ramp rate",
        ev.dyno.set_speed_ramp_rate,
        1000.0
    )

    # Start with the dyno disabled while commands are zeroed.
    checked_command(
        "Dyno disable",
        ev.dyno.set_enable,
        False
    )

    zero_test_commands()

    # Enable only after the command channels are known to be zero.
    checked_command(
        "Dyno enable",
        ev.dyno.set_enable,
        True
    )

    print("Dyno ready.")


# ============================================================
# Temperature control with heating/cooling
# ============================================================

def wait_for_temperature_at_rpm(temp_target, rpm_target):
    print(
        "Waiting for MotorTemp = {} degC +/- {} degC".format(
            temp_target,
            TEMP_TOLERANCE
        )
    )

    start_time = time.time()

    while True:

        # Safety-critical temperature read.
        motor_temp = read_required_channel(
            MOTOR_TEMP_CHANNEL, "MotorTemp"
        )

        # Always check speed and torque before doing anything active.
        measured_rpm, _, measured_torque = check_safety_limits()

        print(
            "MotorTemp = {:.2f} degC, target = {} degC, "
            "DynoRPM = {:.1f}, DynoTorque = {:.2f} Nm".format(
                motor_temp,
                temp_target,
                measured_rpm,
                measured_torque
            )
        )

        # Temperature is close enough.
        if abs(motor_temp - temp_target) <= TEMP_TOLERANCE:
            print("Temperature reached.")
            zero_test_commands()
            return

        # Motor is too cold: heat it at the test RPM with small torque.
        if motor_temp < temp_target - TEMP_TOLERANCE:

            print(
                "Motor too cold. Heating at {} RPM with {} Nm torque request.".format(
                    rpm_target,
                    HEATING_TORQUE_REQUEST
                )
            )

            checked_command(
                "Heating speed setpoint",
                ev.dyno.set_speed_setpoint,
                rpm_target
            )

            timed_out = ev.wait_until_settled(
                DYNO_SPEED_CHANNEL,
                rpm_target + SPEED_TOLERANCE,
                rpm_target - SPEED_TOLERANCE,
                SPEED_SETTLE_TIME,
                timeout=SPEED_TIMEOUT
            )

            if timed_out:
                raise RuntimeError(
                    "Failed to settle at {} RPM during heating".format(
                        rpm_target
                    )
                )

            # Re-check everything immediately before applying heating torque.
            check_safety_limits(
                rpm_target=rpm_target,
                require_test_speed=True
            )

            checked_command(
                "Heating torque request",
                ev.set_channel,
                HEATING_TORQUE_CHANNEL,
                HEATING_TORQUE_REQUEST
            )

        # Motor is too hot: remove heating and return to zero speed.
        elif motor_temp > temp_target + TEMP_TOLERANCE:

            print("Motor too hot. Cooling at 0 RPM.")

            zero_test_commands()

            checked_command(
                "Cooling speed setpoint",
                ev.dyno.set_speed_setpoint,
                0.0
            )

        # Timeout protection.
        if time.time() - start_time > HEATING_TIMEOUT:
            zero_test_commands()
            raise RuntimeError(
                "MotorTemp failed to reach {} degC".format(temp_target)
            )

        time.sleep(HEATING_CHECK_INTERVAL)


# ============================================================
# Speed control
# ============================================================

def set_speed_and_wait(rpm_target):
    print("Setting speed to {} RPM".format(rpm_target))

    checked_command(
        "Speed setpoint",
        ev.dyno.set_speed_setpoint,
        rpm_target
    )

    timed_out = ev.wait_until_settled(
        DYNO_SPEED_CHANNEL,
        rpm_target + SPEED_TOLERANCE,
        rpm_target - SPEED_TOLERANCE,
        SPEED_SETTLE_TIME,
        timeout=SPEED_TIMEOUT
    )

    if timed_out:
        zero_test_commands()
        raise RuntimeError(
            "Failed to settle at {} RPM".format(rpm_target)
        )

    # Confirm using the documented dyno measurement.
    measured_rpm, motor_temp, measured_torque = check_safety_limits(
        rpm_target=rpm_target,
        require_test_speed=True
    )

    print(
        "Speed settled at {:.1f} RPM, MotorTemp = {:.2f} degC, "
        "DynoTorque = {:.2f} Nm".format(
            measured_rpm,
            motor_temp,
            measured_torque
        )
    )


# ============================================================
# Voltage sweep
# ============================================================

def run_voltage_sweep(rpm_target, temp_target, filename):
    print("Starting voltage sweep: {}".format(filename))

    # Delete old file so write_to_csv does not append to old data.
    if os.path.exists(filename):
        os.remove(filename)

    rows = []

    rows.append([
        "Time_s",
        "TargetRPM",
        "MeasuredRPM",
        "TargetTemp_degC",
        "MotorTemp_degC",
        "VoltageRequest_V",
        "MeasuredTorque_Nm"
    ])

    voltage_values = make_voltage_steps(
        VOLTAGE_START,
        VOLTAGE_END,
        VOLTAGE_STEP
    )

    start_time = time.time()

    try:
        # Explicitly start at zero before the sweep.
        checked_command(
            "Initial voltage zero",
            ev.set_channel,
            VOLTAGE_REQUEST_CHANNEL,
            0.0
        )

        # Confirm the operating point one final time.
        check_safety_limits(
            rpm_target=rpm_target,
            require_test_speed=True
        )

        for voltage_request in voltage_values:

            if voltage_request < VOLTAGE_START:
                raise RuntimeError(
                    "Voltage request below configured minimum"
                )

            if voltage_request > VOLTAGE_END:
                raise RuntimeError(
                    "Voltage request above configured maximum"
                )

            print(
                "Voltage request = {:.2f} V".format(
                    voltage_request
                )
            )

            checked_command(
                "Voltage request",
                ev.set_channel,
                VOLTAGE_REQUEST_CHANNEL,
                voltage_request
            )

            time.sleep(VOLTAGE_SETTLE_TIME)

            for _ in range(SAMPLES_PER_VOLTAGE):

                t = time.time() - start_time

                # Every sample is a safety check.
                measured_rpm, motor_temp, measured_torque = (
                    check_safety_limits(
                        rpm_target=rpm_target,
                        require_test_speed=True
                    )
                )

                rows.append([
                    t,
                    rpm_target,
                    measured_rpm,
                    temp_target,
                    motor_temp,
                    voltage_request,
                    measured_torque
                ])

                time.sleep(SAMPLE_INTERVAL)

        # Normal completion: zero the voltage before saving.
        checked_command(
            "Final voltage zero",
            ev.set_channel,
            VOLTAGE_REQUEST_CHANNEL,
            0.0
        )

        error = ev.write_to_csv(
            name=filename,
            data=rows
        )

        if error not in (None, 0):
            raise RuntimeError(
                "CSV write returned error code {}".format(error)
            )

        print("Saved {}".format(filename))

    except Exception:
        # Fail safe if anything goes wrong during the sweep.
        zero_test_commands()

        # Preserve whatever data was collected before the fault.
        try:
            ev.write_to_csv(
                name=filename,
                data=rows
            )
            print("Partial data saved to {}".format(filename))
        except Exception as csv_exc:
            print(
                "WARNING: failed to save partial CSV: {}".format(
                    csv_exc
                )
            )

        raise


# ============================================================
# Helper functions
# ============================================================

def make_voltage_steps(start, end, step):
    values = []
    value = start

    while value <= end:
        values.append(round(value, 3))
        value += step

    if values[-1] != round(end, 3):
        values.append(round(end, 3))

    return values


# ============================================================
# Cleanup
# ============================================================

def cleanup():
    print("Starting cleanup...")

    # First remove inverter-side commands.
    zero_test_commands()

    # Then request zero dyno speed.
    try:
        checked_command(
            "Cleanup speed setpoint",
            ev.dyno.set_speed_setpoint,
            0.0
        )
    except Exception as exc:
        print("WARNING: failed to command dyno to 0 RPM: {}".format(exc))

    # Wait for zero speed using the documented dyno measurement.
    try:
        start_time = time.time()

        while time.time() - start_time < 120.0:
            measured_rpm = get_dyno_speed()
            print(
                "Cleanup: dyno speed = {:.1f} RPM".format(
                    measured_rpm
                )
            )

            if abs(measured_rpm) <= 5.0:
                break

            time.sleep(0.5)
        else:
            print(
                "WARNING: dyno did not reach <=5 RPM within 120 s"
            )

    except Exception as exc:
        print(
            "WARNING: failed while checking dyno speed during cleanup: {}".format(
                exc
            )
        )

    # Disable dyno after the speed command has been brought to zero.
    try:
        checked_command(
            "Dyno disable",
            ev.dyno.set_enable,
            False
        )
    except Exception as exc:
        print(
            "WARNING: failed to disable dyno: {}".format(exc)
        )

    print("Cleanup done.")


# ============================================================
# Run
# ============================================================

if __name__ == "__main__":
    run_test()
