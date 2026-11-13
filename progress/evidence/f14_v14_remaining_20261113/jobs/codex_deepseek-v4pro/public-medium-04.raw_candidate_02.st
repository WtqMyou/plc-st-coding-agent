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
    tmp_SensorFault : BOOL;
    tmp_HeaterRequest : BOOL;
    tmp_OverheatLatched : BOOL;
    tmp_WasOverheat : BOOL;
    tmp_ContinuityTimer : TON;
    tmp_CoolingTimer : TON;
END_VAR

(* ENGINEERING_CONTRACT
HeaterOutput:
  ACT: TemperatureSensorInput < SetTemperature, no sensor fault, no overheat [PUB003].
  HOLD: none; recalculated each scan. OFF: equal/higher setpoint, fault, or overheat [PUB004, PUB005, PUB007].
OverheatProtection:
  ACT: heater remains on continuously for >5s, latched; HOLD: latched; OFF: auto after T#3S cooldown [PUB005].
Displays:
  CurrentTemperature mirrors sensor, SetTempDisplay mirrors setpoint, HeaterStatus mirrors HeaterOutput,
  OverheatProtection mirrors overheat latch [PUB001, PUB006].
Priority same scan: fault and overheat inhibit HeaterOutput. Sensor fault: input <0.0 or >100.0.
Units: REAL temperature values, TIME 5s/3s. Equality/manual reset unspecified; equal setpoint turns heater off.
*)
(* CONTRACT_RULES [] *)

tmp_SensorFault := (TemperatureSensorInput < 0.0) OR (TemperatureSensorInput > 100.0);
CurrentTemperature := TemperatureSensorInput;
SetTempDisplay := SetTemperature;

tmp_WasOverheat := tmp_OverheatLatched;

IF tmp_WasOverheat THEN
    tmp_CoolingTimer(IN := TRUE, PT := T#3S);
    IF tmp_CoolingTimer.Q THEN
        tmp_OverheatLatched := FALSE;
    END_IF;
END_IF;

tmp_HeaterRequest := (NOT tmp_SensorFault) AND (NOT tmp_OverheatLatched) AND (TemperatureSensorInput < SetTemperature);
HeaterOutput := tmp_HeaterRequest;

tmp_ContinuityTimer(IN := HeaterOutput, PT := T#10S);
IF tmp_ContinuityTimer.ET > T#5S THEN
    tmp_OverheatLatched := TRUE;
    HeaterOutput := FALSE;
    tmp_ContinuityTimer(IN := FALSE, PT := T#10S);
END_IF;

OverheatProtection := tmp_OverheatLatched;
HeaterStatus := HeaterOutput;

IF NOT tmp_WasOverheat THEN
    tmp_CoolingTimer(IN := tmp_OverheatLatched, PT := T#3S);
END_IF;
END_FUNCTION_BLOCK