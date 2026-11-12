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

CurrentTemperature := TemperatureSensorInput;
SetTempDisplay := SetTemperature;

IF TemperatureSensorInput < 0.0 OR TemperatureSensorInput > 100.0 THEN
    OverheatProtection := TRUE;
    HeaterOutput := FALSE;
    HeaterStatus := FALSE;
    CooldownTimer(IN := FALSE);
    OverheatTimer(IN := FALSE);
    CooldownDone := FALSE;
    HeaterOn := FALSE;
ELSIF OverheatProtection THEN
    CooldownTimer(IN := TRUE, PT := T#3S);
    CooldownDone := CooldownTimer.Q;
    IF CooldownTimer.Q THEN
        OverheatProtection := FALSE;
        CooldownTimer(IN := FALSE);
        CooldownDone := FALSE;
        HeaterOn := FALSE;
    END_IF;
    HeaterOutput := FALSE;
    HeaterStatus := FALSE;
ELSIF TemperatureSensorInput < SetTemperature THEN
    HeaterOn := TRUE;
    OverheatTimer(IN := TRUE, PT := T#5S);
    IF OverheatTimer.Q THEN
        OverheatProtection := TRUE;
        HeaterOutput := FALSE;
        HeaterStatus := FALSE;
        OverheatTimer(IN := FALSE);
    ELSE
        HeaterOutput := TRUE;
        HeaterStatus := TRUE;
    END_IF;
ELSE
    HeaterOn := FALSE;
    HeaterOutput := FALSE;
    OverheatTimer(IN := FALSE);
    HeaterStatus := FALSE;
END_IF;

END_FUNCTION_BLOCK