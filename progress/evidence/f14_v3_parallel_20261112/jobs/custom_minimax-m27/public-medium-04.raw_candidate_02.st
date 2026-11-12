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
    LockoutTimer : TON;
    OverheatTriggered : BOOL := FALSE;
END_VAR

OverheatTimer.PT := T#5S;
LockoutTimer.PT := T#3S;

(* Sensor fault check: temperature out of valid range *)
IF TemperatureSensorInput < 0.0 OR TemperatureSensorInput > 100.0 THEN
    HeaterOutput := FALSE;
    OverheatTimer(IN := FALSE);
    LockoutTimer(IN := FALSE);
    OverheatTimer(IN := FALSE, PT := T#5S);
    OverheatTriggered := FALSE;
ELSE
    (* Normal temperature control *)
    IF NOT OverheatTriggered THEN
        (* Normal heating decision *)
        IF TemperatureSensorInput < SetTemperature THEN
            HeaterOutput := TRUE;
        ELSE
            HeaterOutput := FALSE;
        END_IF;
    ELSE
        (* Overheat protection active - heater forced off *)
        HeaterOutput := FALSE;
    END_IF;

    (* Overheat timer: accumulate time only when heater is ON and not in protection *)
    IF NOT OverheatTriggered AND HeaterOutput THEN
        OverheatTimer(IN := TRUE);
    ELSE
        OverheatTimer(IN := FALSE);
    END_IF;

    (* Check overheat threshold *)
    IF OverheatTimer.Q AND NOT OverheatTriggered THEN
        OverheatTriggered := TRUE;
    END_IF;

    (* Lockout timer management *)
    IF OverheatTriggered THEN
        LockoutTimer(IN := TRUE);
        IF LockoutTimer.Q THEN
            OverheatTriggered := FALSE;
            LockoutTimer(IN := FALSE);
            OverheatTimer(IN := FALSE, PT := T#5S);
        END_IF;
    ELSE
        LockoutTimer(IN := FALSE);
    END_IF;
END_IF;

(* Update display outputs *)
CurrentTemperature := TemperatureSensorInput;
SetTempDisplay := SetTemperature;
HeaterStatus := HeaterOutput;
OverheatProtection := OverheatTriggered;

END_FUNCTION_BLOCK