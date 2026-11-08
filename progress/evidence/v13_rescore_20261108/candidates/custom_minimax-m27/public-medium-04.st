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
    heating_time_count : INT := 0;
    overheat_wait_count : INT := 0;
    desired_heater : BOOL := FALSE;
    sensor_fault : BOOL := FALSE;
END_VAR

(* ---- Control logic ---- *)
sensor_fault := (TemperatureSensorInput < 0.0) OR (TemperatureSensorInput > 100.0);

desired_heater := FALSE;
IF NOT sensor_fault THEN
    IF TemperatureSensorInput < SetTemperature THEN
        desired_heater := TRUE;
    END_IF;
END_IF;

IF sensor_fault THEN
    HeaterOutput := FALSE;
    heating_time_count := 0;
    overheat_wait_count := 0;
    OverheatProtection := FALSE;
ELSE
    IF OverheatProtection THEN
        overheat_wait_count := overheat_wait_count + 1;
        HeaterOutput := FALSE;
        IF overheat_wait_count >= 3 THEN
            OverheatProtection := FALSE;
            overheat_wait_count := 0;
            heating_time_count := 0;
        END_IF;
    ELSE
        IF desired_heater THEN
            heating_time_count := heating_time_count + 1;
            IF heating_time_count > 5 THEN
                OverheatProtection := TRUE;
                HeaterOutput := FALSE;
                heating_time_count := 0;
                overheat_wait_count := 0;
            ELSE
                HeaterOutput := TRUE;
            END_IF;
        ELSE
            heating_time_count := 0;
            HeaterOutput := FALSE;
        END_IF;
    END_IF;
END_IF;

(* ---- Status outputs ---- *)
CurrentTemperature := TemperatureSensorInput;
SetTempDisplay := SetTemperature;
HeaterStatus := HeaterOutput;
END_FUNCTION_BLOCK