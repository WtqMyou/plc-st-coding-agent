(*
ENGINEERING_CONTRACT:
PUB001: Read TemperatureSensorInput (REAL), display in CurrentTemperature
PUB002: HeaterOutput := TRUE when TemperatureSensorInput < SetTemperature
PUB003: Overheat triggers after >5s continuous HeaterOutput (strict > boundary)
PUB004: Overheat auto-sets HeaterOutput:=FALSE, 3s cooldown before OverheatProtection can clear
PUB005: Sensor fault (<0 OR >100) sets HeaterOutput:=FALSE regardless of temperature
PUB006: Status outputs (CurrentTemperature, SetTempDisplay, HeaterStatus, OverheatProtection) update every scan

Activation: All outputs update every scan (no edge-only behavior)
Retention: OverheatActive retains state across scans until cooldown completes
Reset/Deactivation: OverheatActive resets only after OverheatCooldownTimer.Q (3s elapsed)
Same-scan priority: HeaterOutput finalized BEFORE runtime timer enable is evaluated
Units: TIME/LTIME for timers (TON), REAL for temperatures, BOOL for control/status
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
    HeaterOutput : BOOL;
END_VAR

VAR
    HeaterRuntimeTimer : TON;
    OverheatCooldownTimer : TON;
    OverheatActive : BOOL := FALSE;
    SensorFault : BOOL := FALSE;
END_VAR

// Update display outputs
CurrentTemperature := TemperatureSensorInput;
SetTempDisplay := SetTemperature;

// Sensor fault detection: invalid range turns off heater
SensorFault := (TemperatureSensorInput < 0.0) OR (TemperatureSensorInput > 100.0);

// Temperature control logic
IF NOT SensorFault AND NOT OverheatActive THEN
    // Normal operation: heater ON when below setpoint
    IF TemperatureSensorInput < SetTemperature THEN
        HeaterOutput := TRUE;
    ELSE
        HeaterOutput := FALSE;
    END_IF;
ELSE
    // Sensor fault or overheat protection active - heater OFF
    HeaterOutput := FALSE;
END_IF;

// Update heater status display
HeaterStatus := HeaterOutput;

// Runtime timer: tracks continuous heater ON time (resets when heater OFF)
HeaterRuntimeTimer(IN := HeaterOutput, PT := T#5s);

// Overheat detection: >5s continuous heater operation
IF HeaterRuntimeTimer.Q AND NOT OverheatActive THEN
    OverheatActive := TRUE;
    OverheatCooldownTimer(IN := TRUE, PT := T#3s);
END_IF;

// Overheat cooldown: 3s wait before protection can be lifted
IF OverheatActive THEN
    OverheatCooldownTimer(IN := TRUE, PT := T#3s);
    IF OverheatCooldownTimer.Q THEN
        OverheatActive := FALSE;
    END_IF;
END_IF;

// Update overheat protection status
OverheatProtection := OverheatActive;
END_FUNCTION_BLOCK