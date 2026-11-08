FUNCTION_BLOCK FB
VAR_INPUT
    TemperatureSensorInput: REAL;
    SetTemperature: REAL;
END_VAR
VAR_OUTPUT
    CurrentTemperature: REAL;
    SetTempDisplay: REAL;
    HeaterStatus: BOOL;
    OverheatProtection: BOOL;
    HeaterOutput: BOOL;
END_VAR
VAR
    HeatRunCounter: INT := 0;
    OverheatRemaining: INT := 0;
    SensorFault: BOOL;
END_VAR

CurrentTemperature := TemperatureSensorInput;
SetTempDisplay := SetTemperature;
SensorFault := TemperatureSensorInput < 0.0 OR TemperatureSensorInput > 100.0;

IF OverheatRemaining > 0 THEN
    OverheatProtection := TRUE;
    HeaterOutput := FALSE;
    HeatRunCounter := 0;
    OverheatRemaining := OverheatRemaining - 1;
ELSIF SensorFault THEN
    OverheatProtection := FALSE;
    HeaterOutput := FALSE;
    HeatRunCounter := 0;
ELSIF TemperatureSensorInput >= SetTemperature THEN
    OverheatProtection := FALSE;
    HeaterOutput := FALSE;
    HeatRunCounter := 0;
ELSIF TemperatureSensorInput < SetTemperature THEN
    OverheatProtection := FALSE;
    HeaterOutput := TRUE;
    HeatRunCounter := HeatRunCounter + 1;

    IF HeatRunCounter >= 5 THEN
        HeaterOutput := FALSE;
        OverheatProtection := TRUE;
        HeatRunCounter := 0;
        OverheatRemaining := 2;
    END_IF
END_IF

HeaterStatus := HeaterOutput;

END_FUNCTION_BLOCK