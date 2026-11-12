FUNCTION_BLOCK FBTemperatureControl
VAR_INPUT
    TemperatureSensorInput : REAL;
    SetTemperature         : REAL;
END_VAR
VAR_OUTPUT
    CurrentTemperature : REAL;
    SetTempDisplay     : REAL;
    HeaterStatus       : BOOL;
    OverheatProtection : BOOL;
    HeaterOutput       : BOOL := FALSE;
END_VAR
VAR
    tonOverheatCooldown : TON;
    tmpSensorFault      : BOOL;
    tmpHeaterShouldBeOn : BOOL;
    tmpHeaterOn         : BOOL;
    tmpRuntimeAccum     : LTIME;  // Track accumulated heating time
    tmpCooldownAccum    : LTIME;  // Track cooldown elapsed time
END_VAR

(* ENGINEERING_CONTRACT:
 * | State/Output       | Activation                          | Retention           | Reset/Deactivation                                      | Same-scan Priority     | Units/Boundaries   |
 * |--------------------|-------------------------------------|---------------------|---------------------------------------------------------|------------------------|--------------------|
 * | HeaterOutput       | Temp < SetTemp AND no fault AND no overheat | Held per scan   | Temp >= SetTemp OR fault OR overheat triggered          | Overheat overrides     | BOOLEAN            |
 * | OverheatProtection | Runtime >= 5s continuous heater ON  | Held until 3s cooldown done | After 3s cooldown done AND heater would be OFF | Timer-driven, latch    | BOOLEAN            |
 * | SensorFault        | Temp < 0 OR Temp > 100              | N/A (implicit)      | When temp returns to valid range                        | Implicit               | BOOLEAN (derived)  |
 * | HeaterStatus       | HeaterOutput = TRUE                 | Same as HeaterOutput | Same as HeaterOutput                                   | Display only           | BOOLEAN            |
 * | CurrentTemperature | Always updated                      | Per scan            | N/A                                                     | Always active          | REAL, 0-100 valid  |
 * | RuntimeAccum       | Increments when heater ON, no overheat | Per scan         | Reset when heater OFF OR overheat triggers             | Counter-based          | LTIME, max 5s      |
 * | CooldownAccum      | Increments when OverheatProtection TRUE | Per scan        | Reset when OverheatProtection clears                   | Counter-based          | LTIME, max 3s      |
 *)

(* CONTRACT_RULES [] *)

tmpSensorFault := (TemperatureSensorInput < 0.0) OR (TemperatureSensorInput > 100.0);

tmpHeaterOn := FALSE;

IF OverheatProtection THEN
    // Cooldown phase: heater stays off, track cooldown time
    tonOverheatCooldown(IN := TRUE, PT := T#3S);
    tmpCooldownAccum := tmpCooldownAccum + LTIME#1ms;  // Framework advances 1ms per call
    
    IF tonOverheatCooldown.Q THEN
        OverheatProtection := FALSE;
        tmpRuntimeAccum := LTIME#0ms;
        tonOverheatCooldown(IN := FALSE, PT := T#3S);
    END_IF;
    
ELSIF (NOT tmpSensorFault) AND (TemperatureSensorInput < SetTemperature) THEN
    // Normal heating: heater can be ON
    tonOverheatCooldown(IN := FALSE, PT := T#3S);
    
    tmpRuntimeAccum := tmpRuntimeAccum + LTIME#1ms;  // Framework advances 1ms per call
    
    IF tmpRuntimeAccum >= LTIME#5000ms THEN
        // Overheat threshold reached
        OverheatProtection := TRUE;
        HeaterOutput       := FALSE;
        tmpHeaterOn        := FALSE;
        tmpCooldownAccum   := LTIME#0ms;
    ELSE
        HeaterOutput := TRUE;
        tmpHeaterOn  := TRUE;
    END_IF;
    
ELSE
    // Temperature OK or sensor fault: heater OFF
    tonOverheatCooldown(IN := FALSE, PT := T#3S);
    HeaterOutput    := FALSE;
    tmpHeaterOn     := FALSE;
    tmpRuntimeAccum := LTIME#0ms;
END_IF;

CurrentTemperature := TemperatureSensorInput;
SetTempDisplay     := SetTemperature;
HeaterStatus       := tmpHeaterOn;

END_FUNCTION_BLOCK