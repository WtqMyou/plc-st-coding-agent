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
    local_OverheatActive : BOOL := FALSE;
    local_SensorFault : BOOL;
    local_DesiredHeater : BOOL;
    tmp_HeaterOnTimer : TON;
    tmp_CooldownTimer : TON;
END_VAR

(* ENGINEERING_CONTRACT
   CurrentTemperature/SetTempDisplay: mirror inputs every scan; no retention.
   HeaterOutput: ON only when sensor OK, protection inactive and temp < set (PUB003).
     OFF when temp >= set (PUB004; equality unspecified, implemented OFF).
   Sensor fault (input < 0 or > 100) forces OFF (PUB007).
   OverheatProtection: set when HeaterOutput continuously TRUE > 5000 ms via TON (PUB005).
     Retained TRUE until 3 s cooldown TON completes; then clears automatically (PUB005).
   Same-scan priority: sensor fault and overheat protection override normal compare (PUB005/PUB007).
   HeaterStatus mirrors final HeaterOutput; temperatures in deg C; thresholds strict.
*)
(* CONTRACT_RULES [] *)

CurrentTemperature := TemperatureSensorInput;
SetTempDisplay := SetTemperature;

local_SensorFault := (TemperatureSensorInput < 0.0) OR (TemperatureSensorInput > 100.0);

IF local_SensorFault OR local_OverheatActive THEN
    local_DesiredHeater := FALSE;
ELSIF TemperatureSensorInput < SetTemperature THEN
    local_DesiredHeater := TRUE;
ELSE
    local_DesiredHeater := FALSE;
END_IF;

HeaterOutput := local_DesiredHeater;

tmp_HeaterOnTimer(IN := HeaterOutput, PT := T#5001MS);
IF tmp_HeaterOnTimer.Q THEN
    local_OverheatActive := TRUE;
    HeaterOutput := FALSE;
END_IF;

tmp_CooldownTimer(IN := local_OverheatActive, PT := T#3S);
IF tmp_CooldownTimer.Q THEN
    local_OverheatActive := FALSE;
    IF local_SensorFault THEN
        HeaterOutput := FALSE;
    ELSIF TemperatureSensorInput < SetTemperature THEN
        HeaterOutput := TRUE;
    ELSE
        HeaterOutput := FALSE;
    END_IF;
    tmp_HeaterOnTimer(IN := HeaterOutput, PT := T#5001MS);
END_IF;

HeaterStatus := HeaterOutput;
OverheatProtection := local_OverheatActive;
END_FUNCTION_BLOCK