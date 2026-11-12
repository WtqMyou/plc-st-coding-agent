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
    SensorFault : BOOL;
    OverheatLatched : BOOL;
    HeatOnTimer : TON;
    CoolingTimer : TON;
END_VAR

CurrentTemperature := TemperatureSensorInput;
SetTempDisplay := SetTemperature;

SensorFault := (TemperatureSensorInput < 0.0) OR (TemperatureSensorInput > 100.0);

HeatOnTimer(IN := HeaterOutput AND NOT SensorFault, PT := T#5S);
IF HeatOnTimer.Q THEN
    OverheatLatched := TRUE;
END_IF;

CoolingTimer(IN := OverheatLatched, PT := T#3S);
IF CoolingTimer.Q THEN
    OverheatLatched := FALSE;
END_IF;

OverheatProtection := OverheatLatched;

IF SensorFault THEN
    HeaterOutput := FALSE;
ELSIF OverheatLatched THEN
    HeaterOutput := FALSE;
ELSIF TemperatureSensorInput < SetTemperature THEN
    HeaterOutput := TRUE;
ELSIF TemperatureSensorInput > SetTemperature THEN
    HeaterOutput := FALSE;
END_IF;

HeaterStatus := HeaterOutput;

END_FUNCTION_BLOCK