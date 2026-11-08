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
    sensor_fault : BOOL;
    heater_on_counter : INT := 0;
    protection_counter : INT := 0;
    protection_active : BOOL := FALSE;
END_VAR

    CurrentTemperature := TemperatureSensorInput;
    SetTempDisplay := SetTemperature;

    sensor_fault := (TemperatureSensorInput < 0.0) OR (TemperatureSensorInput > 100.0);

    IF protection_active THEN
        HeaterOutput := FALSE;
        HeaterStatus := FALSE;
        OverheatProtection := TRUE;
        heater_on_counter := 0;

        protection_counter := protection_counter + 1;
        IF protection_counter >= 3 THEN
            protection_active := FALSE;
            OverheatProtection := FALSE;
            protection_counter := 0;
        END_IF;
    ELSE
        OverheatProtection := FALSE;

        IF sensor_fault THEN
            HeaterOutput := FALSE;
            heater_on_counter := 0;
        ELSIF TemperatureSensorInput < SetTemperature THEN
            HeaterOutput := TRUE;
            heater_on_counter := heater_on_counter + 1;

            IF heater_on_counter >= 5 THEN
                protection_active := TRUE;
                OverheatProtection := TRUE;
                HeaterOutput := FALSE;
                heater_on_counter := 0;
                protection_counter := 0;
            END_IF;
        ELSE
            HeaterOutput := FALSE;
            heater_on_counter := 0;
        END_IF;

        HeaterStatus := HeaterOutput;
    END_IF;

END_FUNCTION_BLOCK