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
    tmp_heater_desired : BOOL := FALSE;
    local_heater_duration : TON;
    local_cooling_duration : TON;
    local_sensor_fault : BOOL;
END_VAR

(* ENGINEERING_CONTRACT
HeaterOutput: active <= sensor valid AND TemperatureSensorInput < SetTemperature (PUB003/PUB007).
OverheatProtection: latches when continuous HeaterOutput true >5s strict (T#5001MS); auto-lifts after 3s cooldown.
Fault: TemperatureSensorInput <0.0 or >100.0 forces heater off (PUB007).
Equal setpoint retains last heater command; initial off (unspecified).
Outputs reflect raw REAL/BOOL; HeaterStatus tracks HeaterOutput.
Same-scan priority: fault/overheat off over temp compare; overheat latch before output.
*)

(* CONTRACT_RULES [] *)

CurrentTemperature := TemperatureSensorInput;
SetTempDisplay := SetTemperature;

local_sensor_fault := (TemperatureSensorInput < 0.0) OR (TemperatureSensorInput > 100.0);

IF OverheatProtection THEN
    tmp_heater_desired := FALSE;
ELSE
    IF local_sensor_fault THEN
        tmp_heater_desired := FALSE;
    ELSE
        IF TemperatureSensorInput < SetTemperature THEN
            tmp_heater_desired := TRUE;
        ELSIF TemperatureSensorInput > SetTemperature THEN
            tmp_heater_desired := FALSE;
        END_IF;
    END_IF;
END_IF;

local_heater_duration(IN := tmp_heater_desired, PT := T#5001MS);

IF (NOT OverheatProtection) AND local_heater_duration.Q THEN
    OverheatProtection := TRUE;
    tmp_heater_desired := FALSE;
END_IF;

local_cooling_duration(IN := OverheatProtection, PT := T#3S);

IF OverheatProtection AND local_cooling_duration.Q THEN
    OverheatProtection := FALSE;
END_IF;

HeaterOutput := tmp_heater_desired;
HeaterStatus := HeaterOutput;