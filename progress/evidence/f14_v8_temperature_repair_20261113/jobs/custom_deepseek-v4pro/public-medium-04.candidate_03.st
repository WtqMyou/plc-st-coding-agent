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
   O4 OverheatProtection: latched TRUE when heater has been continuously enabled for **strictly more than 5 seconds**  
       (PUB005). HeatingTimer uses a large PT and compares ET > T#5S to enforce strict >.  
       Cleared automatically after a 3 second cooling period: CoolingTimer.Q (ET >= T#3S).  
       No external reset; state retained during cooldown.
   O5 HeaterOutput: TRUE when sensor input in [0,100] AND TemperatureSensorInput < SetTemperature AND NOT overheat_active  
       (PUB003/PUB004/PUB005/PUB008). FALSE on sensor fault, overheat, or temp >= setpoint.
   State retention: OverheatProtection held during 3 s wait; HeatingTimer resets whenever heater enable goes FALSE;  
       CoolingTimer resets when overheat becomes inactive.
   Same‑scan priority: overheat trigger and heater disable occur in the same scan when ET > 5 s is detected.  
       When cooling completes, heater may re‑enable in the same scan if low‑temperature condition still holds.
   Boundaries: heater start condition is strict “<”; fault uses “<0.0 OR >100.0” (exclusive); exact 0/100 are valid.  
       Overheat uses “>5 s”; cooldown uses “>=3 s”.
*)
(* CONTRACT_RULES [] *)

// 1. Compute sensor fault and basic heater request
sensor_fault := (TemperatureSensorInput < 0.0) OR (TemperatureSensorInput > 100.0);
heater_request := NOT sensor_fault AND (TemperatureSensorInput < SetTemperature);

// 2. Determine heater enable before overheat decision (uses previous overheat state)
tmp_heater_enable := heater_request AND NOT overheat_active;

// 3. Update heating timer with a large PT so ET can exceed T#5S
HeatingTimer(IN := tmp_heater_enable, PT := T#1D);
IF tmp_heater_enable AND (HeatingTimer.ET > T#5S) THEN
    overheat_active := TRUE;
END_IF;

// 4. Update cooling timer (standard TON: Q becomes TRUE at >= T#3S)
CoolingTimer(IN := overheat_active, PT := T#3S);
IF overheat_active AND CoolingTimer.Q THEN
    overheat_active := FALSE;
END_IF;

// 5. Final outputs
CurrentTemperature := TemperatureSensorInput;
SetTempDisplay := SetTemperature;
HeaterOutput := heater_request AND NOT overheat_active;
HeaterStatus := HeaterOutput;
OverheatProtection := overheat_active;

END_FUNCTION_BLOCK