(*====================================================================*)
(*  FUNCTION_BLOCK FB_TemperatureControl                              *)
(*  Implements a temperature‑control loop with over‑heat protection   *)
(*  and sensor‑fault detection.                                       *)
(*                                                                    *)
(*  Inputs:                                                           *)
(*    TemperatureSensorInput  – REAL  – actual temperature (°C)       *)
(*    SetTemperature          – REAL  – desired temperature (°C)      *)
(*                                                                    *)
(*  Outputs:                                                          *)
(*    CurrentTemperature      – REAL  – display of current temperature*)
(*    SetTempDisplay          – REAL  – display of set temperature    *)
(*    HeaterStatus            – BOOL  – heater ON/OFF status          *)
(*    OverheatProtection      – BOOL  – over‑heat protection active   *)
(*    HeaterOutput            – BOOL  – heater control output         *)
(*====================================================================*)

FUNCTION_BLOCK FB_TemperatureControl

VAR_INPUT
    TemperatureSensorInput : REAL;   (* Actual temperature from sensor *)
    SetTemperature         : REAL;   (* Desired temperature set point  *)
END_VAR

VAR_OUTPUT
    CurrentTemperature : REAL;       (* Display of current temperature *)
    SetTempDisplay     : REAL;       (* Display of set temperature      *)
    HeaterStatus       : BOOL;       (* Heater ON/OFF status            *)
    OverheatProtection : BOOL;       (* Over‑heat protection flag       *)
    HeaterOutput       : BOOL;       (* Heater control output           *)
END_VAR

VAR
    (* Internal control signals *)
    HeatingRequested   : BOOL;       (* TRUE when heating is required   *)
    SensorFault        : BOOL;       (* TRUE when sensor reading is out‑of‑range *)

    (* Timer instances *)
    OverheatTimer      : TON;        (* Counts ON‑time of the heater     *)
    OverheatWaitTimer  : TON;        (* Counts the 3 s wait after over‑heat *)
END_VAR

(*------------------------------------------------------------------*)
(* 1. Sensor‑fault detection (0 °C … 100 °C is the valid range)      *)
(*------------------------------------------------------------------*)
SensorFault := (TemperatureSensorInput < 0.0) OR (TemperatureSensorInput > 100.0);

(*------------------------------------------------------------------*)
(* 2. Determine if heating is required (based on temperature)        *)
(*------------------------------------------------------------------*)
IF SensorFault THEN
    HeatingRequested := FALSE;                 (* Fault → no heating *)
ELSE
    IF TemperatureSensorInput < SetTemperature THEN
        HeatingRequested := TRUE;              (* Below set point → heat *)
    ELSE
        HeatingRequested := FALSE;             (* At or above set point   *)
    END_IF
END_IF

(*------------------------------------------------------------------*)
(* 3. Over‑heat detection timer (5 s continuous heater ON)           *)
(*------------------------------------------------------------------*)
OverheatTimer(IN := HeaterOutput, PT := T#5s);

(* If the timer elapses while protection is not yet active,          *)
(* raise the protection flag and force the heater OFF immediately.   *)
IF OverheatTimer.Q AND NOT OverheatProtection THEN
    OverheatProtection := TRUE;
    HeaterOutput       := FALSE;                (* Ensure heater is off   *)
END_IF

(*------------------------------------------------------------------*)
(* 4. Over‑heat wait timer (3 s must elapse before protection can be cleared) *)
(*------------------------------------------------------------------*)
OverheatWaitTimer(IN := OverheatProtection, PT := T#3s);

(* After the mandatory 3 s wait, clear the protection flag.          *)
IF OverheatWaitTimer.Q THEN
    OverheatProtection := FALSE;
END_IF

(*------------------------------------------------------------------*)
(* 5. Final heater command – allowed only when heating is requested  *)
(*    and over‑heat protection is NOT active.                        *)
(*------------------------------------------------------------------*)
HeaterOutput := HeatingRequested AND NOT OverheatProtection;

(*------------------------------------------------------------------*)
(* 6. Status outputs                                                *)
(*------------------------------------------------------------------*)
CurrentTemperature := TemperatureSensorInput;   (* Display current temp *)
SetTempDisplay     := SetTemperature;           (* Display set temp     *)
HeaterStatus       := HeaterOutput;             (* Heater ON/OFF status *)

END_FUNCTION_BLOCK
(*====================================================================*)