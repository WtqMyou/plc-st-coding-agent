(* ENGINEERING_CONTRACT
 * | Output/State         | Activation                          | Retention     | Reset/Deactivation                         | Same-scan Priority         | Units/Boundaries         |
 * |----------------------|-------------------------------------|---------------|--------------------------------------------|----------------------------|--------------------------|
 * | CurrentTemperature   | Mirror TemperatureSensorInput       | Hold last val | On fault: display 0.0 (PUB001, PUB006)     | Sensor fault > all        | REAL 0.0-100.0 valid     |
 * | SetTempDisplay       | Mirror SetTemperature               | Hold          | None (PUB002, PUB006)                       | -                          | REAL user-defined        |
 * | HeaterOutput         | Temp below set + no fault + no prot | Hold          | Fault, overheat, or temp>=set (PUB003/4/7) | Sensor fault > overheat   | BOOL, 5s overheat limit  |
 * | HeaterStatus         | Mirror HeaterOutput                 | Hold          | Same as HeaterOutput (PUB006)               | -                          | BOOL                     |
 * | OverheatProtection   | TON_HeaterRun elapsed >= 5s         | Hold          | After 3s cooldown TON_ProtectionCooldown    | -                          | LTIME TON, T#5s>T#3s     |
 * | tmp_overheatTriggered| OverheatProtection active           | Latch         | After 3s cooldown complete (PUB005)         | -                          | Internal BOOL latch      |
 *
 * Timing: TON.Q = elapsed >= PT (PUB005). Overheat at >5s elapsed, cooldown at >3s.
 * Fault: TemperatureSensorInput < 0 OR > 100 (PUB007).
 *)

FUNCTION_BLOCK FB_TemperatureControl
VAR_INPUT
    TemperatureSensorInput : REAL;
    SetTemperature : REAL;
END_VAR
VAR_OUTPUT
    CurrentTemperature : REAL := 0.0;
    SetTempDisplay : REAL := 0.0;
    HeaterStatus : BOOL := FALSE;
    OverheatProtection : BOOL := FALSE;
    HeaterOutput : BOOL := FALSE;
END_VAR
VAR
    TON_HeaterRun : TON;
    TON_ProtectionCooldown : TON;
    tmp_overheatTriggered : BOOL := FALSE;
    tmp_protectionCooldownActive : BOOL := FALSE;
END_VAR

    CurrentTemperature := TemperatureSensorInput;
    SetTempDisplay := SetTemperature;

    IF TemperatureSensorInput < 0.0 OR TemperatureSensorInput > 100.0 THEN
        HeaterOutput := FALSE;
        OverheatProtection := FALSE;
        tmp_overheatTriggered := FALSE;
        tmp_protectionCooldownActive := FALSE;
        TON_HeaterRun(IN := FALSE);
        TON_ProtectionCooldown(IN := FALSE);
    ELSIF tmp_overheatTriggered THEN
        HeaterOutput := FALSE;
        TON_HeaterRun(IN := FALSE);
        TON_ProtectionCooldown(IN := FALSE);
        TON_ProtectionCooldown.PT := T#3s;
        TON_ProtectionCooldown(IN := TRUE);
        IF TON_ProtectionCooldown.Q THEN
            tmp_overheatTriggered := FALSE;
            tmp_protectionCooldownActive := FALSE;
            OverheatProtection := FALSE;
        ELSE
            OverheatProtection := TRUE;
        END_IF;
    ELSIF TemperatureSensorInput < SetTemperature THEN
        HeaterOutput := TRUE;
        TON_HeaterRun.PT := T#5s;
        TON_HeaterRun(IN := TRUE);
        IF TON_HeaterRun.Q THEN
            tmp_overheatTriggered := TRUE;
            HeaterOutput := FALSE;
        END_IF;
    ELSE
        HeaterOutput := FALSE;
        tmp_overheatTriggered := FALSE;
        tmp_protectionCooldownActive := FALSE;
        TON_HeaterRun(IN := FALSE);
    END_IF;

    HeaterStatus := HeaterOutput;
END_FUNCTION_BLOCK

(* CONTRACT_RULES [] *)