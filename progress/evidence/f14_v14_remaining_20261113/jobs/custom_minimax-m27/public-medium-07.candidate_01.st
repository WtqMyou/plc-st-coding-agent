FUNCTION_BLOCK HVAC_MultiMode_Control
VAR_INPUT
    OCCUPANCY_DETECTED   : BOOL;
    ENERGY_SAVING_MODE   : BOOL;
    HVAC_MODE_SELECTOR   : INT;
END_VAR
VAR_OUTPUT
    SUPPLY_FAN_RUN       : BOOL := FALSE;
    TEMP_SETPOINT_ADJUST : INT  := 0;
END_VAR
VAR
    fan_delay_timer  : TON;
    tmp_fan_run      : BOOL := FALSE;
    tmp_adjust       : INT;
END_VAR

(* CONTRACT_RULES [] *)

(*
ENGINEERING_CONTRACT:
SUPPLY_FAN_RUN:
  - Activation: After 30s continuous occupancy without Night mode (PUB003)
  - Retention: Hold TRUE while conditions remain; reset immediately on occupancy loss or Night mode (PUB003)
  - Explicit Reset: Stop+reset when OCCUPANCY_DETECTED=FALSE OR HVAC_MODE_SELECTOR=3 (PUB003)
  - Same-scan priority: Timer starts fresh on first occupancy detection in Auto/Comfort/Economy mode
  - Boundary: TON.Q true when ET >= PT (30s); saturates at PT

TEMP_SETPOINT_ADJUST:
  - Auto(0): 0°C occupied; +3°C unoccupied with energy-saving, +2°C standard (PUB005)
  - Comfort(1): 0°C occupied; +1°C unoccupied (PUB006)
  - Economy(2): 0°C occupied; +4°C unoccupied (PUB007)
  - Night(3): +4°C regardless of occupancy (PUB008)
  - Energy-saving affects Auto mode only; units °C; clamped to ±4°C (PUB002)
*)

// --- Supply Fan Logic with 30s Delay ---
// Start delay only on first occupancy detection (timer TON resets when running with IN=FALSE)
fan_delay_timer(IN := OCCUPANCY_DETECTED AND (HVAC_MODE_SELECTOR <> 3),
                PT := T#30s);

tmp_fan_run := fan_delay_timer.Q;

// Stop immediately and reset timer if occupancy lost or Night mode selected
IF NOT OCCUPANCY_DETECTED OR (HVAC_MODE_SELECTOR = 3) THEN
    tmp_fan_run := FALSE;
    fan_delay_timer(IN := FALSE);
END_IF;

SUPPLY_FAN_RUN := tmp_fan_run;

// --- Temperature Setpoint Adjustment ---
CASE HVAC_MODE_SELECTOR OF
    0:  // Auto mode
        IF OCCUPANCY_DETECTED THEN
            tmp_adjust := 0;
        ELSE
            IF ENERGY_SAVING_MODE THEN
                tmp_adjust := 3;  // +3°C energy saving
            ELSE
                tmp_adjust := 2;  // +2°C standard
            END_IF;
        END_IF;

    1:  // Comfort mode
        IF OCCUPANCY_DETECTED THEN
            tmp_adjust := 0;
        ELSE
            tmp_adjust := 1;
        END_IF;

    2:  // Economy mode
        IF OCCUPANCY_DETECTED THEN
            tmp_adjust := 0;
        ELSE
            tmp_adjust := 4;
        END_IF;

    3:  // Night mode
        tmp_adjust := 4;

    ELSE
        tmp_adjust := 0;
END_CASE;

// Clamp to ±4°C per PUB002
IF tmp_adjust > 4 THEN
    tmp_adjust := 4;
ELSIF tmp_adjust < -4 THEN
    tmp_adjust := -4;
END_IF;

TEMP_SETPOINT_ADJUST := tmp_adjust;

END_FUNCTION_BLOCK