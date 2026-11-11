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
    ConsecutiveHeatingScans : INT := 0;
    CoolingCounter : INT := 0;
    OverheatProtectionInternal : BOOL := FALSE;
    HeatingDemand : BOOL := FALSE;
END_VAR

IF OverheatProtectionInternal THEN
    CoolingCounter := CoolingCounter + 1;
    IF CoolingCounter >= 3 THEN
        OverheatProtectionInternal := FALSE;
        CoolingCounter := 0;
    END_IF;
    HeatingDemand := FALSE;
ELSE
    IF TemperatureSensorInput >= 0.0 AND TemperatureSensorInput <= 100.0 THEN
        HeatingDemand := (TemperatureSensorInput < SetTemperature);
        IF HeatingDemand THEN
            ConsecutiveHeatingScans := ConsecutiveHeatingScans + 1;
            IF ConsecutiveHeatingScans >= 5 THEN
                OverheatProtectionInternal := TRUE;
                HeatingDemand := FALSE;
                CoolingCounter := 1;
                ConsecutiveHeatingScans := 0;
            END_IF;
        ELSE
            ConsecutiveHeatingScans := 0;
        END_IF;
    ELSE
        HeatingDemand := FALSE;
        ConsecutiveHeatingScans := 0;
    END_IF;
END_IF;

HeaterOutput := HeatingDemand AND NOT OverheatProtectionInternal;
OverheatProtection := OverheatProtectionInternal;
CurrentTemperature := TemperatureSensorInput;
SetTempDisplay := SetTemperature;
HeaterStatus := HeaterOutput;
END_FUNCTION_BLOCK