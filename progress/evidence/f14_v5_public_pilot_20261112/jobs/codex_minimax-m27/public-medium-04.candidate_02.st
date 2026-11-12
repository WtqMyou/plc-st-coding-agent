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
    tonOverheat : TON;
    tonReset : TON;
    SensorFault : BOOL := FALSE;
    OverheatTriggered : BOOL := FALSE;
END_VAR

// Sensor fault detection (PUB008)
SensorFault := (TemperatureSensorInput < 0.0) OR (TemperatureSensorInput > 100.0);

// Update displays (PUB007)
CurrentTemperature := TemperatureSensorInput;
SetTempDisplay := SetTemperature;

// Overheat protection logic (PUB006)
IF OverheatTriggered THEN
    // Overheat active - heater off, start reset timer
    OverheatProtection := TRUE;
    HeaterOutput := FALSE;
    tonOverheat(IN := FALSE);
    tonOverheat();
    tonReset(IN := TRUE, PT := T#3S);
    IF tonReset.Q THEN
        OverheatTriggered := FALSE;
        OverheatProtection := FALSE;
        tonReset(IN := FALSE);
        tonReset();
    END_IF;
ELSE
    // Normal operation
    tonReset(IN := FALSE);
    tonReset();
    OverheatProtection := FALSE;
    
    // Start overheat timer when heater would be on
    IF NOT SensorFault AND (TemperatureSensorInput < SetTemperature) THEN
        tonOverheat(IN := TRUE, PT := T#5S);
    ELSE
        tonOverheat(IN := FALSE);
    END_IF;
    tonOverheat();
    
    // Check if overheat threshold reached
    IF tonOverheat.Q THEN
        OverheatTriggered := TRUE;
        HeaterOutput := FALSE;
    ELSE
        // Normal heater control (PUB003, PUB004, PUB005)
        IF NOT SensorFault THEN
            IF TemperatureSensorInput < SetTemperature THEN
                HeaterOutput := TRUE;
            ELSE
                HeaterOutput := FALSE;
            END_IF;
        ELSE
            HeaterOutput := FALSE;
        END_IF;
    END_IF;
END_IF;

// Update heater status display (PUB007)
HeaterStatus := HeaterOutput;

END_FUNCTION_BLOCK