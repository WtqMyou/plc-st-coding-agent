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
    sensor_fault : BOOL;
    heater_request : BOOL;
    overheat_active : BOOL;
    HeatingTimer : TON;
    CoolingTimer : TON;
END_VAR

(* ENGINEERING_CONTRACT
   O1 CurrentTemperature: always copies TemperatureSensorInput; no fault suppression; units = input units (PUB006/PUB007).
   O2 SetTempDisplay: always copies SetTemperature; units same as input (PUB006/PUB007).
   O3 HeaterStatus: copies final HeaterOutput; true while actual heater command active (PUB006/PUB007).
   O4 OverheatProtection: latched TRUE when HeatingTimer reaches T#5S; holds TRUE while CoolingTimer < T#3S; auto-clears after T#3S; no external reset (PUB005/PUB006).
   O5 HeaterOutput: TRUE when sensor input in [0,100] and TemperatureSensorInput < SetTemperature and not overheat-active; FALSE on sensor fault, overheat, or temp >= set (PUB003/PUB004/PUB005/PUB008).
   State retention: OverheatProtection retained during 3s wait; HeatingTimer resets whenever HeaterOutput is false; CoolingTimer resets when overheat inactive.
   Same-scan priority: overheat set and HeaterOutput forced FALSE in same timer-trigger scan; when cooling timer completes, HeaterOutput may turn on same scan if setpoint condition still true.
   Boundaries: strict < for low-temperature start; fault uses <0.0 or >100.0; exact 0/100 valid; T#5S and T#3S are TIME constants.
*)
(* CONTRACT_RULES [] *)

sensor_fault := (TemperatureSensorInput < 0.0) OR (TemperatureSensorInput > 100.0);
heater_request := (NOT sensor_fault) AND (TemperatureSensorInput < SetTemperature);

(* Initial heater output based on current overheat state *)
HeaterOutput := heater_request AND NOT overheat_active;

(* Heating timer: active only when heater is actually on *)
HeatingTimer(IN := HeaterOutput, PT := T#5S);
IF HeatingTimer.Q THEN
    overheat_active := TRUE;
    HeaterOutput := FALSE;   (* force off immediately *)
    HeatingTimer(IN := FALSE, PT := T#5S); (* reset timer *)
END_IF;

(* Cooling timer: active while overheat protection is latched *)
CoolingTimer(IN := overheat_active, PT := T#3S);
IF overheat_active AND CoolingTimer.Q THEN
    overheat_active := FALSE;
    HeaterOutput := heater_request; (* may turn on again if still low *)
    CoolingTimer(IN := FALSE, PT := T#3S); (* reset cooling timer *)
END_IF;

CurrentTemperature := TemperatureSensorInput;
SetTempDisplay := SetTemperature;
HeaterStatus := HeaterOutput;
OverheatProtection := overheat_active;

END_FUNCTION_BLOCK