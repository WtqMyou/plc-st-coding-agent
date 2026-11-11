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
    heatingRun : INT := 0;
    coolingActive : BOOL := FALSE;
    coolingCount : INT := 0;
    sensorHealthy : BOOL;
    lowDemand : BOOL;
END_VAR

sensorHealthy := (TemperatureSensorInput >= 0.0) AND (TemperatureSensorInput <= 100.0);
lowDemand := sensorHealthy AND (TemperatureSensorInput < SetTemperature);

IF coolingActive THEN
    IF coolingCount >= 2 THEN
        coolingActive := FALSE;
        coolingCount := 0;
        OverheatProtection := FALSE;

        IF lowDemand THEN
            HeaterOutput := TRUE;
            heatingRun := 1;
        ELSE
            HeaterOutput := FALSE;
            heatingRun := 0;
        END_IF
    ELSE
        OverheatProtection := TRUE;
        HeaterOutput := FALSE;
        heatingRun := 0;
        coolingCount := coolingCount + 1;
    END_IF
ELSE
    OverheatProtection := FALSE;

    IF lowDemand AND (heatingRun >= 4) THEN
        OverheatProtection := TRUE;
        HeaterOutput := FALSE;
        heatingRun := 0;
        coolingActive := TRUE;
        coolingCount := 0;
    ELSIF lowDemand THEN
        HeaterOutput := TRUE;
        heatingRun := heatingRun + 1;
    ELSE
        HeaterOutput := FALSE;
        heatingRun := 0;
    END_IF
END_IF

CurrentTemperature := TemperatureSensorInput;
SetTempDisplay := SetTemperature;
HeaterStatus := HeaterOutput;

END_FUNCTION_BLOCK