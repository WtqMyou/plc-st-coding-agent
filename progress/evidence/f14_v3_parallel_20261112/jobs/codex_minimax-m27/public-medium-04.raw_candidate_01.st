FUNCTION_BLOCK FB_TemperatureControl
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
    OverheatTimer : TON;
    CooldownTimer : TON;
    CooldownDone : BOOL;
    HeaterOn : BOOL;
END_VAR

// Update displays
CurrentTemperature := TemperatureSensorInput;
SetTempDisplay := SetTemperature;

// Sensor fault check
IF TemperatureSensorInput < 0.0 OR TemperatureSensorInput > 100.0 THEN
    OverheatProtection := TRUE;
    HeaterOutput := FALSE;
    CooldownTimer(IN := FALSE);
    OverheatTimer(IN := FALSE);
    HeaterStatus := FALSE;
    RETURN;
END_IF;

// Overheat protection cooldown
IF OverheatProtection THEN
    CooldownTimer(IN := TRUE, PT := T#3S);
    CooldownDone := CooldownTimer.Q;
    IF CooldownDone THEN
        OverheatProtection := FALSE;
        CooldownTimer(IN := FALSE);
        HeaterOn := FALSE;
    END_IF;
    HeaterOutput := FALSE;
    HeaterStatus := FALSE;
    RETURN;
END_IF;

// Temperature comparison and heater control
IF TemperatureSensorInput < SetTemperature THEN
    HeaterOn := TRUE;
    OverheatTimer(IN := TRUE, PT := T#5S);
    IF OverheatTimer.Q THEN
        OverheatProtection := TRUE;
        HeaterOn := FALSE;
        HeaterOutput := FALSE;
        OverheatTimer(IN := FALSE);
        RETURN;
    END_IF;
    HeaterOutput := TRUE;
ELSE
    HeaterOn := FALSE;
    HeaterOutput := FALSE;
    OverheatTimer(IN := FALSE);
END_IF;

HeaterStatus := HeaterOutput;

END_FUNCTION_BLOCK