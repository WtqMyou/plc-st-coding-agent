FUNCTION_BLOCK TemperatureControlFB

VAR_INPUT
    TemperatureSensorInput : REAL;   // Actual temperature from sensor
    SetTemperature         : REAL;   // Desired temperature setpoint
END_VAR

VAR_OUTPUT
    CurrentTemperature     : REAL;   // Display of current temperature
    SetTempDisplay         : REAL;   // Display of set temperature
    HeaterStatus           : BOOL;   // Display of heater on/off status
    OverheatProtection     : BOOL;   // Display of overheat protection active
    HeaterOutput           : BOOL;   // Physical heater control output
END_VAR

VAR
    HeaterOnTimer  : TON;            // Timer for continuous heater on duration
    CoolingTimer   : TON;            // Timer for cooling wait after overheat trip
    rTrigHeaterOnQ : R_TRIG;         // Rising edge detector for heater timer Q
    rTrigCoolingQ  : R_TRIG;         // Rising edge detector for cooling timer Q
    bOverheatProtection : BOOL := FALSE;  // Internal overheat protection state
    bSensorFault    : BOOL;               // Internal sensor fault flag
END_VAR

BEGIN
    // --- Sensor fault detection ---
    bSensorFault := (TemperatureSensorInput < 0.0) OR (TemperatureSensorInput > 100.0);

    // --- Output display values ---
    CurrentTemperature := TemperatureSensorInput;
    SetTempDisplay     := SetTemperature;

    // --- Heater control (initial, before protection update) ---
    IF bSensorFault THEN
        // Sensor fault: turn off heater for safety
        HeaterOutput := FALSE;
    ELSIF bOverheatProtection THEN
        // Overheat protection active: keep heater off
        HeaterOutput := FALSE;
    ELSE
        // Normal temperature comparison
        IF TemperatureSensorInput < SetTemperature THEN
            HeaterOutput := TRUE;   // Heat if actual below setpoint
        ELSE
            HeaterOutput := FALSE;  // Stop heating if actual >= setpoint
        END_IF;
    END_IF;

    // --- Overheat protection trigger logic ---
    HeaterOnTimer(IN := HeaterOutput, PT := T#5s);
    rTrigHeaterOnQ(CLK := HeaterOnTimer.Q);
    IF rTrigHeaterOnQ.Q THEN
        // Heater has been on continuously for 5 seconds -> overheat trip
        bOverheatProtection := TRUE;
        HeaterOutput := FALSE;      // Force heater off immediately
    END_IF;

    // --- Cooling wait timer and protection lift ---
    CoolingTimer(IN := bOverheatProtection, PT := T#3s);
    rTrigCoolingQ(CLK := CoolingTimer.Q);
    IF rTrigCoolingQ.Q THEN
        // Cooling period (3s) elapsed -> lift overheat protection
        bOverheatProtection := FALSE;
    END_IF;

    // --- Output statuses ---
    OverheatProtection := bOverheatProtection;
    HeaterStatus       := HeaterOutput;
END_FUNCTION_BLOCK