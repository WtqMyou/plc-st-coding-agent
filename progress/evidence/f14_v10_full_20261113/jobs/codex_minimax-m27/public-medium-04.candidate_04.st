(* CONTRACT_RULES [] *)
FUNCTION_BLOCK FB_TemperatureControl
VAR_INPUT
    TemperatureSensorInput : REAL;
    SetTemperature         : REAL;
END_VAR
VAR_OUTPUT
    CurrentTemperature : REAL;
    SetTempDisplay      : REAL;
    HeaterStatus        : BOOL;
    OverheatProtection  : BOOL;
    HeaterOutput        : BOOL;
END_VAR
VAR
    tonCooldown         : TON;
    local_OverheatActive : BOOL := FALSE;
    local_SensorFault    : BOOL := FALSE;
    local_RuntimeAccum   : LTIME := LTIME#0s;
END_VAR

(* ENGINEERING_CONTRACT
  PUB003: Overheat protection triggers when heater runs continuously > 5s.
    - Activation: local_RuntimeAccum exceeds 5s on same scan it is detected.
    - Retention: OverheatActive stays TRUE until cooldown completes.
    - Reset/Deactivation: 3s cooldown via tonCooldown; heating condition
      must reassert AND cooldown must complete before heater can restart.
    - Same-scan priority: heater outputs set to FALSE when overheat activates;
      local_RuntimeAccum resets only when heating condition drops (not on
      overheat trigger), preserving correct accumulated-time logic.
    - Units/Boundaries: LTIME nanoseconds; strict > 5000ms threshold.
  PUB004: Heater turns on when temperature < setpoint (strict <).
  PUB007: Status outputs reflect current state every scan.
  PUB006: Sensor fault (input < 0 or > 100) turns heater off immediately.
*)

CurrentTemperature := TemperatureSensorInput;
SetTempDisplay     := SetTemperature;

local_SensorFault := (TemperatureSensorInput < 0.0) OR (TemperatureSensorInput > 100.0);

IF local_SensorFault OR local_OverheatActive THEN
    HeaterOutput := FALSE;
ELSE
    IF TemperatureSensorInput < SetTemperature THEN
        HeaterOutput := TRUE;
    ELSE
        HeaterOutput := FALSE;
    END_IF;
END_IF;

IF HeaterOutput THEN
    local_RuntimeAccum := local_RuntimeAccum + TO_LTIME(1);
END_IF;

IF NOT HeaterOutput THEN
    local_RuntimeAccum := LTIME#0s;
END_IF;

IF local_RuntimeAccum > T#5s THEN
    local_OverheatActive := TRUE;
    local_RuntimeAccum   := LTIME#0s;
END_IF;

IF local_OverheatActive THEN
    tonCooldown(IN := TRUE, PT := T#3s);
    IF tonCooldown.Q THEN
        local_OverheatActive := FALSE;
    END_IF;
ELSE
    tonCooldown(IN := FALSE, PT := T#3s);
END_IF;

HeaterStatus       := HeaterOutput;
OverheatProtection := local_OverheatActive;
END_FUNCTION_BLOCK