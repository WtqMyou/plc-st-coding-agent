FUNCTION_BLOCK FB_TemperatureControl
(* ENGINEERING_CONTRACT
   - CurrentTemperature: raw TemperatureSensorInput assigned every scan; no unit conversion; no retention.
   - SetTempDisplay: echoes SetTemperature every scan; no units/bounds applied.
   - HeaterStatus: equals HeaterOutput after all gating; no independent latch.
   - OverheatProtection: latched TRUE when continuous heater on-time exceeds 5 s (PUB006);
     cleared only after 3 s cooldown timer expires (PUB006); retains state across scans.
   - HeaterOutput: TRUE when sensor valid, not overheat-latched, and TemperatureSensorInput < SetTemperature (PUB003);
     FALSE when actual > set, equal, sensor fault, or overheat latched (PUB004/PUB005/PUB008).
   - Sensor fault: TemperatureSensorInput < 0.0 OR > 100.0 disables heating; non-latching (PUB008).
   - Boundary equality: heater off (unspecified by PUB003/PUB004; implemented consistently).
*)
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
    sensorFault : BOOL;
    heaterCmd : BOOL;
    overheatLatched : BOOL;
    heatTimer : TON;
    coolTimer : TON;
END_VAR

CurrentTemperature := TemperatureSensorInput;
SetTempDisplay := SetTemperature;

sensorFault := (TemperatureSensorInput < 0.0) OR (TemperatureSensorInput > 100.0);

heaterCmd := FALSE;
IF NOT sensorFault THEN
    IF TemperatureSensorInput < SetTemperature THEN
        heaterCmd := TRUE;
    ELSIF TemperatureSensorInput > SetTemperature THEN
        heaterCmd := FALSE;
    ELSE
        heaterCmd := FALSE; (* equality -> OFF *)
    END_IF;
END_IF;

heatTimer(IN := heaterCmd AND NOT overheatLatched, PT := T#5S);
IF heatTimer.Q THEN
    overheatLatched := TRUE;
END_IF;

coolTimer(IN := overheatLatched, PT := T#3S);
IF coolTimer.Q THEN
    overheatLatched := FALSE;
END_IF;

OverheatProtection := overheatLatched;

IF sensorFault OR overheatLatched THEN
    HeaterOutput := FALSE;
ELSE
    HeaterOutput := heaterCmd;
END_IF;

HeaterStatus := HeaterOutput;

END_FUNCTION_BLOCK