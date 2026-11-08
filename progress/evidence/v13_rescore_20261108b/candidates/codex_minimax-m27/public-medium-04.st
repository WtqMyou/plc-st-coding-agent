FUNCTION_BLOCK FB
VAR_INPUT
    TemperatureSensorInput : REAL;
    SetTemperature : REAL;
END_VAR
VAR_OUTPUT
    CurrentTemperature : REAL;
    SetTempDisplay : REAL;
    HeaterStatus : BOOL;
    OverheatProtection : BOOL;
    HeaterOutput : BOOL;
END_VAR
VAR
    ContinuousHeatingCount : INT := 0;
    OverheatProtectionCount : INT := 0;
    PrevHeaterOutput : BOOL := FALSE;
END_VAR

// Determine if sensor has a fault
IF TemperatureSensorInput < 0.0 OR TemperatureSensorInput > 100.0 THEN
    // Sensor fault - turn off heater
    HeaterOutput := FALSE;
    ContinuousHeatingCount := 0;
ELSE
    // No sensor fault - check overheat protection status
    IF OverheatProtection THEN
        // Overheat protection is active
        HeaterOutput := FALSE;
        ContinuousHeatingCount := 0;
        
        // Overheat protection can only be cleared after 3 cycles
        IF PrevHeaterOutput = FALSE THEN
            OverheatProtectionCount := OverheatProtectionCount + 1;
            IF OverheatProtectionCount >= 3 THEN
                OverheatProtection := FALSE;
                OverheatProtectionCount := 0;
            END_IF
        END_IF
    ELSE
        // No overheat protection - normal temperature control
        IF TemperatureSensorInput < SetTemperature THEN
            // Temperature below set value - start heater
            HeaterOutput := TRUE;
        ELSE
            // Temperature at or above set value - stop heater
            HeaterOutput := FALSE;
        END_IF
        
        OverheatProtectionCount := 0;
        
        // Track continuous heating time (1 cycle = 1 second)
        IF HeaterOutput THEN
            ContinuousHeatingCount := ContinuousHeatingCount + 1;
            // Trigger overheat protection after 5 seconds continuous heating
            IF ContinuousHeatingCount >= 5 THEN
                OverheatProtection := TRUE;
                HeaterOutput := FALSE;
                ContinuousHeatingCount := 0;
            END_IF
        ELSE
            ContinuousHeatingCount := 0;
        END_IF
    END_IF
END_IF

// Update status outputs
CurrentTemperature := TemperatureSensorInput;
SetTempDisplay := SetTemperature;
HeaterStatus := HeaterOutput;

// Update previous heater output for edge detection
PrevHeaterOutput := HeaterOutput;
END_FUNCTION_BLOCK