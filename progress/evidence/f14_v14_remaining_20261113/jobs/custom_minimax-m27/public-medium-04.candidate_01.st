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
    OverheatTimer : TON;
    CooldownTimer : TON;
    tmp_SensorFault : BOOL;
END_VAR

(* ENGINEERING_CONTRACT:
 * | Output              | Activation                        | Retention/Hold              | Reset/Deactivation                    | Priority/Scan |
 * |---------------------|------------------------------------|-----------------------------|---------------------------------------|---------------|
 * | CurrentTemperature  | Every scan from sensor             | N/A (combinational read)    | N/A                                   | Same-scan     |
 * | SetTempDisplay      | Every scan from input              | N/A (combinational read)    | N/A                                   | Same-scan     |
 * | HeaterStatus        | Every scan = HeaterOutput          | N/A (combinational mirror)  | N/A                                   | Same-scan     |
 * | HeaterOutput        | Temp < SetTemp AND no fault/protection | Hold while conditions met | Sensor fault OR OverheatProtection OR Temp > SetTemp | Same-scan |
 * | OverheatProtection  | 5s continuous HeaterOutput         | Hold until 3s cooldown done | CooldownTimer.Q (elapsed >= 3s)       | Safety latch  |
 *
 * PUB001: HeaterOutput = (TemperatureSensorInput < SetTemperature) when no faults
 * PUB002, PUB005, PUB006, PUB008: Overheat triggers after TON.Q (elapsed >= 5s) with continuous heater ON
 *         3s cooldown via CooldownTimer before OverheatProtection can clear
 * PUB003: All status outputs updated every scan from current sensor/control state
 * PUB004: Sensor fault (temp < 0 OR temp > 100) disables heater immediately; no hysteresis on fault
 * Units: Temperature [degrees], Time [IEC TON with PT=T#5S/T#3S]
 *)

(* Initialize timers on first scan *)
OverheatTimer(IN := FALSE, PT := T#5S);
CooldownTimer(IN := FALSE, PT := T#3S);

(* PUB004: Sensor fault detection - immediate heater disable *)
tmp_SensorFault := (TemperatureSensorInput < 0.0) OR (TemperatureSensorInput > 100.0);

(* Primary control logic with safety priority *)
IF tmp_SensorFault THEN
    (* PUB004: Sensor fault - disable heater, enter protection state *)
    HeaterOutput := FALSE;
    OverheatProtection := TRUE;
    OverheatTimer(IN := FALSE);
    CooldownTimer(IN := TRUE, PT := T#3S);
    IF CooldownTimer.Q THEN
        OverheatProtection := FALSE;
        CooldownTimer(IN := FALSE);
    END_IF;

ELSIF OverheatProtection THEN
    (* PUB005, PUB008: Overheat protection active - heater forced OFF, cooldown in progress *)
    HeaterOutput := FALSE;
    CooldownTimer(IN := TRUE, PT := T#3S);
    OverheatTimer(IN := FALSE);
    IF CooldownTimer.Q THEN
        OverheatProtection := FALSE;
        CooldownTimer(IN := FALSE);
    END_IF;

ELSE
    (* Normal temperature control *)
    IF TemperatureSensorInput < SetTemperature THEN
        HeaterOutput := TRUE;
    ELSE
        HeaterOutput := FALSE;
    END_IF;

    (* PUB005, PUB006: Overheat protection - track 5s continuous heater operation *)
    IF HeaterOutput THEN
        OverheatTimer(IN := TRUE, PT := T#5S);
        IF OverheatTimer.Q THEN
            (* PUB002, PUB008: Overheat triggered - auto-off heater, start 3s cooldown *)
            OverheatProtection := TRUE;
            HeaterOutput := FALSE;
            OverheatTimer(IN := FALSE);
            CooldownTimer(IN := TRUE, PT := T#3S);
        END_IF;
    ELSE
        OverheatTimer(IN := FALSE);
    END_IF;
END_IF;

(* PUB003: Status display outputs updated every scan *)
CurrentTemperature := TemperatureSensorInput;
SetTempDisplay := SetTemperature;
HeaterStatus := HeaterOutput;
END_FUNCTION_BLOCK

(* CONTRACT_RULES [{"kind": "hold_until_reset", "output": "OverheatProtection", "set_input": null, "reset_input": null}] *)