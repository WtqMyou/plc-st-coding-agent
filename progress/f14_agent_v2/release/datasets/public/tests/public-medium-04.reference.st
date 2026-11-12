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
    continuousHeat : TON;
    cooling : TON;
    demand : BOOL;
END_VAR

CurrentTemperature := TemperatureSensorInput;
SetTempDisplay := SetTemperature;
demand := (TemperatureSensorInput >= 0.0) AND (TemperatureSensorInput <= 100.0)
          AND (TemperatureSensorInput < SetTemperature);

cooling(IN := OverheatProtection, PT := T#3s);
IF cooling.Q THEN
    OverheatProtection := FALSE;
    cooling(IN := FALSE, PT := T#3s);
END_IF;

(* Millisecond task clock: the first representable duration over five seconds is 5001 ms. *)
continuousHeat(IN := demand AND NOT OverheatProtection, PT := T#5001ms);
IF continuousHeat.Q THEN
    OverheatProtection := TRUE;
    continuousHeat(IN := FALSE, PT := T#5001ms);
    cooling(IN := TRUE, PT := T#3s);
END_IF;
HeaterOutput := demand AND NOT OverheatProtection;
HeaterStatus := HeaterOutput;
END_FUNCTION_BLOCK
