(*
ENGINEERING_CONTRACT - FB_TemperatureControl
=============================================
| State/Output          | Activation            | Retention    | Reset/Deactivation           | Priority     | Units/Boundaries        |
|-----------------------|-----------------------|--------------|-------------------------------|--------------|-------------------------|
| HeaterOutput=TRUE     | Temp<SetTemp AND      | Held while   | Temp>=SetTemp OR SensorFault  | Normal:1     | BOOL                    |
|                       | NOT OverheatProtection| conditions   | OR OverheatTriggered          | Fault:1      |                         |
| OverheatProtection=TRUE| After 5s continuous   | Latched      | After 3s wait, then auto      | Same-scan    | BOOL                    |
|                       | HeaterOutput=TRUE     | (PUB006)     | reset (PUB006)                | w/ heater off|                         |
| HeaterStatus          | Direct mirror of      | Same as      | Same as HeaterOutput          | Same-scan    | BOOL                    |
|                       | HeaterOutput          | HeaterOutput |                               |              |                         |
| SensorFault Handling  | Temp<0 OR Temp>100    | Latched      | Temp back in [0,100] range    | Highest      | 0 <= Temp <= 100 (PUB007)|
|                       |                       |              |                               |              |                         |
| CurrentTemperature    | Assign from input     | Real-time    | None (display only)           | Passive      | REAL, fault=0           |
| SetTempDisplay        | Assign from input     | Real-time    | None (display only)           | Passive      | REAL                    |
==============================================================================================================
PUB001: Function block implementation
PUB002: TemperatureSensorInput reading
PUB003-005: Temperature comparison and heater control
PUB006: Overheat protection with 5s trigger, 3s reset
PUB007: Status indication outputs
PUB008: Sensor fault detection (0-100 range)
*)
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
    HeaterOutput : BOOL := FALSE;
END_VAR
VAR
    OverheatTimer : TON;
    ResetTimer : TON;
    HeaterRunTimer : TON;
    SensorFault : BOOL := FALSE;
    OverheatTriggered : BOOL := FALSE;
    HeaterShouldBeOn : BOOL := FALSE;
    HeaterOnDuration : TIME := T#0S;
    LastScanHeaterOn : BOOL := FALSE;
END_VAR

// Sensor fault detection (PUB008)
SensorFault := (TemperatureSensorInput < 0.0) OR (TemperatureSensorInput > 100.0);

// Update displays (PUB007)
CurrentTemperature := TemperatureSensorInput;
SetTempDisplay := SetTemperature;

// Normal temperature control logic (PUB003, PUB004)
// If sensor fault, heater should be off
IF NOT SensorFault THEN
    HeaterShouldBeOn := (TemperatureSensorInput < SetTemperature);
ELSE
    HeaterShouldBeOn := FALSE;
END_IF;

// Overheat protection logic (PUB006)
// Track continuous heater on time
IF HeaterShouldBeOn AND NOT OverheatTriggered THEN
    HeaterOnDuration := HeaterOnDuration + T#1S; // Assuming 1s scan time
    IF HeaterOnDuration >= T#5S THEN
        OverheatTriggered := TRUE;
    END_IF;
ELSE
    HeaterOnDuration := T#0S;
END_IF;

// Handle overheat protection state (PUB006)
IF OverheatTriggered THEN
    OverheatProtection := TRUE;
    HeaterOutput := FALSE;
    // Start 3s reset timer after overheat triggered
    ResetTimer(IN := TRUE, PT := T#3S);
    IF ResetTimer.Q THEN
        OverheatTriggered := FALSE;
        OverheatProtection := FALSE;
        ResetTimer(IN := FALSE);
        ResetTimer();
    END_IF;
ELSE
    ResetTimer(IN := FALSE);
    ResetTimer();
    OverheatProtection := FALSE;
    // Normal operation - heater follows temperature comparison
    HeaterOutput := HeaterShouldBeOn;
END_IF;

// Update heater status display (PUB007)
HeaterStatus := HeaterOutput;

END_FUNCTION_BLOCK