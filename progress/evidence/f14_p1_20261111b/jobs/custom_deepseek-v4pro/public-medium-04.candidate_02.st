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
    bOverheatProtection : BOOL := FALSE;  // Internal overheat protection state
    bSensorFault    : BOOL;               // Internal sensor fault flag
END_VAR

BEGIN
    // --- Sensor fault detection ---
    bSensorFault := (TemperatureSensorInput < 0.0) OR (TemperatureSensorInput > 100.0);

    // --- Output display values ---
    CurrentTemperature := TemperatureSensorInput;
    SetTempDisplay     := SetTemperature;

    // --- Heater control logic ---
    IF bSensorFault THEN
        HeaterOutput := FALSE;                // Sensor fault: turn off heater
    ELSIF bOverheatProtection THEN
        HeaterOutput := FALSE;                // Overheat protection active: keep heater off
    ELSE
        IF TemperatureSensorInput < SetTemperature THEN
            HeaterOutput := TRUE;             // Actual below setpoint: start heating
        ELSE
            HeaterOutput := FALSE;            // Actual >= setpoint: stop heating
        END_IF;
    END_IF;

    // --- Overheat protection trigger ---
    HeaterOnTimer(IN := HeaterOutput, PT := T#5s);
    IF HeaterOnTimer.Q THEN
        bOverheatProtection := TRUE;          // Heater on for 5s continuously -> overheat trip
        HeaterOutput := FALSE;                // Force heater off immediately
    END_IF;

    // --- Cooling wait and protection release ---
    CoolingTimer(IN := bOverheatProtection, PT := T#3s);
    IF CoolingTimer.Q THEN
        bOverheatProtection := FALSE;         // Cooling period (3s) elapsed -> release protection
    END_IF;

    // --- Output status assignments ---
    OverheatProtection := bOverheatProtection;
    HeaterStatus       := HeaterOutput;
END_FUNCTION_BLOCK