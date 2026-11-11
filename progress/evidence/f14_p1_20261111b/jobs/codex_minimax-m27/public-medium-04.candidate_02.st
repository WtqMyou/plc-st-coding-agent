FUNCTION_BLOCK FB_TemperatureControl
VAR_INPUT
    TemperatureSensorInput : REAL;
    SetTemperature         : REAL;
END_VAR

VAR_OUTPUT
    CurrentTemperature : REAL;
    SetTempDisplay     : REAL;
    HeaterStatus       : BOOL;
    OverheatProtection : BOOL;
    HeaterOutput       : BOOL;
END_VAR

VAR
    bHeaterOn            : BOOL := FALSE;
    bOverheatProtection  : BOOL := FALSE;
    
    HeaterOnTimer        : TON;
    OverheatCooldownTimer: TON;
    
    MAX_HEATER_ON_TIME   : TIME := T#5S;
    OVERHEAT_COOLDOWN    : TIME := T#3S;
END_VAR

//============================================================================
// Main Control Logic
//============================================================================

// Sensor Fault Detection (0-100 valid range)
IF (TemperatureSensorInput < 0.0) OR (TemperatureSensorInput > 100.0) THEN
    // Sensor fault: disable heater and activate protection
    bHeaterOn := FALSE;
    bOverheatProtection := TRUE;
    HeaterOnTimer(IN := FALSE);
END_IF

// Overheat Protection Logic
IF bOverheatProtection THEN
    OverheatCooldownTimer(IN := TRUE, PT := OVERHEAT_COOLDOWN);
    
    IF OverheatCooldownTimer.Q THEN
        bOverheatProtection := FALSE;
        OverheatCooldownTimer(IN := FALSE);
    END_IF;
    
    bHeaterOn := FALSE;
ELSE
    OverheatCooldownTimer(IN := FALSE);
    
    // Temperature Control (only when no protection active)
    IF TemperatureSensorInput < SetTemperature THEN
        bHeaterOn := TRUE;
    ELSE
        bHeaterOn := FALSE;
    END_IF;
END_IF;

// Heater On-Time Monitoring
IF bHeaterOn THEN
    HeaterOnTimer(IN := TRUE, PT := MAX_HEATER_ON_TIME);
    
    IF HeaterOnTimer.Q THEN
        bHeaterOn := FALSE;
        bOverheatProtection := TRUE;
        HeaterOnTimer(IN := FALSE);
    END_IF;
ELSE
    HeaterOnTimer(IN := FALSE);
END_IF;

//============================================================================
// Update All Outputs (at the end, after all logic)
//============================================================================
CurrentTemperature := TemperatureSensorInput;
SetTempDisplay     := SetTemperature;
HeaterStatus       := bHeaterOn;
OverheatProtection := bOverheatProtection;
HeaterOutput       := bHeaterOn;

END_FUNCTION_BLOCK