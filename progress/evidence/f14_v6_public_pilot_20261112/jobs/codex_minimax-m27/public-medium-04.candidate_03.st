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
    OverheatCooldownTimer : TON;
    tmp_SensorFault : BOOL;
END_VAR

(* ENGINEERING_CONTRACT
 * ============================================================
 * Outputs & State Groups:
 * -----------------------------------------------------------
 * HeaterOutput (BOOL, output):
 *   - Activation: Set TRUE when temp < set, no fault, no overheat
 *   - Retention: Maintained TRUE across scans while conditions hold
 *   - Explicit Reset: Set FALSE by fault OR overheat trigger (same-scan)
 *   - Same-scan Priority: OverheatProtection > Fault > Temperature
 *   - Units: Boolean on/off signal
 * -----------------------------------------------------------
 * OverheatProtection (BOOL, output):
 *   - Activation: Set TRUE after heater runs continuously > 5s (PUB006)
 *   - Retention: Held TRUE for mandatory 3s cooldown (PUB006)
 *   - Explicit Reset: Cleared automatically after 3s elapses
 *   - Units: Boolean flag (TRUE = protection latched)
 * -----------------------------------------------------------
 * CurrentTemperature / SetTempDisplay (REAL, output):
 *   - Activation: Assigned every scan from inputs (PUB007)
 *   - Units: degrees
 * -----------------------------------------------------------
 * HeaterStatus (BOOL, output):
 *   - Activation: Mirrors HeaterOutput each scan (PUB007)
 *   - Units: Boolean status indicator
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
    HeaterOnRequest := (TemperatureSensorInput < SetTemperature);
END_IF;

OverheatTimer(IN := HeaterOnRequest AND NOT OverheatProtection,
              PT := T#5S);

IF OverheatTimer.Q THEN
    OverheatProtection := TRUE;
END_IF;

OverheatCooldownTimer(IN := OverheatProtection,
                      PT := T#3S);

IF OverheatCooldownTimer.Q THEN
    OverheatProtection := FALSE;
END_IF;

IF tmp_SensorFault THEN
    HeaterOutput := FALSE;
ELSIF OverheatProtection THEN
    HeaterOutput := FALSE;
ELSE
    HeaterOutput := HeaterOnRequest;
END_IF;

HeaterStatus := HeaterOutput;

END_FUNCTION_BLOCK