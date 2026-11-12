(* ENGINEERING_CONTRACT
- CurrentTemperature: unconditional pass-through each scan; no hold/reset; temperature units are unspecified.
- SetTempDisplay: unconditional pass-through each scan; no hold/reset; temperature units are unspecified.
- HeaterStatus: mirrors HeaterOutput every scan; no hold/reset.
- HeaterOutput: active when sensor is valid and temperature < setpoint and no overheat; off on >=, fault, or overheat; no latch. PUB003/PUB004/PUB007.
- OverheatProtection: set after heater runs continuously >5000 ms; held for at least 3000 ms, then auto-clears; no manual reset. PUB005.
- Same-scan priority: sensor fault and active overheat force heater off; after the 3s wait elapses, normal heater control can resume in the same scan.
- Boundaries: sensor fault is <0.0 or >100.0; strict >5s uses T#5001MS; cool-down wait uses T#3S.
*)
(* CONTRACT_RULES [] *)

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
    local_SensorFault : BOOL;
    local_BaseHeaterRequest : BOOL;
    local_HeaterAllowed : BOOL;
    local_OverheatActive : BOOL;
    local_HeaterRunTimer : TON;
    local_CooldownTimer : TON;
END_VAR

local_SensorFault := (TemperatureSensorInput < 0.0) OR (TemperatureSensorInput > 100.0);
local_BaseHeaterRequest := (NOT local_SensorFault) AND (TemperatureSensorInput < SetTemperature);

IF local_OverheatActive THEN
    local_CooldownTimer(IN := TRUE, PT := T#3S);
    local_HeaterAllowed := FALSE;

    IF local_CooldownTimer.Q THEN
        local_OverheatActive := FALSE;
        local_HeaterAllowed := local_BaseHeaterRequest;
    END_IF;

    local_HeaterRunTimer(IN := local_HeaterAllowed, PT := T#5001MS);

    IF local_HeaterRunTimer.Q THEN
        local_OverheatActive := TRUE;
        local_HeaterAllowed := FALSE;
    END_IF;
ELSE
    local_CooldownTimer(IN := FALSE, PT := T#3S);
    local_HeaterAllowed := local_BaseHeaterRequest;

    local_HeaterRunTimer(IN := local_HeaterAllowed, PT := T#5001MS);

    IF local_HeaterRunTimer.Q THEN
        local_OverheatActive := TRUE;
        local_HeaterAllowed := FALSE;
    END_IF;
END_IF;

HeaterOutput := (NOT local_SensorFault) AND local_HeaterAllowed;
HeaterStatus := HeaterOutput;
OverheatProtection := local_OverheatActive;
CurrentTemperature := TemperatureSensorInput;
SetTempDisplay := SetTemperature;

END_FUNCTION_BLOCK