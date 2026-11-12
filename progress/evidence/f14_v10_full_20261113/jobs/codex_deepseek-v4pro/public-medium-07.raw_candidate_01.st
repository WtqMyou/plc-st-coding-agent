(* ENGINEERING_CONTRACT
 * SUPPLY_FAN_RUN: activation requires OCCUPANCY_DETECTED=TRUE and selector <> 3
 * continuously for T#30S; holds while those conditions remain; occupancy loss or Night
 * deactivates immediately, resets timer, and recovery requires full T#30S (PUB002, PUB007).
 * TEMP_SETPOINT_ADJUST: recomputed every scan from current occupancy, energy-saving state
 * and HVAC mode; no latch or extra hold beyond current inputs (PUB003, PUB004, PUB005).
 * Same-scan priority: timer-enable is computed before TON, then fan Q and adjustment update
 * in the same scan; no edge-only triggers or resets beyond stated conditions.
 * Units/bounds: delay is exact T#30S; adjustment is integral degC clamped to [-4,4];
 * power-up outputs initialize to FALSE/OFF and 0 under standard VAR defaults (PUB006).
 *)
(* CONTRACT_RULES [] *)
FUNCTION_BLOCK FB_OfficeHvacControl
VAR_INPUT
    OCCUPANCY_DETECTED : BOOL;
    ENERGY_SAVING_MODE : BOOL;
    HVAC_MODE_SELECTOR : INT;
END_VAR
VAR_OUTPUT
    SUPPLY_FAN_RUN : BOOL;
    TEMP_SETPOINT_ADJUST : INT;
END_VAR
VAR
    fanTimer : TON;
    tmp_FanEnable : BOOL;
END_VAR

tmp_FanEnable := OCCUPANCY_DETECTED AND (HVAC_MODE_SELECTOR <> 3);

fanTimer(IN := tmp_FanEnable, PT := T#30S);
SUPPLY_FAN_RUN := fanTimer.Q;

CASE HVAC_MODE_SELECTOR OF
    0:
        IF OCCUPANCY_DETECTED THEN
            TEMP_SETPOINT_ADJUST := 0;
        ELSIF ENERGY_SAVING_MODE THEN
            TEMP_SETPOINT_ADJUST := 3;
        ELSE
            TEMP_SETPOINT_ADJUST := 2;
        END_IF;
    1:
        IF OCCUPANCY_DETECTED THEN
            TEMP_SETPOINT_ADJUST := 0;
        ELSE
            TEMP_SETPOINT_ADJUST := 1;
        END_IF;
    2:
        IF OCCUPANCY_DETECTED THEN
            TEMP_SETPOINT_ADJUST := 0;
        ELSE
            TEMP_SETPOINT_ADJUST := 4;
        END_IF;
    3:
        TEMP_SETPOINT_ADJUST := 4;
    ELSE
        TEMP_SETPOINT_ADJUST := 0;
END_CASE;

IF TEMP_SETPOINT_ADJUST < -4 THEN
    TEMP_SETPOINT_ADJUST := -4;
ELSIF TEMP_SETPOINT_ADJUST > 4 THEN
    TEMP_SETPOINT_ADJUST := 4;
END_IF;

END_FUNCTION_BLOCK