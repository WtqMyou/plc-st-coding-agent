FUNCTION_BLOCK FB_TemperatureLogicControl
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
    heaterOnTimer : TON;
    coolingTimer : TON;
    SensorFault : BOOL;
END_VAR

CurrentTemperature := TemperatureSensorInput;
SetTempDisplay := SetTemperature;

SensorFault := (TemperatureSensorInput < 0.0) OR (TemperatureSensorInput > 100.0);

heaterOnTimer(IN := HeaterOutput, PT := T#5S);
IF (NOT SensorFault) AND (NOT OverheatProtection) AND heaterOnTimer.Q THEN
    OverheatProtection := TRUE;
END_IF;

coolingTimer(IN := OverheatProtection, PT := T#3S);

IF OverheatProtection THEN
    HeaterOutput := FALSE;
    IF coolingTimer.Q THEN
        OverheatProtection := FALSE;
    END_IF;
ELSIF SensorFault THEN
    HeaterOutput := FALSE;
ELSIF TemperatureSensorInput < SetTemperature THEN
    HeaterOutput := TRUE;
ELSE
    HeaterOutput := FALSE;
END_IF;

HeaterStatus := HeaterOutput;

END_FUNCTION_BLOCK