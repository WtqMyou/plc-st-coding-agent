FUNCTION_BLOCK FBTemperatureControl
VAR_INPUT
    TemperatureSensorInput : REAL;
    SetTemperature         : REAL;
END_VAR
VAR_OUTPUT
    CurrentTemperature : REAL;
    SetTempDisplay     : REAL;
    HeaterStatus       : BOOL;
    OverheatProtection : BOOL := FALSE;
    HeaterOutput       : BOOL := FALSE;
END_VAR
VAR
    tonHeaterRuntime   : TON;
    tonOverheatCooldown: TON;
    tmpSensorFault     : BOOL;
    tmpHeaterShouldBeOn: BOOL;
    tmpHeaterLatchedOff: BOOL := FALSE;
END_VAR

(* ENGINEERING_CONTRACT:
 * | State/Output       | Activation                          | Retention           | Reset/Deactivation                                      | Same-scan Priority     | Units/Boundaries   |
 * |--------------------|-------------------------------------|---------------------|---------------------------------------------------------|------------------------|--------------------|
 * | HeaterOutput       | Temp < SetTemp AND no fault AND no overheat/latch | Held per scan       | Temp >= SetTemp OR fault OR overheat/latch triggered    | Overheat overrides     | BOOLEAN            |
 * | OverheatProtection | HeaterOutput TRUE for >= 5s continuous  | Held until 3s cooldown done | After 3s cooldown done AND heater would be OFF | Timer-driven, latch    | BOOLEAN            |
 * | HeaterLatchedOff   | OverheatProtection triggers          | Held indefinitely   | No reset defined; remains latched                       | Latch persists         | BOOLEAN            |
 * | SensorFault        | Temp < 0 OR Temp > 100              | N/A (implicit)      | When temp returns to valid range                        | Implicit               | BOOLEAN (derived)  |
 * | HeaterStatus       | HeaterOutput = TRUE                 | Same as HeaterOutput | Same as HeaterOutput                                   | Display only           | BOOLEAN            |
 * | CurrentTemperature | Always updated                      | Per scan            | N/A                                                     | Always active          | REAL, 0-100 valid  |
 *)

(* CONTRACT_RULES [{"kind":"hold_until_reset","output":"HeaterOutput","set_input":"OverheatProtection","reset_input":null}] *)

tmpSensorFault := (TemperatureSensorInput < 0.0) OR (TemperatureSensorInput > 100.0);

IF OverheatProtection THEN
    tonHeaterRuntime(IN := FALSE, PT := T#5S);
    tonOverheatCooldown(IN := TRUE, PT := T#3S);
    IF tonOverheatCooldown.Q THEN
        OverheatProtection := FALSE;
        tmpHeaterLatchedOff := TRUE;
        tonOverheatCooldown(IN := FALSE, PT := T#3S);
        tonHeaterRuntime(IN := FALSE, PT := T#5S);
    END_IF;
    HeaterOutput := FALSE;
ELSIF tmpSensorFault THEN
    tonHeaterRuntime(IN := FALSE, PT := T#5S);
    tonOverheatCooldown(IN := FALSE, PT := T#3S);
    HeaterOutput := FALSE;
    tmpHeaterLatchedOff := FALSE;
ELSE
    tonOverheatCooldown(IN := FALSE, PT := T#3S);
    tmpHeaterShouldBeOn := (TemperatureSensorInput < SetTemperature) AND (NOT tmpHeaterLatchedOff);
    tonHeaterRuntime(IN := tmpHeaterShouldBeOn, PT := T#5S);
    IF tonHeaterRuntime.Q THEN
        OverheatProtection := TRUE;
        tmpHeaterLatchedOff := TRUE;
        HeaterOutput := FALSE;
    ELSIF tmpHeaterShouldBeOn THEN
        HeaterOutput := TRUE;
    ELSE
        HeaterOutput := FALSE;
        tmpHeaterLatchedOff := FALSE;
    END_IF;
END_IF;

CurrentTemperature := TemperatureSensorInput;
SetTempDisplay     := SetTemperature;
HeaterStatus       := HeaterOutput;

END_FUNCTION_BLOCK