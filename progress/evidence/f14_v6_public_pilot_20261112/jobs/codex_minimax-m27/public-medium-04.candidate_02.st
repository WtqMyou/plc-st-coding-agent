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
    HeaterOnRequest : BOOL;
    OverheatTimer : TON;
    CooldownTimer : TON;
    tmp_SensorFault : BOOL;
    tmp_HeaterShouldBeOn : BOOL;
END_VAR

(* ENGINEERING_CONTRACT
 * ============================================================
 * Outputs & State Groups:
 * -----------------------------------------------------------
 * HeaterOutput (BOOL, output):
 *   - Activation: Set TRUE when temp < set, no fault, no overheat
 *   - Retention: Maintained TRUE across scans while conditions hold
 *   - Explicit Reset: Set FALSE by fault detection OR overheat trigger
 *   - Same-scan Priority: Fault > Overheat > Temperature comparison
 *   - Units: Boolean on/off signal
 * -----------------------------------------------------------
 * OverheatProtection (BOOL, output):
 *   - Activation: Set TRUE after heater runs continuously > 5s (PUB006)
 *   - Retention: Held TRUE for mandatory 3s cooldown period (PUB006)
 *   - Explicit Reset: Cleared automatically after 3s elapses
 *   - Same-scan Priority: Timer expiry drives reset after 3s
 *   - Units: Boolean flag (TRUE = protection latched)
 * -----------------------------------------------------------
 * CurrentTemperature / SetTempDisplay (REAL, output):
 *   - Activation: Assigned every scan from inputs
 *   - Retention: No retention; mirrors inputs each scan
 *   - Explicit Reset: N/A (always reflects current values)
 *   - Units: degrees (temperature values, PUB002/PUB007)
 * -----------------------------------------------------------
 * HeaterStatus (BOOL, output):
 *   - Activation: Mirrors HeaterOutput value each scan
 *   - Retention: Reflects current heater state
 *   - Units: Boolean status indicator (PUB007)
 * ============================================================
 * CONTRACT_RULES []
 * ============================================================ *)

tmp_SensorFault := (TemperatureSensorInput < 0.0) OR (TemperatureSensorInput > 100.0);

CurrentTemperature := TemperatureSensorInput;
SetTempDisplay := SetTemperature;

IF tmp_SensorFault THEN
    HeaterOnRequest := FALSE;
ELSIF OverheatProtection THEN
    HeaterOnRequest := FALSE;
ELSE
    tmp_HeaterShouldBeOn := (TemperatureSensorInput < SetTemperature);
    HeaterOnRequest := tmp_HeaterShouldBeOn;
END_IF;

OverheatTimer(IN := HeaterOnRequest AND NOT OverheatProtection,
              PT := T#5S);

IF OverheatTimer.Q THEN
    OverheatProtection := TRUE;
END_IF;

CooldownTimer(IN := OverheatProtection,
              PT := T#3S);

IF CooldownTimer.Q THEN
    OverheatProtection := FALSE;
END_IF;

HeaterOutput := HeaterOnRequest;
HeaterStatus := HeaterOutput;

END_FUNCTION_BLOCK