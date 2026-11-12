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
    local_HeatCommand : BOOL;
    local_OverheatActive : BOOL;
    HeaterContinuousTimer : TON;
    OverheatCooldownTimer : TON;
END_VAR

(*
ENGINEERING_CONTRACT
- Displays follow inputs each scan; REAL preserved without conversion (PUB002/PUB007).
- Normal heat: on when TemperatureSensorInput < SetTemperature; off when >= SetTemperature.
  Equality is unspecified by PUB003-PUB005 and is interpreted as off.
- Sensor fault: TemperatureSensorInput < 0.0 OR TemperatureSensorInput > 100.0 forces heat off.
  Values 0.0 and 100.0 remain valid (PUB008).
- Overheat: continuous HeaterOutput TRUE for 5 s starts protection; heater is forced off and
  OverheatProtection stays TRUE for a 3 s cooldown, then clears automatically (PUB006).
- Same-scan priority: sensor fault / active overheat overrides normal demand; a 5 s timer hit
  overrides the computed heat command in that scan.
- Units/boundaries: TIME uses T#5S and T#3S.
*)
(* CONTRACT_RULES [] *)

CurrentTemperature := TemperatureSensorInput;
SetTempDisplay := SetTemperature;

local_SensorFault := (TemperatureSensorInput < 0.0) OR (TemperatureSensorInput > 100.0);

IF local_OverheatActive THEN
    OverheatCooldownTimer(IN := TRUE, PT := T#3S);
    IF OverheatCooldownTimer.Q THEN
        local_OverheatActive := FALSE;
    END_IF;
ELSE
    OverheatCooldownTimer(IN := FALSE, PT := T#3S);
END_IF;

IF local_SensorFault OR local_OverheatActive THEN
    local_HeatCommand := FALSE;
ELSIF TemperatureSensorInput < SetTemperature THEN
    local_HeatCommand := TRUE;
ELSE
    local_HeatCommand := FALSE;
END_IF;

HeaterContinuousTimer(IN := local_HeatCommand, PT := T#5S);
IF HeaterContinuousTimer.Q THEN
    local_OverheatActive := TRUE;
    local_HeatCommand := FALSE;
END_IF;

HeaterOutput := local_HeatCommand AND NOT local_SensorFault AND NOT local_OverheatActive;
HeaterStatus := HeaterOutput;
OverheatProtection := local_OverheatActive;

END_FUNCTION_BLOCK