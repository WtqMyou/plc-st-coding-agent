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
    tmp_InOverheatProtection : BOOL;
    tmp_SensorFault : BOOL;
    tmp_HeaterShouldBeOn : BOOL;
END_VAR

(*
ENGINEERING_CONTRACT
================================================================================
| Output/State        | Activation          | Retention/Reset           | Units/Boundaries     |
|---------------------|---------------------|---------------------------|----------------------|
| CurrentTemperature  | Every scan (copy)   | Unchanged when fault      | REAL, no conversion  |
| SetTempDisplay      | Every scan (copy)   | Always updated            | REAL, no conversion  |
| HeaterStatus        | Every scan (AND)    | False on fault or overheat| BOOL, same-scan      |
| OverheatProtection  | tmp_InOverheatProt  | Hold 3s cooldown then OFF | BOOL, timer-driven   |
| HeaterOutput        | temp < set && !prot | Off on fault, >5s prot,   | BOOL, 5s threshold   |
|                     |                     |   or temp >= set          | > not >= per spec    |
================================================================================
PUB001: temp < set triggers heater on
PUB002: temp > set turns heater off  
PUB003: >5s continuous heater runtime triggers overheat protection
PUB004: 3s cooldown before overheat protection can be lifted
PUB005: Sensor fault if input < 0 or > 100
PUB006: Display current temp, set temp, heater status, overheat status
PUB007: Heater must be off during sensor fault
PUB008: Heater off during overheat protection until cooldown completes
================================================================================

CONTRACT_RULES []
*)

// Update display outputs every scan
CurrentTemperature := TemperatureSensorInput;
SetTempDisplay := SetTemperature;

// Detect sensor fault: temperature out of valid range [0, 100]
tmp_SensorFault := (TemperatureSensorInput < 0.0) OR (TemperatureSensorInput > 100.0);

// Determine if heater should be on (based on temperature comparison only)
tmp_HeaterShouldBeOn := (NOT tmp_SensorFault) AND (TemperatureSensorInput < SetTemperature);

// Overheat protection state machine
IF NOT tmp_InOverheatProtection THEN
    // Normal operation: check if overheat protection should trigger
    IF tmp_HeaterShouldBeOn THEN
        // Heater is on, start accumulating runtime
        HeaterRuntimeTimer(IN := TRUE, PT := T#5S);
        IF HeaterRuntimeTimer.Q THEN
            // Heater ran for more than 5 seconds continuously
            tmp_InOverheatProtection := TRUE;
            HeaterRuntimeTimer(IN := FALSE);
        END_IF;
    ELSE
        // Heater is off, reset runtime timer
        HeaterRuntimeTimer(IN := FALSE);
    END_IF;
ELSE
    // In overheat protection state, start 3-second cooldown
    HeaterRuntimeTimer(IN := FALSE);
    OverheatCooldownTimer(IN := TRUE, PT := T#3S);
    IF OverheatCooldownTimer.Q THEN
        // Cooldown complete, clear overheat protection
        tmp_InOverheatProtection := FALSE;
        OverheatCooldownTimer(IN := FALSE);
    END_IF;
END_IF;

// Update overheat protection output
OverheatProtection := tmp_InOverheatProtection;

// Calculate final heater output
// HeaterOutput is true when:
//   - Temperature is below setpoint
//   - Not in sensor fault
//   - Not in overheat protection
HeaterOutput := tmp_HeaterShouldBeOn AND (NOT tmp_InOverheatProtection);

// Heater status follows actual heater output
HeaterStatus := HeaterOutput;

END_FUNCTION_BLOCK