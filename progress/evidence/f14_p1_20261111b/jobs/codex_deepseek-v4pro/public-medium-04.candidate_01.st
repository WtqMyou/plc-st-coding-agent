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
    HeaterCommand : BOOL;
    HeaterOnTimer : TON;
    CoolDownTimer : TON;
END_VAR

(* Display values *)
CurrentTemperature := TemperatureSensorInput;
SetTempDisplay := SetTemperature;

(* Sensor fault: valid measurement range is 0.0 to 100.0 *)
SensorFault := (TemperatureSensorInput < 0.0) OR (TemperatureSensorInput > 100.0);

(* Overheating protection remains active for at least 3 seconds *)
CoolDownTimer(IN := OverheatProtection, PT := T#3S);
IF CoolDownTimer.Q THEN
    OverheatProtection := FALSE;
END_IF;

(* Normal heater command *)
HeaterCommand := (NOT SensorFault)
                 AND (NOT OverheatProtection)
                 AND (TemperatureSensorInput < SetTemperature);

(* Heater running continuously for more than 5 seconds triggers protection *)
HeaterOnTimer(IN := HeaterCommand, PT := T#5S);
IF HeaterOnTimer.Q THEN
    OverheatProtection := TRUE;
END_IF;

(* Force heater off if protection is active, including the trigger moment *)
HeaterOutput := HeaterCommand AND (NOT OverheatProtection);

(* Heater status indication *)
HeaterStatus := HeaterOutput;

END_FUNCTION_BLOCK