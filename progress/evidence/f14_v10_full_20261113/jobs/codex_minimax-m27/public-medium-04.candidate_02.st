(*
ENGINEERING_CONTRACT:
PUB001: TemperatureSensorInput (REAL) -> CurrentTemperature (REAL) every scan
PUB002: HeaterOutput := TRUE when TemperatureSensorInput < SetTemperature (no sensor fault)
PUB003: Overheat triggers when runtime > 5s (strict >), first satisfying tick = 5001ms
PUB004: Overheat sets HeaterOutput:=FALSE, 3s cooldown before OverheatProtection clears
PUB005: Sensor fault (<0 OR >100) sets HeaterOutput:=FALSE regardless of temperature
PUB006: All status outputs (CurrentTemperature, SetTempDisplay, HeaterStatus, OverheatProtection) update every scan
*)
FUNCTION_BLOCK FB_TemperatureControl
VAR_INPUT
    TemperatureSensorInput : REAL;
    SetTemperature         : REAL;
END_VAR

VAR_OUTPUT
    CurrentTemperature : REAL;
    SetTempDisplay      : REAL;
    HeaterStatus        : BOOL;
    OverheatProtection  : BOOL;
    HeaterOutput        : BOOL;
END_VAR

VAR
    HeaterRuntimeTimer   : TON;
    OverheatCooldownTimer: TON;
    OverheatActive       : BOOL := FALSE;
    SensorFault          : BOOL := FALSE;
    Runtimems            : LINT := 0;
END_VAR

SensorFault := (TemperatureSensorInput < 0.0) OR (TemperatureSensorInput > 100.0);

IF NOT SensorFault AND NOT OverheatActive THEN
    IF TemperatureSensorInput < SetTemperature THEN
        HeaterOutput := TRUE;
    ELSE
        HeaterOutput := FALSE;
    END_IF;
ELSE
    HeaterOutput := FALSE;
END_IF;

HeaterRuntimeTimer(IN := FALSE, PT := T#5s);

IF OverheatActive THEN
    IF Runtimems > 5000 THEN
        OverheatActive := TRUE;
    END_IF;
ELSIF HeaterOutput THEN
    Runtimems := Runtimems + TO_LINT(HeaterRuntimeTimer.ET) + 1;
    HeaterRuntimeTimer(IN := TRUE, PT := T#5s);
    IF Runtimems > 5000 THEN
        OverheatActive := TRUE;
        HeaterOutput := FALSE;
    END_IF;
ELSE
    Runtimems := 0;
END_IF;

IF OverheatActive THEN
    OverheatCooldownTimer(IN := TRUE, PT := T#3s);
    IF OverheatCooldownTimer.Q THEN
        OverheatActive := FALSE;
        Runtimems := 0;
    END_IF;
END_IF;

CurrentTemperature := TemperatureSensorInput;
SetTempDisplay := SetTemperature;
HeaterStatus := HeaterOutput;
OverheatProtection := OverheatActive;
END_FUNCTION_BLOCK