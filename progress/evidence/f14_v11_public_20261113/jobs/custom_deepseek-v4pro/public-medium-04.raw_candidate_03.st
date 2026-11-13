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
    tmp_heat_limit : TIME := T#5001MS;  (* strictly more than 5 s continuous heating *)
    tmp_cooldown_limit : TIME := T#3S;
END_VAR

(*
ENGINEERING_CONTRACT
- CurrentTemperature/SetTempDisplay are combinational echoes of the inputs.
- Sensor fault when input < 0.0 or > 100.0; fault forces heater off.
- HeaterOutput is on only when sensor valid, overheat protection inactive,
  and TemperatureSensorInput < SetTemperature. Equal setpoint is off.
- OverheatProtection latches when continuous heater-on time exceeds 5 s,
  and clears after a 3 s cooldown. Cooldown and same-scan reactivation are
  evaluated so clearing protection allows heater and its timer in the same scan.
- HeaterStatus follows HeaterOutput.
*)

(* CONTRACT_RULES [] *)

tmp_sensor_fault := (TemperatureSensorInput < 0.0) OR (TemperatureSensorInput > 100.0);

(* Evaluate cooldown first so a completed cooldown can lift protection
   and permit heater startup during this same invocation. *)
tmp_cooldown_timer(IN := tmp_overheat_active, PT := tmp_cooldown_limit);
IF tmp_cooldown_timer.Q THEN
    tmp_overheat_active := FALSE;
END_IF;

tmp_heat_allowed := (NOT tmp_sensor_fault)
                    AND (NOT tmp_overheat_active)
                    AND (TemperatureSensorInput < SetTemperature);

tmp_heat_on_timer(IN := tmp_heat_allowed, PT := tmp_heat_limit);

IF tmp_heat_on_timer.Q THEN
    tmp_overheat_active := TRUE;
    (* Start cooldown in the same scan when the overheat latch occurs. *)
    tmp_cooldown_timer(IN := TRUE, PT := tmp_cooldown_limit);
END_IF;

HeaterOutput := (NOT tmp_sensor_fault)
                AND (NOT tmp_overheat_active)
                AND (TemperatureSensorInput < SetTemperature);

HeaterStatus := HeaterOutput;
OverheatProtection := tmp_overheat_active;
CurrentTemperature := TemperatureSensorInput;
SetTempDisplay := SetTemperature;

END_FUNCTION_BLOCK