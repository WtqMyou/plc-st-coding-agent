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
    tmp_sensor_fault : BOOL;
    tmp_heat_allowed : BOOL;
    tmp_overheat_active : BOOL;
    tmp_heat_on_timer : TON;
    tmp_cooldown_timer : TON;
    tmp_heat_limit : TIME := T#5001MS;  (* strictly > 5 s continuous heating *)
    tmp_cooldown_limit : TIME := T#3S;
END_VAR

(*
ENGINEERING_CONTRACT
- CurrentTemperature/SetTempDisplay: combinational echoes, raw units.
- HeaterOutput: on when sensor valid, no overheat, sensor < set;
  off when sensor >= set, sensor fault, or overheat. Equal is off.
- OverheatProtection: latched TRUE on continuous heater on >5s; auto clear after 3s cooldown.
- HeaterStatus: echo of HeaterOutput.
- Sensor fault: <0.0 or >100.0. Fault and overheat force heater off.
- Equal setpoint and reset after cooldown interpreted as above.
- Heat timer starts in same scan as heater is newly enabled; heat trip starts cooldown in same scan.
- PUB001-PUB008.
*)

(* CONTRACT_RULES [] *)

tmp_sensor_fault := (TemperatureSensorInput < 0.0) OR (TemperatureSensorInput > 100.0);

(* Process cooldown for any currently active overheat before computing heater command *)
tmp_cooldown_timer(IN := tmp_overheat_active, PT := tmp_cooldown_limit);
IF tmp_cooldown_timer.Q THEN
    tmp_overheat_active := FALSE;
END_IF;

tmp_heat_allowed := (NOT tmp_sensor_fault) AND (NOT tmp_overheat_active) AND (TemperatureSensorInput < SetTemperature);
HeaterOutput := tmp_heat_allowed;

tmp_heat_on_timer(IN := HeaterOutput, PT := tmp_heat_limit);
IF tmp_heat_on_timer.Q THEN
    tmp_overheat_active := TRUE;
    HeaterOutput := FALSE;
    (* Start cooldown timer on the same scan as the overheat trip *)
    tmp_cooldown_timer(IN := TRUE, PT := tmp_cooldown_limit);
END_IF;

HeaterStatus := HeaterOutput;
OverheatProtection := tmp_overheat_active;
CurrentTemperature := TemperatureSensorInput;
SetTempDisplay := SetTemperature;

END_FUNCTION_BLOCK