(* CONTRACT_RULES [] *)
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
    HeaterRuntimeTimer : TON;
    OverheatCooldownTimer : TON;
    OverheatActive : BOOL := FALSE;
    SensorFault : BOOL := FALSE;
END_VAR

CurrentTemperature := TemperatureSensorInput;
SetTempDisplay := SetTemperature;
SensorFault := (TemperatureSensorInput < 0.0) OR (TemperatureSensorInput > 100.0);

HeaterRuntimeTimer(IN := (TemperatureSensorInput < SetTemperature) AND NOT SensorFault AND NOT OverheatActive, PT := T#5s);

IF HeaterRuntimeTimer.Q AND NOT OverheatActive THEN
    OverheatActive := TRUE;
    OverheatCooldownTimer(IN := TRUE, PT := T#3s);
END_IF;

IF OverheatActive THEN
    OverheatCooldownTimer(IN := TRUE, PT := T#3s);
    IF OverheatCooldownTimer.Q THEN
        OverheatActive := FALSE;
    END_IF;
END_IF;

IF NOT SensorFault AND NOT OverheatActive THEN
    IF TemperatureSensorInput < SetTemperature THEN
        HeaterOutput := TRUE;
    ELSE
        HeaterOutput := FALSE;
    END_IF;
ELSE
    HeaterOutput := FALSE;
END_IF;

HeaterStatus := HeaterOutput;
OverheatProtection := OverheatActive;
END_FUNCTION_BLOCK