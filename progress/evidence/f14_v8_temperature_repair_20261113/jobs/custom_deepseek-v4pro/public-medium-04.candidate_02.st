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
   O4 OverheatProtection: latched TRUE when heater has been continuously enabled for at least 5 seconds (PUB005).  
       Cleared automatically after a 3 second cooling period measured with CoolingTimer (PUB005).  
       No external reset; state is retained during the 3 s cooldown.
   O5 HeaterOutput: TRUE when sensor input in [0,100] and TemperatureSensorInput < SetTemperature and not overheat-active  
       (PUB003/PUB004/PUB005/PUB008). FALSE on sensor fault (input <0 or >100), on overheat, or when temperature >= setpoint.
   State retention: OverheatProtection held during 3 s wait; HeatingTimer resets whenever heater enable goes FALSE;  
       CoolingTimer resets when overheat becomes inactive.
   Same‑scan priority: overheat trigger and heater disable occur in the same scan in which the 5 s threshold is reached;  
       when cooling completes, heater may re‑enable in the same scan if the low‑temperature condition still holds.
   Boundaries: heater start condition is strict “<”; fault uses “<0.0 OR >100.0” (both exclusive); exact 0/100 are valid.  
       TIMER thresholds use TIME constants; “≥5 s” for overheat and “≥3 s” for cooldown are implemented with standard TON.Q.
*)
(* CONTRACT_RULES [] *)

// 1. Compute sensor fault and basic heater request
sensor_fault := (TemperatureSensorInput < 0.0) OR (TemperatureSensorInput > 100.0);
heater_request := NOT sensor_fault AND (TemperatureSensorInput < SetTemperature);

// 2. Determine heater enable before overheat decision (uses previous overheat state)
tmp_heater_enable := heater_request AND NOT overheat_active;

// 3. Update 5‑second timer with current enable
HeatingTimer(IN := tmp_heater_enable, PT := T#5S);

// 4. Trigger overheat immediately when timer reaches PT (≥5 s)
IF HeatingTimer.Q AND tmp_heater_enable THEN
    overheat_active := TRUE;
END_IF;

// 5. Update cooling timer (3 s)
CoolingTimer(IN := overheat_active, PT := T#3S);

// 6. Clear overheat when cooling time reaches 3 s
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