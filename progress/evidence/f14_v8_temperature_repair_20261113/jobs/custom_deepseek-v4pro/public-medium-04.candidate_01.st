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
    tmp_heater_enable : BOOL;
    HeatingTimer : TON;
    CoolingTimer : TON;
END_VAR

(* ENGINEERING_CONTRACT
   O1 CurrentTemperature: copies TemperatureSensorInput; no fault suppression; units = input units (PUB006/PUB007).
   O2 SetTempDisplay: copies SetTemperature; units same as input (PUB006/PUB007).
   O3 HeaterStatus: copies final HeaterOutput; true while actual heater command active (PUB006/PUB007).
   O4 OverheatProtection: latched TRUE when heater has been continuously enabled for **strictly more than 5 s** (PUB005).  
       Cleared automatically after a 3 s cooling period measured with CoolingTimer (PUB005).  
       No external reset; state is retained during the 3 s cooldown.
   O5 HeaterOutput: TRUE when sensor input in [0,100] and TemperatureSensorInput < SetTemperature and not overheat-active (PUB003/PUB004/PUB005/PUB008).  
       FALSE on sensor fault (input <0 or >100), on overheat, or when temperature >= setpoint.
   State retention: OverheatProtection held during 3 s wait; HeatingTimer resets whenever heater enable goes FALSE;  
       CoolingTimer resets when overheat becomes inactive.
   Same‑scan priority: overheat trigger and heater disable occur in the same scan in which the strict >5 s condition is first satisfied;  
       when cooling completes, heater may re‑enable in the same scan if the low‑temperature condition still holds.
   Boundaries: heater start condition is strict “<”; fault uses “<0.0 OR >100.0” (both exclusive); exact 0/100 are valid.  
       TIMER thresholds use TIME constants; strict “>5 s” is implemented by requiring the 5 s threshold to have been reached in a previous scan  
       and the heater still enabled in the current scan, thereby ensuring a positive elapsed time beyond 5 s.
*)
(* CONTRACT_RULES [] *)

// 1. Compute sensor fault and basic heater request
sensor_fault := (TemperatureSensorInput < 0.0) OR (TemperatureSensorInput > 100.0);
heater_request := NOT sensor_fault AND (TemperatureSensorInput < SetTemperature);

// 2. Determine heater enable before any new overheat decision (uses previous overheat state)
tmp_heater_enable := heater_request AND NOT overheat_active;

// 3. Detect strict overheat: HeatingTimer had already reached 5 s in the previous scan (Q true)  
//    and the heater is still enabled now -> elapsed time > 5 s.
IF HeatingTimer.Q AND tmp_heater_enable THEN
    overheat_active := TRUE;
    tmp_heater_enable := FALSE;   // force heater off immediately in this scan
END_IF;

// 4. Update 5‑second timer with the current (possibly corrected) enable signal
HeatingTimer(IN := tmp_heater_enable, PT := T#5S);

// 5. Update cooling timer (3 s)
CoolingTimer(IN := overheat_active, PT := T#3S);
IF overheat_active AND CoolingTimer.Q THEN
    overheat_active := FALSE;      // cooling period finished, protection cleared
END_IF;

// 6. Final outputs
CurrentTemperature := TemperatureSensorInput;
SetTempDisplay := SetTemperature;
HeaterOutput := heater_request AND NOT overheat_active;
HeaterStatus := HeaterOutput;
OverheatProtection := overheat_active;

END_FUNCTION_BLOCK