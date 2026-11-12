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
    local_heater_enable : BOOL;

    (* Free-running clock for measuring scan intervals *)
    ClockTimer : TON;
    prev_clock_et : TIME := T#0ms;

    (* Custom heating accumulator for strict >5s detection *)
    heater_on_accum : TIME := T#0ms;

    (* Cooling timer with standard TON (Q at >=3s) *)
    CoolingTimer : TON;
END_VAR

(* ENGINEERING_CONTRACT
   O1 CurrentTemperature: copies TemperatureSensorInput; no fault suppression; units = input units (PUB006/PUB007).
   O2 SetTempDisplay: copies SetTemperature; units same as input (PUB006/PUB007).
   O3 HeaterStatus: copies final HeaterOutput; true while actual heater command active (PUB006/PUB007).
   O4 OverheatProtection: latched TRUE when heater has been continuously enabled for **strictly more than 5 seconds**  
       (PUB005). Uses custom TIME accumulator based on free-running TON delta to correctly include the  
       first scan interval after enable. Cleared automatically after 3 s cooling: CoolingTimer.Q (ET >= T#3S).  
       No external reset; state retained during cooldown.
   O5 HeaterOutput: TRUE when sensor input in [0,100] AND TemperatureSensorInput < SetTemperature AND NOT overheat_active  
       (PUB003/PUB004/PUB005/PUB008). FALSE on sensor fault, overheat, or temp >= setpoint.
   State retention: OverheatProtection held during 3 s wait; heating accumulator resets when heater enable goes FALSE;  
       CoolingTimer resets when overheat becomes inactive.
   Same-scan priority: overheat trigger and heater disable occur in the same scan when accumulated  
       heater-on time exceeds 5 s. When cooling completes, heater may re-enable in the same scan if low-temperature  
       condition still holds.
   Boundaries: heater start condition is strict “<”; fault uses “<0.0 OR >100.0” (exclusive); exact 0/100 are valid.  
       Overheat uses “>5 s”; cooldown uses “>=3 s”. All TIME arithmetic is non-capped because ClockTimer PT is T#1D.
*)
(* CONTRACT_RULES [] *)

// 1. Compute sensor fault and basic heater request
sensor_fault := (TemperatureSensorInput < 0.0) OR (TemperatureSensorInput > 100.0);
heater_request := NOT sensor_fault AND (TemperatureSensorInput < SetTemperature);

// 2. Free-running clock for scan interval measurement
ClockTimer(IN := TRUE, PT := T#1D);
tmp_delta := ClockTimer.ET - prev_clock_et;
prev_clock_et := ClockTimer.ET;

// 3. Heater enable before overheat decision (uses previous overheat state)
local_heater_enable := heater_request AND NOT overheat_active;

// 4. Update heating accumulator (measures continuous heater-on time, including current scan)
IF local_heater_enable THEN
    heater_on_accum := heater_on_accum + tmp_delta;
ELSE
    heater_on_accum := T#0ms;
END_IF;

// 5. Overheat protection trigger: strictly more than 5 s
IF heater_on_accum > T#5S THEN
    overheat_active := TRUE;
END_IF;

// 6. Cooling timer (standard TON; clears after 3 s)
CoolingTimer(IN := overheat_active, PT := T#3S);
IF overheat_active AND CoolingTimer.Q THEN
    overheat_active := FALSE;
END_IF;

// 7. Final outputs
CurrentTemperature := TemperatureSensorInput;
SetTempDisplay := SetTemperature;
HeaterOutput := heater_request AND NOT overheat_active;
HeaterStatus := HeaterOutput;
OverheatProtection := overheat_active;

END_FUNCTION_BLOCK