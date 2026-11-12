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
    LockoutActive : BOOL := FALSE;
END_VAR

(* Constants *)
OverheatTimer.PT := T#5S;
LockoutTimer.PT := T#3S;

(* Sensor fault check: temperature out of valid range *)
IF TemperatureSensorInput < 0.0 OR TemperatureSensorInput > 100.0 THEN
    HeaterOutput := FALSE;
    OverheatTimer(IN := FALSE);
    LockoutTimer(IN := FALSE);
    LockoutActive := FALSE;
    OverheatTriggered := FALSE;
ELSE
    (* Normal temperature control *)

    (* Start overheat timer when heater is commanded ON *)
    OverheatTimer(IN := TRUE);

    (* Check if overheat timer exceeded 5s → trigger protection *)
    IF OverheatTimer.Q AND NOT OverheatTriggered THEN
        OverheatTriggered := TRUE;
        LockoutActive := TRUE;
        LockoutTimer(IN := TRUE);
    END_IF

    (* If protection triggered, force heater OFF and wait lockout *)
    IF OverheatTriggered THEN
        HeaterOutput := FALSE;

        (* After lockout expires, clear protection *)
        IF LockoutTimer.Q THEN
            LockoutActive := FALSE;
            OverheatTriggered := FALSE;
            LockoutTimer(IN := FALSE);
            OverheatTimer(IN := FALSE);
        END_IF
    ELSE
        (* Normal operation: compare temperature vs setpoint *)
        IF TemperatureSensorInput < SetTemperature THEN
            HeaterOutput := TRUE;
        ELSE
            HeaterOutput := FALSE;
        END_IF
    END_IF

    (* Reset overheat timer when heater is OFF (but not in protection) *)
    IF NOT HeaterOutput AND NOT OverheatTriggered THEN
        OverheatTimer(IN := FALSE);
    END_IF
END_IF

(* Update display outputs *)
CurrentTemperature := TemperatureSensorInput;
SetTempDisplay := SetTemperature;
HeaterStatus := HeaterOutput;
OverheatProtection := OverheatTriggered;

END_FUNCTION_BLOCK